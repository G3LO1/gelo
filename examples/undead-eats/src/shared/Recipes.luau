-- Ingredients, dishes, stations and recipes. All numbers are tuning placeholders.
-- Plan: SYS-01, SYS-04
--
-- Recipes.Items[id]   -> { Name, Kind = "Ingredient" | "Dish", Color }
-- Recipes.Dishes[id]  -> { Name, Station, Inputs, CookTime, BurnTime, Price, Color }
-- Recipes.Stations[id]-> { Name }
-- Recipes.IngredientIds / DishIds / StationIds -> sorted arrays for Guard.oneOf
-- Recipes.findDish(stationType, inputs) -> dishId? (exact match)
-- Recipes.canAccept(stationType, inputs, ingredient) -> boolean (can still become a recipe)
--
-- Rule: at one station no recipe's Inputs may be a subset of another's, because a station
-- starts cooking as soon as its inputs match a recipe exactly.

local Recipes = {}

Recipes.Stations = {
	Grill = { Name = "Grill" },
	Fryer = { Name = "Fryer" },
	Oven = { Name = "Oven" },
}

local ingredients = {
	Bun = { Name = "Bun", Color = Color3.fromRGB(222, 184, 120) },
	Patty = { Name = "Patty", Color = Color3.fromRGB(140, 80, 60) },
	Sausage = { Name = "Sausage", Color = Color3.fromRGB(200, 90, 80) },
	Potato = { Name = "Potato", Color = Color3.fromRGB(190, 160, 90) },
	Dough = { Name = "Dough", Color = Color3.fromRGB(240, 230, 200) },
	Cheese = { Name = "Cheese", Color = Color3.fromRGB(250, 205, 60) },
}

Recipes.Dishes = {
	Burger = {
		Name = "Burger",
		Station = "Grill",
		Inputs = { "Bun", "Patty" },
		CookTime = 8,
		BurnTime = 10,
		Price = 12,
		Color = Color3.fromRGB(205, 120, 60),
	},
	HotDog = {
		Name = "Hot Dog",
		Station = "Grill",
		Inputs = { "Bun", "Sausage" },
		CookTime = 7,
		BurnTime = 10,
		Price = 10,
		Color = Color3.fromRGB(225, 110, 80),
	},
	Fries = {
		Name = "Fries",
		Station = "Fryer",
		Inputs = { "Potato" },
		CookTime = 6,
		BurnTime = 8,
		Price = 6,
		Color = Color3.fromRGB(250, 215, 90),
	},
	Pizza = {
		Name = "Pizza",
		Station = "Oven",
		Inputs = { "Dough", "Cheese" },
		CookTime = 12,
		BurnTime = 12,
		Price = 18,
		Color = Color3.fromRGB(230, 120, 70),
	},
}

Recipes.Items = {}
Recipes.IngredientIds = {}
Recipes.DishIds = {}
Recipes.StationIds = {}

for id, item in ingredients do
	Recipes.Items[id] = { Name = item.Name, Kind = "Ingredient", Color = item.Color }
	table.insert(Recipes.IngredientIds, id)
end
for id, dish in Recipes.Dishes do
	Recipes.Items[id] = { Name = dish.Name, Kind = "Dish", Color = dish.Color }
	table.insert(Recipes.DishIds, id)
end
for id in Recipes.Stations do
	table.insert(Recipes.StationIds, id)
end
table.sort(Recipes.IngredientIds)
table.sort(Recipes.DishIds)
table.sort(Recipes.StationIds)

local function count(list: { string }): { [string]: number }
	local counts = {}
	for _, id in list do
		counts[id] = (counts[id] or 0) + 1
	end
	return counts
end

-- true if every ingredient in `have` appears in `need` at least as often as in `have`.
local function isSubset(have: { [string]: number }, need: { [string]: number }): boolean
	for id, amount in have do
		if (need[id] or 0) < amount then
			return false
		end
	end
	return true
end

function Recipes.findDish(stationType: string, inputs: { string }): string?
	local have = count(inputs)
	for id, dish in Recipes.Dishes do
		if dish.Station == stationType and #dish.Inputs == #inputs and isSubset(have, count(dish.Inputs)) then
			return id
		end
	end
	return nil
end

function Recipes.canAccept(stationType: string, inputs: { string }, ingredient: string): boolean
	local combined = table.clone(inputs)
	table.insert(combined, ingredient)
	local have = count(combined)
	for _, dish in Recipes.Dishes do
		if dish.Station == stationType and isSubset(have, count(dish.Inputs)) then
			return true
		end
	end
	return false
end

-- Catch data mistakes at require time instead of in the middle of a run.
for id, dish in Recipes.Dishes do
	assert(Recipes.Stations[dish.Station], `Dish {id} uses unknown station {dish.Station}`)
	for _, input in dish.Inputs do
		assert(ingredients[input], `Dish {id} uses unknown ingredient {input}`)
	end
	for otherId, other in Recipes.Dishes do
		if otherId ~= id and other.Station == dish.Station then
			assert(not isSubset(count(dish.Inputs), count(other.Inputs)), `{id} is a subset of {otherId}`)
		end
	end
end

return Recipes
