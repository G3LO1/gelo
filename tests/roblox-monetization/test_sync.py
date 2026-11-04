#!/usr/bin/env python3
"""monetize.py against a local mock of the Roblox Open Cloud game pass / developer product API.

The mock follows the OpenAPI spec (create.roblox.com/docs/cloud/openapi.json): multipart POST/PATCH,
x-api-key auth, /creator GET and paginated list endpoints, 204 on PATCH, rate-limit 429s.
Usage: test_sync.py <monetize.py> <example manifest> <workdir>   (prints ok/FAIL lines, exit 1 on failure)
"""

import email.parser
import email.policy
import io
import json
import os
import re
import shutil
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from PIL import Image

SCRIPT, EXAMPLE, WORK = sys.argv[1:4]
API_KEY = "test-key-SECRET-0123456789abcdef"
UNIVERSE = 4242

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
            print("       " + str(detail).replace("\n", "\n       "))


# Mock Open Cloud ---------------------------------------------------------------

ROUTES = {
    "game-passes": ("pass", "gamePassId", "iconAssetId", "gamePasses"),
    "developer-products": ("product", "productId", "iconImageAssetId", "developerProducts"),
}


class Backend:
    def __init__(self):
        self.lock = threading.Lock()
        self.reset()

    def reset(self):
        self.items = {"pass": {}, "product": {}}
        self.requests = []
        self.next_id = 1000
        self.next_asset = 9000
        self.fail_next = []  # list of (method, status)
        self.forbidden = False
        self.page_size_cap = 2


backend = Backend()


def parse_multipart(headers, body):
    message = email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(
        b"Content-Type: " + headers["Content-Type"].encode() + b"\r\n\r\n" + body
    )
    fields, files = {}, {}
    for part in message.iter_parts():
        name = part.get_param("name", header="content-disposition")
        if part.get_filename():
            files[name] = part.get_payload(decode=True)
        else:
            fields[name] = part.get_payload(decode=True).decode()
    return fields, files


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status, payload=None, headers=None):
        raw = b"" if payload is None else json.dumps(payload).encode()
        self.send_response(status)
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        if raw:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def handle_any(self, method):
        url = urlparse(self.path)
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        fields, files = ({}, {})
        if body:
            fields, files = parse_multipart(self.headers, body)
        with backend.lock:
            backend.requests.append(
                {"method": method, "path": url.path, "fields": fields, "files": files, "key": self.headers.get("x-api-key")}
            )
            if self.headers.get("x-api-key") != API_KEY:
                return self.reply(401, {"code": "UNAUTHENTICATED", "message": "Invalid API Key"})
            if backend.forbidden:
                return self.reply(403, {"code": "PERMISSION_DENIED", "message": "Insufficient scope"})
            for index, (fail_method, status) in enumerate(backend.fail_next):
                if fail_method == method:
                    backend.fail_next.pop(index)
                    return self.reply(status, {"message": "slow down"}, {"Retry-After": "0"})
            match = re.match(r"^/(game-passes|developer-products)/v[12]/universes/(\d+)/(game-passes|developer-products)(.*)$", url.path)
            if not match or int(match.group(2)) != UNIVERSE:
                return self.reply(404, {"message": "not found"})
            kind, id_field, icon_field, list_key = ROUTES[match.group(1)]
            rest = match.group(4)
            store = backend.items[kind]

            def view(item):
                return {
                    id_field: item["id"],
                    "name": item["name"],
                    "description": item["description"],
                    "isForSale": item["isForSale"],
                    icon_field: item["icon"],
                    "isManagedPricingEnabled": item["managed"],
                    "priceInformation": {"defaultPriceInRobux": item["price"], "enabledFeatures": []},
                    "createdTimestamp": "2026-01-01T00:00:00Z",
                    "updatedTimestamp": "2026-01-01T00:00:00Z",
                }

            if method == "GET" and rest == "/creator":
                query = parse_qs(url.query)
                size = min(int(query.get("pageSize", ["50"])[0]), backend.page_size_cap)
                start = int(query.get("pageToken", ["0"])[0])
                ordered = sorted(store.values(), key=lambda i: i["id"])
                page = ordered[start : start + size]
                token = str(start + size) if start + size < len(ordered) else None
                return self.reply(200, {list_key: [view(i) for i in page], "nextPageToken": token})
            m = re.match(r"^/(\d+)/creator$", rest)
            if method == "GET" and m:
                item = store.get(int(m.group(1)))
                return self.reply(200, view(item)) if item else self.reply(404, {"message": "not found"})
            if method == "POST" and rest == "":
                if "name" not in fields:
                    return self.reply(400, {"message": "name required"})
                backend.next_id += 1
                item = {"id": backend.next_id, "icon": None, "managed": False}
                apply_fields(item, fields, files)
                store[item["id"]] = item
                return self.reply(200, view(item))
            m = re.match(r"^/(\d+)$", rest)
            if method == "PATCH" and m:
                item = store.get(int(m.group(1)))
                if not item:
                    return self.reply(404, {"message": "not found"})
                apply_fields(item, fields, files)
                return self.reply(204)
            return self.reply(404, {"message": "no route"})

    def do_GET(self):
        self.handle_any("GET")

    def do_POST(self):
        self.handle_any("POST")

    def do_PATCH(self):
        self.handle_any("PATCH")


def apply_fields(item, fields, files):
    if "name" in fields:
        item["name"] = fields["name"]
    item.setdefault("description", "")
    if "description" in fields:
        item["description"] = fields["description"]
    if "price" in fields:
        item["price"] = int(fields["price"])
    item.setdefault("price", None)
    if "isForSale" in fields:
        item["isForSale"] = fields["isForSale"] == "true"
    item.setdefault("isForSale", False)
    if "isManagedPricingEnabled" in fields:
        item["managed"] = fields["isManagedPricingEnabled"] == "true"
    if "imageFile" in files:
        backend.next_asset += 1
        item["icon"] = backend.next_asset
        item["iconBytes"] = files["imageFile"]


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{server.server_address[1]}"


# Helpers -----------------------------------------------------------------------

project = os.path.join(WORK, "game")
shutil.rmtree(project, ignore_errors=True)
os.makedirs(project)
manifest_path = os.path.join(project, "monetization.json")
manifest = json.load(open(EXAMPLE))
manifest["universeId"] = UNIVERSE
json.dump(manifest, open(manifest_path, "w"), indent=2)


def run(*args, key=API_KEY, extra_env=None):
    env = {k: v for k, v in os.environ.items() if k not in ("ROBLOX_API_KEY", "ROBLOX_UNIVERSE_ID")}
    env["ROBLOX_OPEN_CLOUD_URL"] = BASE
    if key is not None:
        env["ROBLOX_API_KEY"] = key
    env.update(extra_env or {})
    result = subprocess.run(
        [sys.executable, "-I", os.path.abspath(SCRIPT), *args, "--manifest", "monetization.json"],
        cwd=project,
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )
    return result.returncode, result.stdout + result.stderr


def writes():
    return [r for r in backend.requests if r["method"] != "GET"]


def lock():
    return json.load(open(os.path.join(project, "monetization.lock.json")))


def luau():
    return open(os.path.join(project, "src/shared/Monetization.luau"), encoding="utf-8").read()


def no_key(output):
    return API_KEY not in output and "SECRET" not in output


# Tests -------------------------------------------------------------------------

print("icons and validation")
code, out = run("check")
check(code == 1 and out.count("is missing") == 4, "check fails while the 4 icons are missing", out)
code, out = run("icons")
check(code == 1 and "--placeholder" in out, "icons without --placeholder explains how to get real art", out)
code, out = run("icons", "--placeholder")
check(code == 0 and "4 placeholder icons drawn" in out, "placeholder icons drawn", out)
with Image.open(os.path.join(project, "icons/DoubleCash.png")) as image:
    check(image.size == (512, 512) and image.format == "PNG", "placeholder is a 512x512 PNG")
code, out = run("check")
check(code == 0 and "2 game passes, 2 developer products: 0 errors" in out, "example manifest + placeholders pass check", out)
code, out = run("prompts")
prompts = json.load(open(os.path.join(project, "icons/prompts.json")))
check(
    code == 0 and len(prompts) == 4 and "circle" in prompts[1]["prompt"] and prompts[0]["output"] == "icons/StarterPack.png",
    "prompts.json: one prompt per item with output path, pass prompts mention the circle crop",
    out,
)

bad_dir = os.path.join(WORK, "bad")
os.makedirs(bad_dir, exist_ok=True)
json.dump(
    {
        "universeId": -1,
        "items": [
            {"key": "vip", "kind": "pass", "name": "VIP", "price": 0},
            {"key": "Coins", "kind": "pass", "name": "Coins", "price": 10, "grant": {"type": "currency", "field": "Coins", "amount": 5}},
            {"key": "Boost", "kind": "product", "name": "Boost", "price": 10, "grant": {"type": "multiplier", "stat": "Cash", "value": 2}},
            {"key": "Boost2", "kind": "product", "name": "Boost", "price": 10.5},
            {"key": "Gems", "kind": "product", "name": "Gems", "price": 5, "grant": {"type": "currency", "field": "Gems", "amount": -1}},
            {"key": "Thing", "kind": "badge", "name": "x", "price": 5},
            {"key": "Long", "kind": "pass", "name": "x" * 60, "price": 5, "grant": {"type": "multiplier", "stat": "Cash", "value": 1}},
        ],
    },
    open(os.path.join(bad_dir, "monetization.json"), "w"),
)
result = subprocess.run(
    [sys.executable, "-I", os.path.abspath(SCRIPT), "check"], cwd=bad_dir, capture_output=True, text=True
)
bad = result.stdout
for pattern, label in [
    (r"universeId must be a positive integer", "negative universe"),
    (r"key 'vip' must be a PascalCase", "lowercase key"),
    (r"price must be a whole number of Robux, at least 1", "price 0"),
    (r"Coins: grant.type must be one of handler, multiplier, perk \(a pass is bought once", "currency on a pass"),
    (r"Boost: grant.type must be one of currency, handler \(a product is consumed", "multiplier on a product"),
    (r"Boost2: two developer products named 'Boost'", "duplicate name"),
    (r"Boost2: price must be a whole number", "fractional price"),
    (r"Gems: grant.amount must be a positive whole number", "negative amount"),
    (r"Thing: kind must be 'pass'", "unknown kind"),
    (r"Long: name is 60 characters", "long name"),
    (r"Long: grant.value must be a number above 1", "multiplier of 1"),
]:
    check(re.search(pattern, bad), f"check rejects {label}", bad if not re.search(pattern, bad) else "")
check(result.returncode == 1, "check exits 1 on errors")

print("auth and secrets")
code, out = run("sync", key=None)
check(code == 1 and "ROBLOX_API_KEY is not set" in out and "Never paste it" in out, "no key: clear instructions", out)
code, out = run("sync", key="wrong-key")
check(code == 1 and "HTTP 401" in out and "wrong, expired or revoked" in out and "wrong-key" not in out, "bad key: 401 explained, key not echoed", out)
backend.forbidden = True
code, out = run("sync")
check(
    code == 1 and "HTTP 403" in out and ("game-pass read/write" in out or "developer-product read/write" in out),
    "403: names the missing permission",
    out,
)
check(no_key(out), "key never printed on errors")
backend.forbidden = False
manifest_no_universe = dict(manifest)
manifest_no_universe.pop("universeId")
json.dump(manifest_no_universe, open(manifest_path, "w"), indent=2)
code, out = run("sync", key=API_KEY)
check(code == 1 and "no universe ID" in out, "missing universe ID explained", out)
json.dump(manifest, open(manifest_path, "w"), indent=2)
backend.reset()

print("dry run")
code, out = run("sync", "--dry-run")
check(code == 0 and out.count("CREATE") == 4 and "Dry run: 4 created" in out, "dry run plans 4 creations", out)
check(not writes(), "dry run sends no writes")
check(not os.path.exists(os.path.join(project, "monetization.lock.json")), "dry run writes no lock file")

print("first sync")
backend.fail_next = [("POST", 429), ("POST", 503)]
code, out = run("sync")
check(code == 0 and "4 created, 0 updated, 0 adopted, 0 unchanged" in out, "4 items created (after a 429 and a 503 retry)", out)
check(no_key(out), "key never printed")
posts = [r for r in writes() if r["method"] == "POST"]
check(len(posts) == 6, f"6 POSTs: 4 + 2 retried (got {len(posts)})")
check(all(r["key"] == API_KEY for r in backend.requests), "every request sends x-api-key")
pass_post = next(r for r in posts if r["path"].startswith("/game-passes/v1/") and r["fields"].get("name") == "2x Cash")
check(
    pass_post["fields"] == {
        "name": "2x Cash",
        "description": "Earn double Cash from everything, forever.",
        "price": "199",
        "isForSale": "true",
        "isManagedPricingEnabled": "false",
    },
    "game pass POST fields: name, description, price, isForSale, isManagedPricingEnabled",
    pass_post["fields"],
)
with Image.open(io.BytesIO(pass_post["files"]["imageFile"])) as image:
    check(image.format == "PNG" and image.size == (512, 512), "imageFile is a 512x512 PNG")
check(
    any(r["path"] == f"/developer-products/v2/universes/{UNIVERSE}/developer-products" for r in posts),
    "developer products go to /developer-products/v2/universes/{id}/developer-products",
)
lk = lock()
check(lk["universeId"] == UNIVERSE and set(lk["items"]) == {"StarterPack", "DoubleCash", "BiggerSize", "ServerEvent"}, "lock file lists all 4")
check(all(e["id"] and e["iconAssetId"] and e["iconSha256"] for e in lk["items"].values()), "lock has id, icon asset and icon hash")
source = luau()
double = lk["items"]["DoubleCash"]
check(f"Id = {double['id']}," in source and f'Icon = "rbxassetid://{double["iconAssetId"]}"' in source, "Luau has the pass ID and icon")
check('Kind = "Pass"' in source and 'Kind = "Product"' in source, "Luau kinds")
check('Grant = { type = "multiplier", stat = "Size", value = 1.25 },' in source, "Luau grant table")
check(not re.search(r"^\s*Price", source, re.M) and "199" not in source, "Luau stores no prices")

print("second sync is a no-op")
before = len(writes())
code, out = run("sync")
check(code == 0 and "0 created, 0 updated, 0 adopted, 4 unchanged" in out, "nothing changed", out)
check(len(writes()) == before, "no writes")

print("changes")
manifest["items"][1]["price"] = 249
json.dump(manifest, open(manifest_path, "w"), indent=2)
with Image.open(os.path.join(project, "icons/StarterPack.png")) as image:
    image.rotate(90).resize((800, 600)).save(os.path.join(project, "icons/StarterPack.png"))
old_icon = lock()["items"]["StarterPack"]["iconAssetId"]
code, out = run("sync")
check(code == 0 and "2 updated" in out and "DoubleCash: game pass" in out and "(price)" in out, "price change -> PATCH price only", out)
patches = [r for r in writes() if r["method"] == "PATCH"]
price_patch = next(r for r in patches if r["fields"].get("price") == "249")
check(price_patch["fields"] == {"price": "249"} and not price_patch["files"], "PATCH sends only the changed field")
icon_patch = next(r for r in patches if r["files"])
check("imageFile" in icon_patch["files"] and not icon_patch["fields"], "icon change -> PATCH imageFile only")
new_icon = lock()["items"]["StarterPack"]["iconAssetId"]
check(new_icon != old_icon and f"rbxassetid://{new_icon}" in luau(), "new icon asset ID in lock and Luau")
check("800x600, not square" in out, "non-square icon warned and center-cropped", out)

print("lost lock file: adopt by name, no duplicates")
os.remove(os.path.join(project, "monetization.lock.json"))
posts_before = len([r for r in writes() if r["method"] == "POST"])
code, out = run("sync")
check(code == 0 and "4 adopted" in out, "all 4 adopted through the paginated list (page size 2)", out)
check(len([r for r in writes() if r["method"] == "POST"]) == posts_before, "no new item created")
check(len(backend.items["pass"]) == 2 and len(backend.items["product"]) == 2, "still 2 passes and 2 products in Roblox")

print("deleted in Roblox: recreated")
gone = lock()["items"]["ServerEvent"]["id"]
del backend.items["product"][gone]
code, out = run("sync")
check(code == 0 and "no longer exists" in out and "1 created" in out, "missing product recreated", out)
check(lock()["items"]["ServerEvent"]["id"] != gone, "lock has the new ID")

print("stale item and kind change")
manifest["items"] = manifest["items"][:3]
json.dump(manifest, open(manifest_path, "w"), indent=2)
code, out = run("sync")
check(code == 0 and "ServerEvent is in the lock file but not in the manifest" in out, "removed item: warned, not deleted", out)
manifest["items"][2]["kind"] = "product"
manifest["items"][2]["grant"] = {"type": "handler"}
json.dump(manifest, open(manifest_path, "w"), indent=2)
code, out = run("sync")
check(code == 1 and "a pass cannot become a product" in out, "pass -> product refused", out)

print(".env key")
manifest = json.load(open(EXAMPLE))
manifest["universeId"] = UNIVERSE
json.dump(manifest, open(manifest_path, "w"), indent=2)
with open(os.path.join(project, ".env"), "w") as f:
    f.write(f"# Open Cloud\nexport ROBLOX_API_KEY=\"{API_KEY}\"\n")
code, out = run("sync", key=None)
check(code == 0 and ".env is not in .gitignore" in out, "key read from .env, warns that git does not ignore it", out)
with open(os.path.join(project, ".gitignore"), "w") as f:
    f.write(".env\n")
code, out = run("sync", key=None)
check(code == 0 and ".gitignore" not in out, "no warning once .env is ignored", out)
check(no_key(out), "key from .env never printed")

print("luau command")
os.remove(os.path.join(project, "src/shared/Monetization.luau"))
code, out = run("luau", key=None)
check(code == 0 and "DoubleCash = {" in luau(), "luau rewrites the module from the lock file", out)
shutil.copy(os.path.join(project, "src/shared/Monetization.luau"), os.path.join(WORK, "Monetization.luau"))

server.shutdown()
print()
print(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
