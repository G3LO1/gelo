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
9. Field notes (RDC budgets: ~500 draw calls / 500k tris, ~1.3 GB on 2 GB phones; memory culprits; MicroProfiler and Scene Analysis workflow; measured fixes)

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

## 9. Field notes (Roblox RDC talks and developers)
Labels: [docs] = Roblox talks/docs; [tut xN] = N developer videos agree.
- **Six usual suspects** [docs: RDC 2024]: too many triangles, too many draw calls, high CPU, high memory, long
  loading, too much bandwidth. Check each on a real low-end phone, not only in Studio.
- **Budgets used by Roblox's own performance engineer** for mobile targets [docs: RDC 2024]: roughly 500 draw calls
  and 500,000 scene triangles as an upper ceiling on the densest view (stricter than the illustrative 1000/1M in the
  map builder); client memory around **1.3 GB on 2 GB devices** (about 66% of device memory, where OS ejection
  ramps up); most mobile "crashes" are out-of-memory kills.
- **Studio misreports client memory:** read it on a real device (F9 Developer Console) or a live server; PC
  clients behave differently from phones. Real-device testing early and often. [docs: RDC 2024/2025]
- **Memory culprits** [docs: RDC 2024 + 2026]: textures, part count (each client part costs roughly 1 KB) and audio
  loaded on the client; also script and animation memory (any reference to an animation keeps the whole track
  loaded). Keep sounds out of the client until needed; deparent instead of hiding when something shouldn't render.
- **Parts vs meshes:** after building, merge static part-built scenery into a few meshes; meshes are far more
  memory-efficient than thousands of parts (a top 2025 game cut memory this way; Roblox also reduced the memory
  of parts, tags and attributes after it). [docs: RDC 2025]
- **MicroProfiler workflow:** reproduce the slow action, look for the tallest bars, find the scope; on phones open
  it with a keyboard (Ctrl+F6) or from the Dev Console; download HTML dumps (they now include network data) and
  compare two dumps with the flame-graph diff view; server profiles from live servers too. [docs + tut x2]
- **Scene Analysis** (client and server) for instance composition, script/audio/animation memory; check
  send/receive in the network stats (F7/Shift+F7 overlays) first. [docs: RDC 2026]
- **Developer fixes that measured well** [tut x2]:
  - lower `CollisionFidelity` when "physics parts" memory is high;
  - one mesh id per repeated object (a duplicate upload with a new id breaks instancing and adds draw calls);
  - `Humanoid.EvaluateStateMachine = false` for NPCs/rigs that never need humanoid states;
  - `workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)` to move many anchored parts per
    frame (about half the cost of setting CFrames one by one in one test);
  - fewer unanchored assemblies; adaptive physics stepping; no physics where a tween or CFrame works;
  - server never tweens or plays animations (clients do); assets the client doesn't need stay in ServerStorage;
  - turning off global shadows removes shadow draw calls for phones that struggle (cost: look).
- **Optimize in order:** make it work, test on device, then go to the worst number (render stats -> MicroProfiler
  -> memory). Physics-heavy games start in the physics scopes. [docs: RDC 2025]

Sources: Roblox, "Using Roblox Tools to Improve Performance | RDC 2024" https://www.youtube.com/watch?v=cWDNVvOh4o0 ;
Roblox, "Top Game Performance Tales | RDC 2025" https://www.youtube.com/watch?v=rwLEnBtXr30 ;
Roblox, "Scene Analysis Tool Workshop | RDC 2026" https://www.youtube.com/watch?v=3gnK649VNbY ;
Crusherfire, "Your Roblox Game LAGS (and how to fix it)" (2025-07) https://www.youtube.com/watch?v=YWyJHwynM1M ;
Kenton's Videos, MicroProfiler on mobile (2026-10) https://www.youtube.com/watch?v=FKkh_Z3D6q8 ;
Roblox Creators MicroProfiler / client memory videos https://www.youtube.com/watch?v=XLCZfGEm9tU , https://www.youtube.com/watch?v=OCUZKJJR-TE (titles; excerpts via Perplexity).
