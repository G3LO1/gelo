#!/usr/bin/env python3
"""Static security + performance scan for Roblox Luau code.

Usage:
  scan_luau.py <path>... [--json out.json] [--fail-on high|medium|low|none] [--quiet-low]

<path> can be a folder (Rojo project, scripts dumped from Studio or by audit_place.luau),
.lua/.luau files, or .rbxmx/.rbxlx files (scripts are read from the XML). Binary .rbxl/.rbxm:
dump them first with `lune run audit_place.luau <file> --dump-scripts <dir>`.

Script context (server/client/module) comes from the file name (*.server.luau, *.client.luau),
the folders on its path (server, ServerScriptService, client, StarterPlayer, ...) or the
script class in XML files. Findings are heuristics: each one is a place to read, not a
verdict. Exit code is 1 when a finding at or above --fail-on (default: high) exists.
"""

import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

SEVERITIES = ["high", "medium", "low"]

RULES = {
    "SEC-REQUIRE-ID": ("high", "require() of a number loads code from the Creator Store at runtime: the classic backdoor. Require only ModuleScripts you can read."),
    "SEC-LOADSTRING": ("high", "loadstring() runs arbitrary code; keep ServerScriptService.LoadStringEnabled off and remove it."),
    "SEC-FENV": ("high", "getfenv/setfenv is used by obfuscated backdoors (and disables Luau optimizations); legitimate game code doesn't need it."),
    "SEC-OBFUSCATED": ("high", "Long escaped byte string / string.char chain: typical of hidden payloads. Decode it and read what it does."),
    "SEC-HIDDEN-CODE": ("high", "Code pushed far to the right with whitespace, hidden off-screen in the script editor."),
    "SEC-WEBHOOK": ("high", "Sends data to a webhook/paste site: data exfiltration or a remote-controlled backdoor."),
    "SEC-REMOTE-HOST": ("medium", "Fetches content from a code/paste host at runtime; make sure it is yours and never executed."),
    "SEC-INSERT-ASSET": ("medium", "InsertService loads assets at runtime; only load assets you own and inspect what they contain."),
    "SEC-CLIENT-VALUE": ("high", "A server handler takes a value the server should compute ({param}). Accept ids/intents only and look prices, damage and rewards up on the server."),
    "SEC-CLIENT-AMOUNT": ("medium", "A server handler takes a client number ({param}): check type, NaN, integer and range before using it."),
    "SEC-INVOKE-CLIENT": ("high", "Server calls InvokeClient: an exploiter can make it hang forever or error. Use RemoteEvents server -> client."),
    "SEC-NAME-CHECK": ("medium", "Permission check by player name; names can change. Compare UserId (or group rank)."),
    "SEC-CLIENT-KICK": ("low", "Anti-cheat in a LocalScript: exploiters delete it. Detect on the server."),
    "DATA-SETASYNC": ("medium", "SetAsync overwrites blindly (lost progress, duplication across servers). Use UpdateAsync with a session lock."),
    "DATA-NO-PCALL": ("medium", "DataStore call outside pcall: any outage throws and breaks the calling code."),
    "PURCHASE-MULTI-RECEIPT": ("high", "ProcessReceipt is assigned in more than one script; only the last one runs, the others' products are never granted."),
    "PRICE-HARDCODED": ("medium", "Robux price written into the UI. Managed/regional pricing changes real prices per player: read PriceInRobux from MarketplaceService instead."),
    "PERF-LOOP-NO-YIELD": ("high", "Infinite loop without a yield: freezes the server/client ('Script timeout')."),
    "PERF-FRAME-ALLOC": ("medium", "Creates or scans instances every frame (Heartbeat/RenderStepped/Stepped). Pool, cache or move it out of the frame loop."),
    "PERF-SERVER-TWEEN": ("low", "TweenService on the server replicates every step; tween on clients (FireAllClients) and set the final value on the server."),
    "PERF-DEPRECATED-SCHED": ("low", "wait/spawn/delay are deprecated and throttled; use task.wait/task.spawn/task.delay."),
    "PERF-LONG-LINE": ("medium", "Extremely long line: usually minified or obfuscated code."),
}

VALUE_PARAMS = re.compile(
    r"^(price|cost|damage|dmg|reward|rewards|cash|coins?|money|gems?|gold|xp|exp|experience|robux|health|hp|points|score|currency|balance|multiplier|profit|payout)$",
    re.I,
)
AMOUNT_PARAMS = re.compile(r"^(amount|quantity|qty|count|level|speed|value|number|num)$", re.I)
FRAME_EVENTS = r"(RenderStepped|Heartbeat|Stepped|PreRender|PreSimulation|PostSimulation|PreAnimation)"

SERVER_DIRS = {"server", "serverscriptservice", "serverstorage"}
CLIENT_DIRS = {"client", "starterplayer", "starterplayerscripts", "startercharacterscripts", "startergui", "starterpack", "replicatedfirst"}


# ---------------------------------------------------------------- lexing helpers

def blank(text):
    """Replace comments and string contents with spaces (newlines kept) so code regexes and
    block matching don't trip over keywords inside strings. Returns (code, strings) where
    strings is a list of (offset, literal_text)."""
    out = list(text)
    strings = []
    i, n = 0, len(text)

    def wipe(a, b):
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        c = text[i]
        if c == "-" and text.startswith("--", i):
            m = re.match(r"--\[(=*)\[", text[i:])
            if m:
                close = "]" + m.group(1) + "]"
                end = text.find(close, i + len(m.group(0)))
                end = n if end < 0 else end + len(close)
            else:
                end = text.find("\n", i)
                end = n if end < 0 else end
            wipe(i, end)
            i = end
        elif c == "[" and re.match(r"\[(=*)\[", text[i:]):
            m = re.match(r"\[(=*)\[", text[i:])
            close = "]" + m.group(1) + "]"
            end = text.find(close, i + len(m.group(0)))
            end = n if end < 0 else end + len(close)
            strings.append((i, text[i:end]))
            wipe(i + 1, end - 1)
            i = end
        elif c in "\"'`":
            j = i + 1
            while j < n and text[j] != c:
                if text[j] == "\\":
                    j += 1
                elif text[j] == "\n" and c != "`":
                    break
                j += 1
            end = min(j + 1, n)
            strings.append((i, text[i:end]))
            wipe(i + 1, end - 1)
            i = end
        else:
            i += 1
    return "".join(out), strings


BLOCK_TOKEN = re.compile(r"(?<![.:\w])(function|do|if|repeat|end|until)\b")


def is_if_expression(code, offset):
    """`x = if a then b else c` (Luau if-expression) has no `end`, unlike an if statement."""
    before = code[:offset].rstrip()
    return before.endswith(("=", "(", ",", "[", "{")) or re.search(r"\b(return|and|or|not)$", before) is not None


def block_end(code, start):
    """Given the offset just after a block opener (`do` of a loop, `function`), return the
    offset of its matching `end` (or `until`)."""
    depth = 1
    for m in BLOCK_TOKEN.finditer(code, start):
        tok = m.group(1)
        if tok in ("function", "do", "repeat"):
            depth += 1
        elif tok == "if":
            if not is_if_expression(code, m.start()):
                depth += 1
        else:
            depth -= 1
            if depth == 0:
                return m.start()
    return len(code)


def without_functions(body):
    """Blank nested function bodies: a yield, break or return inside them doesn't apply to the
    enclosing loop."""
    out = body
    pos = 0
    while True:
        m = re.search(r"(?<![.:\w])function\b", out[pos:])
        if not m:
            return out
        start = pos + m.end()
        end = block_end(out, start)
        out = out[:start] + re.sub(r"[^\n]", " ", out[start:end]) + out[end:]
        pos = end


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


# ---------------------------------------------------------------- inputs

def context_for_path(path):
    lower = path.replace("\\", "/").lower()
    name = os.path.basename(lower)
    if re.search(r"\.server\.(lua|luau)$", name):
        return "server"
    if re.search(r"\.client\.(lua|luau)$", name):
        return "client"
    parts = set(lower.split("/"))
    if parts & SERVER_DIRS:
        return "server"
    if parts & CLIENT_DIRS:
        return "client"
    return "module"


def read_xml_scripts(path):
    """Yield (location, context, source) for every script in an .rbxmx/.rbxlx file."""
    tree = ET.parse(path)

    def walk(item, trail):
        cls = item.get("class", "")
        props = item.find("Properties")
        name = cls
        source = None
        run_context = None
        if props is not None:
            for prop in props:
                if prop.get("name") == "Name":
                    name = prop.text or cls
                elif prop.get("name") == "Source":
                    source = prop.text or ""
                elif prop.get("name") == "RunContext":
                    run_context = prop.text
        here = trail + [name]
        if cls in ("Script", "LocalScript", "ModuleScript") and source is not None:
            if cls == "LocalScript" or (cls == "Script" and run_context == "2"):
                ctx = "client"
            elif cls == "Script":
                ctx = "server"
            else:
                ctx = context_for_path("/".join(here))
            yield f"{path}::{'.'.join(here)}", ctx, source
        for child in item.findall("Item"):
            yield from walk(child, here)

    for item in tree.getroot().findall("Item"):
        yield from walk(item, [])


def collect(paths):
    for path in paths:
        if os.path.isdir(path):
            for root, dirs, files in os.walk(path):
                dirs[:] = sorted(d for d in dirs if d not in (".git", "node_modules", "Packages", "DevPackages"))
                for f in sorted(files):
                    yield from collect([os.path.join(root, f)])
        elif re.search(r"\.(lua|luau)$", path):
            with open(path, encoding="utf-8", errors="replace") as fh:
                yield path, context_for_path(path), fh.read()
        elif re.search(r"\.(rbxmx|rbxlx)$", path):
            yield from read_xml_scripts(path)
        elif re.search(r"\.(rbxm|rbxl)$", path):
            print(f"note: {path} is binary; dump its scripts with audit_place.luau --dump-scripts first", file=sys.stderr)


# ---------------------------------------------------------------- rules

def scan_source(location, context, text):
    findings = []
    code, strings = blank(text)

    def add(rule, offset, **fmt):
        severity, message = RULES[rule]
        findings.append({
            "rule": rule,
            "severity": severity,
            "file": location,
            "line": line_of(text, offset),
            "context": context,
            "message": message.format(**fmt),
        })

    for m in re.finditer(r"\brequire\s*\(\s*(\d{4,}|0x[0-9a-fA-F]+|tonumber\s*\(|getfenv|\w+\s*[-+*/%^]\s*\d)", code):
        add("SEC-REQUIRE-ID", m.start())
    for m in re.finditer(r"\bloadstring\s*\(", code):
        add("SEC-LOADSTRING", m.start())
    for m in re.finditer(r"\b(getfenv|setfenv)\s*\(", code):
        add("SEC-FENV", m.start())
    for m in re.finditer(r"(\\\d{1,3}){12,}|(\\x[0-9a-fA-F]{2}){12,}", text):
        add("SEC-OBFUSCATED", m.start())
    for m in re.finditer(r"string\.char\s*\(\s*\d+(\s*,\s*\d+){11,}", code):
        add("SEC-OBFUSCATED", m.start())
    for m in re.finditer(r"\S[ \t]{120,}\S", text):
        add("SEC-HIDDEN-CODE", m.start())

    for offset, literal in strings:
        low = literal.lower()
        if re.search(r"discord(app)?\.com/api/webhooks|webhook\.site|hooks\.slack\.com|api\.telegram\.org/bot", low):
            add("SEC-WEBHOOK", offset)
        elif re.search(r"pastebin\.com|hastebin|paste\.ee|ghostbin|raw\.githubusercontent\.com|gist\.githubusercontent|ngrok|\.glitch\.me|\.repl\.co", low):
            add("SEC-REMOTE-HOST", offset)
        if context != "server" and re.search(r"(r\$|£|robux)\s*\d|\d\s*(r\$|robux)", low):
            add("PRICE-HARDCODED", offset)

    for m in re.finditer(r"InsertService[\s\S]{0,200}?:\s*LoadAsset(Version)?\s*\(", code):
        add("SEC-INSERT-ASSET", m.start())

    # Server handlers: OnServerEvent:Connect(function(player, ...)), OnServerInvoke = function(...),
    # and the template's Net.handle/handleInvoke("Name", function(player, ...)).
    handler = re.compile(
        r"(OnServerEvent\s*:\s*Connect\s*\(\s*function|OnServerInvoke\s*=\s*function|Net\s*\.\s*handle(Invoke)?\s*\([^,]*,\s*function)\s*\(([^)]*)\)"
    )
    for m in handler.finditer(code):
        params = [re.split(r"[:=]", p)[0].strip() for p in m.group(3).split(",")][1:]
        for p in params:
            if p == "...":
                continue
            if VALUE_PARAMS.match(p):
                add("SEC-CLIENT-VALUE", m.start(), param=p)
            elif AMOUNT_PARAMS.match(p):
                add("SEC-CLIENT-AMOUNT", m.start(), param=p)

    if context != "client":
        for m in re.finditer(r":\s*InvokeClient\s*\(", code):
            add("SEC-INVOKE-CLIENT", m.start())
        for m in re.finditer(r"TweenService\s*:\s*Create\s*\(|\b\w*[Tt]ween\w*\s*:\s*Create\s*\(", code):
            if context == "server":
                add("PERF-SERVER-TWEEN", m.start())
    if context == "client":
        for m in re.finditer(r":\s*Kick\s*\(", code):
            add("SEC-CLIENT-KICK", m.start())

    for m in re.finditer(r"\b\w*(player|plr|user|caller)\w*\s*\.\s*(Name|DisplayName)\s*[=~]=|[=~]=\s*\w*(player|plr|user|caller)\w*\s*\.\s*(Name|DisplayName)\b", code, re.I):
        add("SEC-NAME-CHECK", m.start())

    for m in re.finditer(r"(\w*)\s*:\s*SetAsync\s*\(", code):
        if not re.search(r"http", m.group(1), re.I):
            add("DATA-SETASYNC", m.start())
    lines = code.split("\n")
    for m in re.finditer(r"(\w*)\s*:\s*(GetAsync|SetAsync|UpdateAsync|IncrementAsync|RemoveAsync|GetSortedAsync)\s*\(", code):
        if re.search(r"http", m.group(1), re.I):
            continue
        ln = line_of(code, m.start())
        window = "\n".join(lines[max(0, ln - 4):ln])
        if "pcall" not in window:
            add("DATA-NO-PCALL", m.start())

    for m in re.finditer(r"(?<![.:\w])(wait|spawn|delay)\s*\(", code):
        add("PERF-DEPRECATED-SCHED", m.start())

    for m in re.finditer(r"\bwhile\s+(true|1)\s+do\b|\brepeat\b", code):
        body_start = m.end()
        body_end = block_end(code, body_start)
        body = without_functions(code[body_start:body_end])
        if m.group(0).startswith("repeat"):
            tail = code[body_end:body_end + 60]
            if not re.match(r"until\s+(false|nil)\b", tail):
                continue
        if not re.search(r"\b(wait|task\s*\.\s*wait|coroutine\s*\.\s*yield|break|return|error)\b|:\s*Wait\s*\(|Async\s*\(|Yield", body):
            add("PERF-LOOP-NO-YIELD", m.start())

    for m in re.finditer(FRAME_EVENTS + r"\s*:\s*Connect\s*\(\s*function\b", code):
        body_start = m.end()
        body = code[body_start:block_end(code, body_start)]
        hit = re.search(r"Instance\s*\.\s*new\s*\(|:\s*Clone\s*\(|:\s*GetDescendants\s*\(", body)
        if hit:
            add("PERF-FRAME-ALLOC", body_start + hit.start())

    for i, raw in enumerate(text.split("\n")):
        if len(raw) > 2000:
            add("PERF-LONG-LINE", sum(len(l) + 1 for l in text.split("\n")[:i]))

    return findings


def scan(paths):
    findings = []
    receipts = []
    count = 0
    for location, context, source in collect(paths):
        count += 1
        findings.extend(scan_source(location, context, source))
        code, _ = blank(source)
        for m in re.finditer(r"\bProcessReceipt\s*=", code):
            receipts.append((location, line_of(source, m.start()), context))
    if len(receipts) > 1:
        severity, message = RULES["PURCHASE-MULTI-RECEIPT"]
        for location, line, context in receipts:
            findings.append({"rule": "PURCHASE-MULTI-RECEIPT", "severity": severity, "file": location,
                             "line": line, "context": context, "message": message})
    order = {s: i for i, s in enumerate(SEVERITIES)}
    findings.sort(key=lambda f: (order[f["severity"]], f["file"], f["line"]))
    return count, findings


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--json", help="also write findings as JSON to this file")
    ap.add_argument("--fail-on", default="high", choices=SEVERITIES + ["none"])
    ap.add_argument("--quiet-low", action="store_true", help="don't print low-severity findings")
    args = ap.parse_args()

    count, findings = scan(args.paths)
    shown = [f for f in findings if not (args.quiet_low and f["severity"] == "low")]
    for f in shown:
        print(f"{f['severity'].upper():6} {f['rule']:22} {f['file']}:{f['line']}  [{f['context']}]")
        print(f"       {f['message']}")
    totals = {s: sum(1 for f in findings if f["severity"] == s) for s in SEVERITIES}
    print(f"\nScanned {count} script(s): {totals['high']} high, {totals['medium']} medium, {totals['low']} low")
    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump({"scripts": count, "totals": totals, "findings": findings}, fh, indent=2)
    if args.fail_on != "none":
        limit = SEVERITIES.index(args.fail_on)
        if any(SEVERITIES.index(f["severity"]) <= limit for f in findings):
            sys.exit(1)


if __name__ == "__main__":
    main()
