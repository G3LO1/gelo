-- Place audit tests: exact rule sets on in-memory places (all properties readable) and after a
-- save/load round trip (what audit_place.luau sees), then writes the files run.sh uses.
-- Usage (repo root): lune run tests/roblox-security-perf-audit/audit_test <out-dir>

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Places = require("./places")

local out = process.args[1] or "."
local CORE = "plugins/roblox-studio/skills/roblox-security-perf-audit/scripts/audit_studio.luau"
local Audit = luau.load(fs.readFile(CORE), { debugName = "audit_studio", environment = { AUDIT_RETURN = true, Enum = roblox.Enum } })()

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

local function rules(report)
	local list = {}
	for _, finding in report.findings do
		table.insert(list, `{finding.severity}:{finding.rule}`)
	end
	table.sort(list)
	return list
end

local function sameSet(actual, expected)
	table.sort(expected)
	return table.concat(actual, ",") == table.concat(expected, ","), table.concat(actual, ", ")
end

local BAD_FILE = {
	"high:LOADSTRING-ENABLED",
	"high:PARTICLE-RATE",
	"high:SCRIPT-SUSPICIOUS",
	"medium:NO-STREAMING",
	"medium:NPC-HUMANOIDS",
	"medium:PARTICLE-BUDGET",
	"medium:PARTICLE-RATE-MOBILE",
	"medium:SCRIPT-IN-MODEL",
	"medium:SHADOW-LIGHTS",
	"medium:UNANCHORED",
	"low:CHARACTER-CLEANUP",
	"low:LARGE-MODELS",
	"low:OVERDRAW",
	"low:PARTICLE-LIFETIME",
	"low:SMALL-SHADOWS",
	"low:STACKED-POSTFX",
	"low:TINY-COLLIDABLE",
}
local BAD_MEMORY = table.clone(BAD_FILE)
table.insert(BAD_MEMORY, "medium:PRECISE-COLLISION")

print("in-memory places")
local bad, car = Places.bad()
local clean = Places.clean()
local badReport = Audit.run(bad)
local ok, got = sameSet(rules(badReport), table.clone(BAD_MEMORY))
check(ok, `bad place: every rule fires exactly once ({got})`)
local cleanReport = Audit.run(clean)
check(#cleanReport.findings == 0, `clean place: no findings ({table.concat(rules(cleanReport), ", ")})`)
check(badReport.stats.preciseCollision == 60, "precise collision counted")
check(badReport.stats.npcHumanoids == 45, "NPC humanoids counted")
check(badReport.stats.totalParticleRate == 1750, "particle rate summed")
local text, totals = Audit.format(badReport)
check(totals.high == 3 and string.find(text, "Workspace.FreeCar.Engine (require() of an asset id)", 1, true) ~= nil, "report names the backdoored script")

print("saved and loaded again")
fs.writeFile(`{out}/bad.rbxl`, roblox.serializePlace(bad))
fs.writeFile(`{out}/clean.rbxl`, roblox.serializePlace(clean))
fs.writeFile(`{out}/bad.rbxmx`, roblox.serializeModel({ car }, true))
local loaded = Audit.run(roblox.deserializePlace(fs.readFile(`{out}/bad.rbxl`)))
ok, got = sameSet(rules(loaded), table.clone(BAD_FILE))
check(ok, `bad.rbxl: same findings except CollisionFidelity ({got})`)
check(loaded.stats.collisionFidelityUnreadable == 60 or loaded.stats.preciseCollision == 60, "unreadable CollisionFidelity is reported, not silently skipped")
check(#Audit.run(roblox.deserializePlace(fs.readFile(`{out}/clean.rbxl`))).findings == 0, "clean.rbxl: no findings")

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
