# Security review

What to check by hand after the scanners. Sources: create.roblox.com/docs/scripting/security (client-server boundary, security tactics, third-party vulnerabilities, server-side detection), checked October 2026.

## Contents
1. Threat model
2. Remote inventory (do this for every game)
3. Validation checklist
4. Movement and physics
5. Backdoors and Toolbox assets
6. Data and purchases
7. Detection and consequences
8. Settings to check
9. Field notes (noclip/speed/fly checks, hitboxes, honeypots, server authority, device trust, lag-compensated hits)

## 1. Threat model
An exploiter fully controls their own client. They can:
- fire every RemoteEvent / invoke every RemoteFunction with any arguments, any types, at any rate, in any game state;
- read every LocalScript, ModuleScript and instance that replicates to them (ReplicatedStorage, ReplicatedFirst, their PlayerGui, Workspace), so "hidden" remotes and client-side secrets don't exist;
- change anything on their own client (UI, local values, cooldowns, other players' visuals) and anything they have network ownership of: their character (speed, teleport, fly, noclip) and unanchored parts the engine handed to them;
- delete LocalScripts, including client anti-cheats.

They cannot change server state directly. Every exploit is the server trusting something the client said or something the client simulates.

## 2. Remote inventory
List every remote (search `RemoteEvent`, `RemoteFunction`, `UnreliableRemoteEvent`, `FireServer`, `InvokeServer`, `OnServerEvent`, `OnServerInvoke`, and the project's own wrapper such as `Net.handle`). For each, fill one row:

| Remote | Direction | Arguments (type, range) | Server checks | Rate limit | Verdict |
| --- | --- | --- | --- | --- | --- |
| BuyItem | C -> S | itemId: string in Items | exists, price from server table, enough coins, not owned | 3/s | OK |
| DealDamage | C -> S | target: Model, damage: number | none | none | CRITICAL: client sets damage |

Verdicts: OK, FIX (missing check), CRITICAL (client decides an outcome: currency, damage, rewards, ownership, position of others). Remotes that only one side should use: server -> client remotes must have no `OnServerEvent` handler at all, and the server never calls `InvokeClient`.

## 3. Validation checklist
For every argument of every client -> server remote:
- **Type**: `typeof(x) == "string"` etc. Instances: `typeof(x) == "Instance"` and `x:IsA(...)`. Tables: check shape and size; reject unexpected keys.
- **Numbers**: reject NaN (`x ~= x`), +/-inf, non-integers where integers are expected (`x % 1 == 0`), negatives, out-of-range values. Clamp nothing silently that should be rejected.
- **Strings**: max length, allowed characters, `utf8.len` not nil; filter with TextService before anyone else sees it.
- **Identity and ownership**: the player argument is the only trusted identity. An item/plot/pet/vehicle id must belong to that player on the server.
- **Context**: game state allows it (round running, player alive, in the shop zone), distance from the player's character to the target (server positions, with tolerance for latency), line of sight if it matters.
- **Cooldown and rate**: per player, per remote; reject over the limit instead of queuing.
- **Outcome on the server**: prices, damage, rewards, drop tables, odds come from server-side tables keyed by an id the client sent.
- **RemoteFunctions**: the server must return quickly and never yield on client data; never `InvokeClient`.

The `roblox-luau-codegen` template does this through `Net` (declared schemas + per-remote rate limits) and `Guard` validators; patch new code to use them instead of hand-written checks.

## 4. Movement and physics
- Players always own their character's physics: speed, teleport and fly hacks are possible. Check on the server: distance moved per second (with generous tolerance for lag and legitimate boosts), position inside allowed areas, grounded time. Rubber-band to the last valid position rather than kicking.
- Unanchored parts near a player may be handed to that player's client. For anything gameplay-critical (ball, vehicle in a race, moving platform): `part:SetNetworkOwner(nil)` on the server, or anchor and move it with the server.
- Touched events fire for exploiters too, from any distance they can move a part to: re-check distance and state in the handler.

## 5. Backdoors and Toolbox assets
- Every Creator Store model can contain scripts. Toolbox shows when a model has scripts; inspect before inserting and prefer assets you or trusted creators made.
- Backdoor signs: `require(<number>)`, `getfenv`/`setfenv`, `loadstring`, long escaped strings or `string.char` chains, code pushed off-screen with whitespace, HTTP calls to webhooks or paste sites, scripts named like engine objects ("Weld", "Fire", "Script ") inside props, `InsertService:LoadAsset` of unknown ids, plugins that insert scripts.
- Sandboxing (Script Capabilities, beta): set `Workspace.SandboxedInstance` to `Experimental`, set the model's `Sandboxed` to true and grant only the `Capabilities` it needs. Never grant Network, DataStore, AssetRequire, CapabilityControl or LoadString to third-party assets unless you know exactly why.
- Plugins run with full Studio access: install only from creators you trust and remove unused ones.
- After removing a backdoor: search the whole place again (backdoors often copy themselves into several models), check ServerScriptService, ServerStorage, Lighting, ReplicatedFirst, StarterPack/StarterGui and Teams, rotate any Open Cloud API keys the place used.

## 6. Data and purchases
- Player data: session locking (UpdateAsync with a lock or a proven library), save on leave, BindToClose and autosave, schema version with migrations, every DataStore call in pcall with retries. `SetAsync` on player data is a red flag.
- `ProcessReceipt`: exactly one in the whole game, server-side, idempotent (store PurchaseIds), grants and saves before returning `PurchaseGranted`, returns `NotProcessedYet` when the player's data isn't loaded.
- Prices shown in UI come from `MarketplaceService:GetProductInfo(id, Enum.InfoType.Product / GamePass)` (`PriceInRobux`), because Managed Pricing (regional pricing + price optimization, on by default for passes) changes what each player pays. Hard-coded prices show the wrong number.
- Trades and gifts between players with different regional prices: gate them with `MarketplaceService:GetUsersPriceLevelsAsync` to prevent price arbitrage.
- Paid random items and trading: check PolicyService per player.

## 7. Detection and consequences
- The server decides. Client-side detections are only hints; never ban on them.
- Prevent harm first: drop the request, clamp, re-sync, rubber-band. Punish only to protect others.
- Heuristics as signals: rate of gain, completion time, action cadence. Add to a per-player suspicion score; act when several independent signals agree.
- Honeypot remotes: a remote no legitimate client ever fires; firing it is strong evidence.
- Consequence ladder: silent logging -> quiet mitigation -> temporary restrictions (trading, leaderboards) -> kick/temporary ban -> permanent ban. Delay visible consequences so exploiters can't tell what triggered them. For repeat offenders use the Ban API (`Players:BanAsync`) instead of kicks.
- Admin and moderator commands: check `UserId` (or group rank) on the server for every command, never names or a client flag.

## 8. Settings to check
- ServerScriptService.LoadStringEnabled: off.
- Game Settings > Security: Allow HTTP Requests only if the game uses HttpService; Enable Studio Access to API Services only in development places if testers shouldn't touch live data.
- Third-party teleports and Third-party sales: off unless needed.
- Team Create collaborators and group roles with edit access: only people who need it; 2FA on accounts that can publish.

## 9. Field notes (developers and newer engine features)
Labels: [docs] = Roblox docs; [tut xN] = N developer videos agree.
- **Client physics lies are replicated:** an exploiter can set `CanCollide = false` or `CanTouch = false` on their
  own copy of a wall, set their WalkSpeed, or delete a floor locally, and the server accepts the resulting movement
  because the character is client-owned. Detect on the server: raycast or `GetPartsInPart` from the last good
  position to the new one against server geometry (noclip), distance per second with a lag tolerance (speed),
  sustained air time without a jump/fall state (fly). Move them back to the last good position (rubber-band)
  instead of instant bans; false positives (lag, launch pads, knockback, vehicles) must be whitelisted. [tut x3]
- **Touched as a security signal:** a server-created, invisible, non-colliding hitbox part welded to the character
  (CanTouch on, never modified by the server afterwards) still fires Touched even if the exploiter disables
  touching on their client copies; re-check position on the server in the handler. [tut x1]
- **NPCs and loose parts:** `SetNetworkOwner(nil)` on NPC root parts right after spawning, or exploiters teleport
  or fling them. [tut x2 + docs]
- **Client anti-cheats are deletable:** a LocalScript that checks WalkSpeed/JumpPower and fires a "kick me"
  remote is trivial to remove or spoof; free "anti-cheat" models from the Toolbox often do exactly this, produce
  false positives, or contain backdoors. Server checks only. [tut x3]
- **Hide what clients don't need:** modules and remotes that only the server uses belong in ServerScriptService/
  ServerStorage; load sensitive client UI/modules only when needed; anything replicated can be decompiled, and
  memory dumps of the client reveal strings. [tut x1]
- **Honeypots:** a convincing but unused remote (e.g. `GiveCoins`) that bans or flags whoever fires it; also deny
  badges/leaderboard entries to flagged players. Combine with other signals before banning. [tut x2]
- **Server authority model** [docs]: `Workspace.AuthorityMode = Server` makes the server simulate characters and
  physics from client inputs with client prediction, closing speed/fly/teleport classes of exploits for
  competitive games (requires Deferred signals, NextGenerationReplication, Input Action System player scripts,
  fixed simulation, streaming). See `roblox-luau-codegen/references/architecture.md` section 6.
- **Device Trust API** [docs]: a trust level for the joining device you can use to route untrusted devices
  (e.g. to separate servers or limited modes); it never replaces server validation.
- **Hit validation with latency:** clients see targets slightly in the past; validate hits with a tolerance on
  distance/angle, or keep a short server-side history of positions and check against where the target was when
  the client fired (lag compensation). Reject hits through walls with a server raycast. [tut x2]

Sources: GnomeCode, "How to Secure your Game Against Exploiters" (2023-04) https://www.youtube.com/watch?v=2jvahdJnQRI ;
ByteBlox, "Exploits Are EASY to Fix, People Are Just Lazy" (2024-04) https://www.youtube.com/watch?v=vKPZGVtIHy4 ;
"How Roblox Exploits Work (+ how to fix them)" (2023-12) https://www.youtube.com/watch?v=KbW_p_83hgQ ;
"Your Game is Vulnerable. Here's how to fix it." (2026-08) https://www.youtube.com/watch?v=b1t8ZYJt120 ;
GuideRealm / Hypoly client anti-cheat tutorials (examples of what not to rely on) https://www.youtube.com/watch?v=YNk9A7SkL_w , https://www.youtube.com/watch?v=9BpHmhDwz0M ;
creator-docs scripting/security (security-tactics, device-trust, network-ownership), projects/server-authority.
(Transcript excerpts via Perplexity.)
