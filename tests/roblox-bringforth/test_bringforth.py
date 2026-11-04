#!/usr/bin/env python3
"""roblox-bringforth: make_model.py, bringforth.py against a local mock of the Open Cloud Assets API
(multipart create/update, long-running operations, key introspection, asset permissions), the
local feed (`serve`) and the Studio plugin running on Lune against that feed.

Follows create.roblox.com/docs/cloud/openapi.json and the Assets usage guide.
Usage: test_bringforth.py <skill dir> <workdir> [lune binary]   (exit 1 on failure)
"""

import email.parser
import email.policy
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import threading
import time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import urlopen

SKILL, WORK = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
LUNE = sys.argv[3] if len(sys.argv) > 3 else shutil.which("lune")
BRING = os.path.abspath(os.path.join(SKILL, "scripts/bringforth.py"))
MAKE = os.path.abspath(os.path.join(SKILL, "scripts/make_model.py"))
API_KEY = "bf-key-SECRET-abcdef0123456789"
OWNER = 555

passed = failed = 0


def check(condition, message, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print(f"  ok   {message}")
    else:
        failed += 1
        print(f"  FAIL {message}")
        if detail:
            print("       " + str(detail).replace("\n", "\n       ")[:3000])


# Mock Open Cloud ---------------------------------------------------------------------------


class State:
    def __init__(self):
        self.lock = threading.Lock()
        self.requests = []
        self.assets = {}
        self.operations = {}
        self.next_asset = 7000
        self.next_op = 0
        self.expires = (datetime.now(timezone.utc) + timedelta(days=5)).isoformat().replace("+00:00", "Z")
        self.scopes = [{"name": "asset", "operations": ["read", "write"], "userIds": ["*"], "groupIds": ["*"]}]


state = State()


def parse_multipart(content_type, body):
    message = email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(
        b"Content-Type: " + content_type.encode() + b"\r\n\r\n" + body
    )
    fields, files = {}, {}
    for part in message.iter_parts():
        name = part.get_param("name", header="content-disposition")
        if part.get_filename():
            files[name] = {"filename": part.get_filename(), "type": part.get_content_type(), "data": part.get_payload(decode=True)}
        else:
            fields[name] = part.get_payload(decode=True).decode()
    return fields, files


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status, payload=None):
        raw = b"" if payload is None else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def handle_any(self, method):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        content_type = self.headers.get("Content-Type") or ""
        fields, files, payload = {}, {}, None
        if content_type.startswith("multipart/"):
            fields, files = parse_multipart(content_type, body)
        elif body:
            payload = json.loads(body)
        with state.lock:
            state.requests.append(
                {"method": method, "path": self.path, "fields": fields, "files": files, "json": payload, "key": self.headers.get("x-api-key")}
            )
            if self.path == "/api-keys/v1/introspect" and method == "POST":
                if (payload or {}).get("apiKey") != API_KEY:
                    return self.reply(401, {"message": "Invalid API Key"})
                return self.reply(200, {
                    "name": "bringforth", "authorizedUserId": OWNER, "scopes": state.scopes,
                    "enabled": True, "expired": False, "expirationTimeUtc": state.expires,
                })
            if self.headers.get("x-api-key") != API_KEY:
                return self.reply(401, {"code": "UNAUTHENTICATED", "message": "Invalid API Key"})
            if self.path == "/assets/v1/assets" and method == "POST":
                request = json.loads(fields["request"])
                for required in ("assetType", "displayName", "description", "creationContext"):
                    if required not in request:
                        return self.reply(400, {"message": f"{required} is required"})
                if "fileContent" not in files:
                    return self.reply(400, {"message": "fileContent is required"})
                state.next_asset += 1
                asset_id = state.next_asset
                bad = request["displayName"].startswith("Rejected")
                state.assets[asset_id] = {"request": request, "version": 1, "file": files["fileContent"], "rejected": bad}
                return self.reply(200, self.new_operation(asset_id, error=bad))
            match = re.fullmatch(r"/assets/v1/assets/(\d+)", self.path)
            if match and method == "PATCH":
                asset = state.assets.get(int(match.group(1)))
                if not asset:
                    return self.reply(404, {"message": "asset not found"})
                asset["version"] += 1
                asset["file"] = files.get("fileContent")
                asset["patch"] = json.loads(fields["request"])
                return self.reply(200, self.new_operation(int(match.group(1))))
            match = re.fullmatch(r"/assets/v1/operations/(op-\d+)", self.path)
            if match and method == "GET":
                op = state.operations.get(match.group(1))
                if not op:
                    return self.reply(404, {"message": "operation not found"})
                op["polls"] += 1
                if op["polls"] < 2:
                    return self.reply(200, {"path": f"operations/{match.group(1)}", "done": False})
                if op["error"]:
                    return self.reply(200, {"path": f"operations/{match.group(1)}", "done": True,
                                            "error": {"code": 3, "message": "Asset name or description was moderated"}})
                asset = state.assets[op["asset"]]
                return self.reply(200, {
                    "path": f"operations/{match.group(1)}",
                    "done": True,
                    "response": {
                        "@type": "type.googleapis.com/roblox.open_cloud.assets.v1.Asset",
                        "path": f"assets/{op['asset']}",
                        "assetId": str(op["asset"]),
                        "revisionId": str(asset["version"]),
                        "assetType": "ASSET_TYPE_" + asset["request"]["assetType"].upper(),
                        "moderationResult": {"moderationState": "MODERATION_STATE_APPROVED"},
                    },
                })
            if self.path == "/asset-permissions-api/v1/assets/permissions" and method == "PATCH":
                if not any(s["name"] == "asset-permissions" for s in state.scopes):
                    return self.reply(403, {"message": "Insufficient scope"})
                errors = [{"assetId": r["assetId"], "code": "AssetNotFound"} for r in payload["requests"] if r["assetId"] not in state.assets]
                return self.reply(200, {"errors": errors})
            return self.reply(404, {"message": "no route"})

    def new_operation(self, asset_id, error=False):
        state.next_op += 1
        name = f"op-{state.next_op}"
        state.operations[name] = {"asset": asset_id, "polls": 0, "error": error}
        return {"path": f"operations/{name}", "done": False}

    def do_GET(self):
        self.handle_any("GET")

    def do_POST(self):
        self.handle_any("POST")

    def do_PATCH(self):
        self.handle_any("PATCH")


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{server.server_address[1]}"

project = os.path.join(WORK, "game")
shutil.rmtree(project, ignore_errors=True)
os.makedirs(os.path.join(project, "models"))


def env(key=API_KEY, extra=None):
    e = {k: v for k, v in os.environ.items() if not k.startswith("ROBLOX_")}
    e["ROBLOX_OPEN_CLOUD_URL"] = BASE
    if key is not None:
        e["ROBLOX_API_KEY"] = key
    e.update(extra or {})
    return e


def run(script, *args, key=API_KEY, extra=None):
    result = subprocess.run(
        [sys.executable, "-I", script, *args], cwd=project, env=env(key, extra), capture_output=True, text=True, timeout=120
    )
    return result.returncode, result.stdout + result.stderr


def bring(*args, **kw):
    return run(BRING, *args, **kw)


def writes(kind=None):
    return [r for r in state.requests if r["method"] != "GET" and (kind is None or r["path"].startswith(kind))]


def lock():
    return json.load(open(os.path.join(project, "bringforth.lock.json")))


def no_key(text):
    return API_KEY not in text and "SECRET" not in text


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, length = struct.unpack_from("<4sII", data)
    json_len, json_type = struct.unpack_from("<I4s", data, 12)
    doc = json.loads(data[20 : 20 + json_len])
    bin_len, bin_type = struct.unpack_from("<I4s", data, 20 + json_len)
    return magic, version, length, len(data), json_type, bin_type, doc, bin_len


# make_model --------------------------------------------------------------------------------

print("make_model.py")
for example in ("lowpoly_tree", "treasure_chest", "lamp_post"):
    spec = os.path.join(SKILL, "assets/examples", f"{example}.json")
    out = os.path.join(project, "models", f"{example}.glb")
    code, text = run(MAKE, spec, "-o", out, "--preview", os.path.join(project, f"{example}.png"))
    check(code == 0 and "studs" in text and os.path.exists(out), f"{example}: built ({text.split(': ', 1)[-1].splitlines()[0]})", text)
    magic, version, length, size, json_type, bin_type, doc, bin_len = read_glb(out)
    check(magic == b"glTF" and version == 2 and length == size, f"{example}: GLB header and length")
    check(json_type == b"JSON" and bin_type == b"BIN\x00" and doc["buffers"][0]["byteLength"] == bin_len, f"{example}: JSON + BIN chunks")
    views_ok = all(v["byteOffset"] % 4 == 0 and v["byteOffset"] + v["byteLength"] <= bin_len for v in doc["bufferViews"])
    check(views_ok, f"{example}: buffer views aligned and in range")
    colors = {tuple(m["pbrMetallicRoughness"]["baseColorFactor"]) for m in doc["materials"]}
    check(len(doc["meshes"]) == len(colors) == len(doc["materials"]), f"{example}: one mesh per color/material ({len(doc['meshes'])})")
    pos = [doc["accessors"][m["primitives"][0]["attributes"]["POSITION"]] for m in doc["meshes"]]
    low_y = min(a["min"][1] for a in pos)
    check(abs(low_y) < 1e-6, f"{example}: pivot at the bottom (min Y = {low_y:.4f})")
from PIL import Image  # noqa: E402

with Image.open(os.path.join(project, "lowpoly_tree.png")) as image:
    colors = image.convert("RGB").getcolors(512 * 512)
    greens = sum(count for count, (r, g, b) in colors if g > r + 30 and g > b + 30)
    check(image.size == (512, 512) and greens > 8000, f"preview renders the tree's crown ({greens} green pixels)")

with open(os.path.join(project, "bad_shape.json"), "w") as f:
    json.dump({"parts": [{"shape": "torus", "size": [1, 1, 1]}]}, f)
code, text = run(MAKE, "bad_shape.json")
check(code == 1 and "shape must be one of" in text, "unknown shape rejected", text)
with open(os.path.join(project, "bad_size.json"), "w") as f:
    json.dump({"parts": [{"shape": "box", "size": [1, 0, 1]}, {"shape": "box", "size": [1, 1, 1], "color": "red"}]}, f)
code, text = run(MAKE, "bad_size.json")
check(code == 1 and "size must be above 0" in text, "zero size rejected", text)
with open(os.path.join(project, "heavy.json"), "w") as f:
    json.dump({"parts": [{"shape": "sphere", "size": [2, 2, 2], "position": [i * 3, 0, 0], "segments": 48} for i in range(10)]}, f)
code, text = run(MAKE, "heavy.json")
check(code == 1 and "triangles (limit 20,000)" in text, "a mesh over 20,000 triangles is refused", text)

# check -------------------------------------------------------------------------------------

print("bringforth.py check")
code, text = bring("check", "models/lowpoly_tree.glb", "models/treasure_chest.glb")
check(code == 0 and "OK    models/lowpoly_tree.glb: Model (2 meshes, 66 triangles)" in text, "generated GLBs pass", text)
open(os.path.join(project, "rock.obj"), "w").write("v 0 0 0\n")
code, text = bring("check", "rock.obj")
check(code == 1 and "does not take OBJ" in text and "glTF Binary" in text, "OBJ: explains how to convert", text)
open(os.path.join(project, "fake.glb"), "wb").write(b"not a glb at all, sorry")
code, text = bring("check", "fake.glb")
check(code == 1 and "bad header" in text, "broken GLB rejected", text)
heavy = {"asset": {"version": "2.0"}, "meshes": [{"name": "Cliff", "primitives": [{"attributes": {"POSITION": 0}, "indices": 1, "material": 0}, {"attributes": {"POSITION": 0}, "indices": 1, "material": 1}]}],
         "accessors": [{"count": 30000}, {"count": 45000}], "buffers": [{"uri": "cliff.bin", "byteLength": 1}]}
json.dump(heavy, open(os.path.join(project, "cliff.gltf"), "w"))
code, text = bring("check", "cliff.gltf")
check("mesh 'Cliff' has 30,000 triangles" in text, "per-mesh triangle limit from glTF accessors", text)
check("uses 2 materials" in text, "several materials on one mesh warned", text)
check("external files (cliff.bin)" in text and code == 1, "separate .gltf buffers rejected (needs .glb)", text)
with open(os.path.join(project, "huge.png"), "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n" + struct.pack(">I4sII", 13, b"IHDR", 9000, 9000) + b"\x08\x06\x00\x00\x00" + b"\x00" * 64)
code, text = bring("check", "huge.png")
check(code == 1 and "9000x9000; images must be smaller than 8000x8000" in text, "image over 8000 px rejected", text)
with open(os.path.join(project, "big.fbx"), "wb") as f:
    f.write(b"Kaydara FBX Binary  \x00\x1a\x00" + struct.pack("<I", 7400))
    f.truncate(21 * 1024 * 1024)
code, text = bring("check", "big.fbx")
check(code == 1 and "limited to 20 MB" in text, "file over 20 MB rejected", text)

# upload ------------------------------------------------------------------------------------

print("bringforth.py upload")
Image.new("RGB", (512, 512), (200, 60, 60)).save(os.path.join(project, "models", "lava_texture.png"))
with open(os.path.join(project, "models", "rock.fbx"), "wb") as f:
    f.write(b"Kaydara FBX Binary  \x00\x1a\x00" + struct.pack("<I", 7400) + b"\x00" * 200)
code, text = bring("upload", "models/rock.fbx", key=None)
check(code == 1 and "no API key" in text and "Never paste it" in text, "no key: clear instructions", text)
code, text = bring("upload", "models/rock.fbx", key="wrong-key", extra={"ROBLOX_CREATOR_USER_ID": "1"})
check(code == 1 and "HTTP 401" in text and "wrong-key" not in text, "bad key: 401 explained, key not echoed", text)

files = ["models/lowpoly_tree.glb", "models/rock.fbx", "models/lava_texture.png"]
code, text = bring("upload", *files, "--luau", "src/shared/Assets.luau")
check(code == 0 and text.count("DONE") == 3, "3 files uploaded and their operations polled until done", text)
check(no_key(text), "key never printed")
check("expires in 5 days" in text or "expires in 4 days" in text, "expiry within 14 days warned", text)
creates = writes("/assets/v1/assets")
req = {json.loads(r["fields"]["request"])["displayName"]: (json.loads(r["fields"]["request"]), r["files"]["fileContent"]) for r in creates}
tree_req, tree_file = req["lowpoly_tree"]
check(tree_req["assetType"] == "Model" and tree_file["type"] == "model/gltf-binary", "GLB -> Model, model/gltf-binary")
check(req["rock"][0]["assetType"] == "Model" and req["rock"][1]["type"] == "model/fbx", "FBX -> Model, model/fbx")
check(req["lava_texture"][0]["assetType"] == "Decal" and req["lava_texture"][1]["type"] == "image/png", "PNG -> Decal, image/png")
check(tree_req["creationContext"] == {"creator": {"userId": OWNER}, "expectedPrice": 0}, "creator from key introspection, expectedPrice 0", tree_req)
check(tree_req["description"] and open(os.path.join(project, files[0]), "rb").read() == tree_file["data"], "description set, file sent byte for byte")
lk = lock()
check(len(lk["assets"]) == 3 and all(e["moderation"] == "approved" and e["version"] == "1" for e in lk["assets"].values()), "lock: 3 assets, approved, version 1")
luau = open(os.path.join(project, "src/shared/Assets.luau")).read()
tree_id = lk["assets"]["models/lowpoly_tree.glb"]["assetId"]
check(f"LowpolyTree = {tree_id}," in luau and 'LavaTexture = "rbxassetid://' in luau, "Luau module: model IDs and rbxassetid strings", luau)
check(f"LoadAsset({tree_id})" in text, "prints the Studio insert line")

before = len(writes("/assets/"))
code, text = bring("upload", *files)
check(code == 0 and text.count("SKIP") == 3 and len(writes("/assets/")) == before, "unchanged files are not uploaded again", text)

with open(os.path.join(project, "models", "rock.fbx"), "ab") as f:
    f.write(b"changed")
rock_id = lk["assets"]["models/rock.fbx"]["assetId"]
code, text = bring("upload", "models/rock.fbx")
check(code == 0 and f"new version of asset {rock_id}" in text, "changed FBX -> PATCH, same asset", text)
patch = [r for r in writes() if r["method"] == "PATCH" and r["path"] == f"/assets/v1/assets/{rock_id}"]
check(patch and json.loads(patch[-1]["fields"]["request"])["assetId"] == rock_id and patch[-1]["files"]["fileContent"]["type"] == "model/fbx", "PATCH sends assetId + new fileContent")
check(lock()["assets"]["models/rock.fbx"]["version"] == "2" and lock()["assets"]["models/rock.fbx"]["assetId"] == rock_id, "lock: version 2, same ID")

spec = json.load(open(os.path.join(SKILL, "assets/examples/lowpoly_tree.json")))
spec["parts"][0]["color"] = "#553311"
json.dump(spec, open(os.path.join(project, "tree2.json"), "w"))
run(MAKE, "tree2.json", "-o", "models/lowpoly_tree.glb")
code, text = bring("upload", "models/lowpoly_tree.glb")
new_tree = lock()["assets"]["models/lowpoly_tree.glb"]["assetId"]
check(code == 0 and "can only update FBX models" in text and new_tree != tree_id, "changed GLB -> new asset, old one kept and named", text)

code, text = bring("upload", "models/treasure_chest.glb", "--group", "777", "--name", "Treasure Chest")
last = json.loads(writes("/assets/v1/assets")[-1]["fields"]["request"])
check(code == 0 and last["creationContext"]["creator"] == {"groupId": 777} and last["displayName"] == "Treasure Chest", "--group and --name", text)

shutil.copy(os.path.join(project, "models/treasure_chest.glb"), os.path.join(project, "models/Rejected_chest.glb"))
code, text = bring("upload", "models/Rejected_chest.glb")
check(code == 1 and "upload failed: Asset name or description was moderated" in text, "failed operation reported", text)
check("models/Rejected_chest.glb" not in lock()["assets"], "failed upload not recorded")

# whoami, grant -------------------------------------------------------------------------------

print("whoami and grant")
code, text = bring("whoami")
check(code == 0 and "'bringforth'" in text and "scope     asset: read,write" in text and "60 days" in text, "whoami: name, scopes, 60-day rule", text)
check("no asset-permissions write permission" in text and no_key(text), "whoami warns about missing asset-permissions", text)
code, text = bring("grant", "models/rock.fbx", "--universe", "4242")
check(code == 1 and "HTTP 403" in text and "asset-permissions write" in text, "grant without the permission: 403 explained", text)
state.scopes.append({"name": "asset-permissions", "operations": ["write"]})
code, text = bring("grant", "models/rock.fbx", str(new_tree), "--universe", "4242")
body = writes("/asset-permissions-api")[-1]["json"]
check(code == 0 and "granted Use on 2 asset(s) to universe 4242" in text, "grant by file and by ID", text)
check(body == {"subjectType": "Universe", "subjectId": "4242", "action": "Use",
               "requests": [{"assetId": rock_id, "grantToDependencies": True}, {"assetId": new_tree, "grantToDependencies": True}]},
      "grant body: Universe / Use / requests with dependencies", body)
code, text = bring("grant", "999999", "--universe", "4242")
check(code == 1 and "AssetNotFound" in text, "per-asset grant errors reported", text)

# .env and install-plugin ----------------------------------------------------------------------

print(".env and plugin install")
with open(os.path.join(project, ".env"), "w") as f:
    f.write(f"ROBLOX_OPEN_CLOUD_API_KEY='{API_KEY}'\n")
code, text = bring("whoami", key=None)
check(code == 0 and "'bringforth'" in text, "key from .env (ROBLOX_OPEN_CLOUD_API_KEY)", text)
os.utime(os.path.join(project, "models/treasure_chest.glb"))
code, text = bring("upload", "models/treasure_chest.glb", "--force", key=None)
check(code == 0 and ".env is not in .gitignore" in text and no_key(text), "upload warns while .env is not git-ignored", text)
plugins = os.path.join(WORK, "Plugins")
code, text = bring("install-plugin", "--dir", plugins)
check(code == 0 and os.path.exists(os.path.join(plugins, "Bringforth.lua")), "install-plugin copies Bringforth.lua", text)
if not sys.platform.startswith(("win", "darwin")):
    code, text = bring("install-plugin")
    check(code == 1 and "--dir" in text, "no Studio plugins folder on Linux: asks for --dir", text)

# serve + Studio plugin ------------------------------------------------------------------------

print("feed + Studio plugin")
feed = subprocess.Popen([sys.executable, "-I", BRING, "serve", "--port", "0"], cwd=project, env=env(), stdout=subprocess.PIPE, text=True)
line = feed.stdout.readline()
port = int(re.search(r"127\.0\.0\.1:(\d+)", line).group(1))
data = json.loads(urlopen(f"http://127.0.0.1:{port}/assets").read())
models = [a for a in data["assets"] if a["assetType"] == "Model"]
check(len(data["assets"]) == 4 and len(models) == 3, "feed lists every upload from the lock file", data)
check(all("sha256" not in a and "creator" not in a for a in data["assets"]), "feed exposes only IDs and names")

if LUNE:
    result = subprocess.run(
        [LUNE, "run", os.path.join(os.path.dirname(os.path.abspath(__file__)), "plugin_test.luau"),
         os.path.join(SKILL, "assets/BringforthPlugin.lua"), f"http://127.0.0.1:{port}", os.path.join(project, "bringforth.lock.json")],
        capture_output=True, text=True, timeout=90,
    )
    print(result.stdout.rstrip())
    match = re.search(r"(\d+) passed, (\d+) failed", result.stdout)
    if match:
        passed += int(match.group(1))
        failed += int(match.group(2))
    if result.returncode != 0 or not match:
        failed += 1
        print("  FAIL plugin test did not finish cleanly\n" + result.stderr[-2000:])
else:
    print("  lune not installed: Studio plugin test skipped")
feed.terminate()
feed.wait(5)

server.shutdown()
print()
print(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
