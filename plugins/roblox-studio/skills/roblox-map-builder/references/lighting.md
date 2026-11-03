# Lighting pass: workflow, techniques, presets

Distilled from 17 Roblox Studio lighting tutorials (2023-2026, list at the end) and checked against Roblox's
creator docs (`Roblox/creator-docs`: Lighting, Atmosphere, Light, Clouds, post-processing classes, performance
guide). **[docs]** = stated by Roblox docs. **[tut xN]** = consistent advice from N tutorials, not documented:
treat as a starting point and check it with a screenshot. **[unverified]** = claimed in a tutorial, could not be
confirmed: test before relying on it. Every scene differs; every tutorial said "don't copy my numbers, tune".

## 1. Order of work (consensus of the tutorials)

1. **Scenario first.** Pick mood + time: sunny afternoon, golden hour/sunset, overcast, night, interior lit only
   from outside, interior lit by lamps. Gather 2-5 reference photos. Decide the color pair: *warm light / cool
   shadow* (sunset: strong; afternoon: subtle; night: driven by local lights instead). [tut x5]
2. **Clear the template.** Delete the place template's Sky/Bloom/DepthOfField/SunRays/Atmosphere (or merge
   them) so nothing stacks. [tut x5]
3. **Sky before any Lighting property.** Atmosphere and environment lighting take their color from the sky, so
   tuning first and swapping the sky later wastes the work. Check toolbox skies for scripts. [tut x6]
4. **Place the sun to match the sky and the build.** `ClockTime` + `GeographicLatitude` move the sun
   [docs]; `Sky.SkyboxOrientation` rotates the skybox so its painted sun lines up [docs]. Read the sky's sun
   from the cloud shading. Aim for light entering at an interesting angle: ~45 degrees down through windows,
   long shadows across a trench, light stripes on a floor. [tut x6]
5. **Lighting properties** (section 2), then **Atmosphere**, then **post-FX** (ColorCorrection, then a little
   Bloom, SunRays only if the sun is in view, DepthOfField rarely).
6. **Local lights:** every object that visibly glows gets a real light (Neon lights nothing, see SKILL.md hard rules).
7. **Fake what the engine lacks:** bounce/fill lights, contact shadows, light shafts (section 4).
8. **Sound + particles** finish the atmosphere: looping ambience in SoundService, dust in light shafts,
   rain with Clouds. [tut x3]
9. **Validate** at player height, on low graphics and Soft, in grayscale (SKILL.md checklist).

## 2. What each Lighting property really does [docs]

| Property | Effect | Practical use |
| --- | --- | --- |
| `Ambient` | Hue of areas **occluded from the sky** (indoors, deep shade). Default black. | The shadow color. Cool blue/teal for day, near-black for horror. |
| `OutdoorAmbient` | Hue of outdoor areas. Default (127,127,127). Clamped to be >= Ambient per channel. | Outdoor shadow fill; warm for sunset. |
| `GlobalShadows` | Sun/moon shadows + indoor/outdoor split. **Off: no sun shadows, OutdoorAmbient ignored, Ambient everywhere.** | Off only for fully enclosed scenes lit by local lights. |
| `Brightness` | Strength of the sun/moon. | Raise for harsh sun; lower for soft low-poly shadows (section 5). |
| `ColorShift_Top` / `_Bottom` | Tint of surfaces facing toward / away from the sun. | `_Top` = color of sunlight (cream, orange at sunset). |
| `EnvironmentDiffuseScale` | Ambient light derived from the sky, changes with sky and time. When raised, lower Ambient/OutdoorAmbient. | 0 = darker, contrasty shadows; ~0.2-0.5 = sky-tinted fill. |
| `EnvironmentSpecularScale` | Sky reflections on smooth parts; makes metal read as metal. | Lower or 0 in dark interiors (stops roughness maps showing as grime). |
| `ExposureCompensation` | Exposure bias before tonemapping, range -5..5; +1 = double, -1 = half. | Small steps (+-0.1..0.5). |
| `ShadowSoftness` | 0 hard .. 1 soft; **Realistic only**. Default 0.2. | Real sun: 0.2-0.4; low-poly: high. |
| `LightingStyle` | Realistic (shadow maps, full PBR response) or Soft (flat, retro). | See section 3. |
| `PrioritizeLightingQuality` | On low quality levels keep shadows/shaders close up instead of view distance. | On when lighting is the look. Soft + on uses shadow maps, Soft + off uses voxel lighting. |
| `ClockTime` | 0-24; never advances without a script. | Day/night: section 6. |

Atmosphere [docs]: `Density` hides objects/terrain (not the sky directly). `Offset` high = horizon silhouette
against the sky, low = distant objects blend into the sky (too low: skybox "ghosts" through terrain). `Haze`
is needed for `Glare` (glow around the sun) and `Decay` (hue away from the sun) to show at all. `Color` works
best with Haze > 0. An Atmosphere in Lighting hides/overrides FogStart/FogEnd.

Post-FX [docs]: Bloom `Threshold` 1 = only pure white blooms, 0 = everything; `Size` is in pixels.
DepthOfField: blur starts beyond `FocusDistance + InFocusRadius` (far) and before `FocusDistance - InFocusRadius`
(near). ColorCorrection `Brightness` brightens the whole image like a photo filter, unlike Lighting.Brightness
which strengthens the sun. `Sky.SunAngularSize` default 21, range 0-60.

## 3. Realistic vs Soft (unified lighting)

- Realistic: proper PBR response (MaterialVariant/SurfaceAppearance), accurate local-light shadows; costs more,
  each shadowed light adds draws. Use for interiors, many point lights, PBR showcases. [docs + tut x4]
- Soft: flat look, weaker local-light shadows, cheaper; good for outdoor low-poly/stylized and low-end phones.
  [tut x2]
- Realistic shadows were reported to flicker/smear while the camera moves (2025 beta). Check in play mode.
  [unverified]
- Studio's editor shows a lower quality than players may get: raise **Studio Settings > Rendering > Editor
  Quality Level** for judging and screenshots, then also check low graphics. [tut x1, setting exists]

## 4. Techniques that kept coming up

**Bloom, subtle.** Threshold very low (~0.03-0.6), Size very high, Intensity low: a soft glow that blends the
image. Too much intensity with a low threshold makes light-skinned avatars glow: check characters. [tut x4]

**ColorCorrection is the "grade".** Start each value at ~0.05, toggle Enabled to compare. Contrast up a little,
Saturation slightly down for realism (or up for cartoon), TintColor very subtle (warm or cool). [tut x8]

**Two lights per lamp.** PointLight (round fill, reaches everything) + SpotLight (direction, sharp shadow) in the
same fixture, or one *shadowed* SurfaceLight/SpotLight + one *unshadowed* PointLight with lower brightness so
shadows aren't pitch black. Light in an Attachment gives precise placement [docs]. Warm tint, brightness often
below 1. Name the lights by role ("Lamp_Key", "Lamp_Fill") so they can be selected and tuned later. [tut x5]

**Fake bounce / global illumination.** Roblox has no bounce light, so dark corners stay black. Add invisible,
anchored, CanCollide-off parts with low-brightness PointLights (same color as the scene's light, larger
range) where light would bounce: corners, opposite the window, under the lamp. For daylight interiors, a
white/warm light inside the window acts as the sky spilling in. Then set `Ambient` near the scene light color
so remaining darkness isn't pure black. [tut x4]

**Light-emitting things need lights.** Signs, screens, neon strips, glowing text: put a PointLight/SurfaceLight
next to them (invisible part), tinted to the sign. [tut x2 + docs]

**Windows.** Glass parts block the sun: set `CastShadow = false` on panes so sun shafts reach the floor;
tint the glass toward the outside light color to bridge sky and interior. A tutorial claims parts above
Transparency 0.75 stop casting shadows automatically [unverified]: set CastShadow explicitly. [tut x2]

**Contact shadows.** Engine shadows miss small occlusion (under tables, wall/floor creases, behind TVs).
Paint them: soft radial (objects) or linear (walls, corners) gradient Decals on transparent parts, dark,
semi-transparent, tinted toward the shadow color (slightly blue for day). Or thin dark parts under sills.
Place by where the light comes from. [tut x3]

**Light shafts without lag.** Use a `Beam` between two Attachments (low transparency, LightEmission, warm
color) or a few Neon wedge/parts at Transparency ~0.95-0.996 with CastShadow off, aligned with the real sun
patch; add a dust ParticleEmitter inside. **Avoid toolbox "fog mesh" volumetrics**: stacks of overlapping
transparent planes, heavy overdraw; showcases only. [tut x4, overdraw cost: docs]

**Clouds soften sun shadows.** Clouds under Terrain with higher Cover/Density reportedly give softer sun
shadows; combine with ShadowSoftness. [tut x2, unverified]

**Dark/horror base.** Atmosphere Color and Decay black or very dark, Haze/Glare high, Lighting
Ambient/OutdoorAmbient dark, EnvironmentDiffuse/Specular 0, ExposureCompensation ~-0.4; cold teal/green-blue
fixtures for fluorescent dread, or warm but dim. Keep the route readable. [tut x3]

**Daylight interior.** Push sun Brightness far higher than for outdoors (the room is only lit by what gets in),
aim the sun through the windows, then add the window fill light above. [tut x2]

**Retro outlines.** Highlight on characters for a retro/stylized look, DepthMode Occluded so it doesn't show
through walls; 255 Highlights max per client [docs]. [tut x1]

**Material variation.** Two to four similar textures/colors randomized across map parts by a script break up
repetition (store the seed). [tut x1]

**Field of view / letterbox** are for trailers and showcases, not gameplay defaults. [tut x1]

**Don't ship:** "posterization" by setting fog colors to huge RGB values is a rendering bug [tut x1, author's
own words]; Lighting.Technology is deprecated, use LightingStyle (some 2024-25 tutorials still say "Future").

## 5. Style starting points from the tutorials

Use with the style presets in SKILL.md; these are additional data points, not standards.

- **Simulator / bright cartoon** (Rileybytes, 2025): Ambient (200,160,225), Brightness 2.5, ColorShift_Top
  (215,190,135), EnvDiffuse 0.4, EnvSpecular 0.5, OutdoorAmbient (125,100,150), ShadowSoftness 0.2; no
  Atmosphere, legacy fog (200,170,250) FogEnd 2500; ColorCorrection Brightness 0.05 Contrast 0.1 Saturation
  0.15; plain sunless blue sky. Translate "ShadowMap" to Soft + PrioritizeLightingQuality.
- **Low-poly earthy** (barjNET): sky + ColorCorrection + Atmosphere only. Warm orange Ambient and
  OutdoorAmbient, ShadowSoftness max, sun overhead, Exposure +0.1. Trick: **low Lighting.Brightness (~1) +
  high ColorCorrection Brightness** = soft shadows without a dark image; then raise Saturation and Contrast
  (~0.15) to undo the washed-out look. Atmosphere: low Density, higher Offset, no Haze.
- **Stylized** (Lenny, 2026): light blue Ambient, beige OutdoorAmbient, small ColorCorrection boosts, optional
  Atmosphere.
- **Realistic exterior** (Ice Guy, 2026): HDRI sky rotated so its sun matches; low Atmosphere Density; blue-tinted
  Ambient, warm ColorShift_Top, EnvDiffuse low, EnvSpecular slightly down, OutdoorAmbient slightly blue;
  Contrast up, Saturation slightly down, faint warm tint; subtle Bloom; DepthOfField with low near intensity.
- **10x pass** (Develuper, 2026): Realistic, slightly higher Brightness, Atmosphere Density 0.3-0.4 Offset 0,
  small light Glare + a bit of darker Haze, Bloom up a bit, SunRays for late afternoon, ColorCorrection light
  blue tint + Contrast.
- **Night interior lamps** (ToastDevRBLX, 2025): Ambient and OutdoorAmbient black, Brightness 0, ClockTime 0,
  EnvDiffuse 0, EnvSpecular ~0.8, Realistic, lamp lights with Shadows on, ColorCorrection Saturation 0.2 warm
  tint. That tutorial also turned GlobalShadows off (fine for a closed room: no sun anyway).
- **Swamp daylight** (HollyHollers, 2025): sunset sky first; sun moved to the sky's sun; Brightness high;
  ColorShift_Top creamy yellow, ColorShift_Bottom terracotta, Ambient back to neutral blue (cool world, hot
  sun); slight desaturation so greens don't burn, tint returns warmth; Atmosphere thin enough to keep intended
  vistas visible; SunRays small spread.
- **Rainy night** (RingWorld, 2026): night ClockTime, dark Ambient, no Glare, Brightness down, blue tint; one
  focal light made of two PointLights (close bright + far dim long range); Clouds with high Cover/Density;
  rain particles; rain and night sounds.

## 6. Scripts

**Lighting zones** (client): change Lighting when the player enters a region, restore on exit. Store
targets as attributes on the zone part so builders tune them without code.

```lua
-- StarterPlayerScripts/LightingZones.client.luau. Zones: parts tagged "LightingZone" (anchored, CanCollide/
-- CanQuery/CanTouch false, Transparency 1) with attributes ClockTime/Brightness/Ambient/ExposureCompensation...
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local KEYS = { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation", "FogEnd" }
local default = {}
for _, k in KEYS do
	default[k] = Lighting[k]
end

local current: BasePart? = nil
local function apply(zone: BasePart?)
	local goal = {}
	for _, k in KEYS do
		local v = if zone then zone:GetAttribute(k) else nil
		goal[k] = if v ~= nil then v else default[k]
	end
	TweenService:Create(Lighting, TweenInfo.new(1.5), goal):Play()
end

local function inside(zone: BasePart, pos: Vector3): boolean
	local p = zone.CFrame:PointToObjectSpace(pos)
	local h = zone.Size / 2
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.25 then return end -- 4 checks per second is plenty
	acc = 0
	local root = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local found = nil
	for _, zone in CollectionService:GetTagged("LightingZone") do
		if zone:IsA("BasePart") and inside(zone, root.Position) then
			found = zone
			break
		end
	end
	if found ~= current then
		current = found
		apply(found)
	end
end)
```

Atmosphere/ColorCorrection can be tweened the same way (separate tweens on those instances). Lighting is
client-rendered, so per-player changes belong in a LocalScript; server changes replicate to everyone.

**Day/night cycle** (server, one script for everyone):

```lua
local Lighting = game:GetService("Lighting")
local MINUTES_PER_DAY = 20
while true do
	local dt = task.wait(1)
	Lighting.ClockTime = (Lighting.ClockTime + dt * 24 / (MINUTES_PER_DAY * 60)) % 24
end
```

Switch lamps on at dusk by checking ClockTime (e.g. on between 18 and 6) and toggling `Light.Enabled` on
tagged lights, not by creating/destroying them.

## 7. Performance [docs]

- Shadows degrade with graphics quality and are **off below level 4**; design so the scene still reads.
- Shadow-casting lights are expensive: `Shadows = false` on fill/bounce lights and lights that don't need them,
  limit Range and Angle, use fewer lights, turn off lights outside the current room/zone.
- `CastShadow = false` on small parts whose shadow nobody sees, and on moving objects where possible (can cause
  artifacts on shadows cast onto that part: leave on in most cases).
- Partial transparency costs overdraw: few large translucent shafts, never stacks of planes.
- MicroProfiler: `computeLightingPerform` (light grid + shadows), `LightGridCPU` (voxel grid),
  `ShadowMapSystem` (shadow maps).

## Common mistakes the tutorials warned about

Too much Bloom, SunRays, Blur or DepthOfField (focus distance too far = everything blurry); copying a preset
without tuning; tuning before choosing the sky; skipping shadows/contact shadows; pure black corners; one
point light per lamp; glass blocking the sun; fog-mesh volumetrics in a real game; unnamed lights; judging in
low editor quality only; forgetting ambient sound.

## Sources (YouTube, transcripts pulled with `tools/yt_research.py`)

- Ice Guy, "How to Make Realistic Lighting in Roblox Studio" (2026-06) https://www.youtube.com/watch?v=adgCWET34rU
- Ice Guy, "How to Make Realistic INTERIOR Lighting" (2026-07) https://www.youtube.com/watch?v=rewH2lXBYAk
- Develuper, "Make Your Roblox Game Look 10x Better With Lighting" (2026-04) https://www.youtube.com/watch?v=vkEXLmRAQgs
- ToastDevRBLX, "How to Make REALISTIC Lighting (Beginner)" (2026-04) https://www.youtube.com/watch?v=Xkj6zKI4VFI
- ToastDevRBLX, "Fixing Your BAD Roblox Lighting in 5 Minutes" (2025-11) https://www.youtube.com/watch?v=G24yWq9w_7U
- DatBoiEle, "THE Ultimate Lighting Tutorial [ADVANCED]" (2024-12) https://www.youtube.com/watch?v=aq0Fi0R2FAY
- HollyHollers, "How to Make Realistic Lighting" (2025-11) https://www.youtube.com/watch?v=mrPm-nzhaV0
- BONES, "Unified lighting Explained" (2025-07) https://www.youtube.com/watch?v=6zSe8cuBB_I
- BONES, "Advanced Lighting" (2024-11) https://www.youtube.com/watch?v=zAoY8pxJM9c
- RingWorld Studio, "How I Do Lighting & Atmosphere in Roblox" (2026-02) https://www.youtube.com/watch?v=UlvSrWHESwA
- RKGAM3ZS, "making game lighting look REALISTIC" (2026-04) https://www.youtube.com/watch?v=kSa8nuRQicE
- Rileybytes, "Give me 2 minutes and I'll fix your lighting" (2025-04) https://www.youtube.com/watch?v=06KmD8aNJ5o
- Lenny, "Stylized Lighting Tutorial" (2026-09) https://www.youtube.com/watch?v=oDFPoh_pKGQ
- barjNET, "How to Light a Low Poly Map" (2023-12) https://www.youtube.com/watch?v=kJ4Kel0j04g
- ZeDarkAlien, "REALISTIC Horror Game Lighting in 1 MINUTE" (2024-11) https://www.youtube.com/watch?v=2xaHKra6tXs
- plusvii, "How to Make Lighting Zones" (2026-03) https://www.youtube.com/watch?v=TXSvxRv61tA
- StickTrick, "Posterization in Roblox Studio" (2025-03) https://www.youtube.com/watch?v=bTEU8_AyOlo
