#!/usr/bin/env python3
"""Bringforth: uploads 3D models, images, audio and video to Roblox through Open Cloud
(Assets API) and hands the new asset IDs to Roblox Studio.

Usage:
  bringforth.py whoami                                   what the API key can do, when it expires
  bringforth.py check  <files...>                        will Roblox take these files? (format, 20 MB, triangles)
  bringforth.py upload <files...> [--name N] [--description D] [--group ID | --user ID]
                       [--type Model|Decal|Image|Audio|Video] [--max-price 0] [--force] [--luau path]
  bringforth.py grant  <assetId|file> --universe ID [--no-dependencies]
                                                         let an experience use an asset (Asset-Permissions)
  bringforth.py serve  [--port 34873]                    local feed for the Bringforth Studio plugin
  bringforth.py install-plugin [--dir PluginsFolder]     copy the Studio plugin into Studio's Plugins folder

Secrets: the key is read from ROBLOX_API_KEY (or ROBLOX_OPEN_CLOUD_API_KEY), or from a .env file
in the current folder. It is never printed or written anywhere. Permissions it needs:
  assets: read + write (upload, poll the operation), asset-permissions: write (only for grant).
Creator: --group/--user, ROBLOX_CREATOR_GROUP_ID / ROBLOX_CREATOR_USER_ID, else the user who
created the key (from key introspection).

Uploads are recorded in bringforth.lock.json (path -> asset ID, content hash, version): an
unchanged file is not uploaded again, a changed .fbx model becomes a new version of the same
asset, anything else becomes a new asset (Open Cloud can only update FBX model content).
Needs Python 3.9+, no other packages.
"""

import argparse
import hashlib
import io
import json
import os
import re
import shutil
import struct
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE_URL = os.environ.get("ROBLOX_OPEN_CLOUD_URL", "https://apis.roblox.com").rstrip("/")
USER_AGENT = "roblox-studio-bringforth/1.0"
LOCK_FILE = "bringforth.lock.json"
DEFAULT_PORT = 34873
MAX_BYTES = 20 * 1024 * 1024
MAX_TRIANGLES = 20000
HERE = os.path.dirname(os.path.abspath(__file__))

# Supported by the Assets API (create.roblox.com/docs/cloud/guides/usage-assets).
FORMATS = {
    ".fbx": ("Model", "model/fbx"),
    ".gltf": ("Model", "model/gltf+json"),
    ".glb": ("Model", "model/gltf-binary"),
    ".rbxm": ("Model", "model/x-rbxm"),
    ".rbxmx": ("Model", "model/x-rbxm"),
    ".png": ("Decal", "image/png"),
    ".jpg": ("Decal", "image/jpeg"),
    ".jpeg": ("Decal", "image/jpeg"),
    ".bmp": ("Decal", "image/bmp"),
    ".tga": ("Decal", "image/tga"),
    ".mp3": ("Audio", "audio/mpeg"),
    ".ogg": ("Audio", "audio/ogg"),
    ".wav": ("Audio", "audio/wav"),
    ".flac": ("Audio", "audio/flac"),
    ".mp4": ("Video", "video/mp4"),
    ".mov": ("Video", "video/mov"),
}
NOT_SUPPORTED = {
    ".obj": "Open Cloud does not take OBJ: open it in Blender and export glTF Binary (.glb) or FBX, "
    "or import it with Studio's 3D Importer",
    ".blend": "export it from Blender first (File > Export > FBX or glTF Binary; blender_check.py exports FBX)",
    ".dae": "export FBX or glTF Binary instead",
    ".stl": "export FBX or glTF Binary instead (STL has no materials or UVs)",
}
TYPE_CHOICES = ["Model", "Decal", "Image", "Audio", "Video"]


class Fail(Exception):
    pass


class HttpFail(Fail):
    def __init__(self, message, status):
        super().__init__(message)
        self.status = status


# Settings and secrets --------------------------------------------------------------


def read_dotenv(path):
    values = {}
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                name, value = line.split("=", 1)
                name = name.strip().removeprefix("export ").strip()
                values[name] = value.strip().strip("'\"")
    except OSError:
        pass
    return values


def setting(*names):
    dotenv = read_dotenv(os.path.join(os.getcwd(), ".env"))
    for name in names:
        if os.environ.get(name):
            return os.environ[name]
        if dotenv.get(name):
            return dotenv[name]
    return None


def api_key():
    key = setting("ROBLOX_API_KEY", "ROBLOX_OPEN_CLOUD_API_KEY")
    if not key:
        raise Fail(
            "no API key. Create one in Creator Hub > Open Cloud > API Keys with assets read + write "
            "(and asset-permissions write for grant), then set ROBLOX_API_KEY in the environment or in a "
            ".env file that git ignores. Never paste it into the chat or the code."
        )
    return key


def warn_env_not_ignored(log):
    if not os.path.exists(".env"):
        return
    try:
        with open(".gitignore", encoding="utf-8") as f:
            if any(line.strip() in (".env", "/.env", ".env*", "*.env") for line in f):
                return
    except OSError:
        pass
    log("WARN  .env is not in .gitignore: add it so the API key never gets committed")


# HTTP --------------------------------------------------------------------------------


def multipart(fields, files):
    boundary = f"----bringforth{uuid.uuid4().hex}"
    out = io.BytesIO()
    for name, value in fields.items():
        out.write(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n".encode())
        out.write(value.encode("utf-8"))
        out.write(b"\r\n")
    for name, (filename, content_type, data) in files.items():
        out.write(
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"; filename=\"{filename}\"\r\n"
            f"Content-Type: {content_type}\r\n\r\n".encode()
        )
        out.write(data)
        out.write(b"\r\n")
    out.write(f"--{boundary}--\r\n".encode())
    return out.getvalue(), f"multipart/form-data; boundary={boundary}"


def explain(method, path, status, raw, scope):
    try:
        detail = json.loads(raw)
        detail = detail.get("message") or detail.get("errorMessage") or detail.get("errors") or detail
    except (ValueError, AttributeError):
        detail = raw[:300].decode("utf-8", "replace")
    hint = {
        401: " -> the key is wrong, expired, auto-expired (unused for 60 days) or revoked: re-enable or replace it",
        403: f" -> the key lacks {scope}, the creator in the request is not the key's owner/group, "
        "or the key's IP allowlist blocks this machine",
        400: " -> Roblox rejected the request (file format, name/description moderated, upload fee above --max-price)",
        404: " -> not found: check the asset or operation ID",
    }.get(status, "")
    return f"{method} {path}: HTTP {status}: {detail}{hint}"


class OpenCloud:
    def __init__(self, key, sleep=time.sleep):
        self.key = key
        self.sleep = sleep

    def request(self, method, path, scope, fields=None, files=None, json_body=None, auth=True):
        headers = {"User-Agent": USER_AGENT, "Accept": "application/json"}
        if auth:
            headers["x-api-key"] = self.key
        body = None
        if fields is not None or files:
            body, headers["Content-Type"] = multipart(fields or {}, files or {})
        elif json_body is not None:
            body = json.dumps(json_body).encode()
            headers["Content-Type"] = "application/json"
        url = BASE_URL + path
        raw, status = b"", 0
        for attempt in range(6):
            req = urllib.request.Request(url, data=body, method=method, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=120) as response:
                    raw, status = response.read(), response.status
                break
            except urllib.error.HTTPError as e:
                raw, status = e.read(), e.code
                if (status == 429 or status >= 500) and attempt < 5:
                    retry_after = e.headers.get("Retry-After") or ""
                    delay = float(retry_after) if re.fullmatch(r"\d+(\.\d+)?", retry_after) else 2**attempt
                    self.sleep(min(delay, 60))
                    continue
                break
            except urllib.error.URLError as e:
                if attempt == 5:
                    raise Fail(f"{method} {path}: network error {e.reason}")
                self.sleep(2**attempt)
        if status >= 400:
            raise HttpFail(explain(method, path, status, raw, scope), status)
        return json.loads(raw) if raw else None

    def introspect(self):
        return self.request(
            "POST", "/api-keys/v1/introspect", "nothing", json_body={"apiKey": self.key}, auth=False
        )

    def create(self, request, filename, content_type, data):
        return self.request(
            "POST",
            "/assets/v1/assets",
            "assets write",
            fields={"request": json.dumps(request)},
            files={"fileContent": (filename, content_type, data)},
        )

    def update(self, asset_id, request, filename, content_type, data):
        return self.request(
            "PATCH",
            f"/assets/v1/assets/{asset_id}",
            "assets write",
            fields={"request": json.dumps(request)},
            files={"fileContent": (filename, content_type, data)},
        )

    def operation(self, operation_path, timeout=180, log=print):
        operation_id = operation_path.rsplit("/", 1)[-1]
        deadline = time.monotonic() + timeout
        delay = 0.5
        while True:
            result = self.request("GET", f"/assets/v1/operations/{operation_id}", "assets read")
            if result and result.get("done"):
                if result.get("error"):
                    error = result["error"]
                    raise Fail(f"upload failed: {error.get('message') or error}")
                return result.get("response") or {}
            if time.monotonic() > deadline:
                raise Fail(f"operation {operation_id} still running after {timeout} s; check it later in Creator Hub")
            self.sleep(delay)
            delay = min(delay * 2, 5)

    def grant(self, universe_id, asset_ids, dependencies=True):
        return self.request(
            "PATCH",
            "/asset-permissions-api/v1/assets/permissions",
            "asset-permissions write",
            json_body={
                "subjectType": "Universe",
                "subjectId": str(universe_id),
                "action": "Use",
                "requests": [{"assetId": int(a), "grantToDependencies": dependencies} for a in asset_ids],
            },
        )


# Key introspection ---------------------------------------------------------------------


def key_report(info, log=print, need=("asset",)):
    """Prints what matters about the key; returns the authorized user ID."""
    if not info:
        return None
    if not info.get("enabled", True):
        log("WARN  the API key is disabled (Creator Hub > Open Cloud > API Keys > Enable Key)")
    if info.get("expired"):
        log("WARN  the API key has expired: set a new expiration date or make a new key")
    expires = info.get("expirationTimeUtc")
    if expires:
        try:
            when = datetime.fromisoformat(expires.replace("Z", "+00:00"))
            days = (when - datetime.now(timezone.utc)).total_seconds() / 86400
            if 0 <= days < 14:
                log(f"WARN  the API key expires in {days:.0f} days ({expires[:10]}): rotate it soon")
        except ValueError:
            pass
    scopes = {s.get("name"): set(s.get("operations") or []) for s in info.get("scopes") or []}
    for name in need:
        missing = {"read", "write"} - scopes.get(name, set()) if name == "asset" else {"write"} - scopes.get(name, set())
        if missing:
            label = "assets" if name == "asset" else name
            log(f"WARN  the key has no {label} {'/'.join(sorted(missing))} permission")
    return info.get("authorizedUserId")


def whoami(client, log=print):
    info = client.introspect()
    log(f"key       {info.get('name')!r} (enabled: {info.get('enabled')}, expired: {info.get('expired')})")
    log(f"owner     user {info.get('authorizedUserId')}")
    for scope in info.get("scopes") or []:
        targets = []
        for field in ("userIds", "groupIds", "universeIds"):
            if scope.get(field):
                targets.append(f"{field[:-3]} {','.join(map(str, scope[field]))}")
        ops = ",".join(scope.get("operations") or [])
        log(f"scope     {scope.get('name')}: {ops}{'  (' + '; '.join(targets) + ')' if targets else ''}")
    log(f"expires   {info.get('expirationTimeUtc') or 'no date set'}")
    log("note      Roblox auto-expires keys that are not used or updated for 60 days")
    key_report(info, log, need=("asset", "asset-permissions"))
    return info


# File checks -----------------------------------------------------------------------------


def classify(path, forced=None):
    ext = os.path.splitext(path)[1].lower()
    if ext in NOT_SUPPORTED:
        raise Fail(f"{path}: {NOT_SUPPORTED[ext]}")
    if ext not in FORMATS:
        raise Fail(f"{path}: unsupported file type {ext or '(none)'}; use one of {', '.join(sorted(FORMATS))}")
    kind, content_type = FORMATS[ext]
    if forced:
        if forced == "Image" and kind == "Decal":
            kind = "Image"
        elif forced != kind:
            raise Fail(f"{path}: a {ext} file cannot be uploaded as {forced}")
    return kind, content_type


def gltf_document(path, data):
    """Returns (json, binary chunk or None) for .glb / .gltf."""
    if path.lower().endswith(".glb"):
        if len(data) < 20 or data[:4] != b"glTF":
            raise Fail(f"{path}: not a GLB file (bad header)")
        version, length = struct.unpack_from("<II", data, 4)
        if version != 2:
            raise Fail(f"{path}: glTF version {version}; Roblox needs glTF 2.0")
        offset, doc, binary = 12, None, None
        while offset + 8 <= min(length, len(data)):
            chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
            chunk = data[offset + 8 : offset + 8 + chunk_length]
            if chunk_type == 0x4E4F534A:
                doc = json.loads(chunk.decode("utf-8"))
            elif chunk_type == 0x004E4942:
                binary = chunk
            offset += 8 + chunk_length
        if doc is None:
            raise Fail(f"{path}: GLB without a JSON chunk")
        return doc, binary
    try:
        return json.loads(data.decode("utf-8")), None
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        raise Fail(f"{path}: not valid glTF JSON ({e})")


def gltf_stats(path, data):
    doc, _ = gltf_document(path, data)
    accessors = doc.get("accessors") or []
    meshes = []
    for index, mesh in enumerate(doc.get("meshes") or []):
        triangles, materials = 0, set()
        for primitive in mesh.get("primitives") or []:
            mode = primitive.get("mode", 4)
            if "indices" in primitive:
                count = accessors[primitive["indices"]]["count"]
            else:
                count = accessors[primitive["attributes"]["POSITION"]]["count"]
            if mode == 4:
                triangles += count // 3
            elif mode in (5, 6):
                triangles += max(count - 2, 0)
            if "material" in primitive:
                materials.add(primitive["material"])
        meshes.append({"name": mesh.get("name") or f"mesh {index}", "triangles": triangles, "materials": len(materials)})
    external = []
    if path.lower().endswith(".gltf"):
        for item in (doc.get("buffers") or []) + (doc.get("images") or []):
            uri = item.get("uri")
            if uri and not uri.startswith("data:"):
                external.append(uri)
    return meshes, external


def check_file(path, forced=None):
    """Returns (kind, content_type, errors, warnings, notes)."""
    errors, warnings, notes = [], [], []
    kind, content_type = classify(path, forced)
    if not os.path.isfile(path):
        raise Fail(f"{path}: file not found")
    size = os.path.getsize(path)
    limit = 3750 * 1024 * 1024 if kind == "Video" else MAX_BYTES
    if size > limit:
        errors.append(f"{size / 1048576:.1f} MB; one upload is limited to {limit // 1048576} MB")
    if size == 0:
        errors.append("file is empty")
    with open(path, "rb") as f:
        data = f.read(min(size, MAX_BYTES + 1)) if kind != "Video" else f.read(64)
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"):
        meshes, external = gltf_stats(path, data)
        if not meshes:
            errors.append("no meshes in the file")
        for mesh in meshes:
            if mesh["triangles"] > MAX_TRIANGLES:
                errors.append(
                    f"mesh {mesh['name']!r} has {mesh['triangles']:,} triangles; Roblox allows {MAX_TRIANGLES:,} "
                    "per mesh: decimate or split it"
                )
            if mesh["materials"] > 1:
                warnings.append(f"mesh {mesh['name']!r} uses {mesh['materials']} materials: split it, one material per mesh")
        if external:
            errors.append(f"refers to external files ({', '.join(external[:3])}): export glTF Binary (.glb) instead")
        total = sum(m["triangles"] for m in meshes)
        notes.append(f"{len(meshes)} meshes, {total:,} triangles")
    elif ext == ".fbx":
        if data.startswith(b"Kaydara FBX Binary"):
            version = struct.unpack_from("<I", data, 23)[0] if len(data) >= 27 else 0
            notes.append(f"binary FBX {version}")
            if version and version < 7100:
                warnings.append(f"FBX version {version} is old: export FBX 7.4 or newer")
        elif b"FBXHeaderExtension" in data[:4096]:
            notes.append("ASCII FBX")
            warnings.append("ASCII FBX: Blender's binary FBX export is smaller and safer")
        else:
            errors.append("not an FBX file (no FBX header)")
        notes.append("triangle count not read from FBX: run blender_check.py before exporting")
    elif kind in ("Image", "Decal"):
        dims = image_size(data, ext)
        if dims:
            width, height = dims
            notes.append(f"{width}x{height}")
            if width >= 8000 or height >= 8000:
                errors.append(f"{width}x{height}; images must be smaller than 8000x8000")
            if width > 1024 or height > 1024:
                warnings.append("over 1024 px: Roblox downsizes textures to 1024, upload at most 1024x1024")
        elif ext == ".png":
            errors.append("not a PNG file")
    elif kind == "Audio":
        warnings.append("audio: up to 7 minutes; 100 uploads a month with ID verification, 10 without")
    elif kind == "Video":
        warnings.append("video: up to 5 minutes, 4096x2160, 20 uploads a day (13+ and ID-verified)")
    return kind, content_type, errors, warnings, notes


def image_size(data, ext):
    if ext == ".png" and data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) >= 24:
        return struct.unpack(">II", data[16:24])
    if ext == ".bmp" and data[:2] == b"BM" and len(data) >= 26:
        width, height = struct.unpack_from("<ii", data, 18)
        return width, abs(height)
    if ext in (".jpg", ".jpeg") and data[:2] == b"\xff\xd8":
        offset = 2
        while offset + 9 < len(data):
            if data[offset] != 0xFF:
                offset += 1
                continue
            marker = data[offset + 1]
            length = struct.unpack(">H", data[offset + 2 : offset + 4])[0]
            if marker in (0xC0, 0xC1, 0xC2):
                height, width = struct.unpack(">HH", data[offset + 5 : offset + 9])
                return width, height
            offset += 2 + length
    if ext == ".tga" and len(data) >= 18:
        return struct.unpack_from("<HH", data, 12)
    return None


# Lock file and Luau ----------------------------------------------------------------------


def load_lock(path):
    try:
        with open(path, encoding="utf-8") as f:
            lock = json.load(f)
    except FileNotFoundError:
        lock = {}
    lock.setdefault("assets", {})
    return lock


def save_lock(path, lock):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(lock, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)


def lock_key(path):
    return os.path.relpath(os.path.abspath(path)).replace(os.sep, "/")


def luau_name(text):
    words = re.findall(r"[A-Za-z0-9]+", text)
    name = "".join(w[:1].upper() + w[1:] for w in words) or "Asset"
    return name if name[0].isalpha() else "Asset" + name


def render_luau(lock):
    groups = {"Models": {}, "Images": {}, "Audio": {}, "Video": {}}
    group_of = {"Model": "Models", "Image": "Images", "Decal": "Images", "Audio": "Audio", "Video": "Video"}
    for key in sorted(lock["assets"]):
        entry = lock["assets"][key]
        group = groups[group_of[entry["assetType"]]]
        name = luau_name(os.path.splitext(os.path.basename(key))[0])
        while name in group:
            name += "_"
        group[name] = entry["assetId"]
    lines = [
        "-- Generated by the roblox-bringforth skill (scripts/bringforth.py) from bringforth.lock.json.",
        "-- Do not edit by hand: upload again and the IDs here are rewritten.",
        "-- Models: numeric IDs for InsertService:LoadAsset. Images, Audio, Video: rbxassetid:// strings.",
        "",
        "local Assets = {}",
        "",
    ]
    for group, items in groups.items():
        if not items:
            lines.append(f"Assets.{group} = {{}}")
            continue
        lines.append(f"Assets.{group} = {{")
        for name, asset_id in items.items():
            value = str(int(asset_id)) if group == "Models" else f'"rbxassetid://{int(asset_id)}"'
            lines.append(f"\t{name} = {value},")
        lines.append("}")
    lines += ["", "return Assets", ""]
    return "\n".join(lines)


# Commands ----------------------------------------------------------------------------------


def cmd_check(paths, forced=None, log=print):
    failed = False
    for path in paths:
        try:
            kind, _, errors, warnings, notes = check_file(path, forced)
        except Fail as e:
            log(f"ERROR {e}")
            failed = True
            continue
        log(f"{'FAIL ' if errors else 'OK   '} {path}: {kind}{' (' + ', '.join(notes) + ')' if notes else ''}")
        for warning in warnings:
            log(f"WARN  {path}: {warning}")
        for error in errors:
            log(f"ERROR {path}: {error}")
        failed = failed or bool(errors)
    return 1 if failed else 0


def resolve_creator(args, client, log):
    group = args.group or setting("ROBLOX_CREATOR_GROUP_ID")
    user = args.user or setting("ROBLOX_CREATOR_USER_ID")
    info = None
    try:
        info = client.introspect()
    except Fail as e:
        log(f"WARN  could not introspect the key ({e}); continuing")
    authorized = key_report(info, log)
    if group:
        return {"groupId": int(group)}, f"group {group}"
    if user:
        return {"userId": int(user)}, f"user {user}"
    if authorized:
        return {"userId": int(authorized)}, f"user {authorized} (the key's owner)"
    raise Fail("no creator: pass --user <id> or --group <id> (or set ROBLOX_CREATOR_USER_ID / ROBLOX_CREATOR_GROUP_ID)")


def cmd_upload(args, client=None, log=print):
    lock_path = args.lock
    lock = load_lock(lock_path)
    plan = []
    for path in args.files:
        kind, content_type, errors, warnings, notes = check_file(path, args.type)
        for warning in warnings:
            log(f"WARN  {path}: {warning}")
        if errors:
            raise Fail(f"{path}: " + "; ".join(errors))
        with open(path, "rb") as f:
            data = f.read()
        plan.append((path, kind, content_type, data, hashlib.sha256(data).hexdigest()))

    todo = []
    for path, kind, content_type, data, digest in plan:
        entry = lock["assets"].get(lock_key(path))
        if entry and entry.get("sha256") == digest and entry.get("assetType") == kind and not args.force:
            log(f"SKIP  {path}: unchanged, asset {entry['assetId']}")
            continue
        todo.append((path, kind, content_type, data, digest, entry))
    if not todo:
        write_outputs(args, lock, log)
        log("nothing to upload")
        return lock

    if client is None:
        client = OpenCloud(api_key())
        warn_env_not_ignored(log)
    creator, creator_label = resolve_creator(args, client, log)

    for path, kind, content_type, data, digest, entry in todo:
        stem = os.path.splitext(os.path.basename(path))[0]
        name = (args.name if len(args.files) == 1 and args.name else stem)[:50]
        description = args.description or f"{stem}, uploaded with Bringforth"
        can_update = entry and kind == "Model" and path.lower().endswith(".fbx") and entry.get("assetType") == "Model"
        if can_update:
            request = {
                "assetId": int(entry["assetId"]),
                "creationContext": {"creator": creator, "expectedPrice": args.max_price},
            }
            log(f"UPDATE {path}: new version of asset {entry['assetId']}")
            operation = client.update(entry["assetId"], request, os.path.basename(path), content_type, data)
        else:
            if entry:
                log(f"WARN  {path}: changed, but Open Cloud can only update FBX models: uploading a new asset "
                    f"(the old one, {entry['assetId']}, stays)")
            request = {
                "assetType": kind,
                "displayName": name,
                "description": description,
                "creationContext": {"creator": creator, "expectedPrice": args.max_price},
            }
            log(f"UPLOAD {path}: {kind} {name!r} as {creator_label}")
            operation = client.create(request, os.path.basename(path), content_type, data)
        if not operation or not operation.get("path"):
            raise Fail(f"{path}: Roblox returned no operation: {operation}")
        response = operation.get("response") if operation.get("done") else None
        if response is None:
            response = client.operation(operation["path"], log=log)
        asset_id = int(response.get("assetId") or str(response.get("path", "")).rsplit("/", 1)[-1])
        state = (response.get("moderationResult") or {}).get("moderationState", "")
        version = response.get("revisionId") or "1"
        lock["assets"][lock_key(path)] = {
            "assetId": asset_id,
            "assetType": kind,
            "sha256": digest,
            "version": str(version),
            "name": name,
            "creator": creator,
            "uploadedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "moderation": state.replace("MODERATION_STATE_", "").lower() or "unknown",
        }
        save_lock(lock_path, lock)
        log(f"DONE  {path}: asset {asset_id} (version {version}, moderation {state or 'unknown'})")
        if kind == "Model":
            log(f"      Studio: game:GetService(\"InsertService\"):LoadAsset({asset_id}):GetChildren()[1].Parent = workspace")
        else:
            log(f"      rbxassetid://{asset_id}")
        if state.endswith("REJECTED"):
            log(f"WARN  {path}: moderation rejected the asset; it will not load in Studio or in game")
    write_outputs(args, lock, log)
    return lock


def write_outputs(args, lock, log):
    if args.luau:
        os.makedirs(os.path.dirname(args.luau) or ".", exist_ok=True)
        with open(args.luau, "w", encoding="utf-8", newline="\n") as f:
            f.write(render_luau(lock))
        log(f"wrote {args.luau}")


def cmd_grant(args, client=None, log=print):
    lock = load_lock(args.lock)
    ids = []
    for target in args.assets:
        if target.isdigit():
            ids.append(int(target))
        else:
            entry = lock["assets"].get(lock_key(target))
            if not entry:
                raise Fail(f"{target}: not in {args.lock}; upload it first or pass the asset ID")
            ids.append(entry["assetId"])
    client = client or OpenCloud(api_key())
    result = client.grant(args.universe, ids, not args.no_dependencies) or {}
    errors = result.get("errors") or []
    for error in errors:
        log(f"ERROR asset {error.get('assetId')}: {error.get('code') or error.get('message') or error}")
    granted = len(ids) - len(errors)
    log(f"granted Use on {granted} asset(s) to universe {args.universe}")
    return 1 if errors else 0


class FeedHandler(BaseHTTPRequestHandler):
    lock_path = LOCK_FILE

    def log_message(self, *args):
        pass

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path  # some clients send the absolute URL
        if path == "/health":
            return self.reply(200, {"ok": True})
        if path != "/assets":
            return self.reply(404, {"error": "use /assets"})
        lock = load_lock(self.lock_path)
        assets = [
            {"file": key, **{k: entry.get(k) for k in ("assetId", "assetType", "name", "version", "uploadedAt", "moderation")}}
            for key, entry in lock["assets"].items()
        ]
        assets.sort(key=lambda a: (a.get("uploadedAt") or "", a["file"]))
        return self.reply(200, {"assets": assets})

    def reply(self, status, payload):
        raw = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


def cmd_serve(args, ready=None):
    handler = type("Handler", (FeedHandler,), {"lock_path": os.path.abspath(args.lock)})
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    print(f"Bringforth feed on http://127.0.0.1:{server.server_address[1]}/assets (reads {args.lock}); Ctrl+C to stop")
    sys.stdout.flush()
    if ready:
        ready(server)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


def plugins_dir():
    if sys.platform.startswith("win"):
        base = os.environ.get("LOCALAPPDATA")
        return os.path.join(base, "Roblox", "Plugins") if base else None
    if sys.platform == "darwin":
        return os.path.expanduser("~/Documents/Roblox/Plugins")
    return None


def cmd_install_plugin(args, log=print):
    target = args.dir or plugins_dir()
    if not target:
        raise Fail("Roblox Studio runs on Windows and macOS: pass --dir with Studio's Plugins folder")
    os.makedirs(target, exist_ok=True)
    source = os.path.join(HERE, "..", "assets", "BringforthPlugin.lua")
    destination = os.path.join(target, "Bringforth.lua")
    shutil.copyfile(source, destination)
    log(f"installed {destination}: restart Studio (or Plugins > Plugins Folder > reload) to load it")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("whoami")
    p = sub.add_parser("check")
    p.add_argument("files", nargs="+")
    p.add_argument("--type", choices=TYPE_CHOICES)
    p = sub.add_parser("upload")
    p.add_argument("files", nargs="+")
    p.add_argument("--name")
    p.add_argument("--description")
    p.add_argument("--type", choices=TYPE_CHOICES)
    creator = p.add_mutually_exclusive_group()
    creator.add_argument("--group", type=int)
    creator.add_argument("--user", type=int)
    p.add_argument("--max-price", type=int, default=0, help="highest upload fee in Robux to accept (default 0)")
    p.add_argument("--force", action="store_true", help="upload even if the file did not change")
    p.add_argument("--luau", help="also write a Luau module with every uploaded ID (e.g. src/shared/Assets.luau)")
    p.add_argument("--lock", default=LOCK_FILE)
    p = sub.add_parser("grant")
    p.add_argument("assets", nargs="+")
    p.add_argument("--universe", type=int, required=True)
    p.add_argument("--no-dependencies", action="store_true")
    p.add_argument("--lock", default=LOCK_FILE)
    p = sub.add_parser("serve")
    p.add_argument("--port", type=int, default=DEFAULT_PORT)
    p.add_argument("--lock", default=LOCK_FILE)
    p = sub.add_parser("install-plugin")
    p.add_argument("--dir")
    args = parser.parse_args(argv)
    try:
        if args.command == "whoami":
            whoami(OpenCloud(api_key()))
            return 0
        if args.command == "check":
            return cmd_check(args.files, args.type)
        if args.command == "upload":
            cmd_upload(args)
            return 0
        if args.command == "grant":
            return cmd_grant(args)
        if args.command == "serve":
            return cmd_serve(args)
        if args.command == "install-plugin":
            return cmd_install_plugin(args)
    except Fail as e:
        print(f"ERROR {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
