# Performance review

How to measure and what usually fixes it. Sources: create.roblox.com/docs/performance-optimization (identify, improve, design, scene analysis, test on hardware), checked October 2026. Budgets are starting points: measure on the weakest device you support, before and after each fix.

## Contents
1. Measure first
2. Script computation and memory
3. Physics
4. Humanoids and NPCs
5. Rendering
6. Networking
7. Assets, memory, load time
8. Phone checklist

## 1. Measure first
- **Developer Console** (F9, also in live servers): Log for errors/warnings, Memory (client and server: LuaHeap, InstanceCount, PlaceScriptMemory, graphics/texture, sounds, animation), Network, Scripts (activity per script).
- **MicroProfiler** (Ctrl+Alt+F6, or dump from the Dev Console on a phone): frame time spikes and which scopes take them. Server profiles can be captured from the Dev Console too.
- **Scene Analysis** (Window > Performance Summary > Scene Analysis, in a play session): script memory, unparented instances (held by scripts), instance composition, audio memory, animation memory, triangle and draw call composition.
- **Render stats** (Shift+F2) for draw calls and triangles; **Performance** dashboard in Creator Hub analytics for live FPS, memory, crash rate and join time by device.
- Test in the Device Emulator for layout, but performance only on real low-end phones (the documented recommendation).

Record a baseline: FPS and frame time on the densest view, client memory, server heartbeat, join time. Fix the biggest cost first, then measure again.

## 2. Script computation and memory
- Expensive work tied to frame events (`RenderStepped`/`PreRender`, `Heartbeat`, `Stepped`): move it to timers, event-driven updates or spread it across frames; never create instances or call `GetDescendants` every frame. `RenderStepped` blocks rendering: keep it for camera/character work only.
- Big table operations every tick: cache results, update incrementally.
- Leaks: connections never disconnected (the engine never collects a connected callback and what it references), tables of players/instances never cleaned on leave, instances removed from the tree but still referenced (Scene Analysis "unparented instances"), animations/sounds kept alive by scripts. Watch LuaHeap and InstanceCount over a long session: steady growth is a leak.
- `Workspace.PlayerCharacterDestroyBehavior = Enabled` destroys leavers' Player and character objects automatically.
- Parallel Luau (Actors) for heavy independent work (pathfinding batches, procedural generation, raycast fans).

## 3. Physics
- Anchor everything that doesn't need simulation.
- Adaptive physics stepping instead of a fixed high rate.
- Fewer, simpler mechanisms; fewer constraints per assembly.
- CollisionFidelity: Box or Hull for props, Default for most, PreciseConvexDecomposition only where exact collision matters. Decor: CanCollide, CanTouch and CanQuery off.
- Many loose parts settling (debris, ragdolls): clean them up, or make them client-only effects.

## 4. Humanoids and NPCs
- Disable HumanoidStateTypes NPCs never use (`Humanoid:SetStateEnabled`), especially Climbing, Swimming, FallingDown, Ragdoll, GettingUp, Flying, Seated where not needed.
- Static or scripted NPCs: AnimationController + Animator instead of a Humanoid.
- Play NPC animations on clients when there are many NPCs.
- Pool NPC models instead of destroying and cloning; spawn NPCs only near players.
- Don't change sizes/scales or rebuild the avatar hierarchy during gameplay (FastCluster rebuilds).

## 5. Rendering
- Draw calls matter more than triangles: reuse the same meshes and textures (instancing), avoid many unique meshes, decals, textures and particle emitters in one view. Property changes on ParticleEmitters are costly.
- Culling: streaming + `Model.LevelOfDetail = SLIM` for world models, `Workspace.EnableSLIMAvatars` for crowds; `MeshPart.RenderFidelity = Automatic` or `Performance`.
- Shadows: `CastShadow` off on small and distant parts, shadows on only a few local lights.
- Transparency overdraw: avoid stacks of semi-transparent parts, big particles, layered glass.
- Particles: up to 400/s per emitter (100/s on phones), lifetime capped at 20 s. Prefer few large particles or `Emit()` bursts over high rates; disable emitters out of view.
- Skinned MeshParts moving outside a Humanoid model and Models with too many parts both force FastCluster rebuilds.

## 6. Networking
- Remote traffic: send ids and deltas, not whole tables every frame; batch; use `UnreliableRemoteEvent` for frequent cosmetic updates that can be dropped.
- Server-side TweenService replicates every step: tween on clients, set the final value on the server.
- Creating or deleting big instance trees replicates all of it: build big maps in chunks, keep templates in ServerStorage, clone near players.
- Clean animation metadata from rigs; don't replicate what clients never need (keep server-only assets in ServerStorage).

## 7. Assets, memory, load time
- Upload each asset once and reuse its id (duplicates load twice); the 3D Importer doesn't de-duplicate meshes, so import kit pieces one by one.
- Texture memory depends on pixels, not file size: 1024x1024 costs 4x of 512x512. Most images <= 512, minor ones <= 256. Trim sheets for architecture.
- Audio: don't preload every track; load per area/state.
- Instance streaming (StreamingEnabled) for large maps: lower memory and faster joins; client code must handle parts that aren't streamed in yet (WaitForChild with timeouts, `Model.ModelStreamingMode`, `Player:RequestStreamAroundAsync`).
- Join time: keep ReplicatedFirst small (loading screen only), defer non-critical assets with ContentProvider:PreloadAsync on what the first screen needs.

## 8. Phone checklist
- [ ] 30+ FPS on the densest view on a low-end phone, no hitches when the core loop's effects play.
- [ ] Client memory stable over a 30-minute session.
- [ ] Join to playable under ~15-20 s on mobile data.
- [ ] Graphics quality 1-3 still readable (shadows and some effects vanish).
- [ ] No server heartbeat drops with a full server and the maximum number of NPCs/projectiles.
