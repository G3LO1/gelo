# Architecture, Luau practice and engine features

What `patterns.md` doesn't cover: how to structure a codebase, objects and cleanup, events and networking limits,
Parallel Luau, modern Luau syntax, new engine features (2025-2026) and the bugs that keep showing up. Sources:
Roblox creator-docs (scripting, luau, security, multithreading, remote events, server authority, input action
system, script capabilities, Workspace/RemoteEvent/UnreliableRemoteEvent API) and official Roblox Creators
videos, plus experienced scripters' videos (list at the end). **[docs]** = Roblox docs/API/official video.
**[tut xN]** = N independent creators agree. **[unverified]** = single claim. The template's own rules
(`patterns.md` section 1-2) still win where they overlap.

## 1. Structure

- **Single-script architecture** (what the template uses): one Script + one LocalScript boot ModuleScripts
  (Services on the server, Controllers on the client) with `Init()` (set up, no yielding) then `Start()` (connect,
  loop, use other modules). All logic lives in ModuleScripts so code is shared and load order is explicit. Plays
  well with Git/Rojo; most studios end up here. [docs: Roblox Creators architecture video + Connect talk; tut x4]
- **Multi-script** (scripts next to the instances they drive) is fine for small or prototype games and isolates
  failures, but code duplicates and drifts. Mixed setups are common; pick one direction and stay consistent.
  [docs: Connect talk]
- **Module rules:** a ModuleScript runs once per environment (server, each client) and returns the same table to
  every `require`; avoid circular requires (`Requested module was required recursively`); keep server-only code in
  ServerScriptService/ServerStorage, never in ReplicatedStorage (clients can decompile anything replicated,
  including ModuleScripts that never run there). [docs]
- **Public vs private:** return one table of public functions; keep helpers `local` or prefix with `_`;
  document the API in the module header (template convention). [tut x2]
- **Toolchain studios use:** VS Code + Rojo (sync), Rokit (tool versions), Wally (packages), luau-lsp (types),
  StyLua + Selene, Git/GitHub with branches and pull requests; ignore `Packages/`, `sourcemap.json`,
  `wally.lock`. AI coding agents work through the same Rojo setup. [tut x3]

## 2. Objects, types and cleanup

- **Classes** are tables + a metatable with `__index` pointing at the class; constructor `.new` (dot), methods
  with `:` (colon injects `self`). Inheritance: `setmetatable(Child, Parent)`, `Child.__index = Child`, and the
  child constructor builds a parent object then re-sets its metatable to the child. [docs: Roblox OOP video]
- **Typed class** (works in `--!strict`): declare the object shape and use `typeof(setmetatable(...))`:

```lua
--!strict
local Projectile = {}
Projectile.__index = Projectile

type Fields = { part: BasePart, speed: number, _connections: { RBXScriptConnection }, _destroyed: boolean }
export type Projectile = typeof(setmetatable({} :: Fields, Projectile))

function Projectile.new(part: BasePart, speed: number): Projectile
	local self = setmetatable({ part = part, speed = speed, _connections = {}, _destroyed = false }, Projectile)
	table.insert(self._connections, part.Destroying:Connect(function()
		self:Destroy()
	end))
	return self
end

function Projectile.Destroy(self: Projectile)
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self.part:Destroy()
end

return Projectile
```

- **Every object that connects events owns a cleanup method** and is cleaned when its owner goes away (player
  leaves, character dies, round ends). Cleanup helpers (Trove, Janitor, Maid) collect connections, instances,
  threads and functions and release them in one call; any of them, or a small table like above, is fine; just
  be consistent. [tut x3]
- **Memory leaks** come from two things: connections that are never disconnected and tables that never drop
  entries (keyed by Player, Instance, or ever-growing caches). `Destroy()` disconnects an instance's events;
  setting `Parent = nil` or a variable to nil does not. [docs: Roblox memory-leak video; tut x3]
- Enable `Workspace.PlayerCharacterDestroyBehavior` so old characters (on respawn) and Player objects (on leave)
  are destroyed automatically; otherwise destroy them yourself. [docs]
- **Finding leaks:** F9 developer console -> Luau Heap: take snapshots during a playtest, compare against a
  baseline, look for categories that only grow (e.g. RBXScriptConnection), and check "unique references"
  (instances only Luau holds, not parented to the DataModel). Look for trends and high watermarks, not single
  numbers. [docs + tut x1]

## 3. Events, remotes and networking [docs]

- **Deferred events:** with `Workspace.SignalBehavior = Deferred`, handlers run at the next resumption point
  (input processing, PreRender/PreAnimation/PreSimulation/PostSimulation/Heartbeat, `task.*` resumptions,
  BindToClose) instead of immediately. Write handlers that don't assume they run inside the firing call
  (e.g. re-check that an instance still exists). Deferred is required for the server authority model.
- **RemoteEvent ordering:** reliable and ordered per direction per client, even across different RemoteEvents;
  ordering applies to when handlers *start* (a handler that yields lets the next message start). Messages that
  arrive before a handler is connected are queued (limited) and delivered when it connects.
- **Rate limit:** about **500 requests per second per client, shared by all RemoteEvents** (and separately all
  UnreliableRemoteEvents). Excess reliable messages are delayed, not dropped. The template's per-remote limits
  stay far below this; batch frequent updates instead of firing per frame.
- **UnreliableRemoteEvent:** unordered, may drop, lower latency; for continuously changing or cosmetic data
  (positions for effects, aim direction). **Payloads over 1000 bytes are dropped.** Never use it for anything
  that changes state.
- **RemoteFunction:InvokeClient** is risky: a client error re-throws on the server, it errors if the client
  disconnects, and the server yields forever if the client never returns; don't use it. Clients can't talk to each other; route through the server.
- **Argument limits:** non-string table keys become strings; don't mix numeric and string keys in one table or
  leave nil holes; metatables and functions are lost; the receiver gets a copy, not the same table; instances
  only visible to the sender (ServerStorage, client-created parts) arrive as nil. Send plain data.
- **Bandwidth:** watch Network stats in the developer console; creators treat ~50 KB/s per client as the budget
  [tut x2]. Throttle client sends with an accumulator in Heartbeat (e.g. 10/s) instead of every frame, send only
  the fields needed, and merge many tiny remotes into one event with an action id. [tut x3]
- **Buffers** shrink payloads (a number sent plainly costs ~9 bytes; a Color3 13; packed into a buffer far
  less). Worth it only when measured bandwidth is a problem; libraries like Packet or Squash/Sera add batching and
  schemas. Validate buffer length on the server before reading. [tut x3]

```lua
-- 12-byte position packing for an UnreliableRemoteEvent (cosmetic replication)
local function packPosition(position: Vector3): buffer
	local b = buffer.create(12)
	buffer.writef32(b, 0, position.X)
	buffer.writef32(b, 4, position.Y)
	buffer.writef32(b, 8, position.Z)
	return b
end

local function unpackPosition(b: unknown): Vector3?
	if typeof(b) ~= "buffer" or buffer.len(b) ~= 12 then
		return nil -- wrong type or size from a client: ignore
	end
	local x, y, z = buffer.readf32(b, 0), buffer.readf32(b, 4), buffer.readf32(b, 8)
	if x ~= x or y ~= y or z ~= z or math.abs(x) > 1e5 or math.abs(y) > 1e5 or math.abs(z) > 1e5 then
		return nil -- NaN or absurd values
	end
	return Vector3.new(x, y, z)
end
```

## 4. Parallel Luau [docs]

- Scripts under an `Actor` can run in parallel; they start serial. Enter parallel with `task.desynchronize()`
  (or connect with `:ConnectParallel()`), return with `task.synchronize()` before writing to the DataModel.
- Scripts in the **same** actor always run one after another: split work across **many actors by logical unit**
  (one per NPC, chunk, or validator); more actors than cores balances better, but don't fragment connected logic.
- `require()` is not allowed in a desynchronized phase: require in serial first. APIs carry thread-safety tags
  (Unsafe by default, ReadSafe, Local, Safe): reading shared data is usually fine, writing other actors' state is
  not; e.g. `Terrain:WriteVoxels` must be serial.
- Communicate with Actor messaging (`Actor:SendMessage`, `BindToMessage`/`BindToMessageParallel`) or
  `SharedTable` for large shared data.
- Use it for heavy, measurable work (many raycasts for hit validation, NPC perception, terrain/procedural
  generation, pathfinding batches); check the MicroProfiler before and after. Long parallel phases still spill
  into the next frame. Most games don't need it. [docs + tut x3]

## 5. Modern Luau worth using [docs + tut]

- Generalized iteration `for k, v in t do` (no pairs/ipairs needed), string interpolation
  `` `{player.Name} has {cash} coins` ``, `continue`, floor division `//`, compound assignment `+=`, numeric
  separators `1_000_000`, `if x then a else b` expressions.
- `--!strict` with type annotations, generics and `export type`; luau-lsp in VS Code reports errors before
  playtesting. `--!native` compiles hot math-heavy modules to native code (measure first).
- `typeof()` for Roblox types (`"Vector3"`, `"Instance"`, `"buffer"`), `assert` for programmer errors,
  early returns instead of nested ifs, `table.clear`/`table.create`, `table.freeze` for constant tables.
- Variadics (`...`, `select("#", ...)`) carefully in remote handlers: count and validate every argument.

## 6. Newer engine features to know (verify availability per place)

- **Server authority model** [docs]: the server simulates the whole game; clients send only inputs and predict
  locally with rollback/resimulation on misprediction, which removes fly/speed hacks. Requires
  `Workspace.AuthorityMode = Server` (sets NextGenerationReplication, PlayerScriptsUseInputActionSystem,
  SignalBehavior Deferred, UseFixedSimulation, StreamingEnabled). For competitive FPS, racing, sports, combat.
- **Input Action System** [docs, beta]: `InputContext` -> `InputAction` -> `InputBinding` set up at edit time
  (e.g. `ReplicatedStorage.Inputs.PlayContext`), cross-device bindings, enable/disable contexts per game state;
  the default player scripts can use it.
- **Device Trust API** [docs]: tells you how much a joining device can be trusted (your decision what to do, e.g.
  separate servers); never replaces server validation.
- **Script capabilities** [docs, experimental]: `Workspace.SandboxedInstanceMode = Experimental`, then
  `Sandboxed` + `Capabilities` on a Model/Folder/Script limit what code inside can do: useful for Toolbox models
  and user-generated code.
- **Configs and Experiments** [docs]: tune values (XP curves, starting currency) live without restarting servers
  and A/B test them (see launch-kit `growth.md`).

## 7. Bugs that keep showing up [tut + docs]

- **Client race conditions:** LocalScripts start while the world still streams in; `WaitForChild(name, timeout)`
  for things the client didn't create, `FindFirstChild` + nil check when something may legitimately be absent.
  Server scripts can index directly. Never `task.wait(1)` "to let it load". [tut x3]
- `FindFirstChild`/`WaitForChild` inside Heartbeat or tight loops: cache references once. [tut x1]
- **Connecting inside loops or other connections** (Touched inside ChildAdded, a connection per loop tick):
  connections pile up and fire many times. Connect once, outside. [tut x2]
- **Touched without a debounce** (per player, server-side) fires many times per contact. [tut x2]
- **Doing it on the client** (healing, currency, damage): only looks right locally; the server never sees it or
  exploiters fake it. Client = input and visuals. [tut x3 + docs]
- `Parent = nil` instead of `Destroy()`; tables keyed by Player never cleared on PlayerRemoving. [tut x3]
- A separate RemoteEvent for every tiny action (OpenShop/CloseShop/PlayMusic/StopMusic): one event with a
  validated action id is easier to rate-limit and audit (the template's `Net` already centralizes them). [tut x1]
- Deprecated APIs (`wait`, `spawn`, `delay`, `Humanoid:LoadAnimation`, BodyMovers): see `patterns.md` section 1.

## Sources

Official: creator-docs `scripting/` (index, module, events, events/remote, multithreading, capabilities,
security/security-tactics, security/device-trust, security/network-ownership), `luau/` (type-checking,
metatables, tables, strings, queues), `projects/` (client-server, server-authority), `input/input-action-system`,
`studio/debugging`, `performance-optimization/` (identify, design); API: RemoteEvent, UnreliableRemoteEvent,
Actor, Workspace (SignalBehavior, PlayerCharacterDestroyBehavior, AuthorityMode).

Videos (transcript excerpts via Perplexity; YouTube rate-limited full downloads this round):
- Roblox Creators, "How to use OOP with Luau on Roblox" (2025-06) https://www.youtube.com/watch?v=fByFKZarNiI
- Roblox Creators, "How to find and fix memory leaks on Roblox" (2025-08) https://www.youtube.com/watch?v=x1JgsC8c8VQ
- Roblox Creators, "Single vs Multi script architecture on Roblox" https://www.youtube.com/watch?v=Yxh8IsUIsZk
- Roblox Learn, "UI Programming Architecture Best Practices with Blend by Quenty | Connect 2023" https://www.youtube.com/watch?v=ccRydE3HN4Q
- Leif, "How Big Studios Develop on Roblox" (2025-05) https://www.youtube.com/watch?v=IJDg6tRJmHo
- Crusherfire, "These Tiny Mistakes Destroy Roblox Games (Memory Leaks)" (2025-10) https://www.youtube.com/watch?v=0moy04A9vFg
- Crusherfire, "MULTI-THREADING on ROBLOX?! - Parallel Luau" (2024-02) https://www.youtube.com/watch?v=MyM3JkHEPmA
- Crusherfire, "Serialization with Roblox's Buffer Library" (2025-04) https://www.youtube.com/watch?v=M2YKE07cUOc
- Stewiepfing, "How Roblox Uses Multiple CPU Threads (Parallel Luau)" (2026-01) https://www.youtube.com/watch?v=_99zdTIqXFc
- Stewiepfing, "The Networking Trick Pros Use (Buffers & Serialization)" (2026-07) https://www.youtube.com/watch?v=_2R2kzyw0bE
- Stewiepfing, "It's Not Just YOU That's Lagging..." (2025-12) https://www.youtube.com/watch?v=3L2a9mrOyFk
- Stewiepfing, "Luau Patterns & Tricks Most Roblox Devs Don't Know" (2026-03) https://www.youtube.com/watch?v=JG1fkhCKAB4
- Stewiepfing, "More Luau Tricks Most Roblox Devs Don't Know" (2026-08) https://www.youtube.com/watch?v=5k4MJW277qY
- Suphi Kaner, "Packet - Networking library" (2025-03) https://www.youtube.com/watch?v=WoIElUdj64A
- "5 Most Common Beginning Developer Mistakes - Roblox Scripting Tutorial" (2021-05) https://www.youtube.com/watch?v=0CZ3LilS76g
- Driple Studios, "WaitForChild vs FindFirstChild in Roblox Studio (Explained)" (2026-09) https://www.youtube.com/watch?v=ZRKZe4b9mMs
- "How to PREVENT Memory Leaks in Your Roblox Scripts!" https://www.youtube.com/watch?v=ZVfKrgRkDYk
- "Roblox Studio 30DSC | Day 10.5: Framework" (2025-09) https://www.youtube.com/watch?v=M6a-otA1Si8
