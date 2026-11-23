#!/usr/bin/env python3
"""Sound effects manifest: the SFX column of the moment table as data, plus a local checker for
the takes (WAV files), a cleaner, a generation plan and the Luau module the game plays from.
Python standard library only.

  sfx_manifest.py plan  sounds.json                 prompts with the style line, takes, seconds, price
  sfx_manifest.py check sounds.json [--root dir] [--animations animations.json] [--vfx Vfx.luau]
  sfx_manifest.py trim  sounds.json --out dir | --in-place      cut leading silence, match loudness
  sfx_manifest.py luau  sounds.json -o src/shared/SfxIds.luau   approved ids only

sounds.json:
{
  "style": "anime, loud, punchy, no music, no voice",    style line added to every prompt
  "takes": 2, "targetLoudness": -16, "pricePerSecond": 0.002,
  "defaults": { "maxLead": 0.03, "syncTolerance": 0.05, "maxAttack": 0.25, "volume": 0.6,
                "pitch": [0.95, 1.05], "minInterval": 0.05, "repeatVolume": 0.5 },
  "sounds": [
    { "name": "SwordHit", "prompt": "two steel swords clashing hard, a bright ringing clang",
      "marker": "Chop:Hit", "vfx": "Slash", "maxLength": 0.8,
      "variants": [ { "file": "sfx/SwordHit_1.wav", "status": "approved", "id": "rbxassetid://123" },
                    { "file": "sfx/SwordHit_2.wav", "status": "generated" } ] }
  ]
}
  marker   "Animation:Marker" from animations.json: the sound plays on that animation event, so
           its onset plus its build-up must land within syncTolerance of the marker
  event    name of a code-triggered moment instead (pickup, UI hover...)
  vfx      Vfx preset played on the same marker (checked against Vfx.luau with --vfx)
  status   generated -> picked (someone listened and chose it) -> uploaded (has an id, waiting for
           moderation: plays nothing yet) -> approved (moderation passed: goes into the game);
           rejected takes are kept for the record and skipped
Take checks: empty (silent) file, silence before the sound (lag), a late hit (onset + build-up
after the marker, or a long build-up), longer than maxLength, clipping, loudness off target,
sample rate. Exit 1 on errors. The AI can measure a sound but can't hear it: picking stays human.
"""

import argparse
import json
import math
import os
import re
import sys
import wave
from array import array

STATUSES = ("generated", "picked", "uploaded", "approved", "rejected")
DEFAULTS = {"maxLead": 0.03, "syncTolerance": 0.05, "maxAttack": 0.25, "volume": 0.6, "pitch": [0.95, 1.05], "minInterval": 0.05, "repeatVolume": 0.5}
SOUND_KEYS = {"name", "prompt", "marker", "event", "vfx", "maxLength", "maxLead", "maxAttack", "syncTolerance", "takes", "volume", "pitch", "minInterval", "repeatVolume", "spatial", "variants"}
TOP_KEYS = {"style", "takes", "targetLoudness", "pricePerSecond", "defaults", "sounds"}
WINDOW = 0.005  # envelope window, seconds
EMPTY_DB = -50.0  # quieter than this everywhere = nothing plays
ONSET_BELOW_PEAK = 30.0  # the sound starts where the envelope comes within 30 dB of its peak
NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


class ManifestError(Exception):
    pass


def db(value):
    return 20 * math.log10(value) if value > 1e-12 else -240.0


# ---------------------------------------------------------------- WAV


def read_wav(path):
    """Interleaved float samples in -1..1, channels, rate, bits."""
    with wave.open(path, "rb") as f:
        channels, width, rate, count = f.getnchannels(), f.getsampwidth(), f.getframerate(), f.getnframes()
        if f.getcomptype() != "NONE":
            raise ValueError("compressed WAV; export PCM")
        raw = f.readframes(count)
    if width == 1:
        samples = [(b - 128) / 128 for b in raw]
    elif width == 2:
        data = array("h", raw)
        if sys.byteorder == "big":
            data.byteswap()
        samples = [v / 32768 for v in data]
    elif width == 3:
        samples = [int.from_bytes(raw[i : i + 3], "little", signed=True) / 8388608 for i in range(0, len(raw), 3)]
    elif width == 4:
        data = array("i", raw)
        if sys.byteorder == "big":
            data.byteswap()
        samples = [v / 2147483648 for v in data]
    else:
        raise ValueError(f"{width * 8}-bit samples are not supported")
    return samples, channels, rate, width * 8


def write_wav(path, samples, channels, rate):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    data = array("h", (max(-32768, min(32767, int(round(s * 32767)))) for s in samples))
    if sys.byteorder == "big":
        data.byteswap()
    with wave.open(path, "wb") as f:
        f.setnchannels(channels)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(data.tobytes())


def analyze(path):
    samples, channels, rate, bits = read_wav(path)
    frames = len(samples) // channels
    duration = frames / rate
    peak = max((abs(s) for s in samples), default=0.0)
    clipped = sum(1 for s in samples if abs(s) >= 0.999)
    hop = max(1, int(rate * WINDOW)) * channels
    envelope = []
    for start in range(0, len(samples), hop):
        chunk = samples[start : start + hop]
        envelope.append(math.sqrt(sum(s * s for s in chunk) / len(chunk)) if chunk else 0.0)
    result = {"duration": duration, "rate": rate, "channels": channels, "bits": bits, "peakDb": db(peak), "clipped": clipped}
    top = max(envelope, default=0.0)
    if db(peak) < EMPTY_DB or not envelope:
        result.update(empty=True, onset=None, peakTime=None, end=None, loudnessDb=None)
        return result
    threshold = max(top * 10 ** (-ONSET_BELOW_PEAK / 20), 10 ** (EMPTY_DB / 20))
    loud = [i for i, v in enumerate(envelope) if v >= threshold]
    first, last = loud[0], loud[-1]
    peak_index = envelope.index(top)
    active = envelope[first : last + 1]
    result.update(
        empty=False,
        onset=first * WINDOW,
        peakTime=peak_index * WINDOW,
        end=min(duration, (last + 1) * WINDOW),
        loudnessDb=db(math.sqrt(sum(v * v for v in active) / len(active))),
    )
    return result


# ---------------------------------------------------------------- manifest


def load(path):
    with open(path, encoding="utf-8") as f:
        manifest = json.load(f)
    unknown = set(manifest) - TOP_KEYS
    if unknown:
        raise ManifestError(f"unknown top-level key(s) {sorted(unknown)}")
    if not isinstance(manifest.get("sounds"), list) or not manifest["sounds"]:
        raise ManifestError("'sounds' must be a non-empty list")
    defaults = {**DEFAULTS, **(manifest.get("defaults") or {})}
    sounds, names = [], set()
    for index, raw in enumerate(manifest["sounds"]):
        name = raw.get("name") if isinstance(raw, dict) else None
        if not isinstance(name, str) or not NAME.match(name):
            raise ManifestError(f"sounds[{index}]: needs a 'name' that is a Luau identifier")
        if name in names:
            raise ManifestError(f"{name}: duplicate name")
        names.add(name)
        unknown = set(raw) - SOUND_KEYS
        if unknown:
            raise ManifestError(f"{name}: unknown key(s) {sorted(unknown)}")
        sound = {**defaults, "takes": manifest.get("takes", 2), **raw}
        if sound.get("marker") is not None and not re.match(r"^[A-Za-z_]\w*:[A-Za-z_]\w*$", str(sound["marker"])):
            raise ManifestError(f"{name}: marker must look like 'Animation:Marker' (e.g. Chop:Hit)")
        pitch = sound["pitch"]
        if not (isinstance(pitch, list) and len(pitch) == 2 and 0.5 <= pitch[0] <= pitch[1] <= 2):
            raise ManifestError(f"{name}: pitch must be [min, max] within 0.5..2")
        for key in ("maxLength", "maxLead", "maxAttack", "syncTolerance", "volume", "minInterval", "repeatVolume"):
            value = sound.get(key)
            if value is not None and (isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0):
                raise ManifestError(f"{name}: {key} must be a number >= 0")
        for v_index, variant in enumerate(sound.get("variants") or []):
            if not isinstance(variant, dict) or variant.get("status", "generated") not in STATUSES:
                raise ManifestError(f"{name}.variants[{v_index}]: status must be one of {', '.join(STATUSES)}")
        sounds.append(sound)
    return manifest, sounds


def asset_id(value):
    match = re.fullmatch(r"(?:rbxassetid://)?(\d+)", str(value or "").strip())
    return int(match.group(1)) if match and int(match.group(1)) > 0 else None


def vfx_presets(path):
    """Preset names from Vfx.luau: the keys of Vfx.Presets."""
    text = open(path, encoding="utf-8").read()
    body = text[text.index("Vfx.Presets = {") :]
    return set(re.findall(r"^\t([A-Za-z_]\w*) = \{\s*\n\t\tkind =", body, re.M))


def animation_markers(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return {a.get("name"): set(a.get("markers") or []) for a in data.get("animations", [])}


# ---------------------------------------------------------------- commands


def cmd_plan(manifest, sounds):
    style = manifest.get("style", "")
    price = manifest.get("pricePerSecond")
    total_takes = total_seconds = 0
    for sound in sounds:
        takes = int(sound["takes"])
        seconds = float(sound.get("maxLength") or 1.0)
        total_takes += takes
        total_seconds += takes * seconds
        if not sound.get("prompt"):
            print(f"WARN  {sound['name']}: no prompt")
            continue
        prompt = sound["prompt"] + (f", {style}" if style else "") + f", under {seconds:g} seconds"
        print(f"{sound['name']} x{takes} ({seconds:g} s): {prompt}")
    cost = f", about ${price * total_seconds:.2f} at ${price}/s" if price else ""
    print(f"{len(sounds)} sound(s), {total_takes} take(s), {total_seconds:g} s of audio{cost}. Nothing was generated: run your generator after a yes.")
    return 0


def cmd_check(manifest, sounds, root, animations=None, vfx=None):
    errors = warnings = 0
    markers = animation_markers(animations) if animations else None
    presets = vfx_presets(vfx) if vfx else None
    target = manifest.get("targetLoudness")

    def say(level, where, message):
        nonlocal errors, warnings
        errors += level == "ERROR"
        warnings += level == "WARN"
        print(f"{level:5} {where}: {message}")

    for sound in sounds:
        name = sound["name"]
        if sound.get("marker") and markers is not None:
            anim, marker = sound["marker"].split(":")
            if anim not in markers:
                say("ERROR", name, f"marker {sound['marker']}: no animation '{anim}' in {os.path.basename(animations)}")
            elif marker not in markers[anim]:
                say("ERROR", name, f"marker {sound['marker']}: '{anim}' has no '{marker}' marker in {os.path.basename(animations)}")
        if not sound.get("marker") and not sound.get("event"):
            say("WARN", name, "neither 'marker' nor 'event': nothing says when it plays")
        if sound.get("vfx") and presets is not None and sound["vfx"] not in presets:
            say("ERROR", name, f"vfx '{sound['vfx']}' is not a preset in {os.path.basename(vfx)}")
        approved = pending = 0
        for index, variant in enumerate(sound.get("variants") or []):
            status = variant.get("status", "generated")
            where = f"{name}[{index + 1}] {variant.get('file', '?')}"
            if status == "rejected":
                continue
            if status in ("uploaded", "approved") and asset_id(variant.get("id")) is None:
                say("ERROR", where, f"status {status} needs the uploaded 'id'")
            approved += status == "approved"
            pending += status == "uploaded"
            path = os.path.join(root, variant.get("file", ""))
            if not variant.get("file") or not os.path.exists(path):
                if status in ("generated", "picked"):
                    say("ERROR", where, "file not found")
                continue
            try:
                a = analyze(path)
            except (ValueError, wave.Error, EOFError) as error:
                say("ERROR", where, f"can't read: {error}")
                continue
            if a["empty"]:
                level = "no signal" if a["peakDb"] < -200 else f"peak {a['peakDb']:.0f} dBFS"
                say("ERROR", where, f"empty: silent all through ({level}), plays nothing")
                continue
            lead, attack, length = a["onset"], a["peakTime"] - a["onset"], a["end"] - a["onset"]
            print(f"take  {where}: {status}, {a['duration']:.2f} s file, sound {lead * 1000:.0f}-{a['end'] * 1000:.0f} ms, loudest at {a['peakTime'] * 1000:.0f} ms, {a['loudnessDb']:.1f} dBFS")
            if lead > sound["maxLead"]:
                say("ERROR", where, f"{lead * 1000:.0f} ms of silence before the sound (lag in game); run trim")
            if sound.get("marker"):
                late = lead + attack
                if late > sound["syncTolerance"]:
                    say("ERROR", where, f"hits {late * 1000:.0f} ms after the {sound['marker']} marker ({lead * 1000:.0f} ms silence + {attack * 1000:.0f} ms build-up; max {sound['syncTolerance'] * 1000:.0f} ms){'' if attack <= sound['syncTolerance'] else ': pick a take that hits at once'}")
            elif attack > sound["maxAttack"]:
                say("WARN", where, f"builds up for {attack * 1000:.0f} ms before it is loudest (max {sound['maxAttack'] * 1000:.0f} ms)")
            if sound.get("maxLength") and length > sound["maxLength"] + 1e-6:
                say("ERROR", where, f"the sound lasts {length:.2f} s, max {sound['maxLength']:g} s (trim only cuts silence: regenerate it shorter)")
            if a["clipped"] >= 4:
                say("WARN", where, f"{a['clipped']} clipped samples (peak {a['peakDb']:.1f} dBFS); lower the gain")
            if target is not None and abs(a["loudnessDb"] - target) > 3:
                say("WARN", where, f"loudness {a['loudnessDb']:.1f} dBFS, target {target} (run trim to match)")
            if a["rate"] not in (44100, 48000):
                say("WARN", where, f"{a['rate']} Hz; use 44.1 or 48 kHz")
        if approved == 0:
            say("WARN", name, "no approved take: plays nothing in game" + (f" ({pending} waiting for moderation)" if pending else ""))
        elif pending:
            say("INFO", name, f"{pending} take(s) waiting for moderation")
    print(f"{errors} error(s), {warnings} warning(s)")
    return 1 if errors else 0


def cmd_trim(manifest, sounds, root, out=None, in_place=False):
    target = manifest.get("targetLoudness", -16)
    done = 0
    for sound in sounds:
        for variant in sound.get("variants") or []:
            if variant.get("status") == "rejected" or not variant.get("file"):
                continue
            src = os.path.join(root, variant["file"])
            if not os.path.exists(src):
                print(f"skip  {variant['file']}: not found")
                continue
            a = analyze(src)
            if a["empty"]:
                print(f"skip  {variant['file']}: silent, nothing to keep")
                continue
            samples, channels, rate, _ = read_wav(src)
            start = max(0, int((a["onset"] - 0.005) * rate))  # 5 ms pre-roll keeps the transient
            stop = min(len(samples) // channels, int((a["end"] + 0.08) * rate))
            cut = samples[start * channels : stop * channels]
            gain_db = min(target - a["loudnessDb"], -1.0 - a["peakDb"])  # never above -1 dBFS peak
            gain = 10 ** (gain_db / 20)
            fade_in, fade_out = max(1, int(0.003 * rate)), max(1, int(0.02 * rate))
            frames = len(cut) // channels
            for i in range(frames):
                g = gain
                if i < fade_in:
                    g *= i / fade_in
                if frames - 1 - i < fade_out:
                    g *= (frames - 1 - i) / fade_out
                for c in range(channels):
                    cut[i * channels + c] *= g
            dst = src if in_place else os.path.join(out, variant["file"])
            write_wav(dst, cut, channels, rate)
            done += 1
            print(f"trim  {variant['file']}: cut {start / rate * 1000:.0f} ms before, {(a['duration'] - stop / rate) * 1000:.0f} ms after, {gain_db:+.1f} dB -> {dst}")
    print(f"{done} take(s) written")
    return 0


def luau_string(text):
    return '"' + str(text).replace("\\", "\\\\").replace('"', '\\"') + '"'


def cmd_luau(manifest, sounds, out, source):
    lines = [
        f"-- Generated by sfx_manifest.py from {source}. Edit the JSON and regenerate.",
        "-- Approved takes only (uploaded takes wait for moderation and play nothing until then).",
        "-- Sfx.configure(require(this)) then Sfx.play(name, part) or Sfx.bind(animationSet, part).",
        "",
        "return {",
    ]
    for sound in sorted(sounds, key=lambda s: s["name"]):
        ids = [f"rbxassetid://{asset_id(v.get('id'))}" for v in sound.get("variants") or [] if v.get("status") == "approved" and asset_id(v.get("id"))]
        if not ids:
            lines.append(f"\t-- {sound['name']}: no approved take yet")
        fields = [
            f"Ids = {{ {', '.join(luau_string(i) for i in ids)} }}" if ids else "Ids = {}",
            f"Volume = {sound['volume']:g}",
            f"Pitch = {{ {sound['pitch'][0]:g}, {sound['pitch'][1]:g} }}",
            f"MinInterval = {sound['minInterval']:g}",
            f"RepeatVolume = {sound['repeatVolume']:g}",
        ]
        if sound.get("marker"):
            fields.append(f"Marker = {luau_string(sound['marker'])}")
        if sound.get("event"):
            fields.append(f"Event = {luau_string(sound['event'])}")
        if sound.get("vfx"):
            fields.append(f"Vfx = {luau_string(sound['vfx'])}")
        fields.append(f"Spatial = {'false' if sound.get('spatial') is False else 'true'}")
        lines.append(f"\t{sound['name']} = {{ {', '.join(fields)} }},")
    lines += ["}", ""]
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"wrote {out}")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="command", required=True)
    for name in ("plan", "check", "trim", "luau"):
        p = sub.add_parser(name)
        p.add_argument("manifest")
        p.add_argument("--root", help="folder the variant files are relative to (default: the manifest's folder)")
        if name == "check":
            p.add_argument("--animations", help="animations.json: markers must exist")
            p.add_argument("--vfx", help="Vfx.luau: vfx presets must exist")
        if name == "trim":
            group = p.add_mutually_exclusive_group(required=True)
            group.add_argument("--out", help="write cleaned copies here (same relative paths)")
            group.add_argument("--in-place", action="store_true", help="overwrite the takes")
        if name == "luau":
            p.add_argument("-o", "--out", required=True)
    args = ap.parse_args()
    try:
        manifest, sounds = load(args.manifest)
    except (ManifestError, json.JSONDecodeError) as error:
        print(f"manifest error: {error}")
        return 2
    root = args.root or os.path.dirname(os.path.abspath(args.manifest))
    if args.command == "plan":
        return cmd_plan(manifest, sounds)
    if args.command == "check":
        return cmd_check(manifest, sounds, root, args.animations, args.vfx)
    if args.command == "trim":
        return cmd_trim(manifest, sounds, root, args.out, args.in_place)
    return cmd_luau(manifest, sounds, args.out, os.path.basename(args.manifest))


if __name__ == "__main__":
    sys.exit(main())
