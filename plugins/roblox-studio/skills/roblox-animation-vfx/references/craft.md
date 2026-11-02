# Craft: animation principles, combat feel, VFX building

`animation.md` and `vfx.md` cover the tools and properties; this file covers how to make motion and effects
*feel* good. Sources: Roblox animators' and VFX artists' videos, general game-feel analyses (list at the end).
**[tut xN]** = N independent creators agree. **[unverified]** = single claim. Snippets are original and
client-side (cosmetic); the server still decides outcomes (`vfx.md` section 6).

## 1. Animation principles applied in Roblox [tut x3]

- **Anticipation:** move back before moving forward (an arm swings back ~10 frames before the punch); length
  sets the weight: long for slow heavy attacks, a single 0.1 s pose for fast action games.
- **Drag / overlap:** parts lag behind the part that leads (forearm trails the upper arm, sword trails the
  hand); offset limbs and torso by a few frames instead of moving everything together.
- **Follow-through / overshoot:** past the impact pose, then settle back; nothing stays perfectly still at the
  end of a move.
- **Arcs:** check motion paths (Moon Animator: calculate motion paths around the frame) and fix jagged arcs.
- **Body leans into the action:** torso leans in on the strike and out on recovery; weight shifts sell power.
- **Momentum = weight:** a heavy weapon is held with both hands and struggles to come back out after the hit.
- **Timing:** ~0.1 s reads as "instant but smooth" for hit reactions [tut x2]; keep the existing guide in
  `animation.md` (hit reactions 0.2-0.4 s, light attacks 0.3-0.6 s).
- **Learning loop:** rotoscope references (a baseball throw GIF, a fighting game move) limb by limb to learn
  posing and timing, keep early animations simple, study the 12 principles. Never post copied animations as your
  own. [tut x2]
- **Tools:** Roblox Animation Editor (Clip/Curve Editor, IK, events) is enough; community plugins add speed:
  Moon Animator 2 (popular, motion paths, easy tool rigging), MegMo Animator (2026: motion builder from markers,
  physics capture for ragdolls/explosions baked to keyframes, attach/detach props, audio track, cutscene export,
  R15<->R6 conversion). Plugins are third-party: check permissions and keep exported animations owned by the
  experience's owner (`animation.md` section 7). [tut x3]

## 2. Tools and weapons [tut x1 + common practice]

- Animate a held tool by joining it to the arm with a **Motor6D** (Part0 = RightHand/Right Arm, Part1 = the tool's
  handle), not a Weld, so the animation can move it; name the joint consistently because the animation stores
  joint names. Create the Motor6D at runtime when the tool is equipped (server, so it replicates) and destroy it
  on unequip; in the animator, rig a copy of the tool the same way. A Tool with a part named `Handle` gets an automatic
  `RightGrip` weld when equipped: either remove that weld and add the Motor6D, or set `RequiresHandle = false`
  and name the part something else.
- Moon Animator and MegMo can attach/detach props mid-animation (picking up, throwing, swapping weapons).
- One animation per state (equip, idle, attack 1/2/3, block) with markers for hit frames and VFX/SFX timing.

## 3. Combat feel: the hit in three phases [tut x4]

1. **Anticipation** (wind-up): pose + optional smear/trail; the window the opponent reads.
2. **Hit** (a few frames, most of the feel):
   - target reaction: stagger and knockback in ~0.1 s;
   - **hit-stop**: freeze the attacker and target for a moment (a light hit ~1/8 s, a heavy hit up to ~1/4 s in
     Capcom's numbers; tens of milliseconds is enough on Roblox for normal hits);
   - **white flash** on the target for 2-3 frames (Highlight with white fill, or a quick tween);
   - **impact frame** for super moves: a full-screen white `Frame` flash or a ColorCorrection contrast/saturation
     spike for one frame (respect reduced flashing);
   - **camera shake**, short and decaying (one of the cheapest, strongest tools; also the most disliked: always
     offer an option to reduce or disable it);
   - particles: sparks or a burst at the contact point, a ring/shockwave for heavy hits;
   - **sound**: layered impact (body hit + weapon + whoosh); sound is the best value per effort.
3. **Recovery / follow-through:** longer for weighty combat, short (or cancelable) for fast action; effects fade
   out here.
- **Juice only on real hits.** Celebrate landed hits and keep misses quiet; effects on every swing made players
  feel *less* skilled in studies, and too much noise buries the real hits. [tut x2]
- Environmental impact for heavy attacks: rocks rising along the attack direction (compute a horizontal forward
  vector and a perpendicular "right" vector, spawn pairs of rocks stepping forward, tilt them inward, tween up
  then down and destroy). [tut x1]
- Readability beats fidelity: simple, consistent effects plus good sound and timing feel better than high-detail
  VFX on flat combat. [tut x2]

```lua
-- Client-side helpers (cosmetic). Call them when the server confirms a hit or from your own predicted hit.
local RunService = game:GetService("RunService")

local function hitStop(animators: { Animator }, duration: number)
	local paused: { [AnimationTrack]: number } = {}
	for _, animator in animators do
		for _, track in animator:GetPlayingAnimationTracks() do
			paused[track] = track.Speed
			track:AdjustSpeed(0)
		end
	end
	task.delay(duration, function()
		for track, speed in paused do
			if track.IsPlaying then
				track:AdjustSpeed(speed)
			end
		end
	end)
end

local shakeId = 0
local function shakeCamera(degrees: number, duration: number)
	-- runs right after the default camera so it doesn't accumulate; scale `degrees` by the player's setting
	shakeId += 1
	local name = "CameraShake" .. shakeId
	local start = os.clock()
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
		local t = (os.clock() - start) / duration
		if t >= 1 then
			RunService:UnbindFromRenderStep(name)
			return
		end
		local strength = degrees * (1 - t) ^ 2 -- decays quickly
		local camera = workspace.CurrentCamera
		camera.CFrame *= CFrame.Angles(
			math.rad((math.random() - 0.5) * strength),
			math.rad((math.random() - 0.5) * strength),
			0
		)
	end)
end
```

## 4. Building a VFX effect [tut x4]

- **Layers:** an effect is several emitters with different jobs: a bright core (short, additive), secondary
  shapes (sparks with Squash, rings, shards), and residue (smoke, dust, embers that linger and fade). Add a light
  flash and a sound. Stagger them in time: core first, then secondary, residue last.
- **Every particle fades:** always give Size and/or Transparency a curve over lifetime; nothing should pop out.
- **Attachments, not parts:** emitters inside Attachments emit from a point and move with the model; one
  Attachment per element of the effect inside a template Part or rig keeps it organized.
- **Beams** for tethers, lasers, waterfalls, spirals (Segments up for smooth curves, FaceCamera on, textures that
  reach both edges); **Trails** for swings and dashes (two attachments, short Lifetime, MinLength).
- **Mesh VFX:** shockwave rings, slashes, tornadoes and auras made from meshes (often with a texture/decal and
  LightEmission-like transparency) animated by tweening Size, CFrame and Transparency; good for stylized and anime
  looks, costs more to make. [tut x2]
- **Sync with animation** through animation events/markers (`Shoot`, `Hit`, `Release`), never with waits; Moon
  Animator lets you preview effects on its timeline. [tut x3]
- **Learn by taking apart** open-source and toolbox effects, then rebuild them; VFX plugins (particle editors,
  texture libraries with thousands of textures, VFX timeline plugins) speed up iteration. Free texture packs are
  common; check the license and upload with the experience owner. [tut x3]
- **Who plays it:** creators disagree; some fire impact VFX on the server "so everyone sees them". Keep this
  skill's rule: server decides and fires one remote, every client plays the effect (`vfx.md` section 6); server-
  created particles replicate as instances and cost bandwidth. The acting player plays its own effect instantly.

**Prefab effects with emit attributes.** Many artists and VFX plugins tag each emitter with `EmitCount`,
`EmitDelay` and `EmitDuration`. `Vfx.luau` plays this skill's presets; for hand-made or toolbox prefabs that use
those attributes, a small player:

```lua
-- prefab: an anchored, invisible Part (CanCollide/CanQuery/CanTouch off) with Attachments holding
-- ParticleEmitters (Enabled = false). EmitDuration > 0 = enable for that long, else Emit(EmitCount).
local Debris = game:GetService("Debris")

local function playPrefab(prefab: BasePart, at: CFrame, lifetime: number)
	local fx = prefab:Clone()
	fx.CFrame = at
	fx.Parent = workspace
	for _, item in fx:GetDescendants() do
		if not item:IsA("ParticleEmitter") then
			continue
		end
		local emitter = item
		local delayTime = tonumber(emitter:GetAttribute("EmitDelay")) or 0
		local duration = tonumber(emitter:GetAttribute("EmitDuration")) or 0
		local count = tonumber(emitter:GetAttribute("EmitCount")) or 0
		task.delay(delayTime, function()
			if duration > 0 then
				emitter.Enabled = true
				task.delay(duration, function()
					emitter.Enabled = false
				end)
			elseif count > 0 then
				emitter:Emit(count)
			end
		end)
	end
	Debris:AddItem(fx, lifetime)
end
```

Keep `lifetime` >= the longest delay + duration + particle Lifetime. Scale counts with the quality setting the
same way `Vfx.scaled` does.

## Sources

- Devgrams, "Make Your Roblox Animations Feel REAL | Roblox Animation Tips 2026" (2026-06) https://www.youtube.com/watch?v=AH30avEEC9A (full transcript)
- Develuper, "Make Your Attacks Feel POWERFUL in Roblox" (2026-05) https://www.youtube.com/watch?v=KdARoj-IWds (full transcript)
- Develuper, "How to ACTUALLY Use VFX in Roblox" (2026-03) https://www.youtube.com/watch?v=TkNZETIu0CM (excerpt)
- "The RIGHT Way to Handle VFX in Roblox" (2026-09) https://www.youtube.com/watch?v=HjDD_0cDfPg (excerpt)
- Twist VFX, "How to Start Learning Roblox VFX" (2026-04) https://www.youtube.com/watch?v=GJOTJiUiYr4 (excerpt)
- Twist VFX, "How to Learn Roblox VFX in 60 MINUTES" (2026-03) https://www.youtube.com/watch?v=u2o-wHKDlpw (excerpt)
- Plebarae, "VFX Academy: How to Make Roblox VFX" (2025-08) https://www.youtube.com/watch?v=UimSdBlsDzo (excerpt)
- "ROBLOX VFX Guide #2 - Trails & Beams" (2025-12) https://www.youtube.com/watch?v=rIXyQ4RAwws (excerpt)
- IndividualKex, "A Guide to Good Combat Feel" (2023-08) https://www.youtube.com/watch?v=FpGgpUWEb_k (excerpt)
- GamedevPL, "Game Feel: Why Some Games Feel Good" (2026-10) https://www.youtube.com/watch?v=H84ZL7a3A_0 (excerpt)
- "Same swing, twice: why the frozen hit feels harder" (2026-10) https://www.youtube.com/watch?v=99WJlCkyIP4 (excerpt)
- The Meg and Mo Show, MegMo Animator videos (2026-05/08/09) https://www.youtube.com/watch?v=wRA8PolifSg , https://www.youtube.com/watch?v=qP2gEErOtBw (excerpts)
- Search results for Motor6D tool animation and Moon Animator 2 tutorials (titles only, not quoted): Mattronix, PeteTheSpeed, THE GREY RIG, six (official Moon Animator 2 basics).
