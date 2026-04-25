local module = {
	{
		id = "dig_25",
		description = "Dig 25 blocks",
		type = "blocks_dug",
		target = 25,
		rarityFilter = nil,
		reward = { coins = 250, fragments = 2 },
	},
	{
		id = "dig_100",
		description = "Dig 100 blocks",
		type = "blocks_dug",
		target = 100,
		rarityFilter = nil,
		reward = { coins = 950, fragments = 6 },
	},
	{
		id = "find_5_items",
		description = "Find 5 items",
		type = "items_found",
		target = 5,
		rarityFilter = nil,
		reward = { coins = 350, fragments = 3 },
	},
	{
		id = "find_15_items",
		description = "Find 15 items",
		type = "items_found",
		target = 15,
		rarityFilter = nil,
		reward = { coins = 900, fragments = 6 },
	},
	{
		id = "find_2_rare_items",
		description = "Find 2 Rare items",
		type = "rarity_found",
		target = 2,
		rarityFilter = "Rare",
		reward = { coins = 650, fragments = 6 },
	},
	{
		id = "find_1_epic_item",
		description = "Find 1 Epic item",
		type = "rarity_found",
		target = 1,
		rarityFilter = "Epic",
		reward = { coins = 1400, fragments = 10 },
	},
	{
		id = "earn_1500_coins",
		description = "Earn 1,500 coins",
		type = "coins_earned",
		target = 1500,
		rarityFilter = nil,
		reward = { coins = 500, fragments = 4 },
	},
	{
		id = "reach_depth_50",
		description = "Reach depth 50",
		type = "depth_reached",
		target = 50,
		rarityFilter = nil,
		reward = { coins = 1000, fragments = 8 },
	},
}

local function makeRng(seed)
	local state = math.floor(math.abs(tonumber(seed) or 0)) % 2147483647
	if state == 0 then
		state = 1
	end

	return function(maxValue)
		state = (state * 48271) % 2147483647
		if maxValue then
			return (state % maxValue) + 1
		end
		return state
	end
end

function module.dailyRoll(seed)
	local ids = {}
	for index, quest in ipairs(module) do
		ids[index] = quest.id
	end

	local rng = makeRng(seed)
	for index = #ids, 2, -1 do
		local swapIndex = rng(index)
		ids[index], ids[swapIndex] = ids[swapIndex], ids[index]
	end

	return { ids[1], ids[2], ids[3] }
end

return module
