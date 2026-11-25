-- ModelSpecs.luau (written by model_batch.py) under Lune with Roblox's API database: apply() sets
-- the pivot and the grip Attachments on a real MeshPart, keeps existing Attachments, and warns
-- when the part was imported at another scale.
-- Usage (repo root): lune run tests/roblox-animation-vfx/model_specs_test <ModelSpecs.luau>

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

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

local function near(a, b)
	return (a - b).Magnitude < 1e-4 -- properties are stored as float32
end

local warnings = {}
local ModelSpecs = luau.load(fs.readFile(process.args[1]), {
	debugName = "ModelSpecs",
	environment = {
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Instance = roblox.Instance,
		math = math,
		warn = function(message)
			table.insert(warnings, message)
		end,
	},
})()

local katana = ModelSpecs.Models.Katana
check(katana and katana.Size.Y == 4 and katana.Attachments.Grip and katana.Attachments.BladeStart, "Katana spec: 4 studs tall, Grip and BladeStart")

local part = roblox.Instance.new("MeshPart")
part.Name = "Katana"
part.Size = katana.Size
local existing = roblox.Instance.new("Attachment")
existing.Name = "Grip"
existing.Parent = part
check(ModelSpecs.apply(part) == true and #warnings == 0, "apply() on a MeshPart with the expected size, no warnings")
local grip = part:FindFirstChild("Grip")
check(grip == existing and near(grip.Position, katana.Attachments.Grip), "an existing Grip Attachment is reused and moved")
check(part:FindFirstChild("BladeStart") and part.BladeStart:IsA("Attachment") and near(part.BladeStart.Position, katana.Attachments.BladeStart), "BladeStart Attachment created")
check(near(part.PivotOffset.Position, katana.PivotOffset) and near(katana.PivotOffset, katana.Attachments.Grip), "PivotOffset at the grip (pivot = Grip)")

local pedestal = roblox.Instance.new("MeshPart")
pedestal.Name = "Pedestal"
pedestal.Size = ModelSpecs.Models.Pedestal.Size * 100 -- imported in centimeters
ModelSpecs.apply(pedestal)
check(#warnings == 1 and string.find(warnings[1], "importer's scale", 1, true) ~= nil, "a part imported at another scale warns")
check(math.abs(pedestal.PivotOffset.Position.Y + ModelSpecs.Models.Pedestal.Size.Y / 2) < 1e-4, "Pedestal pivot at the bottom")
check(ModelSpecs.apply(roblox.Instance.new("MeshPart"), "Nope") == false and #warnings == 2, "unknown model name warns and returns false")

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
