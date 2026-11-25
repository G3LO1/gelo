-- UiStates.luau behaviour under Lune with stand-in GUI objects: the same component goes through
-- its states with mouse, touch and gamepad input, disabled components ignore input, motion is
-- read from the StyleSheet, open() staggers, reduced motion skips animation.
-- Usage (repo root): lune run tests/roblox-ui-designer/states_test

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local Enum = roblox.Enum
local passed, failed = 0, 0
local function check(condition, message)
	if condition then
		passed += 1
		print(`  ok   {message}`)
	else
		failed += 1
		print(`  FAIL {message}`)
	end
end

-- Minimal signal + instance stand-ins (Lune's instances have no events).
local function signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		local connection = { Connected = true }
		table.insert(self.handlers, { fn = fn, connection = connection })
		function connection:Disconnect()
			self.Connected = false
		end
		return connection
	end
	function s:Fire(...)
		for _, h in self.handlers do
			if h.connection.Connected then
				h.fn(...)
			end
		end
	end
	return s
end

local CLASSES = {
	ImageButton = { "ImageButton", "GuiButton", "GuiObject" },
	TextButton = { "TextButton", "GuiButton", "GuiObject" },
	ImageLabel = { "ImageLabel", "GuiObject" },
	Frame = { "Frame", "GuiObject" },
	UIScale = { "UIScale" },
	ScreenGui = { "ScreenGui", "LayerCollector" },
	StyleLink = { "StyleLink" },
	StyleSheet = { "StyleSheet" },
}

local function new(className, props)
	local inst = {
		ClassName = className,
		Name = className,
		children = {},
		tags = {},
		attributes = {},
		attrSignals = {},
		InputBegan = signal(),
		InputEnded = signal(),
		SelectionGained = signal(),
		SelectionLost = signal(),
		AncestryChanged = signal(),
		DescendantAdded = signal(),
		LayoutOrder = 0,
		destroyed = false,
	}
	for k, v in props or {} do
		inst[k] = v
	end
	function inst:IsA(name)
		return table.find(CLASSES[self.ClassName] or { self.ClassName }, name) ~= nil
	end
	function inst:SetParent(parent)
		rawset(self, "_parent", parent)
		table.insert(parent.children, self)
		local node = parent
		while node do
			node.DescendantAdded:Fire(self)
			node = node.Parent
		end
		return self
	end
	function inst:GetChildren()
		return table.clone(self.children)
	end
	function inst:GetDescendants()
		local out = {}
		local function walk(node)
			for _, c in node.children do
				table.insert(out, c)
				walk(c)
			end
		end
		walk(self)
		return out
	end
	function inst:FindFirstChild(name)
		for _, c in self.children do
			if c.Name == name then
				return c
			end
		end
		return nil
	end
	function inst:FindFirstChildWhichIsA(className)
		for _, c in self.children do
			if c:IsA(className) then
				return c
			end
		end
		return nil
	end
	function inst:FindFirstAncestorWhichIsA(className)
		local node = self.Parent
		while node do
			if node:IsA(className) then
				return node
			end
			node = node.Parent
		end
		return nil
	end
	function inst:IsDescendantOf(other)
		local node = self.Parent
		while node do
			if node == other then
				return true
			end
			node = node.Parent
		end
		return false
	end
	function inst:HasTag(tag)
		return self.tags[tag] == true
	end
	function inst:AddTag(tag)
		self.tags[tag] = true
	end
	function inst:RemoveTag(tag)
		self.tags[tag] = nil
	end
	function inst:GetAttribute(name)
		return self.attributes[name]
	end
	function inst:SetAttribute(name, value)
		self.attributes[name] = value
		if self.attrSignals[name] then
			self.attrSignals[name]:Fire()
		end
	end
	function inst:GetAttributeChangedSignal(name)
		self.attrSignals[name] = self.attrSignals[name] or signal()
		return self.attrSignals[name]
	end
	function inst:Destroy()
		self.destroyed = true
	end
	-- `x.Parent = y` works like in Roblox (the module creates UIScales that way)
	return setmetatable(inst, {
		__index = function(t, key)
			return if key == "Parent" then rawget(t, "_parent") else nil
		end,
		__newindex = function(t, key, value)
			if key == "Parent" then
				t:SetParent(value)
			else
				rawset(t, key, value)
			end
		end,
	})
end

local tweens = {}
local tweenService = {
	Create = function(_, instance, info, goal)
		local tween = { instance = instance, info = info, goal = goal, played = false, cancelled = false }
		function tween:Play()
			self.played = true
		end
		function tween:Cancel()
			self.cancelled = true
		end
		table.insert(tweens, tween)
		return tween
	end,
}
local delays = {}
local function delay(seconds, fn)
	table.insert(delays, seconds)
	fn()
end

local TweenInfo = {
	new = function(time, style, direction, repeats, reverses)
		return { Time = time, EasingStyle = style, EasingDirection = direction, RepeatCount = repeats or 0, Reverses = reverses or false }
	end,
}

local env = {
	Instance = {
		new = function(className)
			return new(className)
		end,
	},
	Enum = Enum,
	UDim2 = roblox.UDim2,
	TweenInfo = TweenInfo,
	table = table,
	string = string,
	game = { GetService = function() return tweenService end },
	task = { delay = delay },
	setmetatable = setmetatable,
}
local UiStates = luau.load(
	fs.readFile("plugins/roblox-studio/skills/roblox-ui-designer/assets/UiStates.luau"),
	{ debugName = "UiStates", environment = env }
)()

-- A ScreenGui linked to a StyleSheet that carries the spec's motion numbers.
local function makeScreen()
	local gui = new("ScreenGui")
	local sheet = new("StyleSheet")
	sheet.attributes.MotionHoverScale = 1.06
	sheet.attributes.MotionStagger = 0.07
	sheet.attributes.MotionBreathe = 2
	new("StyleLink", { StyleSheet = sheet }):SetParent(gui)
	local row = new("Frame", { Name = "Cards" }):SetParent(gui)
	local function component(name, tag, order)
		local c = new("ImageButton", { Name = name, LayoutOrder = order, Selectable = true, Interactable = true, AutoButtonColor = true })
		c.tags[tag] = true
		new("UIScale"):SetParent(c)
		new("ImageLabel", { Name = "Glow", Size = roblox.UDim2.new(1, 28, 1, 28) }):SetParent(c)
		return c:SetParent(row)
	end
	local cards = { component("CardA", "ItemCard", 2), component("CardB", "ItemCard", 1), component("Buy", "Button", 3) }
	local plain = new("ImageButton", { Name = "Untagged" }):SetParent(row)
	return gui, row, cards, plain
end

local function input(kind, keyCode)
	return { UserInputType = Enum.UserInputType[kind], KeyCode = keyCode and Enum.KeyCode[keyCode] or Enum.KeyCode.Unknown }
end
local function tagsOf(c)
	local out = {}
	for tag in c.tags do
		if string.sub(tag, 1, 5) == "State" then
			table.insert(out, tag)
		end
	end
	table.sort(out)
	return table.concat(out, ",")
end

print("UiStates")
local gui, row, cards, plain = makeScreen()
local states = UiStates.bind(gui, { tweenService = tweenService, delay = delay })
local card = cards[1]
check(states:state(card) == "Default" and tagsOf(card) == "" and states:state(plain) == nil, "binds tagged components only, starting in Default")
check(states.motion.hoverScale == 1.06 and states.motion.stagger == 0.07 and states.motion.pressScale == 0.98, "motion read from the linked StyleSheet (defaults for the rest)")
check(card.AutoButtonColor == false and card.SelectionImageObject ~= nil and card.SelectionImageObject.BackgroundTransparency == 1, "default button tint and gamepad selection box are replaced by the glow")

-- mouse: hover -> press -> release -> leave
card.InputBegan:Fire(input("MouseMovement"))
check(states:state(card) == "Focused" and tagsOf(card) == "StateFocused" and card.attributes.State == "Focused", "mouse over: Focused (tag + State attribute)")
check(#tweens >= 1 and tweens[#tweens].instance.Name == "Glow" and tweens[#tweens].info.RepeatCount == -1 and tweens[#tweens].info.Time == 1, "focused glow breathes (period from motion.breathe)")
card.InputBegan:Fire(input("MouseButton1"))
check(states:state(card) == "Pressed" and tagsOf(card) == "StatePressed", "mouse down: Pressed")
local breath = tweens[#tweens]
check(breath.cancelled and card:FindFirstChild("Glow").Size == roblox.UDim2.new(1, 28, 1, 28), "breathing stops and the glow size resets when pressed")
card.InputEnded:Fire(input("MouseButton1"))
check(states:state(card) == "Focused", "mouse up while over it: back to Focused")
card.InputEnded:Fire(input("MouseMovement"))
check(states:state(card) == "Default" and tagsOf(card) == "", "mouse leaves: Default, no state tags")
card.InputBegan:Fire(input("MouseMovement"))
card.InputBegan:Fire(input("MouseButton1"))
card.InputEnded:Fire(input("MouseMovement"))
check(states:state(card) == "Default", "dragged off while held: not pressed any more")

-- touch: no hover, ever
card.InputBegan:Fire(input("Touch"))
check(states:state(card) == "Pressed", "finger down: Pressed")
card.InputEnded:Fire(input("Touch"))
check(states:state(card) == "Default", "finger up: Default (touch never leaves Focused behind)")
-- some touch devices also report an emulated mouse move on tap, with no matching end
card.InputBegan:Fire(input("MouseMovement"))
card.InputBegan:Fire(input("Touch"))
card.InputEnded:Fire(input("Touch"))
check(states:state(card) == "Default", "tap with an emulated mouse move: still Default after the finger lifts")

-- gamepad: selection = focus, A = press
card.SelectionGained:Fire()
check(states:state(card) == "Focused", "gamepad selection: Focused")
card.InputBegan:Fire(input("Gamepad1", "ButtonA"))
check(states:state(card) == "Pressed", "gamepad A on the selected card: Pressed")
card.InputEnded:Fire(input("Gamepad1", "ButtonA"))
check(states:state(card) == "Focused", "A released: Focused (still selected)")
card.SelectionLost:Fire()
check(states:state(card) == "Default", "selection moves away: Default")
card.InputBegan:Fire(input("Gamepad1", "ButtonA"))
check(states:state(card) == "Default", "A without selection does nothing")

-- disabled
card.InputBegan:Fire(input("MouseMovement"))
states:setDisabled(card, true)
check(states:state(card) == "Disabled" and tagsOf(card) == "StateDisabled" and card.Interactable == false and card.Selectable == false, "Disabled attribute: StateDisabled, not interactable, not selectable")
card.InputBegan:Fire(input("MouseButton1"))
card.InputBegan:Fire(input("Touch"))
check(states:state(card) == "Disabled", "disabled ignores mouse and touch presses")
card:SetAttribute("Disabled", false)
check(states:state(card) == "Focused" and card.Interactable == true and card.Selectable == true, "re-enabled while the mouse is over it: Focused again")

-- components added later (shop lists) are bound too
local late = new("ImageButton", { Name = "Late", LayoutOrder = 9 })
late.tags.ItemCard = true
late:SetParent(row)
check(states:state(late) == "Default", "components added later are bound")

-- open: staggered pop-in in LayoutOrder
table.clear(tweens)
table.clear(delays)
local opened = states:open(row)
check(#opened == 4 and opened[1].Name == "CardB" and opened[2].Name == "CardA", "open() goes through components in LayoutOrder")
check(delays[2] == 0.07 and delays[3] == 0.14 and #tweens == 4 and tweens[1].goal.Scale == 1 and tweens[1].info.Time == 0.3, "pop-in one after another: stagger and openTime from motion")
check(late:FindFirstChildWhichIsA("UIScale") ~= nil, "a UIScale is added when a component has none")

-- reduced motion
local gui2, row2, cards2 = makeScreen()
table.clear(tweens)
local calm = UiStates.bind(gui2, { tweenService = tweenService, delay = delay, reducedMotion = true, motion = UiStates.DefaultMotion })
cards2[1].InputBegan:Fire(input("MouseMovement"))
calm:open(row2)
check(calm:state(cards2[1]) == "Focused" and #tweens == 0, "reduced motion: states still change, nothing breathes or pops")

-- destroy
states:destroy()
card.InputBegan:Fire(input("Touch"))
check(states:state(card) == nil and card.attributes.State == "Focused", "destroy() disconnects every component")

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
