#!/usr/bin/env python3
"""Repeatable scenes for test captures, trailers and thumbnails: one JSON file per scene with the
camera path, the actors and where they stand, the events (animations, effects, sounds, moves) on a
beat grid, the shots to capture, and what must be loaded first. ShotDirector.luau plays them in the
game; this script checks them and writes the module it reads.

  scene_spec.py check scenes/*.json [--animations animations.json] [--sounds sounds.json] [--vfx Vfx.luau]
  scene_spec.py timeline scenes/Clash.json          the shot list: bar, second, camera, events, shots
  scene_spec.py luau scenes/*.json -o src/client/Scenes.luau

Scene file:
{
  "name": "SwordClash", "bpm": 130, "length": { "bars": 4 },
  "ready": { "preload": ["ReplicatedStorage/SceneAssets/Hero"], "streamAround": true, "timeout": 10, "rehearse": true },
  "camera": [ { "at": { "bar": 0 }, "position": [0, 6, -30], "lookAt": [0, 4, 0], "fov": 50 },
              { "at": { "bar": 4 }, "position": [12, 5, -14], "lookAt": [0, 4, 0], "fov": 40, "ease": "Sine" } ],
  "actors": [ { "name": "Hero", "from": "ReplicatedStorage/SceneAssets/Hero", "position": [-4, 0, 0], "face": 90 } ],
  "events": [ { "at": { "bar": 1 }, "kind": "animation", "actor": "Hero", "name": "Chop" },
              { "at": { "bar": 1.5 }, "kind": "vfx", "actor": "Hero", "part": "RightHand", "name": "Slash" } ],
  "shots": [ { "at": { "bar": 1.5 }, "name": "Clash", "use": ["test", "thumbnail"] } ]
}
Times are seconds or { "bar": n } (one bar = 4 beats at bpm; bar 0 is the song's drop), so a
scene that gets shorter keeps everything after it on the beat. Event kinds: animation (name from
animations.json), vfx (Vfx preset), sfx (sounds.json; muted during the rehearsal), move (to, time),
visible (value), or any custom kind the game handles. "ready.rehearse" plays the whole scene once
behind a black screen before the real take, so everything is drawn once before the camera gets there.
"""

import argparse
import glob
import json
import os
import re
import sys

KINDS = {"animation", "vfx", "sfx", "move", "visible"}
USES = {"test", "trailer", "thumbnail"}
EASES = {"Linear", "Sine", "Quad", "Cubic"}
NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


class SceneError(Exception):
    pass


def seconds(value, bpm, where):
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    if isinstance(value, dict) and len(value) == 1 and next(iter(value)) in ("bar", "bars"):
        bars = next(iter(value.values()))
        if not isinstance(bars, (int, float)) or isinstance(bars, bool):
            raise SceneError(f"{where}: bar must be a number")
        if not bpm:
            raise SceneError(f"{where}: bar times need 'bpm'")
        return bars * 4 * 60.0 / bpm
    raise SceneError(f"{where}: time must be seconds or {{\"bar\": n}}")


def vec3(value, where):
    if not (isinstance(value, list) and len(value) == 3 and all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in value)):
        raise SceneError(f"{where}: needs [x, y, z]")
    return [float(v) for v in value]


def load(path):
    with open(path, encoding="utf-8") as f:
        raw = json.load(f)
    name = raw.get("name")
    if not isinstance(name, str) or not NAME.match(name):
        raise SceneError(f"{path}: 'name' must be a Luau identifier")
    bpm = raw.get("bpm")
    if bpm is not None and (not isinstance(bpm, (int, float)) or not 40 <= bpm <= 240):
        raise SceneError(f"{name}: bpm must be 40-240")
    length = seconds(raw.get("length"), bpm, f"{name}.length")
    if length <= 0:
        raise SceneError(f"{name}: length must be > 0")
    scene = {"name": name, "bpm": bpm, "length": length, "source": os.path.basename(path)}

    ready = raw.get("ready") or {}
    unknown = set(ready) - {"preload", "streamAround", "timeout", "rehearse"}
    if unknown:
        raise SceneError(f"{name}.ready: unknown key(s) {sorted(unknown)}")
    scene["ready"] = {
        "preload": list(ready.get("preload") or []),
        "streamAround": bool(ready.get("streamAround", True)),
        "timeout": float(ready.get("timeout", 10)),
        "rehearse": bool(ready.get("rehearse", True)),
    }

    camera = []
    for i, key in enumerate(raw.get("camera") or []):
        where = f"{name}.camera[{i}]"
        k = {"t": seconds(key.get("at"), bpm, where), "position": vec3(key.get("position"), f"{where}.position"), "lookAt": vec3(key.get("lookAt"), f"{where}.lookAt")}
        k["fov"] = float(key.get("fov", 70))
        k["ease"] = key.get("ease", "Sine")
        if k["ease"] not in EASES:
            raise SceneError(f"{where}: ease must be one of {sorted(EASES)}")
        if not 1 <= k["fov"] <= 120:
            raise SceneError(f"{where}: fov must be 1-120")
        if k["position"] == k["lookAt"]:
            raise SceneError(f"{where}: position and lookAt are the same point")
        camera.append(k)
    if not camera:
        raise SceneError(f"{name}: needs at least one camera key")
    times = [k["t"] for k in camera]
    if times != sorted(times):
        raise SceneError(f"{name}: camera keys must be in time order")
    scene["camera"] = camera

    actors, names = [], set()
    for i, actor in enumerate(raw.get("actors") or []):
        where = f"{name}.actors[{i}]"
        if not NAME.match(str(actor.get("name", ""))) or actor["name"] in names:
            raise SceneError(f"{where}: needs a unique 'name' (identifier)")
        if not isinstance(actor.get("from"), str) or "/" not in actor["from"]:
            raise SceneError(f"{where}: 'from' must be a path like ReplicatedStorage/SceneAssets/Hero")
        names.add(actor["name"])
        actors.append({"name": actor["name"], "from": actor["from"], "position": vec3(actor.get("position", [0, 0, 0]), f"{where}.position"), "face": float(actor.get("face", 0))})
    scene["actors"] = actors

    events = []
    for i, event in enumerate(raw.get("events") or []):
        where = f"{name}.events[{i}]"
        e = dict(event)
        e["t"] = seconds(event.get("at"), bpm, where)
        e.pop("at", None)
        if not isinstance(e.get("kind"), str):
            raise SceneError(f"{where}: needs a 'kind'")
        if e.get("actor") is not None and e["actor"] not in names:
            raise SceneError(f"{where}: unknown actor '{e['actor']}'")
        if e["kind"] in ("animation", "vfx", "sfx") and not isinstance(e.get("name"), str):
            raise SceneError(f"{where}: {e['kind']} events need a 'name'")
        if e["kind"] in ("animation", "move", "visible") and not e.get("actor"):
            raise SceneError(f"{where}: {e['kind']} events need an 'actor'")
        if e["kind"] == "move":
            e["to"] = vec3(e.get("to"), f"{where}.to")
            e["time"] = float(e.get("time", 0))
        events.append(e)
    scene["events"] = sorted(events, key=lambda e: e["t"])

    shots = []
    for i, shot in enumerate(raw.get("shots") or []):
        where = f"{name}.shots[{i}]"
        if not NAME.match(str(shot.get("name", ""))):
            raise SceneError(f"{where}: needs a 'name' (identifier)")
        use = shot.get("use") or ["test"]
        if not set(use) <= USES:
            raise SceneError(f"{where}: use must be from {sorted(USES)}")
        shots.append({"t": seconds(shot.get("at"), bpm, where), "name": shot["name"], "use": use})
    scene["shots"] = sorted(shots, key=lambda s: s["t"])
    return scene


def check(scene, animations=None, sounds=None, presets=None):
    """Problems that are valid JSON but break the take: list of (level, message)."""
    out = []
    length = scene["length"]
    for what, items in (("camera key", scene["camera"]), ("event", scene["events"]), ("shot", scene["shots"])):
        for item in items:
            if not 0 <= item["t"] <= length + 1e-9:
                out.append(("ERROR", f"{what} at {item['t']:.2f} s is outside the scene (0-{length:.2f} s)"))
    if scene["camera"][0]["t"] > 0:
        out.append(("WARN", f"first camera key at {scene['camera'][0]['t']:.2f} s: the camera holds that pose from 0"))
    if scene["camera"][-1]["t"] < length - 1e-9:
        out.append(("INFO", f"last camera key at {scene['camera'][-1]['t']:.2f} s, the camera holds until {length:.2f} s"))
    if not scene["shots"]:
        out.append(("WARN", "no shots: nothing is captured for tests, trailers or thumbnails"))
    if not scene["ready"]["preload"] and scene["actors"]:
        out.append(("WARN", "ready.preload is empty: actors and props may pop in late on the first take"))
    if not scene["ready"]["rehearse"]:
        out.append(("WARN", "ready.rehearse is off: the first take is also the one where things load late"))
    for event in scene["events"]:
        kind, name = event["kind"], event.get("name")
        if kind == "animation" and animations is not None and name not in animations:
            out.append(("ERROR", f"animation '{name}' is not in animations.json"))
        elif kind == "sfx" and sounds is not None and name not in sounds:
            out.append(("ERROR", f"sound '{name}' is not in sounds.json"))
        elif kind == "vfx" and presets is not None and name not in presets:
            out.append(("ERROR", f"vfx '{name}' is not a Vfx preset"))
        elif kind not in KINDS:
            out.append(("INFO", f"custom event kind '{kind}': the game must pass a handler for it"))
    return out


def bar_of(t, bpm):
    return f"{t / (4 * 60.0 / bpm):g}" if bpm else "-"


def timeline(scene):
    rows = [(k["t"], "camera", f"at {k['position']} looking at {k['lookAt']}, fov {k['fov']:g} ({k['ease']})") for k in scene["camera"]]
    rows += [(e["t"], e["kind"], " ".join(str(e[k]) for k in ("actor", "name", "part", "to") if e.get(k) is not None)) for e in scene["events"]]
    rows += [(s["t"], "SHOT", f"{s['name']} ({', '.join(s['use'])})") for s in scene["shots"]]
    lines = [f"# {scene['name']}: {scene['length']:.2f} s" + (f", {scene['bpm']:g} BPM, {bar_of(scene['length'], scene['bpm'])} bars" if scene["bpm"] else ""), "", "| Bar | Second | What | Details |", "| --- | --- | --- | --- |"]
    for t, what, details in sorted(rows, key=lambda r: (r[0], r[1] != "camera", r[1] == "SHOT")):
        lines.append(f"| {bar_of(t, scene['bpm'])} | {t:.2f} | {what} | {details} |")
    return "\n".join(lines)


def lua(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return f"{value:g}" if isinstance(value, int) else f"{round(value, 4):g}"
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list):
        return "{ " + ", ".join(lua(v) for v in value) + " }"
    raise TypeError(value)


def v3(v):
    return f"Vector3.new({v[0]:g}, {v[1]:g}, {v[2]:g})"


def to_luau(scenes):
    out = [
        f"-- Generated by scene_spec.py from {', '.join(s['source'] for s in scenes)}. Edit the JSON and regenerate.",
        "-- Times in seconds. Play with ShotDirector.run(Scenes.<Name>, options).",
        "",
        "return {",
    ]
    for s in scenes:
        out.append(f"\t{s['name']} = {{")
        out.append(f"\t\tName = {lua(s['name'])},")
        out.append(f"\t\tLength = {lua(s['length'])},")
        r = s["ready"]
        out.append(f"\t\tReady = {{ Preload = {lua(r['preload'])}, StreamAround = {lua(r['streamAround'])}, Timeout = {lua(r['timeout'])}, Rehearse = {lua(r['rehearse'])} }},")
        out.append("\t\tCamera = {")
        for k in s["camera"]:
            out.append(f"\t\t\t{{ T = {lua(k['t'])}, Position = {v3(k['position'])}, LookAt = {v3(k['lookAt'])}, Fov = {lua(k['fov'])}, Ease = {lua(k['ease'])} }},")
        out.append("\t\t},")
        out.append("\t\tActors = {")
        for a in s["actors"]:
            out.append(f"\t\t\t{{ Name = {lua(a['name'])}, From = {lua(a['from'])}, Position = {v3(a['position'])}, Face = {lua(a['face'])} }},")
        out.append("\t\t},")
        out.append("\t\tEvents = {")
        for e in s["events"]:
            fields = [f"T = {lua(e['t'])}", f"Kind = {lua(e['kind'])}"]
            for key in sorted(k for k in e if k not in ("t", "kind")):
                value = e[key]
                field = key[0].upper() + key[1:]
                fields.append(f"{field} = {v3(value)}" if key == "to" else f"{field} = {lua(value)}")
            out.append(f"\t\t\t{{ {', '.join(fields)} }},")
        out.append("\t\t},")
        out.append("\t\tShots = {")
        for sh in s["shots"]:
            out.append(f"\t\t\t{{ T = {lua(sh['t'])}, Name = {lua(sh['name'])}, Use = {lua(sh['use'])} }},")
        out.append("\t\t},")
        out.append("\t},")
    out += ["}", ""]
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="command", required=True)
    c = sub.add_parser("check")
    c.add_argument("scenes", nargs="+")
    c.add_argument("--animations")
    c.add_argument("--sounds")
    c.add_argument("--vfx")
    t = sub.add_parser("timeline")
    t.add_argument("scene")
    l = sub.add_parser("luau")
    l.add_argument("scenes", nargs="+")
    l.add_argument("-o", "--out", required=True)
    args = ap.parse_args()

    paths = [p for pattern in getattr(args, "scenes", [getattr(args, "scene", "")]) for p in (sorted(glob.glob(pattern)) or [pattern])]
    try:
        scenes = [load(p) for p in paths]
    except (SceneError, json.JSONDecodeError, OSError) as error:
        print(f"scene error: {error}")
        return 2
    if len({s["name"] for s in scenes}) != len(scenes):
        print("scene error: two scenes share a name")
        return 2
    if args.command == "timeline":
        print(timeline(scenes[0]))
        return 0
    if args.command == "luau":
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(to_luau(scenes))
        print(f"wrote {args.out} ({len(scenes)} scene(s))")
        return 0
    animations = sounds = presets = None
    if args.animations:
        animations = {a.get("name") for a in json.load(open(args.animations, encoding="utf-8")).get("animations", [])}
    if args.sounds:
        sounds = {s.get("name") for s in json.load(open(args.sounds, encoding="utf-8")).get("sounds", [])}
    if args.vfx:
        text = open(args.vfx, encoding="utf-8").read()
        presets = set(re.findall(r"^\t([A-Za-z_]\w*) = \{\s*\n\t\tkind =", text[text.index("Vfx.Presets = {") :], re.M))
    errors = 0
    for scene in scenes:
        problems = check(scene, animations, sounds, presets)
        for level, message in problems:
            print(f"{level:5} {scene['name']}: {message}")
        errors += sum(1 for level, _ in problems if level == "ERROR")
        print(f"scene {scene['name']}: {scene['length']:.2f} s, {len(scene['camera'])} camera key(s), {len(scene['actors'])} actor(s), {len(scene['events'])} event(s), {len(scene['shots'])} shot(s)")
    print(f"{errors} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
