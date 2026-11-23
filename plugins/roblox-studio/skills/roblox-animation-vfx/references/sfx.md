# Sound effects reference

The SFX column of the moment table as data (`sounds.json`), checked locally before anything is uploaded. The `Sound` properties used by `Sfx.luau` are checked against Roblox's API database in the tests; upload formats, size limits and moderation rules change, so confirm them in the Creator Hub (create.roblox.com/docs/audio) before a big upload.

## Contents
1. Moment table -> sounds.json
2. Making the takes
3. Checking and cleaning
4. Upload, moderation, ids
5. In the game: Sfx.luau and the marker sync
6. What stays human

## 1. Moment table -> sounds.json
Every moment row that has a sound gets one entry (`scripts/sfx_manifest.py` documents the format; example `assets/examples/sounds.json`):
- `name` (Luau identifier, what code calls), `prompt` (what it is), `maxLength` (a swing is under a second, a footstep under half), `takes` (how many to generate, 2-3; more variants for frequent sounds).
- **When it plays**: `marker` = `"Animation:Marker"` from `animations.json` (hits, footsteps, releases: the sound lands with the pose) or `event` for code-triggered moments (pickup, purchase, UI focus).
- `vfx`: the Vfx preset that plays on the same marker; `volume`, `pitch` range for variation, `minInterval` + `repeatVolume` for sounds that can repeat fast, `spatial: false` for UI and 2D sounds.
- `variants`: one per take with `file`, `status` and, once uploaded, `id`. Status: `generated` -> `picked` (a person listened and chose it) -> `uploaded` (has an id, in moderation, plays nothing yet) -> `approved` (goes into the game); `rejected` stays for the record.

## 2. Making the takes
- Every prompt is two parts: what it is ("two steel swords clashing hard, a bright ringing clang") plus one **style line** shared by the whole game (`style`: "anime, loud, punchy, no music, no voice"), and short. `sfx_manifest.py plan sounds.json` prints the full prompts, the number of takes, the seconds of audio and, with `pricePerSecond`, the price, and generates nothing: show it, get a yes, then run the generator.
- Generator APIs (sound-effect models on hosted model platforms) need a key: the user stores it as an environment variable once; code reads it from the environment and never prints it. Never paste keys into the chat. Show the price before every batch; 2 takes each is the usual start.
- Try a model by hand on a few prompts first; switching models is one line of code, picking the style is not.

## 3. Checking and cleaning
`python3 scripts/sfx_manifest.py check sounds.json --animations animations.json --vfx Vfx.luau` measures every take (WAV, PCM) and the manifest:
- **empty**: silent all through (hover and pickup takes come back empty more often than you'd think);
- **silence before the sound**: more than `maxLead` (30 ms) is lag in game;
- **late hit**: for marker sounds, silence + build-up to the loudest point must fit in `syncTolerance` (50 ms, about 1.5 frames), or the hit lands after the pose; event sounds warn above `maxAttack`;
- **too long** (the sound itself, not its trailing silence), **clipping**, **loudness** more than 3 dB off `targetLoudness`, sample rate;
- the marker exists on that animation, the vfx preset exists, uploaded/approved takes have ids, sounds with no approved take play nothing.

`sfx_manifest.py trim sounds.json --out cleaned/` (or `--in-place`) cuts each take where it gets loud (5 ms pre-roll), drops trailing silence, matches loudness to the target with the peak kept under -1 dBFS, and fades the edges. It fixes lag and loudness; a slow build-up or a sound that is too long needs another take.

## 4. Upload, moderation, ids
- Upload the picked takes with the account or group that owns the experience (Creator Hub, Asset Manager bulk import, or the Open Cloud assets API with a key from the environment). Put each id in its variant and set `uploaded`.
- New audio goes through moderation; until it passes it plays nothing in game. Check each one, then set `approved`. `check` lists sounds with takes still waiting.
- `sfx_manifest.py luau sounds.json -o src/shared/SfxIds.luau` writes only approved ids, with volume, pitch, repeat settings, marker, event, vfx and spatial.

## 5. In the game: Sfx.luau and the marker sync
- `Sfx.configure(require(SfxIds), { vfx = Vfx })`, then `Sfx.bind(animationSet, weaponOrRoot)`: every sound with a `marker` plays on that AnimationSet marker together with its Vfx preset, at the same part, on the same frame. Code-triggered sounds: `Sfx.play(name, part)`.
- Each play picks a random approved take and a pitch in the range; a repeat inside `minInterval` plays at `repeatVolume`, so a hundred hits or a horde don't sound like a machine gun.
- Sounds play on the client, like effects: the server fires one remote per moment, clients play animation, effect and sound.

## 6. What stays human
The checker measures; it can't hear. An explosion that sounds like a balloon losing air passes every number. A person listens to every take (`picked`), and to the moment in a playtest with the animation and the effect.
