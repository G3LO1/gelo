# Level design: layout, guidance, genre maps, kits

How to lay out a map so it plays well, from Roblox's environmental-art curriculum (greybox -> polished assets ->
asset library -> construct -> optimize, laser-tag sample) and ~20 builder/level-design videos (2021-2026, list at
the end). **[docs]** = Roblox docs/curriculum or API. **[tut xN]** = N independent creators agree.
**[unverified]** = single claim. Pairs with `terrain.md` (ground) and `lighting.md` (mood); SKILL.md has the
scale numbers and validation checklist.

## 1. Plan before building

- **Design vision = 4 decisions:** lighting and style serve the *mood* (how players feel), theme and layout serve
  the *gameplay* (what they do). Pick the theme from the mechanics when the game isn't tied to a setting
  (melee fantasy -> medieval, round-based shooter -> urban/industrial). [tut x2]
- **Map size follows pace:** faster gameplay = smaller map, slower = larger. Linearity follows the genre: story
  games linear, shooters a few paths to the same goals, open world/roleplay mostly open with difficulty
  increasing outward. [tut x2]
- **Draw it first:** a top-down sketch (paint.net, Krita, paper) with zones, paths, landmarks and height levels;
  put the sketch on a Decal part in Studio as an underlay; list every asset the sketch needs, ordered by
  importance. Big maps without a sketch stall. [tut x3]
- **Mood board** of references for the art style, used as the source of truth for every asset. [docs + tut x3]
- **Don't waste space:** bigger isn't better. Every area needs a purpose (a goal, reward, view, or a deliberate
  calm moment); group related services together so players don't walk back and forth through nothing. [tut x2]
- **Your game is a language:** levels must reflect what the game is about (speedrun = fast lines, horror =
  helplessness, power fantasy = open space), not copy layouts that worked elsewhere. [tut x1]

## 2. Greybox [docs]

- Simple parts on a grid (the curriculum uses 5-stud move snapping and 90 degree rotation), anchored, before any
  polish. The point: find traversal problems, unfair vantage points and wrong scale while changes are cheap.
- Minimums from the sample: **doorways and hallways >= 10 studs wide** (two players pass at once, camera fits),
  **walls >= 10 studs tall** where players must not jump over (default CharacterJumpHeight is 7.2 studs; the
  curriculum text says 5, the API says 7.2). WalkSpeed 16 studs/s: use it to estimate travel times.
- **Elevation** (peaks and valleys) controls sight lines and engagement distance; high ground gives overview
  and a feeling of ascent, a descent pushes quick decisions.
- **Placeholder colors that orient:** paint the left half one color and the right half another, the back wall a
  third, the outdoor ramp a fourth, so a player seeing any one color knows where they are. Keep the same scheme
  in the final art (team colors, floor materials for inside vs outside).
- **Playtest at nearly every step** with these questions: does either side have an advantage? Can players tell
  where they are anywhere on the map? Is any area choice overload? What's fun, what's frustrating? Does each area
  feel the way it should? Can any part be skipped while still reaching the goal?
- Only move to detailing when the greybox plays well; props must never block the natural path. [docs + tut x2]

## 3. Guiding players

- **Landmarks:** one unmistakable landmark per zone, visible from spawn; distant landmarks pull players across
  the map. [tut x2 + SKILL.md]
- **Light:** players move toward light; a lit doorway or a colored light marks the way (keep a consistent
  meaning per color). [tut x2 + docs: spotlights highlight doorways]
- **Framing and breadcrumbs:** frame the next goal with arches, trees or walls; a trail of small pickups, lamps
  or path material leads the eye. Paths that never change angle abruptly read cleaner. [tut x2]
- **"Yellow paint"** (obvious markers on climbable/usable things) works but use it sparingly. [tut x1]
- **Choice:** at most ~3 entrances/exits per room or combat pocket; 2 exits from a spawn room (1 bottlenecks, 3
  leaves no cover). [docs]
- **Let players miss things:** optional secrets and side paths add replay value; nudge with sound and framing
  instead of map markers everywhere. [tut x1]
- **Spawn view:** from spawn the player should see the main points of interest (shop, eggs, leaderboard, the
  locked VIP door, an intriguing path), so the map invites exploration. [tut x2]

## 4. Layouts by genre

**Shooter / PvP (three-lane)** [docs + tut x2]
- Spawn zones at opposite ends; three primary lanes spawn-to-spawn; cross lanes linking them. Combat pockets form
  where cross lanes meet the middle lane, so the middle lane sees the most fights.
- Equal travel time from each spawn to the center (layout needn't be mirrored, timing must be fair); if one team
  owns one lane's choke point, give the other team an advantage elsewhere.
- Cover and sight-line breaks in central rooms (pillars, cores) so fights are cat-and-mouse, not first-click wins;
  cross lanes with little cover make players keep moving; loops let players disengage and flank.
- Use some non-90-degree angles for tactics and atmosphere; match map scale to weapons (no long open lanes for
  SMG games, no tiny rooms for snipers); avoid huge open areas ringed by vantage points.

**Simulator** [tut x3]
- Ground ~250x250 to 300x300 studs per area; spawn in the center (or a corner when progress should flow one way).
- Around spawn: leaderboards and the free reward (spin wheel), the shop and the starter eggs, a visible premium
  item; eggs a little away from spawn and shops on the opposite side so players cross the map.
- Layout types: **linear** zones in a row (simplest, overused), **hub** with zones around a big central spawn
  (favored), portals to separate worlds. Locked zones bought with currency.
- Borders: no perfect square; vary heights, rotate and offset border pieces, give each zone a themed border (dead
  trees for desert, snow hills for winter, UFOs for space); duplicate the border row outward so the map feels
  complete; terrain varied with hills, not flat.
- Fill with props in a size order: large trees on borders, large rocks, then grass and small details.

**Obby** [tut x4]
- Difficulty curve: teach jumping first, then add moving platforms, narrow ledges, timed parts; one new idea at a
  time, then combine them. Tier colors (green easy, yellow medium, red hard, purple extreme) and a consistent
  build style per section so players read the challenge.
- Checkpoints after hard parts and closer together in very hard sections; kill bricks used sparingly; size and
  gap spacing are the main difficulty dials; optional harder paths for skilled players; studded vs smooth parts
  change how readable edges are.
- Know the sub-genre players expect: linear/standard (clean skill jumps), tower (floor after floor, often timed:
  Tower of Hell style), rush/escape (rising water or lava, buttons), proximity/wrap (wraparounds and stick-outs,
  camera skill), story/design-led, physics-trick styles (wall hops, ledge climbs; niche, often disliked outside
  difficulty-chart games). [tut x1]

**Horror** [tut x3]
- Trapped, not confused: tight spaces, corners and long hallways that still guide; give false safety (an open
  calm area) before taking it away; pacing = slow tension and short intense moments, never constant scares.
- Plan rooms on a sketch around a starting room; environmental storytelling (sounds, a still-smoking campfire,
  props that make sense in each room); keep cutscene dialogue short. Route stays readable without the
  flashlight (see SKILL.md horror preset).

**Tycoon / hub-and-plot games** [tut x1, unverified detail]
- Equal plots arranged around a shared center (shops, leaderboards, social space) so players see each other's
  progress; each plot's build path unfolds toward the center view.

**Large/open maps** [tut x2]
- Sketch with height levels -> block the landmass in parts per height level -> pink placeholder blocks for every
  building/landmark at real size -> make assets -> replace placeholders; optimize from the start.

## 5. Modular kits and props [docs]

- **Modular kit:** pieces that snap together on the map grid; consistent pivots (forward-most lower corner or
  wherever snapping makes sense); every size a multiple of the smallest (sample: smallest 5x5, largest 15x5);
  split large pieces into named child meshes (Wall, UpperTrim, LowerTrim) so each can get its own material,
  collision and render settings. Test from many angles for clashing geometry (= inconsistent pivot).
- **Textures:** tileable textures for big surfaces (no seam, no standout element that reveals repetition; hide
  repetition with organic tiling and decal overlays) and **trim sheets** shared by the whole kit and props for
  cohesion; textures up to 1024x1024, smaller is cheaper.
- **Props** tell the story (glowing orbs + skeletons = magic and danger); detail only as much as the silhouette
  needs; logical pivots (back for wall props, bottom for floor props); reuse the kit's trim sheet; distinctive
  props show repetition fastest.
- **Asset library:** import into one organized place, set physics/render properties once, make packages
  (SurfaceAppearance packages nested in model packages) so edits propagate.
- Per-asset settings: Anchored everything static; CanCollide off on foliage and decoration; CanTouch only where
  a Touched event is needed; CanQuery off where raycasts never matter (keep it on walls for weapons);
  CastShadow where shadows are noticed; DoubleSided only for planar foliage/cloth cards; CollisionFidelity Box
  for simple blockers, Hull for trims players brush against, precise where shape matters (doorway edges);
  RenderFidelity Performance for complex foliage.
- After building: **delete the greybox** and baseplate, contain the playable area with invisible barriers (check
  for gaps), add movement (clouds, slow foreground particles, dust), then lights that also orient (team-colored
  surface lights, spotlights over doorways).

## 6. Composition and set dressing [tut]

- Work big shapes first, then medium rhythm, then small detail (SKILL.md); place large fillers before small ones
  so you don't overfill. [tut x3]
- Pick 1-2 accent colors (e.g. orange + teal) and check the screenshot's palette; desaturate anything that
  fights the accents. [tut x2]
- Point of view matters: dress what the player's camera sees on the main routes; showcase-level detail
  everywhere costs performance. [tut x3]
- Detail where a space invites it: corners, path intersections, entrances. [tut x2]
- Scenes need a reason: every prop placed where it would logically be (a basket in a kitchen, not on a random
  crate). [tut x2]
- Finishing a scene a day later with fresh eyes catches what you stopped seeing. [tut x1]
- From any standing point something should be interesting to look at (a landmark, a detail, motion in the
  distance); curves and diagonals beat only straight lines. [tut x1]
- "Organized randomness": nothing in nature (or even cities) is perfectly uniform; avoid visible patterns in
  trees, props, parked cars, litter. Observe real places and copy their logic. [tut x2]

## 7. Travel-time check (run in Studio, Edit mode or playtest server)

Tag points of interest "POI" and run this to print walking distance and time from spawn; long or failing
routes are where players get bored or lost.

```lua
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local speed = game:GetService("StarterPlayer").CharacterWalkSpeed -- 16 by default
local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
assert(spawnLocation, "no SpawnLocation in Workspace")
local start = spawnLocation.Position + Vector3.new(0, 3, 0)
for _, poi in CollectionService:GetTagged("POI") do
	local goal = if poi:IsA("PVInstance") then poi:GetPivot().Position else nil
	if not goal then
		continue
	end
	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
	local ok = pcall(function()
		path:ComputeAsync(start, goal)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		warn(("%s: no walkable path from spawn"):format(poi:GetFullName()))
		continue
	end
	local waypoints, length = path:GetWaypoints(), 0
	for i = 2, #waypoints do
		length += (waypoints[i].Position - waypoints[i - 1].Position).Magnitude
	end
	print(("%-28s %6.0f studs %6.1f s"):format(poi.Name, length, length / speed))
end
```

Rules of thumb to judge the output: core services near spawn reachable in a few seconds; the first goal of a
simulator/obby within roughly 10-20 s of walking; shooters: equal times from both spawns to the center (within a
second or two). [unverified, tune per game]

## Common mistakes

Building without a sketch; detailing before the greybox plays well; square maps with straight identical borders;
empty space with no purpose; everything visible and reachable at once (no reason to explore) or the opposite
(lost players); spawn rooms with one exit; unfair travel times in PvP; props blocking paths; one color/material
everywhere so players can't tell where they are; leaving the greybox and baseplate in the final place.

## Sources

Official: creator-docs `tutorials/curriculums/environmental-art/` (index, greybox-your-environment,
develop-polished-assets, assemble-an-asset-library, construct-your-world, optimize-your-experience) and the
`Humanoid` API (JumpHeight 7.2, WalkSpeed 16).

YouTube (full transcripts unless marked excerpt; YouTube rate-limited the rest, excerpts via Perplexity):
- EndorsedModel, "How to design AWESOME maps in Roblox Studio" (2021-05) https://www.youtube.com/watch?v=9OPZBtV_qZM
- DeHapy, "How to Build PRO Roblox Maps!" (2024-05) https://www.youtube.com/watch?v=I-AB6pJ-y5g
- DatBoiEle, "I just figured out how ALL ROBLOX games make their MAPS..." (2026-04) https://www.youtube.com/watch?v=wmB8BW4y5EA
- John Aljets, "5 TIPS for Designing Better Maps & Levels" (2017-02) https://www.youtube.com/watch?v=WoNUaqWJrcI
- AmusingThing, "Every Obby Style Explained" (2024-02) https://www.youtube.com/watch?v=_tcjS1nsFoE
- Apox Fox, "5 Tips for Great Level Design" (2024-05, excerpt) https://www.youtube.com/watch?v=LBtucVc8l0M
- RoBuilder, "How To Make Good Simulator Maps..." (2021-10) https://www.youtube.com/watch?v=Y3eUDs3FFGQ
- RoBuilder, "How to Plan and Build HUGE Maps..." (2021-11) https://www.youtube.com/watch?v=eRnnjqVOq7c
- "3 Popular Simulator Map Layouts you Should Know!" (2021-02, excerpt) https://www.youtube.com/watch?v=e6aGXz0wMVA
- "How to design a 3-lane FPS map on Roblox" (2025-11, excerpt) https://www.youtube.com/watch?v=fGaiAvh7Q-4
- Model Creator, "Best Tips to Make the Perfect FPS Map In ROBLOX!" (2023-09, excerpt) https://www.youtube.com/watch?v=cp1JZO1CWKw
- GalicEnder, "The Art of Designing FPS Maps" (2025-03, excerpt) https://www.youtube.com/watch?v=z5AWLend7dw
- Open World Tycoons, obby difficulty videos (2025-09/10, excerpts) https://www.youtube.com/watch?v=-cCJaM6b13Q , https://www.youtube.com/watch?v=xBmD1ovMhpg , https://www.youtube.com/watch?v=Z0d7MDBPbak
- "Ultimate Guide To Creating Obby!" (2025-03, excerpt) https://www.youtube.com/watch?v=bGHY_DxiAWw
- OKI, "How to make your roblox game ACTUALLY SCARY." (2025-08, excerpt) https://www.youtube.com/watch?v=WC1R4eCnYBE
- "How to PLAN Your Horror Game in Roblox Studio" (2024-02, excerpt) https://www.youtube.com/watch?v=RZj0CuKkVPI
- Rembot Games, "7 SECRETS for Good Level Design" (2025-12, excerpt) https://www.youtube.com/watch?v=eL8PFNupTHk
- "Building My DREAM GAME!" (2026-10, excerpt) https://www.youtube.com/watch?v=r-HdpXMsm0o
