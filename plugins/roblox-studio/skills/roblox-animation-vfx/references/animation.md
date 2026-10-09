# Animation reference

Checked against create.roblox.com/docs/animation (editor, events, curve editor, IK, capture, graph editor, state machines, using animations), characters/adaptive-animation and avatar/emotes/import on 9 October 2026. Blender workflow: `blender.md`.

## Contents
1. Rig decision
2. Animation list and priorities
3. Tools: Animation Editor, Capture, Graph Editor, external
4. Markers (animation events)
5. IK: in the editor and IKControl at runtime
6. Playing animations in code
7. Permissions and publishing
8. Common failures

## 1. Rig decision
- **Players' own R15 avatars** (most games): animations must work on any body shape and scale; test on a tall, a short and a blocky avatar.
- **Custom StarterCharacter**: full control of proportions and style, loses avatar self-expression. Import it as a **Custom** rig and set up **Adaptive Animation**: Studio fills a `HumanoidRigDescription` (and `DigitsRigDescription` for fingers) that maps its joints to R15, with joint-assignment and T-pose tools to fix the mapping; then any R15 animation (catalog, emotes, your own) plays on it.
- **R6**: 6 parts, retro look, simpler to animate; R15 and R6 animations don't play on each other.
- **Non-humanoid rigs** (monsters, vehicles, props): parts joined with Motor6D (or Bones in a skinned mesh), `AnimationController` + `Animator`. Static or scripted NPCs don't need a Humanoid (cheaper).

## 2. Animation list and priorities
Per character: idle, walk, run, jump, fall, climb, swim (or keep Roblox defaults), plus one per verb in the mechanic matrix (attack combo, hit reaction, death, interact/use, carry, tool equip/idle, emotes, victory). NPCs: idle, walk, attack, hit, death, special.

Priority (low -> high): Core < Idle < Movement < Action < Action2 < Action3 < Action4. A higher priority overrides lower ones on the joints it animates.

| Kind | Priority | Looped | Notes |
| --- | --- | --- | --- |
| Idle, breathing | Idle (or Core) | yes | |
| Walk, run, swim, climb | Movement | yes | match speed to WalkSpeed so feet don't slide |
| Jump, fall, land | Movement | fall yes, others no | |
| Attacks, tool use, interact | Action | no | marker on the hit frame |
| Hit reaction, stagger | Action2 | no | must override attacks |
| Emotes, victory | Action | depends | stop on movement |
| Death | Action4 | no | hold last pose |

Timing guide: hit reactions 0.2-0.4 s, light attacks 0.3-0.6 s with a readable anticipation, emotes 2-4 s loops. Fade 0.1-0.2 s between gameplay animations, 0 for instant snaps.

Default character animations can be replaced by changing the `AnimationId` values inside the character's `Animate` script (run, walk, jump, idle Animation1/2, fall, swim, swimidle, climb) from a server script on CharacterAdded, or with catalog animations.

## 3. Tools
- **Animation Editor** (Avatar tab > Clip Editor): keyframes and poses, easing per keyframe, **Curve Editor** for per-channel curves, IK in the editor, events track (Show Animation Events). Publish to Roblox to get the asset id.
- **Import from FBX** (`...` > Import > From FBX Animation / From File) for Blender, Maya or Moon Animator work: same rig and joint names as the target character (standard R15 hierarchy), 30 FPS, animation in place (no root travel), baked keys, one animation per file. Details and the Blender check script: `blender.md`.
- **Emotes** for the Marketplace must be a `CurveAnimation` (convert in the Curve Editor before publishing), then an `Animation` object with that id is uploaded as an avatar item.
- **Animation Capture** (in the Animation Editor; face capture is a beta): record your face with a webcam for animation-compatible (dynamic) heads, or upload full-body video to generate keyframes. Clean up the result by hand: feet contacts, hands on props, loop points.
- **Animation Graph Editor** (Avatar tab > Graph Editor): node graph for blends and logic without scripting. Nodes such as Clip, Add (base + additive), Blend1D (blend by a parameter, e.g. idle -> run by Speed) and State Machine (named states like Locomotion / Fall / LandIdle with transitions on expressions such as `not Grounded`, `Finished`, transition length and curve; clips with Play Mode `OnceAndHold`). Publishing creates an `AnimationGraphDefinition` asset; load its id on the Animator like any animation, then drive it with `AnimationTrack:SetParameter(name, value)` every frame or on change. Good fit: locomotion blends, layered upper-body actions, jump/fall/land chains.
- Rig tools: Rig Builder for test rigs, Avatar > Character > My Avatar to animate on your own avatar.

## 4. Markers
Add named markers on the events track at the exact frame something must happen (`Hit`, `Release`, `Footstep`, `Spawn`). In code: `track:GetMarkerReachedSignal("Hit"):Connect(fn)` (the callback gets the marker's parameter string). Use markers for damage windows, projectile release, footsteps, sound and VFX timing instead of `task.wait(0.3)`, which breaks as soon as the animation is retimed or played at another speed. Remember: the client that plays its own character's animation sees markers first; the server must still validate hits (see the security references).

## 5. IK
- In the Animation Editor: IK mode for posing limbs by dragging hands/feet.
- At runtime, `IKControl` under the Humanoid or AnimationController. Required: `Type` (`Position`, `Transform`, `Rotation`, `LookAt`), `EndEffector` (a part or bone, e.g. LeftHand), `Target` (anything with a world position: an Attachment on a door knob, a mouse-hit part), `ChainRoot` (where the chain starts, e.g. LeftUpperArm). Tune `Weight` (blend with the animation) and `SmoothTime`; turn it off with `Enabled`.
- Constraints for natural limbs: HingeConstraint on elbows/knees, BallSocketConstraint with limits on wrists/shoulders; the constraints and the IKControl must share the same parent Model.
- Uses: head/eyes look-at, hands on a weapon or steering wheel, feet on slopes and stairs, pointing at objectives. Test with an Attachment as target during a playtest.

## 6. Playing animations in code
- Load each animation once per Animator (`animator:LoadAnimation(animation)` -> AnimationTrack) and reuse the track; never load on every play.
- The local player's animations play on their client and replicate. NPCs: a few can play from the server; many NPCs should be animated on clients.
- `track:Play(fadeTime, weight, speed)`, `track:Stop(fadeTime)`, `track.Priority`, `track.Looped` override what the asset saved.
- Stop and destroy tracks with the character; disconnect marker connections (leaked tracks keep animation assets in memory; Scene Analysis has an animation memory view).
- Use `AnimationSet.luau` from this skill (manifest -> `Animations.Specs` -> one object per character); the `roblox-luau-codegen` patterns read the plain `Animations.Ids` table.

## 7. Permissions and publishing
- Animations are always Restricted and can't be Open Use (since July 2025). The experience needs permission for each animation: upload them with the account or group that owns the experience, insert or playtest them as an editor, or add their ids in Creator Hub > experience > Configure > Permissions > Assets. Otherwise they play in Studio and silently fail for players.
- Keep a manifest (`animations.json`) with every id, its owner and its rig, so a move to a group or a second place doesn't lose track of which animations need re-upload.

## 8. Common failures
- Works in Studio, frozen for players: permissions/owner.
- Animation plays but walking overrides it: priority too low.
- Attacks keep looping: Looped saved true in the asset and not overridden.
- Damage happens before/after the swing: timing by wait instead of a marker.
- Feet slide: run animation speed doesn't match WalkSpeed; adjust playback speed from velocity.
- R6 animation on R15 avatar (or the reverse): nothing plays.
- Memory grows each respawn: tracks and marker connections never cleaned up.
