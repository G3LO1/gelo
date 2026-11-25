--!strict
-- UiStates: one state machine for layered components (Button, ItemCard...) that works the same
-- for mouse, touch and gamepad. It only sets STATE TAGS; the look of each state lives in style
-- rules (ui-spec `styles`, e.g. ".StateFocused > ImageLabel#Glow"), which tween with the shared
-- `motion` numbers. So the spec, the browser preview and the game show the same states.
--
--   Default   nothing
--   Focused   mouse over it, or gamepad selection on it      tag StateFocused
--   Pressed   mouse button / finger / gamepad A held on it    tag StatePressed
--   Disabled  attribute Disabled = true                       tag StateDisabled, Interactable/Selectable off
--
-- Touch has no hover: a tap goes Default -> Pressed -> Default (hover comes from MouseMovement
-- input only, so a finger never leaves a card stuck in Focused).
--
-- Put it in ReplicatedStorage and bind on the client after the ScreenGui exists:
--   local states = UiStates.bind(playerGui.Shop, { reducedMotion = settings.reducedMotion })
--   states:open(playerGui.Shop.Gallery.Cards)   -- cards pop in one after another
--   card:SetAttribute("Disabled", true)          -- or states:setDisabled(card, true)
--   card.Activated:Connect(buy)                  -- Activated works for mouse, touch and gamepad

local UiStates = {}

UiStates.Tags = { "Button", "ItemCard" } -- components to bind
UiStates.StateTags = { Focused = "StateFocused", Pressed = "StatePressed", Disabled = "StateDisabled" }

-- Same keys and defaults as `motion` in ui-spec (spec_to_luau.py MOTION); the build script stores
-- them on the StyleSheet as Motion<Key> attributes.
UiStates.DefaultMotion = {
	hoverScale = 1.04,
	pressScale = 0.98,
	hoverTime = 0.12,
	pressTime = 0.08,
	openTime = 0.3,
	stagger = 0.05,
	glowIdle = 1,
	glowFocused = 0.35,
	glowPressed = 0.15,
	disabledTransparency = 0.5,
	breathe = 1.6,
}

export type Motion = typeof(UiStates.DefaultMotion)
export type Options = {
	motion: Motion?, -- default: read from the StyleSheet linked to the ScreenGui
	tags: { string }?,
	reducedMotion: boolean?, -- no breathing, no pop-in (state looks still change)
	hideSelectionImage: boolean?, -- default true: the glow layer shows gamepad focus
	-- for tests: stand-ins for engine services
	tweenService: any?,
	delay: ((number, () -> ()) -> ())?,
}

type Entry = {
	hovered: boolean,
	selected: boolean,
	pressed: boolean,
	state: string,
	connections: { RBXScriptConnection },
	breath: Tween?,
	glowSize: UDim2?,
}

local function readMotion(root: Instance): Motion
	local motion = table.clone(UiStates.DefaultMotion)
	local gui = if root:IsA("LayerCollector") then root else root:FindFirstAncestorWhichIsA("LayerCollector")
	local link = gui and gui:FindFirstChildWhichIsA("StyleLink")
	local sheet = link and (link :: any).StyleSheet
	if sheet then
		for key in UiStates.DefaultMotion do
			local value = sheet:GetAttribute("Motion" .. string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2))
			if type(value) == "number" then
				(motion :: any)[key] = value
			end
		end
	end
	return motion
end

local function stateOf(entry: Entry, disabled: boolean): string
	if disabled then
		return "Disabled"
	elseif entry.pressed then
		return "Pressed"
	elseif entry.hovered or entry.selected then
		return "Focused"
	end
	return "Default"
end

local Binder = {}
Binder.__index = Binder

export type Binder = typeof(setmetatable(
	{} :: {
		root: Instance,
		motion: Motion,
		options: Options,
		entries: { [GuiObject]: Entry },
		connections: { RBXScriptConnection },
		noSelection: Frame?,
	},
	Binder
))

function UiStates.bind(root: Instance, options: Options?): Binder
	local opts = options or {}
	local self = setmetatable({
		root = root,
		motion = opts.motion or readMotion(root),
		options = opts,
		entries = {},
		connections = {},
		noSelection = nil :: Frame?,
	}, Binder)
	if opts.hideSelectionImage ~= false then
		local blank = Instance.new("Frame")
		blank.Name = "NoSelectionImage"
		blank.BackgroundTransparency = 1
		self.noSelection = blank
	end
	for _, descendant in root:GetDescendants() do
		self:add(descendant)
	end
	table.insert(
		self.connections,
		root.DescendantAdded:Connect(function(descendant)
			self:add(descendant)
		end)
	)
	return self
end

function Binder.isComponent(self: Binder, instance: Instance): boolean
	if not instance:IsA("GuiButton") then
		return false
	end
	for _, tag in self.options.tags or UiStates.Tags do
		if instance:HasTag(tag) then
			return true
		end
	end
	return false
end

function Binder.tween(self: Binder, instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween?
	local service = self.options.tweenService or game:GetService("TweenService")
	local tween = service:Create(instance, info, goal)
	tween:Play()
	return tween
end

function Binder.add(self: Binder, instance: Instance)
	if self.entries[instance :: GuiObject] or not self:isComponent(instance) then
		return
	end
	local element = instance :: GuiButton
	local entry: Entry = { hovered = false, selected = false, pressed = false, state = "", connections = {} }
	self.entries[element] = entry
	element.AutoButtonColor = false
	if self.noSelection then
		element.SelectionImageObject = self.noSelection
	end
	local function update()
		self:apply(element)
	end
	local function isPress(input: InputObject): boolean
		local kind = input.UserInputType
		return kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.Touch
			or (input.KeyCode == Enum.KeyCode.ButtonA and entry.selected)
	end
	table.insert(
		entry.connections,
		element.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				entry.hovered = true
			elseif isPress(input) then
				entry.pressed = true
			end
			update()
		end)
	)
	table.insert(
		entry.connections,
		element.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				entry.hovered = false
				entry.pressed = false -- dragged off while held: not pressed any more
			elseif input.UserInputType == Enum.UserInputType.Touch then
				entry.pressed = false
				entry.hovered = false -- touch never hovers
			elseif isPress(input) then
				entry.pressed = false
			end
			update()
		end)
	)
	table.insert(
		entry.connections,
		element.SelectionGained:Connect(function()
			entry.selected = true
			update()
		end)
	)
	table.insert(
		entry.connections,
		element.SelectionLost:Connect(function()
			entry.selected = false
			entry.pressed = false
			update()
		end)
	)
	table.insert(entry.connections, element:GetAttributeChangedSignal("Disabled"):Connect(update))
	table.insert(
		entry.connections,
		element.AncestryChanged:Connect(function()
			if not element:IsDescendantOf(self.root) then
				self:remove(element)
			end
		end)
	)
	update()
end

function Binder.apply(self: Binder, element: GuiButton)
	local entry = self.entries[element]
	if not entry then
		return
	end
	local disabled = element:GetAttribute("Disabled") == true
	if disabled then
		entry.pressed = false
	end
	local state = stateOf(entry, disabled)
	if state == entry.state then
		return
	end
	entry.state = state
	element:SetAttribute("State", state)
	for name, tag in UiStates.StateTags do
		if name == state then
			element:AddTag(tag)
		else
			element:RemoveTag(tag)
		end
	end
	element.Interactable = not disabled
	element.Selectable = not disabled
	self:breathe(element, entry, state == "Focused")
end

-- The glow layer swells and settles while focused ("the glow breathes").
function Binder.breathe(self: Binder, element: GuiButton, entry: Entry, on: boolean)
	local glow = element:FindFirstChild("Glow") :: GuiObject?
	if entry.breath then
		entry.breath:Cancel()
		entry.breath = nil
		if glow and entry.glowSize then
			glow.Size = entry.glowSize
		end
	end
	if not (on and glow) or self.options.reducedMotion or self.motion.breathe <= 0 then
		return
	end
	entry.glowSize = glow.Size
	local size = glow.Size
	local info = TweenInfo.new(self.motion.breathe / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	entry.breath = self:tween(glow, info, { Size = UDim2.new(size.X.Scale, size.X.Offset + 8, size.Y.Scale, size.Y.Offset + 8) })
end

-- Window opening: components under `container` pop in one after another (LayoutOrder), each
-- from 0.9 to 1 over motion.openTime, motion.stagger apart. Reduced motion shows them at once.
function Binder.open(self: Binder, container: Instance)
	local items = {}
	for _, child in container:GetChildren() do
		if self.entries[child :: GuiObject] then
			table.insert(items, child :: GuiObject)
		end
	end
	table.sort(items, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local wait = self.options.delay or task.delay
	for index, item in items do
		local scale = item:FindFirstChildWhichIsA("UIScale")
		if not scale then
			local created = Instance.new("UIScale")
			created.Parent = item
			scale = created
		end
		local uiScale = scale :: UIScale
		if self.options.reducedMotion then
			uiScale.Scale = 1
			continue
		end
		uiScale.Scale = 0.9
		wait((index - 1) * self.motion.stagger, function()
			self:tween(uiScale, TweenInfo.new(self.motion.openTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		end)
	end
	return items
end

function Binder.setDisabled(_self: Binder, element: GuiButton, disabled: boolean)
	element:SetAttribute("Disabled", disabled)
end

function Binder.state(self: Binder, element: GuiButton): string?
	local entry = self.entries[element]
	return entry and entry.state
end

function Binder.remove(self: Binder, element: GuiButton)
	local entry = self.entries[element]
	if not entry then
		return
	end
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	if entry.breath then
		entry.breath:Cancel()
	end
	self.entries[element] = nil
end

function Binder.destroy(self: Binder)
	for element in self.entries do
		self:remove(element :: GuiButton)
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.noSelection then
		self.noSelection:Destroy()
	end
end

return UiStates
