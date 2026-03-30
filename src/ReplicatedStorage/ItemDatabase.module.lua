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
