#!/usr/bin/env python3
"""Reads the current state of any Roblox game project and prints the facts a review needs.

Usage:
  collect_state.py [project-dir] [--json state.json]

Works on a Rojo project or any folder with .lua/.luau/.rbxmx/.rbxlx files (default: current folder).
It only counts and quotes; it never scores. The reviewer (Claude) turns these facts into evidence for
review_score.py. Each signal says where it was found, so nothing has to be taken on trust.

Collected: scripts by side (server/client/shared), remotes, TODO/FIXME, placeholder IDs (= 0 next to
"TODO" or "paste"), debug/greybox flags, and presence of: persistence (DataStore/ProfileStore, session
lock, BindToClose), purchases (ProcessReceipt, product IDs), tutorial/onboarding, audio, animation, VFX,
UI (ScreenGui, ui-spec), localization, tests, CI, production plan, StreamingEnabled, plus the
roblox-security-perf-audit scanner counts when the scanner is next to this skill.
"""

import argparse
import json
import os
import re
import subprocess
import sys

CODE_EXT = {".lua", ".luau"}
XML_EXT = {".rbxmx", ".rbxlx"}
SKIP_DIRS = {".git", "node_modules", "Packages", "DevPackages", ".claude", "build", "dist", ".venv"}
SIDE_HINTS = (
    ("server", ("server", "serverscriptservice", "serverstorage")),
    ("client", ("client", "starterplayer", "startergui", "startercharacter")),
    ("shared", ("shared", "replicatedstorage", "common")),
)

SIGNALS = {
    "persistence": r"\b(DataStoreService|GetDataStore|ProfileStore|ProfileService|UpdateAsync|SetAsync)\b",
    "session_lock": r"\b(session ?lock|SessionLock|UpdateAsync|ProfileStore|ProfileService|LockId)\b",
    "bind_to_close": r"\bBindToClose\b",
    "purchases": r"\b(ProcessReceipt|PromptProductPurchase|PromptGamePassPurchase|PromptPurchase)\b",
    "tutorial": r"\b(tutorial|onboarding|FirstTime|TutorialStep)\b",
    "audio": r"\b(SoundService|Instance\.new\(\s*[\"']Sound[\"']|SoundGroup|rbxassetid://\d+.*[Ss]ound|:Play\(\))",
    "animation": r"\b(LoadAnimation|AnimationTrack|Animator|AnimationSet)\b",
    "vfx": r"\b(ParticleEmitter|Vfx\.|TweenService|Beam|Trail)\b",
    "ui": r"\b(ScreenGui|PlayerGui|StarterGui|UIScale|ScreenInsets)\b",
    "localization": r"\b(LocalizationTable|LocalizationService|GetTranslatorForPlayer)\b",
    "analytics": r"\b(AnalyticsService|LogEconomyEvent|LogOnboardingFunnelStepEvent|LogCustomEvent|LogFunnelStepEvent)\b",
    "remotes": r"\b(RemoteEvent|RemoteFunction|UnreliableRemoteEvent|OnServerEvent|OnServerInvoke|FireServer|InvokeServer)\b",
    "pathfinding_or_ai": r"\b(PathfindingService|ComputeAsync)\b",
    "teleport_or_matchmaking": r"\b(TeleportService|MessagingService|MemoryStoreService)\b",
}
PLACEHOLDER = re.compile(r"=\s*0\s*,?\s*(--.*)?\b(TODO|paste|placeholder|fill)\b", re.I)
DEBUG_FLAG = re.compile(r"\b(Greybox|Debug|DEBUG|DevMode|GodMode|SkipTutorial|MockData|UseMock)\w*\s*=\s*true", re.I)
TODO = re.compile(r"\b(TODO|FIXME|HACK|XXX)\b")
HARD_ROBUX = re.compile(r"\b(\d{2,5})\s*Robux\b|\bRobuxPrice\s*=\s*\d+", re.I)


def side_of(path):
    low = path.lower().replace("\\", "/")
    name = os.path.basename(low)
    if ".server." in name:
        return "server"
    if ".client." in name:
        return "client"
    for side, hints in SIDE_HINTS:
        if any(f"/{h}/" in f"/{low}" or low.startswith(h + "/") for h in hints):
            return side
    return "unknown"


def walk(root):
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            yield os.path.join(base, f)


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def find_scanner():
    here = os.path.dirname(os.path.abspath(__file__))
    cand = os.path.normpath(os.path.join(here, "..", "..", "roblox-security-perf-audit", "scripts", "scan_luau.py"))
    return cand if os.path.isfile(cand) else None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project", nargs="?", default=".")
    ap.add_argument("--json", help="also write the facts to this file")
    args = ap.parse_args()
    root = os.path.abspath(args.project)
    if not os.path.isdir(root):
        sys.exit(f"not a folder: {root}")

    files = list(walk(root))
    rel = lambda p: os.path.relpath(p, root).replace("\\", "/")
    code = [p for p in files if os.path.splitext(p)[1].lower() in CODE_EXT]
    xml = [p for p in files if os.path.splitext(p)[1].lower() in XML_EXT]
    sides = {"server": 0, "client": 0, "shared": 0, "unknown": 0}
    loc = 0
    signals = {k: [] for k in SIGNALS}
    todos, placeholders, flags, robux = [], [], [], []
    for p in code + xml:
        text = read(p)
        if os.path.splitext(p)[1].lower() in CODE_EXT:
            sides[side_of(rel(p))] += 1
            loc += text.count("\n") + 1
        body = text
        if os.path.splitext(p)[1].lower() in CODE_EXT:  # comments are not evidence that something exists
            body = re.sub(r"--\[=*\[.*?\]=*\]", "", body, flags=re.S)
            body = "\n".join(re.sub(r"--.*$", "", ln) for ln in body.splitlines())
        for key, pat in SIGNALS.items():
            if re.search(pat, body):
                signals[key].append(rel(p))
        for n, line in enumerate(text.splitlines(), 1):
            if TODO.search(line):
                todos.append(f"{rel(p)}:{n}: {line.strip()[:110]}")
            if PLACEHOLDER.search(line):
                placeholders.append(f"{rel(p)}:{n}: {line.strip()[:110]}")
            if DEBUG_FLAG.search(line):
                flags.append(f"{rel(p)}:{n}: {line.strip()[:110]}")
            if HARD_ROBUX.search(line) and not line.strip().startswith("--"):
                robux.append(f"{rel(p)}:{n}: {line.strip()[:110]}")

    names = {os.path.basename(p).lower() for p in files}
    paths = [rel(p).lower() for p in files]
    has = lambda pred: [p for p in paths if pred(p)][:5]
    project_json = {}
    for cand in ("default.project.json",):
        if os.path.isfile(os.path.join(root, cand)):
            try:
                project_json = json.loads(read(os.path.join(root, cand)))
            except json.JSONDecodeError:
                pass
    streaming = None
    m = re.search(r"StreamingEnabled\"\s*:\s*(true|false)", json.dumps(project_json))
    if m:
        streaming = m.group(1) == "true"
    elif xml:
        streaming = any(re.search(r"StreamingEnabled\">true", read(p)) for p in xml)

    project = {
        "folder": root,
        "name": project_json.get("name") or os.path.basename(root),
        "rojo_project": bool(project_json),
        "place_files": [rel(p) for p in xml][:5],
        "scripts": len(code),
        "lines_of_luau": loc,
        "scripts_by_side": sides,
        "streaming_enabled": streaming,
    }
    docs = {
        "readme": "readme.md" in names,
        "production_plan": bool(has(lambda p: "plan" in os.path.basename(p) and p.endswith(".md"))),
        "ui_spec": bool(has(lambda p: p.endswith("ui-spec.json"))),
        "tests": has(lambda p: p.startswith("tests/") or "/tests/" in p or p.endswith((".spec.luau", ".spec.lua", ".test.luau"))),
        "ci": has(lambda p: p.startswith(".github/workflows/")),
        "linters": [n for n in ("selene.toml", "stylua.toml", ".luaurc") if n in names],
        "store_assets": has(lambda p: os.path.basename(p) in ("icon.png", "icon.jpg") or "thumbnail" in p)[:3],
        "previous_reviews": has(lambda p: "review" in os.path.basename(p) and p.endswith(".json")),
    }
    scanner = None
    path = find_scanner()
    if path and code:
        try:
            out = subprocess.run([sys.executable, path, root], capture_output=True, text=True, timeout=120).stdout
            m = re.search(r"Scanned (\d+) script\(s\): (\d+) high, (\d+) medium, (\d+) low", out)
            if m:
                scanner = {"scripts": int(m[1]), "high": int(m[2]), "medium": int(m[3]), "low": int(m[4])}
        except (OSError, subprocess.SubprocessError):
            pass

    state = {
        "project": project,
        "docs": docs,
        "signals": {k: v[:5] for k, v in signals.items()},
        "signal_file_counts": {k: len(v) for k, v in signals.items()},
        "todos": {"count": len(todos), "examples": todos[:8]},
        "placeholders": placeholders[:10],
        "debug_flags": flags[:10],
        "hardcoded_robux_prices": robux[:10],
        "security_scan": scanner,
    }
    print(render(state))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(state, fh, indent=2, ensure_ascii=False)
    return 0


def render(s):
    p, d, c = s["project"], s["docs"], s["signal_file_counts"]
    sd = p["scripts_by_side"]
    out = [f"# State of {p['name']}", ""]
    if not p["scripts"] and not p["place_files"]:
        out.append("No Luau scripts or place files found here. Point this at the game's project folder, or export the place "
                   "(File > Save to File As) and review it through Studio MCP instead.")
        return "\n".join(out)
    out += [
        f"- {p['scripts']} scripts, ~{p['lines_of_luau']} lines (server {sd['server']}, client {sd['client']}, "
        f"shared {sd['shared']}, unknown {sd['unknown']}); Rojo project: {'yes' if p['rojo_project'] else 'no'}"
        + (f"; place files: {', '.join(p['place_files'])}" if p["place_files"] else ""),
        f"- StreamingEnabled: {p['streaming_enabled'] if p['streaming_enabled'] is not None else 'unknown'}",
        "",
        "## Signals (files that contain them; 0 means nothing found, which is evidence of absence only for code on disk)",
    ]
    labels = [
        ("persistence", "player data saving"), ("session_lock", "session lock / safe saves"), ("bind_to_close", "BindToClose"),
        ("remotes", "remotes"), ("purchases", "purchases"), ("tutorial", "tutorial / onboarding"), ("audio", "audio"),
        ("animation", "animation"), ("vfx", "VFX / tweens"), ("ui", "UI code"), ("localization", "localization"),
        ("analytics", "analytics / funnels"), ("pathfinding_or_ai", "pathfinding / AI"),
        ("teleport_or_matchmaking", "teleport / cross-server"),
    ]
    for key, label in labels:
        eg = f" e.g. {s['signals'][key][0]}" if s["signals"][key] else ""
        out.append(f"- {label}: {c[key]} file(s){eg}")
    out += ["", "## Project hygiene"]
    out.append(f"- README: {d['readme']}; production plan: {d['production_plan']}; ui-spec: {d['ui_spec']}")
    out.append(f"- tests: {', '.join(d['tests'][:3]) or 'none found'}; CI: {', '.join(d['ci'][:2]) or 'none found'}; "
               f"linters: {', '.join(d['linters']) or 'none'}")
    out.append(f"- store assets (icon/thumbnails) in repo: {', '.join(d['store_assets']) or 'none found'}")
    if d["previous_reviews"]:
        out.append(f"- previous review files (use with --previous): {', '.join(d['previous_reviews'])}")
    sc = s["security_scan"]
    out.append("- security/perf scanner: " + (f"{sc['scripts']} scripts, {sc['high']} high, {sc['medium']} medium, {sc['low']} low"
                                             if sc else "not run (scanner not found next to this skill)"))
    out += ["", f"## Loose ends ({s['todos']['count']} TODO/FIXME)"]
    out += [f"- {x}" for x in s["todos"]["examples"]] or ["- none"]
    for title, key in (("Placeholder IDs / values", "placeholders"), ("Debug / greybox flags left on", "debug_flags"),
                       ("Hard-coded Robux prices", "hardcoded_robux_prices")):
        if s[key]:
            out += ["", f"## {title}"] + [f"- {x}" for x in s[key]]
    out += ["", "Facts only: nothing here is a score. Confirm anything surprising by opening the file, and add a playtest "
                "and analytics before scoring."]
    return "\n".join(out)


if __name__ == "__main__":
    sys.exit(main())
