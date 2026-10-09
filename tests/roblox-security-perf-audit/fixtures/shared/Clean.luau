-- expect:
-- Strings and comments that mention dangerous things must not trigger: require(123456), loadstring(x),
-- getfenv(), while true do end, wait(1), player.Name == "x"
local Clean = {}
local note = "never call require(123456) or loadstring() or SetAsync in this module"
local long = [[
while true do
	print("this is a string, not a loop")
end
]]
function Clean.describe(player: Player): string
	local label = if player.UserId > 0 then player.Name else "guest"
	return `{label} has {note:len()} {long:len()}`
end
function Clean.waitFor(signal)
	return signal:Wait()
end
return Clean
