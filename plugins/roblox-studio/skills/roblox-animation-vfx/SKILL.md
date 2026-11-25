---
name: "roblox-animation-vfx"
description: "Plan, make and wire Roblox character animations and visual effects: rig choice (R15/R6/custom), the animation list from the game's mechanics, priorities and looping, Animation Editor, Animation Capture, the Animation Graph Editor (blend trees, state machines, SetParameter), markers for hit timing, IKControl, permissions; plus game-feel VFX (hits, pickups, level ups, purchases, heals, dust, explosions, rarity glows, ambience, trails) with ParticleEmitters, beams, trails, highlights and lights, matched to the art style and kept within phone budgets, with quality and reduced-flashing settings. Uses a Blender MCP server when one is connected (or offers to connect it) for rigs, animation blocking, flipbooks and Roblox-ready FBX exports checked by a script. Ships a validated animation manifest -> Luau module generator, an AnimationSet runtime, a Vfx preset library, generated particle textures and a Studio showcase model. Use whenever someone needs animations, an animation list, attack/emote/idle animations, Animation Graph or IK help, effects, particles, VFX, juice or game feel for a Roblox game, mentions Blender animations or exporting rigs/FBX to Roblox, or says 'zrób animacje', 'efekty cząsteczkowe', 'dodaj efekty', 'animacja ataku', 'animacja w blenderze'."
---

# Roblox Animation & VFX

Goal: every action in the game reads instantly and feels good (anticipation, impact, reward), plays correctly for real players (not just in Studio), and stays cheap on phones. Animation and VFX are planned together from the mechanics, because the same moment (a hit, a pickup, a purchase) needs a pose, an effect and a sound landing on the same frame.

Answer in the user's language; names, ids and code in English.

## 1. Inputs
From `PRODUCTION_PLAN.md` (mechanic -> asset matrix, art direction, avatar type) or the conversation. Ask once with AskUserQuestion (recommended option first) only what is missing:
- Rig: players' own R15 avatars (recommended default), custom StarterCharacter, R6, non-humanoid NPCs.
- Who animates: the user in the Animation Editor / Blender / Moon Animator, Animation Capture from video, Creator Store/catalog animations, or Claude only plans and wires them.
- **Blender**: check whether a Blender MCP server is connected (tools with `blender` in the name; ToolSearch `blender` for deferred ones). If it is, use it for blocking/procedural animations, rig clean-up, flipbook textures and exports. If it isn't and the work needs it, ask once whether they have Blender and offer to connect it, as described in `references/blender.md` section 1; continue with the Studio route if they don't.
- Art style (cartoon, low-poly, realistic, anime, horror, sci-fi, cozy) if not already known from the map or UI style.
- Owner account (user or group): it must upload the animations and textures.

## 2. Plan
Read `references/animation.md`, `references/vfx.md` and `references/sfx.md` (and `references/blender.md` when Blender is in play).
1. **Moment table**: for every verb/event in the mechanic matrix, one row: animation (name, priority, loop, length, markers), VFX preset and size, SFX (name, the marker or event it plays on, max length, takes, status of each take and its id), camera/UI feedback, who plays it (local client, all clients via remote). Big moments get all channels; frequent ones stay small. The SFX columns are `sounds.json` (`references/sfx.md`, example `assets/examples/sounds.json`).
2. **Animation manifest**: write `animations.json` (format in `scripts/anim_manifest.py`; ids 0 until uploaded). Priorities, looping and markers follow the table in the reference. Use an Animation Graph for locomotion blends and jump/fall/land chains when the team has someone to build it; plain tracks otherwise.
3. **VFX list**: map moments to `Vfx.luau` presets; add or tune presets for the style (colors, sizes, textures, counts) in its `Vfx.Presets` table.
4. **SFX list**: `sounds.json` with a prompt + the game's style line per sound, `sfx_manifest.py plan` for the takes and the price before anything is generated.

## 3. Build
**Animations**
- Give the animator a brief per animation: purpose, length, key poses (anticipation -> action -> recovery), the marker frames, loop or not, priority, rig, and how it must look on a tall and a short avatar.
- With Studio MCP tools: set up the rig (Avatar > Character), and for runtime IK create `IKControl`s (Type, EndEffector, Target, ChainRoot, Weight) with `execute_luau`; animation keyframes themselves are made by a person in the Animation Editor (or Capture), then published.
- Sounds: generate the takes from the plan (API key from the environment, price shown first), `python3 scripts/sfx_manifest.py check sounds.json --animations animations.json --vfx src/shared/Vfx.luau` (empty takes, silence before the sound, hits that land after the marker, too long, clipping, loudness), `trim` to cut the silence and match loudness, a person listens and picks, upload, wait for moderation, `luau -o src/shared/SfxIds.luau`; in game `Sfx.configure(SfxIds, { vfx = Vfx })` + `Sfx.bind(set, part)` plays sound and effect on the same marker (`assets/Sfx.luau`).
- Motion moved over from another skeleton (video mocap, AI motion, store packs) or made for both R15 and R6: add `accept` blocks (and `"rigs": ["R15", "R6"]`, `idR6`) to `animations.json` and run `scripts/anim_accept.py` in Blender on every clip until it passes: feet on the floor, no sliding against the game's speed, root in place, the prop stays in the hand and out of the body on every frame, loops close, markers present, R6 matches R15 (`references/animation.md` section 9; example `assets/examples/animations.json`). Load with `AnimationSet.new(animator, Animations.specsFor(humanoid))`.
- Sets of props (weapons, tools, generated models): `scripts/model_batch.py` with a manifest (`assets/examples/models.json`) stands them up, scales them to studs, sets pivots and grip points, keeps them under the triangle budget, closes holes, exports FBX and renders icons from one camera; `--dry-run` first, re-runs redo only what changed (`references/blender.md` section 10). In Studio `ModelSpecs.apply(part)` adds the pivot and grip Attachments.
- With Blender MCP tools: follow `references/blender.md` (R15 rig, 30 FPS, in place, small steps with viewport and timeline screenshots), block or build the animation, run `scripts/blender_check.py` through the code tool, export FBX with its settings, then the user imports it in the Animation Editor (`...` > Import > From FBX Animation), adds events and publishes. Character acting and combat polish stay with a human animator; say so instead of shipping a stiff result.
- After uploading: paste the ids into `animations.json` and run
  `python3 scripts/anim_manifest.py animations.json -o src/shared/Animations.luau` (errors on missing ids unless `--allow-todo`; warns about wrong priorities, loops, missing hit markers, rig mismatches, duplicates).
- Copy `assets/AnimationSet.luau` into shared code; one `AnimationSet.new(animator, Animations.Specs)` per character, `play`, `onMarker`, `setParameter` for graphs, `destroy` on death/despawn.

**VFX**
- Copy `assets/Vfx.luau` into shared code. Server decides, fires a remote with the effect name and target, clients call `Vfx.play(name, positionOrPart)`; loops through `Vfx.attach` + `:Stop()`. Hook `Vfx.setQuality` and `Vfx.setReducedFlashing` to the settings menu.
- Textures: `assets/textures/*.png` (or `python3 scripts/make_textures.py <dir> --size 128`), or flipbook sheets rendered in Blender when it's connected; uploaded by the owner, ids pasted into `Vfx.Textures`.
- Layered flipbooks (slashes, fire bursts, magic): white layers on one 4x4 sheet, colored per variant in game (`Vfx.play("Slash", tip, { variant = "Ember" })`). Pack, check and preview sheets with `python3 scripts/flipbook.py pack|check|preview` (4 px clear margins, power-of-two, frame lit up on the sheet); recipe in `references/vfx.md` section 8.
- Check every preset against Roblox's API database and get a model to look at:
  `lune run scripts/vfx_showcase.luau src/shared/Vfx.luau VfxShowcase.rbxmx` (also `--quality 0.3 --reduced-flashing`). Drag the model into Studio (or insert it with MCP tools) and `screen_capture` each pad (one per preset and per color variant); particles play in Edit mode.
- With Studio MCP: insert, playtest with `start_stop_play`, trigger the moments, `screen_capture`, read `get_console_output` (AnimationSet warns about missing ids and markers).

## 4. Check
- Every animation id in the manifest is owned by (or granted to) the experience; tested in a published place or Team Test, not only in Studio.
- Priorities: attacks override walking, hit reactions override attacks, death overrides everything; no unintended loops.
- Damage, projectiles, footsteps and effects fire from markers, and the server still validates hits.
- Every sound on a marker passes `sfx_manifest.py check` (lands within 50 ms of the marker), only approved (moderated) ids are in `SfxIds.luau`, and someone listened to each take and to the moment in a playtest.
- Retargeted clips passed `anim_accept.py`; after publishing, `AnimCheck.runAll(Animations)` in Studio finds every marker and the saved looping/priority match the manifest.
- Effects read at phone size and low quality, never hide hazards or UI, nothing flashes with reduced flashing on.
- Before/after an effect, animation or sound change: play the same `roblox-launch-kit` scene (`ShotDirector.luau`, shots marked `test`) and compare the captures 1:1.
- `roblox-security-perf-audit` place audit: no emitter over 100/s, total particle budget fine, effect lights without shadows.
Don't claim an animation or effect looks right without a screenshot or playtest; list what a human still has to look at.

## 5. Report
Moment table, the manifest status (done / todo ids), files added (Animations.luau, AnimationSet.luau, Vfx.luau, textures), what was verified (manifest check, showcase validation, playtest, screenshots) and the manual steps (animating, uploading animations and textures with the owner account, permissions, pasting ids).

## Hand-off
`roblox-luau-codegen` to wire remotes and controllers that trigger animations and effects (UI controller pattern, `Net.fire`); `roblox-ui-designer` for UI feedback (pops, toasts, reward screens); `roblox-map-builder` for ambient effects and lighting that the VFX must read against.
