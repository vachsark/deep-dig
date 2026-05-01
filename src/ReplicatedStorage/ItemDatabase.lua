-- ItemDatabase.module.lua — All discoverable items
-- Place in: ReplicatedStorage/ItemDatabase (ModuleScript)

local ItemDatabase = {}

-- Rarity weights (higher = more common)
local RARITY = {
	Common    = { weight = 60, color = Color3.fromRGB(180, 180, 180), multiplier = 1 },
	Uncommon  = { weight = 25, color = Color3.fromRGB(30, 200, 30),   multiplier = 3 },
	Rare      = { weight = 10, color = Color3.fromRGB(30, 100, 255),  multiplier = 8 },
	Epic      = { weight = 4,  color = Color3.fromRGB(160, 50, 255),  multiplier = 20 },
	Legendary = { weight = 1,  color = Color3.fromRGB(255, 170, 0),   multiplier = 50 },
	Mythic    = { weight = 0.2,color = Color3.fromRGB(255, 50, 50),   multiplier = 200 },
}

ItemDatabase.RARITY = RARITY

-- Items organized by tier (depth layer)
ItemDatabase.ITEMS = {
	Modern = {
		{ name = "Old Coin",         rarity = "Common",    baseValue = 5  },
		{ name = "Bottle Cap",       rarity = "Common",    baseValue = 3  },
		{ name = "Rusty Key",        rarity = "Common",    baseValue = 8  },
		{ name = "Broken Phone",     rarity = "Uncommon",  baseValue = 15 },
		{ name = "Silver Ring",      rarity = "Uncommon",  baseValue = 25 },
		{ name = "Gold Watch",       rarity = "Rare",      baseValue = 50 },
		{ name = "Diamond Earring",  rarity = "Epic",      baseValue = 150 },
		{ name = "Buried Safe",      rarity = "Legendary", baseValue = 500 },
	},
	Industrial = {
		{ name = "Iron Gear",        rarity = "Common",    baseValue = 10 },
		{ name = "Copper Wire",      rarity = "Common",    baseValue = 8  },
		{ name = "Steam Valve",      rarity = "Common",    baseValue = 12 },
		{ name = "Brass Compass",    rarity = "Uncommon",  baseValue = 30 },
		{ name = "Pocket Watch",     rarity = "Uncommon",  baseValue = 40 },
		{ name = "Train Whistle",    rarity = "Rare",      baseValue = 80 },
		{ name = "Gold Nugget",      rarity = "Epic",      baseValue = 250 },
		{ name = "Steam Engine Core",rarity = "Legendary", baseValue = 800 },
	},
	Medieval = {
		{ name = "Arrowhead",        rarity = "Common",    baseValue = 15 },
		{ name = "Clay Pot",         rarity = "Common",    baseValue = 12 },
		{ name = "Iron Shield",      rarity = "Common",    baseValue = 20 },
		{ name = "Knight's Helm",    rarity = "Uncommon",  baseValue = 50 },
		{ name = "Royal Seal",       rarity = "Uncommon",  baseValue = 65 },
		{ name = "Enchanted Sword",  rarity = "Rare",      baseValue = 150 },
		{ name = "Crown Jewel",      rarity = "Epic",      baseValue = 500 },
		{ name = "Dragon Scale",     rarity = "Legendary", baseValue = 1500 },
	},
	Ancient = {
		{ name = "Clay Tablet",      rarity = "Common",    baseValue = 25 },
		{ name = "Bronze Coin",      rarity = "Common",    baseValue = 20 },
		{ name = "Stone Idol",       rarity = "Uncommon",  baseValue = 60 },
		{ name = "Gold Scarab",      rarity = "Uncommon",  baseValue = 80 },
		{ name = "Ancient Scroll",   rarity = "Rare",      baseValue = 200 },
		{ name = "Pharaoh's Mask",   rarity = "Epic",      baseValue = 800 },
		{ name = "Rosetta Fragment", rarity = "Legendary", baseValue = 2500 },
		{ name = "Ark Shard",        rarity = "Mythic",    baseValue = 10000 },
	},
	Prehistoric = {
		{ name = "Fossil Fragment",  rarity = "Common",    baseValue = 30 },
		{ name = "Petrified Wood",   rarity = "Common",    baseValue = 25 },
		{ name = "Ammonite",         rarity = "Uncommon",  baseValue = 70 },
		{ name = "Raptor Claw",      rarity = "Uncommon",  baseValue = 100 },
		{ name = "T-Rex Tooth",      rarity = "Rare",      baseValue = 300 },
		{ name = "Amber Specimen",   rarity = "Epic",      baseValue = 1200 },
		{ name = "Complete Skeleton",rarity = "Legendary", baseValue = 5000 },
		{ name = "Frozen Embryo",    rarity = "Mythic",    baseValue = 20000 },
	},
	Unknown = {
		{ name = "Strange Ore",      rarity = "Common",    baseValue = 50 },
		{ name = "Void Crystal",     rarity = "Uncommon",  baseValue = 150 },
		{ name = "Alien Circuit",    rarity = "Rare",      baseValue = 500 },
		{ name = "Plasma Core",      rarity = "Epic",      baseValue = 2000 },
		{ name = "Singularity Shard",rarity = "Legendary", baseValue = 8000 },
		{ name = "The Origin Stone", rarity = "Mythic",    baseValue = 50000 },
	},
}

ItemDatabase.SEASONAL_EXCLUSIVES = {
	{
		id = "halloween",
		season = "Halloween",
		theme = "The Bone Age",
		displayName = "Ghost Fossil",
		rarity = "Epic",
		baseValue = 600,
		tint = Color3.fromRGB(155, 255, 210),
	},
	{
		id = "winter",
		season = "Winter",
		theme = "The Ice Age",
		displayName = "Frozen Artifact",
		rarity = "Legendary",
		baseValue = 900,
		tint = Color3.fromRGB(120, 220, 255),
	},
	{
		id = "spring",
		season = "Spring",
		theme = "Fossil Rush",
		displayName = "Dino Egg",
		rarity = "Epic",
		baseValue = 650,
		tint = Color3.fromRGB(120, 255, 145),
	},
	{
		id = "summer",
		season = "Summer",
		theme = "Volcano Event",
		displayName = "Obsidian Relic",
		rarity = "Legendary",
		baseValue = 950,
		tint = Color3.fromRGB(255, 95, 45),
	},
}

ItemDatabase.SPRING_DINO_EGGS = {
	Modern = {
		displayName = "Modern Dino Egg",
		rarity = "Uncommon",
		baseValue = 35,
		tint = Color3.fromRGB(125, 230, 145),
	},
	Industrial = {
		displayName = "Industrial Dino Egg",
		rarity = "Rare",
		baseValue = 95,
		tint = Color3.fromRGB(95, 205, 135),
	},
	Medieval = {
		displayName = "Medieval Dino Egg",
		rarity = "Epic",
		baseValue = 260,
		tint = Color3.fromRGB(115, 190, 110),
	},
	Ancient = {
		displayName = "Ancient Dino Egg",
		rarity = "Legendary",
		baseValue = 850,
		tint = Color3.fromRGB(170, 210, 85),
	},
	Prehistoric = {
		displayName = "Prehistoric Dino Egg",
		rarity = "Legendary",
		baseValue = 1800,
		tint = Color3.fromRGB(230, 185, 70),
	},
	Unknown = {
		displayName = "Unknown Dino Egg",
		rarity = "Mythic",
		baseValue = 6500,
		tint = Color3.fromRGB(195, 110, 255),
	},
}

ItemDatabase.HALLOWEEN_GHOST_FOSSILS = {
	Modern = {
		displayName = "Modern Ghost Fossil",
		rarity = "Rare",
		baseValue = 90,
		tint = Color3.fromRGB(145, 245, 205),
	},
	Industrial = {
		displayName = "Industrial Ghost Fossil",
		rarity = "Rare",
		baseValue = 170,
		tint = Color3.fromRGB(125, 235, 220),
	},
	Medieval = {
		displayName = "Medieval Ghost Fossil",
		rarity = "Epic",
		baseValue = 420,
		tint = Color3.fromRGB(170, 225, 255),
	},
	Ancient = {
		displayName = "Ancient Ghost Fossil",
		rarity = "Legendary",
		baseValue = 1050,
		tint = Color3.fromRGB(195, 210, 255),
	},
	Prehistoric = {
		displayName = "Prehistoric Ghost Fossil",
		rarity = "Legendary",
		baseValue = 2350,
		tint = Color3.fromRGB(215, 190, 255),
	},
	Unknown = {
		displayName = "Unknown Ghost Fossil",
		rarity = "Mythic",
		baseValue = 7800,
		tint = Color3.fromRGB(255, 150, 235),
	},
}

ItemDatabase.SUMMER_OBSIDIAN_TOOLS = {
	Modern = {
		displayName = "Modern Obsidian Trowel",
		rarity = "Rare",
		baseValue = 80,
		tint = Color3.fromRGB(55, 45, 65),
	},
	Industrial = {
		displayName = "Industrial Obsidian Wrench",
		rarity = "Rare",
		baseValue = 150,
		tint = Color3.fromRGB(75, 60, 70),
	},
	Medieval = {
		displayName = "Medieval Obsidian Chisel",
		rarity = "Epic",
		baseValue = 360,
		tint = Color3.fromRGB(95, 50, 55),
	},
	Ancient = {
		displayName = "Ancient Obsidian Adze",
		rarity = "Legendary",
		baseValue = 950,
		tint = Color3.fromRGB(150, 55, 40),
	},
	Prehistoric = {
		displayName = "Prehistoric Obsidian Hand Axe",
		rarity = "Legendary",
		baseValue = 2100,
		tint = Color3.fromRGB(220, 75, 35),
	},
	Unknown = {
		displayName = "Unknown Obsidian Multitool",
		rarity = "Mythic",
		baseValue = 7200,
		tint = Color3.fromRGB(255, 90, 45),
	},
}

local SEASONAL_EXCLUSIVE_BY_ID = {}
for _, exclusive in ipairs(ItemDatabase.SEASONAL_EXCLUSIVES) do
	SEASONAL_EXCLUSIVE_BY_ID[exclusive.id] = exclusive
end

function ItemDatabase.getSeasonalExclusive(seasonId)
	return SEASONAL_EXCLUSIVE_BY_ID[seasonId]
end

function ItemDatabase.buildSeasonalItem(seasonId)
	local exclusive = ItemDatabase.getSeasonalExclusive(seasonId)
	if not exclusive then
		return nil
	end

	local rarity = exclusive.rarity or "Rare"
	local rarityData = RARITY[rarity] or RARITY.Rare
	local baseValue = exclusive.baseValue or 100

	return {
		name = exclusive.displayName,
		rarity = rarity,
		baseValue = baseValue,
		sellValue = baseValue * rarityData.multiplier,
		color = exclusive.tint or rarityData.color,
		seasonalExclusive = true,
		seasonId = exclusive.id,
	}
end

function ItemDatabase.buildSpringDinoEgg(tierName)
	local egg = ItemDatabase.SPRING_DINO_EGGS[tierName] or ItemDatabase.SPRING_DINO_EGGS.Unknown
	if not egg then
		return nil
	end

	local rarity = egg.rarity or "Epic"
	local rarityData = RARITY[rarity] or RARITY.Epic
	local baseValue = egg.baseValue or 100

	return {
		name = egg.displayName,
		rarity = rarity,
		baseValue = baseValue,
		sellValue = baseValue * rarityData.multiplier,
		color = egg.tint or rarityData.color,
		seasonalExclusive = true,
		seasonId = "spring",
		tierName = tierName or "Unknown",
	}
end

function ItemDatabase.buildHalloweenGhostFossil(tierName)
	local fossil = ItemDatabase.HALLOWEEN_GHOST_FOSSILS[tierName] or ItemDatabase.HALLOWEEN_GHOST_FOSSILS.Unknown
	if not fossil then
		return nil
	end

	local rarity = fossil.rarity or "Epic"
	local rarityData = RARITY[rarity] or RARITY.Epic
	local baseValue = fossil.baseValue or 100

	return {
		name = fossil.displayName,
		rarity = rarity,
		baseValue = baseValue,
		sellValue = baseValue * rarityData.multiplier,
		color = fossil.tint or rarityData.color,
		seasonalExclusive = true,
		seasonId = "halloween",
		tierName = tierName or "Unknown",
	}
end

function ItemDatabase.buildSummerObsidianTool(tierName)
	local tool = ItemDatabase.SUMMER_OBSIDIAN_TOOLS[tierName] or ItemDatabase.SUMMER_OBSIDIAN_TOOLS.Unknown
	if not tool then
		return nil
	end

	local rarity = tool.rarity or "Legendary"
	local rarityData = RARITY[rarity] or RARITY.Legendary
	local baseValue = tool.baseValue or 100

	return {
		name = tool.displayName,
		rarity = rarity,
		baseValue = baseValue,
		sellValue = baseValue * rarityData.multiplier,
		color = tool.tint or rarityData.color,
		seasonalExclusive = true,
		seasonId = "summer",
		tierName = tierName or "Unknown",
	}
end

-- Pick a random item from a tier based on rarity weights
function ItemDatabase.rollItem(tierName)
	local tierItems = ItemDatabase.ITEMS[tierName]
	if not tierItems then return nil end

	-- Build weighted pool
	local pool = {}
	local totalWeight = 0
	for _, item in ipairs(tierItems) do
		local rarityData = RARITY[item.rarity]
		if rarityData then
			totalWeight = totalWeight + rarityData.weight
			table.insert(pool, { item = item, cumWeight = totalWeight })
		end
	end

	-- Roll
	local roll = math.random() * totalWeight
	for _, entry in ipairs(pool) do
		if roll <= entry.cumWeight then
			local item = entry.item
			local rarityData = RARITY[item.rarity]
			return {
				name = item.name,
				rarity = item.rarity,
				baseValue = item.baseValue,
				sellValue = item.baseValue * rarityData.multiplier,
				color = rarityData.color,
			}
		end
	end

	return nil
end

-- Ordered rarity tiers, from least to most rare.
-- Used to enforce a max rarity ceiling (e.g. FTUE first-find guard).
local RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
local RARITY_RANK = {}
for i, r in ipairs(RARITY_ORDER) do RARITY_RANK[r] = i end

-- Like rollItem(), but caps the result at maxRarity.
-- Any item rolled above maxRarity is re-weighted to zero so it can't be selected.
-- This lets the FTUE guarantee Common/Uncommon for the first find while still
-- using the normal weighted distribution within the allowed rarities.
function ItemDatabase.rollItemWithMaxRarity(tierName, maxRarity)
	local tierItems = ItemDatabase.ITEMS[tierName]
	if not tierItems then return nil end

	local maxRank = RARITY_RANK[maxRarity] or #RARITY_ORDER

	-- Build weighted pool, excluding any item above maxRarity
	local pool = {}
	local totalWeight = 0
	for _, item in ipairs(tierItems) do
		local rarityData = RARITY[item.rarity]
		local rank = RARITY_RANK[item.rarity] or 999
		if rarityData and rank <= maxRank then
			totalWeight = totalWeight + rarityData.weight
			table.insert(pool, { item = item, cumWeight = totalWeight })
		end
	end

	if totalWeight == 0 then
		-- Fallback: no items within the cap (shouldn't happen for Common/Uncommon)
		return ItemDatabase.rollItem(tierName)
	end

	-- Roll
	local roll = math.random() * totalWeight
	for _, entry in ipairs(pool) do
		if roll <= entry.cumWeight then
			local item = entry.item
			local rarityData = RARITY[item.rarity]
			return {
				name = item.name,
				rarity = item.rarity,
				baseValue = item.baseValue,
				sellValue = item.baseValue * rarityData.multiplier,
				color = rarityData.color,
			}
		end
	end

	return nil
end

-- Pick a random item from a tier at one exact rarity.
function ItemDatabase.rollItemOfRarity(tierName, targetRarity)
	local tierItems = ItemDatabase.ITEMS[tierName]
	local rarityData = RARITY[targetRarity]
	if not tierItems or not rarityData then return nil end

	local candidates = {}
	for _, item in ipairs(tierItems) do
		if item.rarity == targetRarity then
			table.insert(candidates, item)
		end
	end

	if #candidates == 0 then return nil end

	local chosen = candidates[math.random(#candidates)]
	return {
		name = chosen.name,
		rarity = chosen.rarity,
		baseValue = chosen.baseValue,
		sellValue = chosen.baseValue * rarityData.multiplier,
		color = rarityData.color,
	}
end

-- Get tier name for a given depth (in blocks)
function ItemDatabase.getTierForDepth(depth)
	local Config = require(script.Parent.Config)
	for _, tier in ipairs(Config.TIERS) do
		if depth >= tier.minDepth and depth <= tier.maxDepth then
			return tier.name
		end
	end
	return "Unknown"
end

return ItemDatabase
