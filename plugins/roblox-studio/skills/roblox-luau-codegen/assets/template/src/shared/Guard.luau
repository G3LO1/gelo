-- Validators for values that arrive from the client. Each builder returns a function
-- (value) -> boolean. Never trust a client value that has not passed one of these.

export type Check = (value: any) -> boolean

local Guard = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Guard.number(min: number?, max: number?): Check
	return function(value)
		return isFiniteNumber(value) and (min == nil or value >= min) and (max == nil or value <= max)
	end
end

function Guard.integer(min: number?, max: number?): Check
	local isNumber = Guard.number(min, max)
	return function(value)
		return isNumber(value) and math.floor(value) == value
	end
end

function Guard.string(maxLength: number?): Check
	local limit = maxLength or 200
	return function(value)
		return type(value) == "string" and #value <= limit and utf8.len(value) ~= nil
	end
end

function Guard.boolean(): Check
	return function(value)
		return type(value) == "boolean"
	end
end

-- Only one of the listed strings/numbers, e.g. Guard.oneOf({ "Sword", "Bow" }).
function Guard.oneOf(allowed: { any }): Check
	local set = {}
	for _, item in allowed do
		set[item] = true
	end
	return function(value)
		return (type(value) == "string" or type(value) == "number") and set[value] == true
	end
end

-- An Instance of the class, optionally required to be inside `ancestor` (e.g. workspace.Map).
function Guard.instance(className: string, ancestor: Instance?): Check
	return function(value)
		return typeof(value) == "Instance"
			and value:IsA(className)
			and (ancestor == nil or value:IsDescendantOf(ancestor))
	end
end

function Guard.vector3(maxMagnitude: number?): Check
	return function(value)
		return typeof(value) == "Vector3"
			and isFiniteNumber(value.X)
			and isFiniteNumber(value.Y)
			and isFiniteNumber(value.Z)
			and (maxMagnitude == nil or value.Magnitude <= maxMagnitude)
	end
end

-- A plain array (keys 1..n) of at most maxLength items that all pass `check`.
function Guard.array(check: Check, maxLength: number): Check
	return function(value)
		if type(value) ~= "table" then
			return false
		end
		local count = 0
		for key, item in value do
			count += 1
			if type(key) ~= "number" or key ~= count or count > maxLength or not check(item) then
				return false
			end
		end
		return true
	end
end

function Guard.optional(check: Check): Check
	return function(value)
		return value == nil or check(value)
	end
end

return Guard
