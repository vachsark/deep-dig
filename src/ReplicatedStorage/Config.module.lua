-- Config.module.lua — Game constants
-- Place in: ReplicatedStorage/Config (ModuleScript)

local Config = {}

-- Dig grid
Config.BLOCK_SIZE = 4           -- Studs per block
Config.GRID_WIDTH = 40          -- Blocks wide (160 studs)
Config.GRID_DEPTH_BLOCKS = 200  -- Max depth in blocks (800 studs)
Config.DIG_SITE_CENTER = Vector3.new(0, 0, 0)

-- Depth tiers (in blocks, not studs)
Config.TIERS = {
	{ name = "Modern",       minDepth = 0,   maxDepth = 12,  color = Color3.fromRGB(139, 119, 101) },
	{ name = "Industrial",   minDepth = 13,  maxDepth = 37,  color = Color3.fromRGB(160, 140, 110) },
	{ name = "Medieval",     minDepth = 38,  maxDepth = 75,  color = Color3.fromRGB(130, 120, 100) },
	{ name = "Ancient",      minDepth = 76,  maxDepth = 125, color = Color3.fromRGB(110, 100, 85)  },
	{ name = "Prehistoric",  minDepth = 126, maxDepth = 187, color = Color3.fromRGB(90, 80, 70)    },
	{ name = "Unknown",      minDepth = 188, maxDepth = 200, color = Color3.fromRGB(40, 20, 50)    },
}

-- Tools
Config.TOOLS = {
	{ name = "Rusty Shovel",      power = 1, speed = 1.0, cost = 0,      tier = 1 },
	{ name = "Iron Pickaxe",      power = 2, speed = 0.8, cost = 500,    tier = 2 },
	{ name = "Steel Drill",       power = 3, speed = 0.6, cost = 2500,   tier = 3 },
	{ name = "Dynamite Kit",      power = 5, speed = 0.4, cost = 10000,  tier = 4 },
	{ name = "Laser Cutter",      power = 8, speed = 0.25,cost = 50000,  tier = 5 },
	{ name = "Quantum Excavator", power = 15,speed = 0.15,cost = 250000, tier = 6 },
}

-- Loot
Config.BASE_SELL_MULTIPLIER = 1
Config.LOOT_DROP_CHANCE = 0.35  -- 35% chance per block

-- Economy
Config.STARTING_COINS = 50

-- Events
Config.EVENT_CHANCE = 0.02  -- 2% per block broken
Config.EVENTS = {
	{ name = "Fossil Layer",   duration = 30, effect = "2x_rare",    message = "FOSSIL LAYER EXPOSED! 2x rare finds for 30 seconds!" },
	{ name = "Cave System",    duration = 45, effect = "bonus_loot",  message = "CAVE DISCOVERED! Bonus loot for 45 seconds!" },
	{ name = "Gold Vein",      duration = 20, effect = "gold_rush",   message = "GOLD VEIN! All finds worth 3x for 20 seconds!" },
	{ name = "Earthquake",     duration = 5,  effect = "instant_dig", message = "EARTHQUAKE! 5 layers crumble instantly!" },
}

return Config
