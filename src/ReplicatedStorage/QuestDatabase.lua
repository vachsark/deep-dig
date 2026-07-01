local module = {
	{
		id = "dig_25",
		description = "Dig 25 blocks",
		shortName = "Dig 25",
		type = "blocks_dug",
		target = 25,
		rarityFilter = nil,
		reward = { coins = 250, fragments = 2 },
		rewardText = "+250 coins, +2 fragments",
	},
	{
		id = "dig_100",
		description = "Dig 100 blocks",
		shortName = "Dig 100",
		type = "blocks_dug",
		target = 100,
		rarityFilter = nil,
		reward = { coins = 950, fragments = 6 },
		rewardText = "+950 coins, +6 fragments",
	},
	{
		id = "find_5_items",
		description = "Find 5 items",
		shortName = "Find 5",
		type = "items_found",
		target = 5,
		rarityFilter = nil,
		reward = { coins = 350, fragments = 3 },
		rewardText = "+350 coins, +3 fragments",
	},
	{
		id = "find_15_items",
		description = "Find 15 items",
		shortName = "Find 15",
		type = "items_found",
		target = 15,
		rarityFilter = nil,
		reward = { coins = 900, fragments = 6 },
		rewardText = "+900 coins, +6 fragments",
	},
	{
		id = "find_2_rare_items",
		description = "Find 2 Rare items",
		shortName = "Find 2 Rare",
		type = "rarity_found",
		target = 2,
		rarityFilter = "Rare",
		reward = { coins = 650, fragments = 6 },
		rewardText = "+650 coins, +6 fragments",
	},
	{
		id = "find_1_epic_item",
		description = "Find 1 Epic item",
		shortName = "Find 1 Epic",
		type = "rarity_found",
		target = 1,
		rarityFilter = "Epic",
		reward = { coins = 1400, fragments = 10 },
		rewardText = "+1,400 coins, +10 fragments",
	},
	{
		id = "earn_1500_coins",
		description = "Earn 1,500 coins",
		shortName = "Earn 1.5K",
		type = "coins_earned",
		target = 1500,
		rarityFilter = nil,
		reward = { coins = 500, fragments = 4 },
		rewardText = "+500 coins, +4 fragments",
	},
	{
		id = "chain_streak_10",
		description = "Reach a x10 dig chain",
		shortName = "x10 Chain",
		type = "chain_streak",
		target = 10,
		rarityFilter = nil,
		reward = { coins = 600, fragments = 5 },
		rewardText = "+600 coins, +5 fragments",
	},
	{
		id = "chain_streak_20",
		description = "Reach a x20 dig chain",
		shortName = "x20 Chain",
		type = "chain_streak",
		target = 20,
		rarityFilter = nil,
		reward = { coins = 1300, fragments = 9 },
		rewardText = "+1,300 coins, +9 fragments",
	},
	{
		id = "defeat_3_enemies",
		description = "Defeat 3 buried enemies",
		shortName = "Defeat 3 Enemies",
		type = "kill_enemies",
		target = 3,
		rarityFilter = nil,
		reward = { coins = 700, fragments = 5 },
		rewardText = "+700 coins, +5 fragments",
	},
	{
		id = "defeat_6_enemies",
		description = "Defeat 5 buried enemies",
		shortName = "Defeat 5 Enemies",
		type = "kill_enemies",
		target = 5,
		rarityFilter = nil,
		reward = { coins = 1100, fragments = 8 },
		rewardText = "+1,100 coins, +8 fragments",
	},
	{
		id = "reach_depth_50",
		description = "Reach depth 50",
		shortName = "Depth 50",
		type = "depth_reached",
		target = 50,
		rarityFilter = nil,
		reward = { coins = 1000, fragments = 8 },
		rewardText = "+1,000 coins, +8 fragments",
	},
}

module.weeklyQuest = {
	id = "weekly_daily_claims",
	description = "Complete 5 daily quest claims",
	shortName = "Claim 5 Dailies",
	type = "daily_claims",
	target = 5,
	reward = { coins = 2000, fragments = 12 },
	rewardText = "+2,000 coins, +12 fragments",
}

module.weeklyQuests = {
	module.weeklyQuest,
	{
		id = "weekly_hollow_king",
		description = "Defeat Hollow King this week",
		shortName = "Hollow King",
		type = "miniboss_kills",
		target = 1,
		enemyIdFilter = "hollow_king",
		reward = { coins = 5000, fragments = 40 },
		rewardText = "+5,000 coins, +40 fragments",
	},
	{
		id = "weekly_depth_100",
		description = "Reach depth 100 this week",
		shortName = "Depth 100",
		type = "depth_reached",
		target = 100,
		reward = { coins = 3200, fragments = 18 },
		rewardText = "+3,200 coins, +18 fragments",
	},
	{
		id = "weekly_enemy_hunter",
		description = "Defeat 20 buried enemies this week",
		shortName = "Defeat 20",
		type = "kill_enemies",
		target = 20,
		reward = { coins = 3500, fragments = 20 },
		rewardText = "+3,500 coins, +20 fragments",
	},
}

local function makeSeed(seed)
	if type(seed) == "number" then
		return math.floor(math.abs(seed))
	end

	if type(seed) == "string" then
		local value = 0
		for index = 1, #seed do
			value = (value * 31 + string.byte(seed, index)) % 2147483647
		end
		return value
	end

	return 0
end

local function makeRng(seed)
	local state = makeSeed(seed) % 2147483647
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

function module.weeklyRoll(seed)
	local pool = module.weeklyQuests
	if type(pool) ~= "table" or #pool == 0 then
		if type(module.weeklyQuest) == "table" then
			return module.weeklyQuest.id
		end
		return nil
	end

	local rng = makeRng(seed)
	local selectedQuest = pool[rng(#pool)]
	if type(selectedQuest) ~= "table" then
		return nil
	end

	return selectedQuest.id
end

return module
