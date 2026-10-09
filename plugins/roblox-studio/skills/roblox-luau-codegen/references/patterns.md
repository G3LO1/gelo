# Roblox Luau patterns

Rules and patterns for systems built on the template (`DataService`, `PurchaseService`, `Net`, `Guard`, `Config`). Snippets assume the usual service locals (`local Players = game:GetService("Players")`, etc.) and the template modules required at the top.

## Contents
1. Coding rules
2. Security checklist
3. Patterns: currency + analytics, shop, cooldowns, hit validation, round state, interactions, placement, NPC pathfinding, leaderboards, codes, daily rewards, text filtering, PolicyService, animations, sounds, UI controllers, monetization service

## 1. Coding rules
- `game:GetService` for every service; `task.wait/spawn/delay/defer` (never `wait`, `spawn`, `delay`); `os.clock()` for durations, `os.time()` for saved timestamps.
- Set properties first and `Parent` last on new instances; don't use the `Instance.new(class, parent)` form.
- Modern APIs: `Animator:LoadAnimation` (not `Humanoid:LoadAnimation`), `LinearVelocity`/`AlignPosition`/`AlignOrientation` (not `BodyVelocity`/`BodyPosition`/`BodyGyro`), `workspace:Raycast` + `RaycastParams`, `GetPartBoundsInBox`/`GetPartsInPart` + `OverlapParams`, `UserInputService`/`ContextActionService` (not `Mouse`), `TextChatService`.
- Handle players already in game and characters already spawned: loop `Players:GetPlayers()` after connecting `PlayerAdded`; check `player.Character` before `CharacterAdded`.
- Clean up per-player and per-character state on `PlayerRemoving` and `Humanoid.Died`/`CharacterRemoving` (tables keyed by Player leak otherwise). Disconnect connections you own.
- Client code assumes streaming: `WaitForChild(name, timeout)` and nil checks for anything in Workspace.
- Asset IDs (animations, sounds, images) live in one shared module (e.g. `src/shared/Assets.luau`), not scattered literals.
- Performance: no per-part `while true` loops; one loop or `RunService.Heartbeat` handler per system iterating a set built with `CollectionService` tags; visuals (tweens, particles, camera) on the client; server only does authority.
- Type annotations on public functions; add `--!strict` when the team uses luau-lsp.

## 2. Security checklist
The client is controlled by the player. For every remote and every system ask:
- Does the server decide the outcome (currency, damage, price, ownership, cooldown, position, timer)? The client only says what it wants.
- Every argument validated with `Guard` (type, range, length, membership, Instance class and ancestry). NaN and huge numbers rejected (Guard.number does this).
- Is the player allowed to do this now: alive, in the right round/state, owns the item/plot, close enough, off cooldown?
- Rate limited (Net default 10/s; lower for expensive or economy actions).
- Instances passed by the client are re-checked: still exist, belong to this player or are public, within range.
- No remote that runs arbitrary code, sets arbitrary properties or accepts paths.
- NPCs and server-owned physics: `PrimaryPart:SetNetworkOwner(nil)`.
- Data: changes go through `DataService.Update`; never trust a client copy; purchases only through `PurchaseService`.
- Player text is filtered before anyone else sees it.

## 3. Patterns

### Currency change + analytics
Signature (checked against create.roblox.com, Oct 2026): `LogEconomyEvent(player, flowType, currencyType, amount, endingBalance, transactionType, itemSku?, customFields?)`. Amount comes before the balance.
```lua
local AnalyticsService = game:GetService("AnalyticsService")

local CurrencyService = {}

function CurrencyService.Add(player: Player, amount: number, transactionType: string, sku: string): boolean
	local changed = DataService.Update(player, function(data)
		data.Coins += amount
	end)
	if changed then
		local data = DataService.Get(player)
		AnalyticsService:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Source,
			"Coins", -- currencyType
			amount, -- amount of this transaction (always positive)
			data.Coins, -- endingBalance after it
			transactionType, -- e.g. Enum.AnalyticsEconomyTransactionType.Gameplay.Name
			sku -- itemSku
		)
	end
	return changed
end

-- Returns false (and changes nothing) if the player can't afford it.
function CurrencyService.Spend(player: Player, amount: number, transactionType: string, sku: string): boolean
	local spent = false
	DataService.Update(player, function(data)
		if data.Coins >= amount then
			data.Coins -= amount
			spent = true
		end
	end)
	if spent then
		local data = DataService.Get(player)
		AnalyticsService:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Sink,
			"Coins", -- currencyType
			amount, -- amount (positive, the dashboard shows sinks as negative)
			data.Coins, -- endingBalance
			transactionType,
			sku
		)
	end
	return spent
end
```

### Shop (in-game currency)
Prices live in a shared table the server enforces; the client only names the item.
```lua
-- src/shared/ItemData.luau
local ItemData = {
	Items = {
		Sword = { Price = 100 },
		Bow = { Price = 250 },
	},
	Ids = {} :: { string },
}
for id in ItemData.Items do
	table.insert(ItemData.Ids, id)
end
return ItemData
```
```lua
-- ShopService.Start()
Net.handle("BuyItem", { Guard.oneOf(ItemData.Ids) }, function(player, itemId)
	local data = DataService.Get(player)
	if not data or data.Inventory[itemId] then
		return
	end
	local price = ItemData.Items[itemId].Price
	if CurrencyService.Spend(player, price, Enum.AnalyticsEconomyTransactionType.Shop.Name, itemId) then
		DataService.Update(player, function(playerData)
			playerData.Inventory[itemId] = true
		end)
	end
end, { rate = 2 })
```

### Server cooldowns
```lua
local lastUse: { [Player]: { [string]: number } } = {}

local function tryUse(player: Player, ability: string, cooldown: number): boolean
	local uses = lastUse[player]
	if not uses then
		uses = {}
		lastUse[player] = uses
	end
	local now = os.clock()
	if uses[ability] and now - uses[ability] < cooldown then
		return false
	end
	uses[ability] = now
	return true
end

Players.PlayerRemoving:Connect(function(player)
	lastUse[player] = nil
end)
```

### Hit validation (melee)
The client may play the swing and report a target; the server checks everything and computes damage.
```lua
local RANGE = 8
local TOLERANCE = 4 -- latency slack

Net.handle("Attack", { Guard.instance("Model", workspace) }, function(player, target)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid and targetRoot and targetHumanoid) then
		return
	end
	if humanoid.Health <= 0 or targetHumanoid.Health <= 0 or target == character then
		return
	end
	if (root.Position - targetRoot.Position).Magnitude > RANGE + TOLERANCE then
		return
	end
	if not tryUse(player, "Attack", 0.5) then
		return
	end
	targetHumanoid:TakeDamage(10)
end, { rate = 5 })
```
Projectiles: the server either simulates them or checks that the origin is near the character and the direction is plausible, then raycasts itself.

### Round / game state
Broadcast state with attributes (they replicate) instead of extra remotes.
```lua
local STATES = { "Intermission", "Day", "Night", "Results" }
local DURATIONS = { Intermission = 15, Day = 120, Night = 90, Results = 10 }

local function setState(state: string, endsAt: number)
	workspace:SetAttribute("GameState", state)
	workspace:SetAttribute("StateEndsAt", endsAt) -- client shows a countdown from workspace:GetServerTimeNow()
end

task.spawn(function()
	while true do
		for _, state in STATES do
			local duration = DURATIONS[state]
			setState(state, workspace:GetServerTimeNow() + duration)
			task.wait(duration)
		end
	end
end)

-- Client: workspace:GetAttributeChangedSignal("GameState"):Connect(updateUi)
```

### Interactions
`ProximityPrompt.Triggered` fires on the server with the player and the engine already checks distance; still check game rules.
```lua
local CollectionService = game:GetService("CollectionService")

local function setupStation(station: Instance)
	local prompt = station:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		return
	end
	prompt.Triggered:Connect(function(player)
		if workspace:GetAttribute("GameState") ~= "Day" then
			return
		end
		-- server-side effect here
	end)
end

CollectionService:GetInstanceAddedSignal("Station"):Connect(setupStation)
for _, station in CollectionService:GetTagged("Station") do
	setupStation(station)
end
```

### Placement (building, towers, furniture)
The client previews and sends the item and a desired position; the server snaps, checks ownership/bounds/overlap/cost and builds the real object.
```lua
local GRID = 4

Net.handle("Place", { Guard.oneOf(ItemData.Ids), Guard.vector3(10000) }, function(player, itemId, position)
	local plot = getPlot(player) -- the player's own area (Part); returns nil if none
	if not plot then
		return
	end
	local snapped = Vector3.new(
		math.round(position.X / GRID) * GRID,
		plot.Position.Y + plot.Size.Y / 2,
		math.round(position.Z / GRID) * GRID
	)
	local localPos = plot.CFrame:PointToObjectSpace(snapped)
	if math.abs(localPos.X) > plot.Size.X / 2 or math.abs(localPos.Z) > plot.Size.Z / 2 then
		return
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { plot.Placed }
	local size = Vector3.new(GRID - 0.1, 4, GRID - 0.1)
	if #workspace:GetPartBoundsInBox(CFrame.new(snapped + Vector3.new(0, 2, 0)), size, params) > 0 then
		return
	end
	local price = ItemData.Items[itemId].Price
	if not CurrencyService.Spend(player, price, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, itemId) then
		return
	end
	-- clone the model from ServerStorage, PivotTo(CFrame.new(snapped)), parent to plot.Placed, save to data if persistent
end, { rate = 4 })
```

### NPC pathfinding
```lua
local PathfindingService = game:GetService("PathfindingService")

local function walkTo(npc: Model, goal: Vector3): boolean
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local root = npc.PrimaryPart
	if not humanoid or not root then
		return false
	end
	root:SetNetworkOwner(nil)
	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
	local ok = pcall(path.ComputeAsync, path, root.Position, goal)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return false
	end
	local blocked = false
	local connection = path.Blocked:Connect(function()
		blocked = true
	end)
	for _, waypoint in path:GetWaypoints() do
		if blocked or humanoid.Health <= 0 then
			break
		end
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		humanoid:MoveTo(waypoint.Position)
		if not humanoid.MoveToFinished:Wait() then
			break -- MoveTo timed out (stuck)
		end
	end
	connection:Disconnect()
	return not blocked
end
```
Re-call `walkTo` when it returns false. Many NPCs: stagger path computations, reuse paths for groups, use simple `MoveTo` on open ground.

### Leaderboard (OrderedDataStore)
```lua
local DataStoreService = game:GetService("DataStoreService")
local board = DataStoreService:GetOrderedDataStore("Coins_v1")

local function submit(player: Player, value: number) -- on leave and every few minutes, not every change
	pcall(board.SetAsync, board, tostring(player.UserId), math.floor(value))
end

local function top(count: number): { { key: string, value: number } }
	local ok, pages = pcall(board.GetSortedAsync, board, false, count)
	if not ok then
		return {}
	end
	return pages:GetCurrentPage()
end
-- Refresh the shown board every 60-120 seconds; resolve names with Players:GetNameFromUserIdAsync (cache it).
```

### Codes
```lua
local CODES = {
	LAUNCH = { Coins = 500, Expires = os.time({ year = 2027, month = 1, day = 1, hour = 0 }) },
}

Net.handleInvoke("RedeemCode", { Guard.string(32) }, function(player, input)
	local code = string.upper(input)
	local reward = CODES[code]
	if not reward or os.time() > reward.Expires then
		return "Invalid"
	end
	local granted = false
	DataService.Update(player, function(data)
		data.RedeemedCodes = data.RedeemedCodes or {}
		if not data.RedeemedCodes[code] then
			data.RedeemedCodes[code] = true
			data.Coins += reward.Coins
			granted = true
		end
	end)
	return if granted then "Redeemed" else "AlreadyUsed"
end, { rate = 1, burst = 3 })
```
Add `RedeemedCodes = {}` to `Config.DefaultData` instead of the inline fallback when writing it for real.

### Daily reward
```lua
local DAY = 24 * 60 * 60

local function claimDaily(player: Player): boolean
	local claimed = false
	DataService.Update(player, function(data)
		local now = os.time()
		if now - (data.LastDaily or 0) >= DAY then
			data.Streak = if now - (data.LastDaily or 0) < 2 * DAY then (data.Streak or 0) + 1 else 1
			data.LastDaily = now
			data.Coins += 50 * math.min(data.Streak, 7)
			claimed = true
		end
	end)
	return claimed
end
```

### Filtering player text
```lua
local TextService = game:GetService("TextService")

local function filterForEveryone(player: Player, text: string): string?
	local ok, result = pcall(TextService.FilterStringAsync, TextService, text, player.UserId)
	if not ok then
		return nil -- don't show unfiltered text
	end
	local okText, filtered = pcall(result.GetNonChatStringForBroadcastAsync, result)
	return if okText then filtered else nil
end
```

### PolicyService (paid random items, trading)
```lua
local PolicyService = game:GetService("PolicyService")

local function canBuyRandomItems(player: Player): boolean
	local ok, policy = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	return ok and not policy.ArePaidRandomItemsRestricted
end
-- Same pattern: policy.IsPaidItemTradingAllowed before enabling Robux-bought item trading.
```

### Animations
Upload animations to the account or group that owns the experience and give the experience permission, otherwise they play in Studio and fail for players. Load once per character, play many times.
```lua
local Assets = require(ReplicatedStorage.Shared.Assets) -- { Animations = { Chop = "rbxassetid://..." } }

local function loadTracks(character: Model): { [string]: AnimationTrack }
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local animator = humanoid:WaitForChild("Animator") :: Animator
	local tracks = {}
	for name, id in Assets.Animations do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action
		tracks[name] = track
	end
	return tracks
end
```
Play the local player's animations on the client (they replicate); play NPC animations on the server. Use `track:GetMarkerReachedSignal("Hit")` for timing instead of `task.wait`.

### Sounds
UI and feedback sounds on the client (`SoundService:PlayLocalSound(sound)`); 3D world sounds parented to a part; every `Sound` in a `SoundGroup` (Music, SFX, UI) whose `Volume` the settings menu controls.

### UI controller
Layout is built in StarterGui by the UI designer; the controller binds to it by name, reads `DataController`, sends intents with `Net`.
```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataController = require(script.Parent.DataController)
local Net = require(ReplicatedStorage.Shared.Net)

local HudController = {}

function HudController.Start()
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Hud")
	local coinsLabel = gui:WaitForChild("Coins") :: TextLabel
	DataController.OnChanged(function(data)
		coinsLabel.Text = tostring(data.Coins)
	end)
	local buyButton = gui:WaitForChild("BuySword") :: TextButton
	buyButton.Activated:Connect(function()
		Net.fire("BuyItem", "Sword")
	end)
end

return HudController
```
Use `Activated` (works for touch, mouse and gamepad), Scale-based sizes, and test in the device emulator.

### Monetization service
```lua
local MonetizationService = {}

function MonetizationService.Init()
	PurchaseService.RegisterProduct(Config.Products.Coins500, function(_player, data)
		data.Coins += 500
	end)
end

function MonetizationService.Start()
	local function applyPerks(player: Player)
		if PurchaseService.OwnsPass(player, Config.Passes.VIP) then
			player:SetAttribute("VIP", true) -- read by other systems (e.g. 2x coins), replicated to UI
		end
	end
	Players.PlayerAdded:Connect(applyPerks)
	for _, player in Players:GetPlayers() do
		task.spawn(applyPerks, player)
	end
	PurchaseService.OnPassPurchased(function(player, passId)
		if passId == Config.Passes.VIP then
			player:SetAttribute("VIP", true)
		end
	end)
end

return MonetizationService
```
Calling `RegisterProduct` in `Init` is fine: it only fills a table.
