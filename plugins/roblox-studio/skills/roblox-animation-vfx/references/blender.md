# Blender with a Blender MCP server

How the skills in this plugin use Blender when the user has a Blender MCP server, and how to offer it when they don't. Studio settings and specs checked against create.roblox.com (art/blender, art/modeling/export-requirements, art/modeling/specifications, avatar/character-bodies/specifications, export-avatar-animations guides, custom-characters, avatar/emotes/import) on 9 October 2026.

## Contents
1. Detect, ask, offer
2. Setting it up (user's machine)
3. What it's good for (and not)
4. Working rules
5. Blender <-> Studio settings
6. Animation pipeline
7. Model pipeline
8. VFX and UI renders
9. blender_check.py

## 1. Detect, ask, offer
**Detect**: Blender MCP tools are connected when the tool list (including deferred tools: ToolSearch with the query `blender`) has tools from a Blender server, e.g. `execute_blender_code`, `get_scene_info`, `get_object_info`, `get_viewport_screenshot` (names differ between servers; anything under an `mcp__blender...` prefix counts). If connected, say so in one line and use it where section 3 says it helps.

**Ask** (only when not connected, only when the task involves 3D models, character animation, flipbook textures or rendered icons, and only once per project): AskUserQuestion, options in this order:
1. "I have Blender + a Blender MCP server, I'll connect it": wait for the tools, then continue.
2. "I have Blender, show me how to connect it": give the setup from section 2 (two commands), then continue without it until it's connected.
3. "No Blender: do it in Studio": Animation Editor, Studio modeling/Creator Store assets, generate_mesh/material tools of the Roblox Studio MCP where available.
4. "Someone on the team works in Blender by hand": Claude writes the briefs and checks their exports with blender_check.py.

Record the answer in `PRODUCTION_PLAN.md` assumptions (or say it in the summary) so other skills don't ask again. Never install anything on the user's machine yourself; this session may also be a cloud session that can't reach a local Blender at all (the MCP server talks to Blender over localhost), so say that if it applies.

## 2. Setting it up (user's machine)
The most used server is MCP for Blender (github.com/ahujasid/blender-mcp, PyPI `mcp-for-blender`): a Blender add-on opens a local socket (default localhost:9876) and an MCP server talks to it. With uv installed (official installer, not `pip install uv`):
```
claude mcp add blender uvx mcp-for-blender     # Claude Code
uvx mcp-for-blender install-addon              # installs and enables the Blender add-on
```
Then open Blender, press N in the 3D viewport, open the "MCP for Blender" tab and Start MCP Server if it isn't running. It sends a minimal anonymous usage record by default; `DISABLE_TELEMETRY=true` in the server's environment turns that off. Other Blender MCP servers exist (some with explicit keyframe tools and no free-form code); any of them works with these instructions as long as it can run Blender Python or set keyframes and take viewport screenshots. Check the server's README for the current install steps.

## 3. What it's good for (and not)
Good:
- Technical work: units/axes/scale setup, renaming bones to the R15 scheme, applying transforms, triangle budgets (decimate), splitting multi-material meshes, UVs for simple props, baking, in-place root, FBX export with the right settings, batch operations over many files.
- Blocking and procedural motion: idle breathing, bobbing/spinning pickups, doors, levers, simple tool swings, NPC loops, turntables; first-pass poses for an animator to polish.
- Kit pieces and props from primitives in a low-poly or blocky style; variants of one asset; LOD-friendly simplification.
- Renders: particle flipbook sheets, item icons, thumbnails' 3D elements (final store images must still show real gameplay).
Not good alone: hand-key quality character acting and combat animation (timing, weight, appeal), detailed sculpts and hero characters. Plan those for a human animator/modeler; Claude blocks them out, briefs them and checks the exports.

## 4. Working rules
- The code tool runs arbitrary Python in Blender: ask the user to save first, work in a new file or a new collection, and ask before changing or deleting anything they made.
- Small steps, each followed by a viewport screenshot (several angles, and the timeline/animation strip for animation) that you actually look at.
- Keep the scene in Roblox units from the start (section 5), one object per Roblox MeshPart, names that will make sense in Studio.
- Run `scripts/blender_check.py` before every export; export with its `export_fbx()` (or glTF) settings.
- After import, the Studio side is checked too: screenshot in Studio, playtest animations on a real character.

## 5. Blender <-> Studio settings
- Scene > Units: Unit System None (1 Blender unit = 1 stud), Rotation Degrees.
- Blender is Z-up, Studio is Y-up. Studio -> Blender import: Scale 1, Forward Z, Up Y.
- Blender -> Studio export (FBX/OBJ/glTF): Limit to Selected Objects; FBX Transform > Apply Scalings = FBX Unit Scale (recommended; other scale values left at 1.0; alternatives: export Scale 0.01, or scene Unit Scale 0.01); Forward = Z Forward, Up = Y Up. glTF needs none of the scale settings.
- FBX: Path Mode Copy + Embed Textures, Armature > Add Leaf Bones off, Bake Animation only when exporting animation.
- Studio 3D Importer: Import Only as a Model for multi-object files, Upload to Roblox with Creator = the account/group that owns the game, Insert Using Scene Position, World Forward Front, World Up Top, Scale Unit Stud.
- The official Roblox Blender plugin (open-source Open Cloud add-on) can upload meshes from Blender straight to the account/Studio session.

## 6. Animation pipeline
1. **Rig**: for player avatars use a standard R15 rig. Hierarchy: Root > HumanoidRootNode > LowerTorso > (UpperTorso > Head, LeftUpperArm > LeftLowerArm > LeftHand, RightUpperArm > RightLowerArm > RightHand), LeftUpperLeg > LeftLowerLeg > LeftFoot, RightUpperLeg > RightLowerLeg > RightFoot. (The body spec names the root bone HumanoidRootNode; the animation export guides use HumanoidRootPart; blender_check.py accepts both.) Skeleton scale 1, meshes with zero transforms and scale 1 before skinning. Custom characters: import as Custom and use Adaptive Animation (HumanoidRigDescription) to map them to R15 so any R15 animation plays on them.
2. **Animate** at 30 FPS (at least 30; other rates make Studio warn about key alignment), with the same character the animation is for. Avatar animations play in place: the root doesn't travel (walk cycles animate on the spot; code moves the character).
3. **Name markers** you'll need (Hit, Release, Footstep) and list them in `animations.json`. Don't count on Blender timeline markers arriving as Roblox animation events: after import, check the Animation Editor's events track and add any that are missing.
4. **Check and export**: `blender_check.py` (mode animation), then FBX with Bake Animation on, one animation per file.
5. **Import in Studio**: Avatar tab > Character (R15) or your custom rig, open the Animation Editor (Avatar > Clip Editor), select the rig, `...` > Import > From FBX Animation (From File in newer builds), check the timeline, add events, set priority and looping, Publish to Roblox with the owner account/group. Emotes must be converted to a CurveAnimation (Curve Editor) before publishing.
6. Paste the id into `animations.json`, run `anim_manifest.py`, play it through AnimationSet.

## 7. Model pipeline
- Specs: at most 20,000 triangles per mesh, watertight, applied transforms, UVs when textured, one material per mesh (split otherwise), textures sized by on-screen size (256 for ~5-stud props, 512 for ~10, 1024 for ~20).
- Modular kits for maps: pieces on the map's grid (4/8/16 studs), pivots at a consistent corner, shared materials/trim sheets, one mesh reused many times instead of many unique meshes (draw calls, memory).
- Import kit pieces one by one (the Importer doesn't de-duplicate meshes), then assemble in Studio.
- Collision: set CollisionFidelity per role in Studio (Box/Hull for props), invisible simple colliders for walkways.

## 8. VFX and UI renders
- Particle flipbooks: render frames of a simulation or stylized shape to a 2x2/4x4/8x8 grid sheet (power-of-two, up to 1024 px for hero effects), white/grayscale with alpha so ParticleEmitter.Color tints it; set FlipbookLayout and FlipbookMode on the emitter.
- Item and shop icons: consistent camera, light and outline across items, transparent background, 256-512 px; hand them to `roblox-ui-designer` as images.

## 9. blender_check.py
`scripts/blender_check.py` reads the open scene and prints errors/warnings (units, FPS, triangles, watertight, transforms, materials, UVs, R15 bone names and parents, leaf bones, root travel). Through MCP: send the whole file to the code tool (set `MODE` and optionally `EXPORT_PATH` at the top; it exports only when there are no errors). From a terminal: `blender -b file.blend --python blender_check.py -- --mode animation --export out.fbx`. It never modifies or saves the .blend.
