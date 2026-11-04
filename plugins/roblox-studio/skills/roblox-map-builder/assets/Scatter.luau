--!nocheck
-- Seeded, constrained scatter for trees, rocks, bushes, props.
--
-- Pure function of (seed, options, sampler): the same inputs give the same placements on every
-- machine, so a map can be rebuilt from its Seed attribute. The sampler is injected so the
-- logic is testable without an engine; in Studio use Scatter.terrainSampler(workspace, ...).
--
--   local Scatter = require(path.to.Scatter)   -- or paste the file into execute_luau
--   local sample = Scatter.terrainSampler(workspace, { materials = { [Enum.Material.Grass] = true } })
--   local trees = Scatter.generate({
--       seed = seed + 1, minX = -100, maxX = 100, minZ = -100, maxZ = 100,
--       count = 75, spacing = 8, minNormalY = 0.8, sample = sample,
--       exclude = { { x = 0, z = 0, radius = 14 }, ... },       -- spawn, landmark, path samples
--       groves = { { x = 30, z = -20, radius = 25 }, ... },     -- optional: only inside a grove
--       existing = previousPlacements,                          -- keep spacing from earlier kinds
--   })
--   for _, p in trees do ... place a clone at Vector3.new(p.x, p.y - 0.5, p.z), yaw p.yaw, scale p.scale ... end
--
-- Options (all numbers in studs):
--   seed, minX, maxX, minZ, maxZ  area and the Random seed
--   count          how many to place (fewer if the area runs out of room; see result.rejected)
--   spacing        minimum distance between any two placements, including `existing`
--   minNormalY     slope limit: surface Normal.Y must be at least this (0.78-0.86 is gentle)
--   maxY / minY    optional height band
--   sample(x, z)   -> y, normalY  (or nil when there is no valid ground there)
--   exclude        list of { x, z, radius } circles to keep clear
--   groves         optional list of { x, z, radius }: when given, placements fall inside one
--   scaleMin/Max   random uniform scale (default 0.85-1.2)
--   tries          attempts per placement before giving up (default 30)
--   existing       placements from earlier calls (same shape), to space against
-- Returns a list of { x, y, z, normalY, yaw (radians), scale } and, as the second value, a
-- table of rejection counts { slope, band, noGround, excluded, spacing, grove }.
--
-- First pass is usually too sparse on a real map: call again with a bigger count and
-- `existing = firstPass` instead of loosening spacing.

local Scatter = {}

-- Park-Miller generator: integer maths below 2^53, identical on every platform.
function Scatter.newRandom(seed)
	local state = math.floor(math.abs(seed)) % 2147483646 + 1
	local function nextUnit()
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
	return nextUnit
end

local function cellKey(cx, cz)
	return cx * 73856093 + cz * 19349663
end

function Scatter.generate(options)
	local nextUnit = options.random or Scatter.newRandom(options.seed or 0)
	local spacing = options.spacing or 6
	local tries = options.tries or 30
	local scaleMin, scaleMax = options.scaleMin or 0.85, options.scaleMax or 1.2
	local rejected = { slope = 0, band = 0, noGround = 0, excluded = 0, spacing = 0, grove = 0 }
	local cell = math.max(spacing, 0.01)

	local grid = {}
	local function insert(placement)
		local key = cellKey(math.floor(placement.x / cell), math.floor(placement.z / cell))
		grid[key] = grid[key] or {}
		table.insert(grid[key], placement)
	end
	local function tooClose(x, z)
		local cx, cz = math.floor(x / cell), math.floor(z / cell)
		for dx = -1, 1 do
			for dz = -1, 1 do
				local bucket = grid[cellKey(cx + dx, cz + dz)]
				if bucket then
					for _, other in bucket do
						local ddx, ddz = other.x - x, other.z - z
						if ddx * ddx + ddz * ddz < spacing * spacing then
							return true
						end
					end
				end
			end
		end
		return false
	end

	for _, placement in options.existing or {} do
		insert(placement)
	end

	local function excluded(x, z)
		for _, zone in options.exclude or {} do
			local dx, dz = zone.x - x, zone.z - z
			if dx * dx + dz * dz < zone.radius * zone.radius then
				return true
			end
		end
		return false
	end
	local function inGrove(x, z)
		if not options.groves or #options.groves == 0 then
			return true
		end
		for _, grove in options.groves do
			local dx, dz = grove.x - x, grove.z - z
			if dx * dx + dz * dz <= grove.radius * grove.radius then
				return true
			end
		end
		return false
	end

	local results = {}
	local wanted = options.count or 0
	local width, depth = options.maxX - options.minX, options.maxZ - options.minZ
	for _ = 1, wanted do
		local placed = false
		for _ = 1, tries do
			local x = options.minX + nextUnit() * width
			local z = options.minZ + nextUnit() * depth
			-- Always consume the same random numbers per attempt so results stay stable
			-- when a constraint changes.
			local yaw = nextUnit() * math.pi * 2
			local scale = scaleMin + nextUnit() * (scaleMax - scaleMin)
			if not inGrove(x, z) then
				rejected.grove += 1
			elseif excluded(x, z) then
				rejected.excluded += 1
			elseif tooClose(x, z) then
				rejected.spacing += 1
			else
				local y, normalY = options.sample(x, z)
				if y == nil then
					rejected.noGround += 1
				elseif options.minNormalY and (normalY or 1) < options.minNormalY then
					rejected.slope += 1
				elseif (options.minY and y < options.minY) or (options.maxY and y > options.maxY) then
					rejected.band += 1
				else
					local placement = { x = x, y = y, z = z, normalY = normalY, yaw = yaw, scale = scale }
					insert(placement)
					table.insert(results, placement)
					placed = true
					break
				end
			end
		end
		if not placed and options.stopWhenFull then
			break
		end
	end
	return results, rejected
end

-- Studio sampler: raycast straight down onto Terrain (optionally only some materials).
function Scatter.terrainSampler(workspace, options)
	options = options or {}
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = options.include or { workspace.Terrain }
	local top, depth = options.top or 500, options.depth or 1000
	return function(x, z)
		local hit = workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -depth, 0), params)
		if not hit then
			return nil
		end
		if options.materials and not options.materials[hit.Material] then
			return nil
		end
		return hit.Position.Y, hit.Normal.Y
	end
end

return Scatter
