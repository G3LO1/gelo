---
name: "roblox-animation-vfx"
description: "Plan, make and wire Roblox character animations and visual effects: rig choice (R15/R6/custom), the animation list from the game's mechanics, priorities and looping, Animation Editor, Animation Capture, the Animation Graph Editor (blend trees, state machines, SetParameter), markers for hit timing, IKControl, permissions; plus game-feel VFX (hits, pickups, level ups, purchases, heals, dust, explosions, rarity glows, ambience, trails) with ParticleEmitters, beams, trails, highlights and lights, matched to the art style and kept within phone budgets, with quality and reduced-flashing settings. Ships a validated animation manifest -> Luau module generator, an AnimationSet runtime, a Vfx preset library, generated particle textures and a Studio showcase model. Use whenever someone needs animations, an animation list, attack/emote/idle animations, Animation Graph or IK help, effects, particles, VFX, juice or game feel for a Roblox game, or says 'zrób animacje', 'efekty cząsteczkowe', 'dodaj efekty', 'animacja ataku'."
---

# Roblox Animation & VFX

Goal: every action in the game reads instantly and feels good (anticipation, impact, reward), plays correctly for real players (not just in Studio), and stays cheap on phones. Animation and VFX are planned together from the mechanics, because the same moment (a hit, a pickup, a purchase) needs a pose, an effect and a sound landing on the same frame.

Answer in the user's language; names, ids and code in English.

## 1. Inputs
From `PRODUCTION_PLAN.md` (mechanic -> asset matrix, art direction, avatar type) or the conversation. Ask once with AskUserQuestion (recommended option first) only what is missing:
- Rig: players' own R15 avatars (recommended default), custom StarterCharacter, R6, non-humanoid NPCs.
- Who animates: the user in the Animation Editor / Blender / Moon Animator, Animation Capture from video, Creator Store/catalog animations, or Claude only plans and wires them.
- Art style (cartoon, low-poly, realistic, anime, horror, sci-fi, cozy) if not already known from the map or UI style.
- Owner account (user or group): it must upload the animations and textures.

## 2. Plan
Read `references/animation.md` and `references/vfx.md`.
1. **Moment table**: for every verb/event in the mechanic matrix, one row: animation (name, priority, loop, length, markers), VFX preset and size, SFX, camera/UI feedback, who plays it (local client, all clients via remote). Big moments get all channels; frequent ones stay small.
2. **Animation manifest**: write `animations.json` (format in `scripts/anim_manifest.py`; ids 0 until uploaded). Priorities, looping and markers follow the table in the reference. Use an Animation Graph for locomotion blends and jump/fall/land chains when the team has someone to build it; plain tracks otherwise.
3. **VFX list**: map moments to `Vfx.luau` presets; add or tune presets for the style (colors, sizes, textures, counts) in its `Vfx.Presets` table.

## 3. Build
**Animations**
- Give the animator a brief per animation: purpose, length, key poses (anticipation -> action -> recovery), the marker frames, loop or not, priority, rig, and how it must look on a tall and a short avatar.
- With Studio MCP tools: set up the rig (Avatar > Character), and for runtime IK create `IKControl`s (Type, EndEffector, Target, ChainRoot, Weight) with `execute_luau`; animation keyframes themselves are made by a person in the Animation Editor (or Capture), then published.
- After uploading: paste the ids into `animations.json` and run
  `python3 scripts/anim_manifest.py animations.json -o src/shared/Animations.luau` (errors on missing ids unless `--allow-todo`; warns about wrong priorities, loops, missing hit markers, rig mismatches, duplicates).
- Copy `assets/AnimationSet.luau` into shared code; one `AnimationSet.new(animator, Animations.Specs)` per character, `play`, `onMarker`, `setParameter` for graphs, `destroy` on death/despawn.

**VFX**
- Copy `assets/Vfx.luau` into shared code. Server decides, fires a remote with the effect name and target, clients call `Vfx.play(name, positionOrPart)`; loops through `Vfx.attach` + `:Stop()`. Hook `Vfx.setQuality` and `Vfx.setReducedFlashing` to the settings menu.
- Textures: `assets/textures/*.png` (or `python3 scripts/make_textures.py <dir> --size 128`), uploaded by the owner, ids pasted into `Vfx.Textures`.
- Check every preset against Roblox's API database and get a model to look at:
  `lune run scripts/vfx_showcase.luau src/shared/Vfx.luau VfxShowcase.rbxmx` (also `--quality 0.3 --reduced-flashing`). Drag the model into Studio (or insert it with MCP tools) and `screen_capture` each pad; particles play in Edit mode.
- With Studio MCP: insert, playtest with `start_stop_play`, trigger the moments, `screen_capture`, read `get_console_output` (AnimationSet warns about missing ids and markers).

## 4. Check
- Every animation id in the manifest is owned by (or granted to) the experience; tested in a published place or Team Test, not only in Studio.
- Priorities: attacks override walking, hit reactions override attacks, death overrides everything; no unintended loops.
- Damage, projectiles, footsteps and effects fire from markers, and the server still validates hits.
- Effects read at phone size and low quality, never hide hazards or UI, nothing flashes with reduced flashing on.
- `roblox-security-perf-audit` place audit: no emitter over 100/s, total particle budget fine, effect lights without shadows.
Don't claim an animation or effect looks right without a screenshot or playtest; list what a human still has to look at.

## 5. Report
Moment table, the manifest status (done / todo ids), files added (Animations.luau, AnimationSet.luau, Vfx.luau, textures), what was verified (manifest check, showcase validation, playtest, screenshots) and the manual steps (animating, uploading animations and textures with the owner account, permissions, pasting ids).

## Hand-off
`roblox-luau-codegen` to wire remotes and controllers that trigger animations and effects (UI controller pattern, `Net.fire`); `roblox-ui-designer` for UI feedback (pops, toasts, reward screens); `roblox-map-builder` for ambient effects and lighting that the VFX must read against.
