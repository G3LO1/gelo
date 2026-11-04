#!/usr/bin/env python3
"""Creates and updates a Roblox game's game passes and developer products through Open Cloud,
uploads their icons, and writes the IDs into a Luau module the game reads.

Usage (paths are relative to the current folder; the manifest's own paths are relative to it):
  monetize.py check   [--manifest monetization.json]           validate manifest + icons
  monetize.py prompts [--manifest ...]                          icon prompts for an image generator
  monetize.py icons   [--manifest ...] [--placeholder] [--force] make missing icons (placeholder art)
  monetize.py sync    [--manifest ...] [--dry-run]              create/update in Roblox, write lock + Luau
  monetize.py luau    [--manifest ...]                          rewrite the Luau module from the lock file

Secrets: the Open Cloud API key is read from ROBLOX_API_KEY, or from a .env file next to the
manifest or in the current folder (ROBLOX_API_KEY=...). It is never printed or written anywhere.
The key needs the game-pass (read, write) and developer-product (read, write) permissions for
this experience. The universe ID comes from the manifest ("universeId") or ROBLOX_UNIVERSE_ID.

sync is idempotent: IDs are kept in the lock file (commit it), an item without an ID is first
looked up by its exact name (so a crashed run never creates duplicates), and only changed
fields are sent. Icons are re-uploaded only when the image changes. Needs Python 3.9+, and
Pillow for icons (pip install pillow).
"""

import argparse
import hashlib
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

BASE_URL = os.environ.get("ROBLOX_OPEN_CLOUD_URL", "https://apis.roblox.com").rstrip("/")
USER_AGENT = "roblox-studio-monetize/1.0"

KINDS = {
    "pass": {
        "label": "game pass",
        "luau": "Pass",
        "base": "/game-passes/v1/universes/{universe}/game-passes",
        "get": "/game-passes/v1/universes/{universe}/game-passes/{id}/creator",
        "list": "/game-passes/v1/universes/{universe}/game-passes/creator",
        "list_key": "gamePasses",
        "id_field": "gamePassId",
        "icon_field": "iconAssetId",
        "scope": "game-pass",
        "write_interval": 0.25,  # 5 writes/s per API key owner
    },
    "product": {
        "label": "developer product",
        "luau": "Product",
        "base": "/developer-products/v2/universes/{universe}/developer-products",
        "get": "/developer-products/v2/universes/{universe}/developer-products/{id}/creator",
        "list": "/developer-products/v2/universes/{universe}/developer-products/creator",
        "list_key": "developerProducts",
        "id_field": "productId",
        "icon_field": "iconImageAssetId",
        "scope": "developer-product",
        "write_interval": 0.4,  # 3 writes/s per API key owner
    },
}

GRANTS = {
    "product": {"currency", "handler"},
    "pass": {"perk", "multiplier", "handler"},
}

KEY_RE = re.compile(r"^[A-Z][A-Za-z0-9_]{0,39}$")
FIELD_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
NAME_LIMIT = 50
DESCRIPTION_LIMIT = 1000
ICON_SIZE = 512
ICON_FORMATS = {"PNG", "JPEG", "BMP"}


class Fail(Exception):
    pass


class HttpFail(Fail):
    def __init__(self, message, status):
        super().__init__(message)
        self.status = status


# Manifest --------------------------------------------------------------------


def load_manifest(path):
    try:
        with open(path, encoding="utf-8") as f:
            manifest = json.load(f)
    except FileNotFoundError:
        raise Fail(f"{path} not found (copy assets/monetization.example.json to start)")
    except json.JSONDecodeError as e:
        raise Fail(f"{path}: invalid JSON: {e}")
    root = os.path.dirname(os.path.abspath(path))
    manifest.setdefault("items", [])
    manifest.setdefault("lockFile", "monetization.lock.json")
    manifest.setdefault("luauOutput", "src/shared/Monetization.luau")
    manifest.setdefault("iconsDir", "icons")
    manifest["_root"] = root
    manifest["_path"] = path
    for index, item in enumerate(manifest["items"]):
        if isinstance(item, dict):
            item.setdefault("description", "")
            item.setdefault("forSale", True)
            item.setdefault("managedPricing", False)
            item.setdefault("icon", f"{manifest['iconsDir']}/{item.get('key', index)}.png")
            item.setdefault("grant", {"type": "perk"} if item.get("kind") == "pass" else {"type": "handler"})
            item["_order"] = index + 1
    return manifest


def resolve(manifest, relative):
    return os.path.normpath(os.path.join(manifest["_root"], relative))


def validate(manifest, check_icons=True):
    """Returns (errors, warnings) as lists of strings."""
    errors, warnings = [], []
    items = manifest["items"]
    if not isinstance(items, list) or not items:
        errors.append("items: add at least one game pass or developer product")
        return errors, warnings
    universe = manifest.get("universeId")
    if universe is not None and not (isinstance(universe, int) and universe > 0):
        errors.append("universeId must be a positive integer (Creator Hub > experience > ... > Copy Universe ID)")
    keys, names = set(), set()
    for index, item in enumerate(items):
        where = f"items[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{where}: must be an object")
            continue
        key = item.get("key")
        if not isinstance(key, str) or not KEY_RE.match(key):
            errors.append(f"{where}: key {key!r} must be a PascalCase Luau identifier (e.g. DoubleCash)")
        else:
            where = key
            if key in keys:
                errors.append(f"{key}: duplicate key")
            keys.add(key)
        kind = item.get("kind")
        if kind not in KINDS:
            errors.append(f"{where}: kind must be 'pass' (bought once) or 'product' (bought again and again)")
            continue
        name = item.get("name")
        if not isinstance(name, str) or not name.strip():
            errors.append(f"{where}: name is required")
        else:
            if len(name) > NAME_LIMIT:
                errors.append(f"{where}: name is {len(name)} characters, keep it at most {NAME_LIMIT}")
            if (kind, name) in names:
                errors.append(f"{where}: two {KINDS[kind]['label']}s named {name!r} (sync matches existing items by name)")
            names.add((kind, name))
        description = item.get("description")
        if not isinstance(description, str):
            errors.append(f"{where}: description must be a string")
        elif len(description) > DESCRIPTION_LIMIT:
            errors.append(f"{where}: description is {len(description)} characters, limit is {DESCRIPTION_LIMIT}")
        price = item.get("price")
        if isinstance(price, bool) or not isinstance(price, int) or price < 1:
            errors.append(f"{where}: price must be a whole number of Robux, at least 1")
        elif price > 100000:
            warnings.append(f"{where}: price {price} Robux is unusually high, check for a typo")
        for flag in ("forSale", "managedPricing"):
            if not isinstance(item.get(flag), bool):
                errors.append(f"{where}: {flag} must be true or false")
        errors.extend(validate_grant(where, kind, item.get("grant")))
        if check_icons:
            errors_icon, warnings_icon = check_icon(resolve(manifest, item["icon"]), kind)
            errors.extend(f"{where}: {message}" for message in errors_icon)
            warnings.extend(f"{where}: {message}" for message in warnings_icon)
    return errors, warnings


def validate_grant(where, kind, grant):
    if not isinstance(grant, dict) or grant.get("type") not in GRANTS[kind]:
        allowed = ", ".join(sorted(GRANTS[kind]))
        hint = (
            " (a pass is bought once: give perks or multipliers, not currency)"
            if kind == "pass"
            else " (a product is consumed: give currency or run a handler; multipliers belong on a pass)"
        )
        return [f"{where}: grant.type must be one of {allowed}{hint}"]
    errors = []
    kind_of = grant["type"]
    if kind_of == "currency":
        if not isinstance(grant.get("field"), str) or not FIELD_RE.match(grant["field"]):
            errors.append(f"{where}: grant.field must name a number field in Config.DefaultData (e.g. Coins)")
        amount = grant.get("amount")
        if isinstance(amount, bool) or not isinstance(amount, int) or amount < 1:
            errors.append(f"{where}: grant.amount must be a positive whole number")
    elif kind_of == "multiplier":
        if not isinstance(grant.get("stat"), str) or not FIELD_RE.match(grant["stat"]):
            errors.append(f"{where}: grant.stat must be an identifier (e.g. Cash, Size, Speed)")
        value = grant.get("value")
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not 1 < value <= 100:
            errors.append(f"{where}: grant.value must be a number above 1 (2 = double, 1.25 = +25%)")
    for extra in grant:
        if extra not in ("type", "field", "amount", "stat", "value"):
            errors.append(f"{where}: grant.{extra} is not a known field")
    return errors


# Icons -----------------------------------------------------------------------


def pillow():
    try:
        import PIL.Image  # noqa: F401
    except ImportError:
        raise Fail("Pillow is required for icons: pip install pillow")


def check_icon(path, kind):
    if not os.path.exists(path):
        return [f"icon {path} is missing (generate it, or run `monetize.py icons --placeholder`)"], []
    pillow()
    from PIL import Image, ImageStat

    try:
        with Image.open(path) as image:
            image.load()
            fmt, size = image.format, image.size
            rgb = image.convert("RGB")
    except Exception as e:  # noqa: BLE001 - any decoder error means Roblox rejects it too
        return [f"icon {path} is not a readable image ({e})"], []
    errors, warnings = [], []
    if fmt not in ICON_FORMATS:
        errors.append(f"icon is {fmt}; upload PNG, JPEG or BMP")
    width, height = size
    if abs(width - height) > max(width, height) * 0.02:
        warnings.append(f"icon is {width}x{height}, not square: sync center-crops it")
    if min(width, height) < ICON_SIZE:
        warnings.append(f"icon is {width}x{height}; use at least {ICON_SIZE}x{ICON_SIZE} so it stays sharp")
    if max(ImageStat.Stat(rgb.resize((64, 64))).stddev) < 12:
        warnings.append("icon is almost one flat color: it will not read in the shop or purchase prompt")
    if kind == "pass":
        # Roblox shows game pass icons in a circle: content in the corners is cut off.
        corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
        center = rgb.getpixel((width // 2, height // 2))
        if all(distance(rgb.getpixel(c), center) > 120 for c in corners):
            warnings.append("pass icons are shown as a circle: keep the art inside the middle 80%")
    return errors, warnings


def distance(a, b):
    return sum(abs(x - y) for x, y in zip(a, b))


def normalized_icon(path):
    """Square, 512x512 PNG bytes: what is uploaded and hashed."""
    pillow()
    from PIL import Image

    with Image.open(path) as image:
        image = image.convert("RGBA")
    width, height = image.size
    side = min(width, height)
    left, top = (width - side) // 2, (height - side) // 2
    image = image.crop((left, top, left + side, top + side))
    if side != ICON_SIZE:
        image = image.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS)
    out = io.BytesIO()
    image.save(out, "PNG", optimize=True)
    return out.getvalue()


PALETTE = [
    ((255, 196, 0), (255, 102, 0)),
    ((0, 214, 143), (0, 122, 204)),
    ((255, 85, 170), (136, 51, 255)),
    ((90, 200, 255), (40, 80, 230)),
    ((255, 120, 90), (210, 30, 60)),
    ((170, 230, 60), (30, 150, 70)),
]


def placeholder_icon(item, path):
    """Readable stand-in art (gradient, badge, big label) so the pipeline works before real art exists."""
    pillow()
    from PIL import Image, ImageDraw, ImageFont

    size = ICON_SIZE
    top, bottom = PALETTE[int(hashlib.sha256(item["key"].encode()).hexdigest(), 16) % len(PALETTE)]
    image = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(image)
    for y in range(size):
        t = y / (size - 1)
        draw.line([(0, y), (size, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    margin = int(size * 0.12)
    draw.ellipse([margin, margin, size - margin, size - margin], outline=(255, 255, 255), width=18)
    label = short_label(item)
    font = load_font(150 if len(label) <= 3 else 110 if len(label) <= 5 else 78)
    box = draw.textbbox((0, 0), label, font=font, stroke_width=10)
    x = (size - (box[2] - box[0])) / 2 - box[0]
    y = (size - (box[3] - box[1])) / 2 - box[1]
    draw.text((x, y), label, font=font, fill=(255, 255, 255), stroke_width=10, stroke_fill=(30, 30, 40))
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    image.save(path, "PNG")


def short_label(item):
    grant = item.get("grant") or {}
    if grant.get("type") == "multiplier":
        value = grant["value"]
        if value >= 2 and float(value).is_integer():
            return f"{int(value)}x"
        return f"+{round((value - 1) * 100)}%"
    if grant.get("type") == "currency":
        amount = grant["amount"]
        return f"{amount // 1000}K" if amount >= 1000 and amount % 1000 == 0 else str(amount)
    words = re.findall(r"[A-Za-z0-9]+", item.get("name") or item["key"])
    return "".join(w[0] for w in words[:3]).upper() or "?"


def load_font(px):
    from PIL import ImageFont

    for name in ("DejaVuSans-Bold.ttf", "Arial Bold.ttf", "arialbd.ttf", "LiberationSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, px)
        except OSError:
            continue
    try:
        return ImageFont.load_default(size=px)
    except TypeError:  # Pillow < 10.1
        return ImageFont.load_default()


def icon_prompt(manifest, item):
    style = manifest.get(
        "iconStyle",
        "Roblox game shop icon, bright saturated colors, bold dark outline, soft glossy shading, "
        "one centered object, plain radial-gradient background, no text, no Robux symbol, no logos",
    )
    subject = item.get("iconPrompt") or f"{item['name']}: {item.get('description') or item['key']}"
    shape = (
        "Square 1:1 image; the subject fits inside a centered circle (corners get cropped)."
        if item["kind"] == "pass"
        else "Square 1:1 image, subject centered with a small margin."
    )
    return f"{subject}. {style}. {shape}"


# Open Cloud ------------------------------------------------------------------


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


def setting(manifest, name):
    if os.environ.get(name):
        return os.environ[name]
    for folder in (manifest["_root"], os.getcwd()):
        value = read_dotenv(os.path.join(folder, ".env")).get(name)
        if value:
            return value
    return None


class OpenCloud:
    def __init__(self, api_key, universe, sleep=time.sleep):
        self.api_key = api_key
        self.universe = universe
        self.sleep = sleep
        self.last_write = {}

    def url(self, kind, which, item_id=None, query=None):
        path = KINDS[kind][which].format(universe=self.universe, id=item_id)
        if item_id is not None and which == "base":
            path += f"/{item_id}"
        url = BASE_URL + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        return url

    def request(self, method, url, kind, fields=None, image=None):
        if method != "GET":
            wait = KINDS[kind]["write_interval"] - (time.monotonic() - self.last_write.get(kind, 0))
            if wait > 0:
                self.sleep(wait)
        body, headers = None, {"x-api-key": self.api_key, "User-Agent": USER_AGENT, "Accept": "application/json"}
        if fields is not None:
            body, content_type = multipart(fields, image)
            headers["Content-Type"] = content_type
        for attempt in range(6):
            req = urllib.request.Request(url, data=body, method=method, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=60) as response:
                    raw = response.read()
                    status = response.status
                break
            except urllib.error.HTTPError as e:
                raw, status = e.read(), e.code
                if status == 429 or status >= 500:
                    if attempt == 5:
                        break
                    retry_after = e.headers.get("Retry-After")
                    delay = float(retry_after) if retry_after and retry_after.replace(".", "", 1).isdigit() else 2**attempt
                    self.sleep(min(delay, 60))
                    continue
                break
            except urllib.error.URLError as e:
                if attempt == 5:
                    raise Fail(f"{method} {url}: network error {e.reason}")
                self.sleep(2**attempt)
        if method != "GET":
            self.last_write[kind] = time.monotonic()
        if status >= 400:
            raise HttpFail(explain(method, url, status, raw, kind), status)
        if not raw:
            return None
        return json.loads(raw)

    def get(self, kind, item_id):
        try:
            return self.request("GET", self.url(kind, "get", item_id), kind)
        except HttpFail as e:
            if e.status == 404:
                return None
            raise

    def list_all(self, kind):
        items, token = [], None
        while True:
            query = {"pageSize": 100}
            if token:
                query["pageToken"] = token
            page = self.request("GET", self.url(kind, "list", query=query), kind) or {}
            items.extend(page.get(KINDS[kind]["list_key"]) or [])
            token = page.get("nextPageToken")
            if not token:
                return items

    def create(self, kind, fields, image):
        return self.request("POST", self.url(kind, "base"), kind, fields, image)

    def update(self, kind, item_id, fields, image):
        self.request("PATCH", self.url(kind, "base", item_id), kind, fields, image)


def multipart(fields, image):
    boundary = f"----monetize{uuid.uuid4().hex}"
    out = io.BytesIO()
    for name, value in fields.items():
        if isinstance(value, bool):
            value = "true" if value else "false"
        out.write(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n".encode())
        out.write(str(value).encode("utf-8"))
        out.write(b"\r\n")
    if image is not None:
        out.write(
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"imageFile\"; filename=\"icon.png\"\r\n"
            "Content-Type: image/png\r\n\r\n".encode()
        )
        out.write(image)
        out.write(b"\r\n")
    out.write(f"--{boundary}--\r\n".encode())
    return out.getvalue(), f"multipart/form-data; boundary={boundary}"


def explain(method, url, status, raw, kind):
    try:
        detail = json.loads(raw)
        detail = detail.get("message") or detail.get("errorMessage") or detail.get("errors") or detail
    except (ValueError, AttributeError):
        detail = raw[:300].decode("utf-8", "replace")
    path = urllib.parse.urlparse(url).path
    hint = ""
    if status == 401:
        hint = " -> the API key is wrong, expired or revoked: make a new one and update ROBLOX_API_KEY"
    elif status == 403:
        scope = KINDS[kind]["scope"]
        hint = (
            f" -> the key lacks {scope} read/write for this experience, the experience is not in the key's list,"
            " or the key's IP allowlist blocks this machine (Creator Hub > Open Cloud > API Keys)"
        )
    elif status == 400:
        hint = " -> Roblox rejected a field (name taken or moderated, price out of range, image not accepted)"
    elif status == 409:
        hint = " -> conflict: an item with this name may already exist; run sync again to adopt it"
    return f"{method} {path}: HTTP {status}: {detail}{hint}"


# Sync ------------------------------------------------------------------------


def load_lock(manifest):
    path = resolve(manifest, manifest["lockFile"])
    try:
        with open(path, encoding="utf-8") as f:
            lock = json.load(f)
    except FileNotFoundError:
        lock = {}
    lock.setdefault("items", {})
    return lock


def save_lock(manifest, lock):
    path = resolve(manifest, manifest["lockFile"])
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(lock, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)


def remote_state(kind, remote):
    price = (remote.get("priceInformation") or {}).get("defaultPriceInRobux")
    return {
        "name": remote.get("name"),
        "description": remote.get("description") or "",
        "price": price,
        "forSale": bool(remote.get("isForSale")),
        "managedPricing": bool(remote.get("isManagedPricingEnabled")),
        "iconAssetId": remote.get(KINDS[kind]["icon_field"]),
    }


def wanted_fields(item):
    return {
        "name": item["name"],
        "description": item["description"],
        "price": item["price"],
        "isForSale": item["forSale"],
        "isManagedPricingEnabled": item["managedPricing"],
    }


FIELD_MAP = {
    "name": "name",
    "description": "description",
    "price": "price",
    "isForSale": "forSale",
    "isManagedPricingEnabled": "managedPricing",
}


def sync(manifest, dry_run=False, client=None, log=print):
    errors, warnings = validate(manifest)
    for warning in warnings:
        log(f"WARN  {warning}")
    if errors:
        raise Fail("manifest has errors:\n  " + "\n  ".join(errors))

    universe = manifest.get("universeId") or setting(manifest, "ROBLOX_UNIVERSE_ID")
    if not universe or not str(universe).isdigit():
        raise Fail("no universe ID: set \"universeId\" in the manifest or ROBLOX_UNIVERSE_ID")
    universe = int(universe)
    lock = load_lock(manifest)
    if lock.get("universeId") not in (None, universe):
        raise Fail(
            f"the lock file belongs to universe {lock['universeId']}, the manifest says {universe}: "
            "use a separate lock file per experience (\"lockFile\" in the manifest)"
        )

    if client is None:
        api_key = setting(manifest, "ROBLOX_API_KEY")
        if not api_key:
            raise Fail(
                "ROBLOX_API_KEY is not set. Create a key in Creator Hub > Open Cloud > API Keys with game-pass and "
                "developer-product read+write for this experience, then put it in an environment variable or a "
                ".env file that git ignores. Never paste it into the chat or the code."
            )
        warn_if_env_tracked(manifest, log)
        client = OpenCloud(api_key, universe)

    listed = {}

    def find_by_name(kind, name):
        if kind not in listed:
            listed[kind] = client.list_all(kind)
        matches = [r for r in listed[kind] if r.get("name") == name]
        if len(matches) > 1:
            ids = ", ".join(str(r[KINDS[kind]["id_field"]]) for r in matches)
            raise Fail(f"{len(matches)} {KINDS[kind]['label']}s are named {name!r} ({ids}): put the right id in the lock file")
        return matches[0] if matches else None

    summary = {"created": 0, "updated": 0, "unchanged": 0, "adopted": 0}
    if not dry_run:
        lock["universeId"] = universe
    for item in manifest["items"]:
        kind, key = item["kind"], item["key"]
        meta = KINDS[kind]
        image = normalized_icon(resolve(manifest, item["icon"]))
        icon_hash = hashlib.sha256(image).hexdigest()
        entry = lock["items"].get(key)
        if entry and entry.get("kind") != kind:
            raise Fail(f"{key}: the lock file has it as a {entry.get('kind')}; a pass cannot become a product. Use a new key.")

        remote = None
        if entry and entry.get("id"):
            remote = client.get(kind, entry["id"])
            if remote is None:
                log(f"WARN  {key}: {meta['label']} {entry['id']} no longer exists, creating it again")
                entry = None
        if remote is None:
            remote = find_by_name(kind, item["name"])
            if remote is not None:
                summary["adopted"] += 1
                log(f"ADOPT {key}: existing {meta['label']} {remote[meta['id_field']]} named {item['name']!r}")
                entry = {"kind": kind, "id": remote[meta["id_field"]], "iconSha256": None}

        wanted = wanted_fields(item)
        if remote is None:
            log(f"CREATE {meta['label']} {key}: {item['name']!r}, {item['price']} Robux")
            if dry_run:
                summary["created"] += 1
                continue
            created = client.create(kind, wanted, image)
            entry = {
                "kind": kind,
                "id": created[meta["id_field"]],
                "iconAssetId": created.get(meta["icon_field"]),
                "iconSha256": icon_hash,
            }
            lock["items"][key] = entry
            save_lock(manifest, lock)
            summary["created"] += 1
            continue

        state = remote_state(kind, remote)
        changes = {field: value for field, value in wanted.items() if state[FIELD_MAP[field]] != value}
        icon_changed = entry.get("iconSha256") != icon_hash
        if not changes and not icon_changed:
            summary["unchanged"] += 1
            log(f"OK    {key}: {meta['label']} {entry['id']} up to date")
            entry["iconAssetId"] = state["iconAssetId"]
            if not dry_run:
                lock["items"][key] = entry
                save_lock(manifest, lock)
            continue
        what = ", ".join(sorted(changes) + (["icon"] if icon_changed else []))
        log(f"UPDATE {key}: {meta['label']} {entry['id']} ({what})")
        summary["updated"] += 1
        if dry_run:
            continue
        client.update(kind, entry["id"], changes, image if icon_changed else None)
        entry["iconSha256"] = icon_hash
        refreshed = client.get(kind, entry["id"]) if icon_changed else remote
        entry["iconAssetId"] = (refreshed or remote).get(meta["icon_field"])
        lock["items"][key] = entry
        save_lock(manifest, lock)

    stale = sorted(set(lock["items"]) - {item["key"] for item in manifest["items"]})
    for key in stale:
        log(
            f"WARN  {key} is in the lock file but not in the manifest. Open Cloud cannot delete it: "
            "set forSale false in the manifest to stop selling it, or remove it from the lock file."
        )
    if not dry_run:
        write_luau(manifest, lock, log)
    log(
        f"{'Dry run: ' if dry_run else ''}{summary['created']} created, {summary['updated']} updated, "
        f"{summary['adopted']} adopted, {summary['unchanged']} unchanged"
    )
    return summary


def warn_if_env_tracked(manifest, log):
    env = os.path.join(manifest["_root"], ".env")
    if not os.path.exists(env):
        return
    gitignore = os.path.join(manifest["_root"], ".gitignore")
    try:
        with open(gitignore, encoding="utf-8") as f:
            ignored = any(line.strip() in (".env", "/.env", ".env*", "*.env") for line in f)
    except OSError:
        ignored = False
    if not ignored:
        log("WARN  .env is not in .gitignore next to the manifest: add it so the API key never gets committed")


# Luau ------------------------------------------------------------------------


def luau_string(value):
    quote = "'" if '"' in value and "'" not in value else '"'
    escaped = value.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
    escaped = escaped.replace(quote, "\\" + quote)
    return quote + escaped + quote


def luau_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value) if isinstance(value, float) else str(value)
    if isinstance(value, str):
        return luau_string(value)
    raise Fail(f"cannot write {value!r} to Luau")


def render_luau(manifest, lock):
    lines = [
        "-- Generated by the roblox-monetization skill (scripts/monetize.py) from monetization.json.",
        "-- Do not edit by hand: change the manifest and run `monetize.py sync` (or `monetize.py luau`).",
        "-- Prices are not stored here on purpose: managed and regional pricing change what each player",
        "-- pays, so the shop reads PriceInRobux from MarketplaceService:GetProductInfoAsync.",
        "",
        "export type Grant = { type: string, field: string?, amount: number?, stat: string?, value: number? }",
        "export type Item = {",
        "\tKey: string,",
        '\tKind: "Pass" | "Product",',
        "\tId: number,",
        "\tName: string,",
        "\tDescription: string,",
        "\tIcon: string,",
        "\tOrder: number,",
        "\tForSale: boolean,",
        "\tGrant: Grant,",
        "}",
        "",
        "local Monetization = {}",
        "",
        f"Monetization.UniverseId = {int(lock.get('universeId') or manifest.get('universeId') or 0)}",
        "",
        "Monetization.Items = {",
    ]
    for item in manifest["items"]:
        entry = lock["items"].get(item["key"]) or {}
        icon = f"rbxassetid://{entry['iconAssetId']}" if entry.get("iconAssetId") else ""
        grant = ", ".join(f"{name} = {luau_value(value)}" for name, value in item["grant"].items())
        lines += [
            f"\t{item['key']} = {{",
            f"\t\tKey = {luau_string(item['key'])},",
            f"\t\tKind = {luau_string(KINDS[item['kind']]['luau'])},",
            f"\t\tId = {int(entry.get('id') or 0)},{' -- not created yet: run monetize.py sync' if not entry.get('id') else ''}",
            f"\t\tName = {luau_string(item['name'])},",
            f"\t\tDescription = {luau_string(item['description'])},",
            f"\t\tIcon = {luau_string(icon)},",
            f"\t\tOrder = {item['_order']},",
            f"\t\tForSale = {luau_value(item['forSale'])},",
            f"\t\tGrant = {{ {grant} }},",
            "\t},",
        ]
    lines += ["} :: { [string]: Item }", "", "return Monetization", ""]
    return "\n".join(lines)


def write_luau(manifest, lock, log=print):
    path = resolve(manifest, manifest["luauOutput"])
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(render_luau(manifest, lock))
    log(f"wrote {os.path.relpath(path)}")


# CLI -------------------------------------------------------------------------


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["check", "prompts", "icons", "sync", "luau"])
    parser.add_argument("--manifest", default="monetization.json")
    parser.add_argument("--dry-run", action="store_true", help="sync: show what would change, write nothing")
    parser.add_argument("--placeholder", action="store_true", help="icons: draw placeholder art for missing icons")
    parser.add_argument("--force", action="store_true", help="icons: redraw placeholders even if the icon exists")
    args = parser.parse_args(argv)
    try:
        manifest = load_manifest(args.manifest)
        if args.command == "check":
            errors, warnings = validate(manifest)
            for warning in warnings:
                print(f"WARN  {warning}")
            for error in errors:
                print(f"ERROR {error}")
            counts = {kind: sum(1 for i in manifest["items"] if isinstance(i, dict) and i.get("kind") == kind) for kind in KINDS}
            print(f"{counts['pass']} game passes, {counts['product']} developer products: {len(errors)} errors, {len(warnings)} warnings")
            return 1 if errors else 0
        errors, _ = validate(manifest, check_icons=False)
        if errors:
            raise Fail("manifest has errors:\n  " + "\n  ".join(errors))
        if args.command == "prompts":
            prompts = [
                {"key": i["key"], "kind": i["kind"], "output": i["icon"], "size": "1024x1024", "prompt": icon_prompt(manifest, i)}
                for i in manifest["items"]
            ]
            out = resolve(manifest, os.path.join(manifest["iconsDir"], "prompts.json"))
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out, "w", encoding="utf-8") as f:
                json.dump(prompts, f, indent=2)
                f.write("\n")
            for p in prompts:
                print(f"{p['output']}: {p['prompt']}")
            print(f"wrote {os.path.relpath(out)}")
        elif args.command == "icons":
            if not args.placeholder:
                raise Fail("icons needs --placeholder (real art: generate it from `monetize.py prompts`)")
            made = 0
            for item in manifest["items"]:
                path = resolve(manifest, item["icon"])
                if args.force or not os.path.exists(path):
                    placeholder_icon(item, path)
                    made += 1
                    print(f"placeholder {os.path.relpath(path)}")
            print(f"{made} placeholder icons drawn")
        elif args.command == "sync":
            sync(manifest, dry_run=args.dry_run)
        elif args.command == "luau":
            write_luau(manifest, load_lock(manifest))
        return 0
    except Fail as e:
        print(f"ERROR {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
