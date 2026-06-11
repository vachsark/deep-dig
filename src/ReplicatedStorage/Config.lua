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
	{
		name = "Rusty Shovel",
		power = 1,
		speed = 0.7,
		cost = 0,
		tier = 1,
		damage = 1,
		visual = {
			handleColor = Color3.fromRGB(139, 90, 43),
			handleMaterial = Enum.Material.Wood,
			handleSize = Vector3.new(1, 1, 4),
		},
	},
	{
		name = "Iron Pickaxe",
		power = 2,
		speed = 0.5,
		cost = 250,
		tier = 2,
		damage = 5,
		visual = {
			handleColor = Color3.fromRGB(130, 130, 140),
			handleMaterial = Enum.Material.Metal,
			handleSize = Vector3.new(1.1, 1.1, 4.2),
		},
	},
	{
		name = "Steel Drill",
		power = 3,
		speed = 0.38,
		cost = 1500,
		tier = 3,
		damage = 9,
		visual = {
			handleColor = Color3.fromRGB(70, 105, 150),
			handleMaterial = Enum.Material.DiamondPlate,
			handleSize = Vector3.new(1.25, 1.25, 4.4),
		},
	},
	{
		name = "Dynamite Kit",
		power = 5,
		speed = 0.28,
		cost = 10000,
		tier = 4,
		damage = 14,
		visual = {
			handleColor = Color3.fromRGB(190, 55, 45),
			handleMaterial = Enum.Material.Granite,
			handleSize = Vector3.new(1.35, 1.35, 4.7),
		},
	},
	{
		name = "Laser Cutter",
		power = 8,
		speed = 0.2,
		cost = 50000,
		tier = 5,
		damage = 19,
		visual = {
			handleColor = Color3.fromRGB(35, 220, 255),
			handleMaterial = Enum.Material.Neon,
			handleSize = Vector3.new(1.45, 1.45, 5),
		},
	},
	{
		name = "Quantum Excavator",
		power = 15,
		speed = 0.15,
		cost = 250000,
		tier = 6,
		damage = 25,
		visual = {
			handleColor = Color3.fromRGB(170, 70, 255),
			handleMaterial = Enum.Material.ForceField,
			handleSize = Vector3.new(1.6, 1.6, 5.4),
		},
	},
}

-- Loot
Config.BASE_SELL_MULTIPLIER = 1
Config.LOOT_DROP_CHANCE = 0.5   -- 50% chance per block
Config.RARE_PITY_THRESHOLD = 8

-- Per-dig payout: every broken block pays a little directly (on top of
-- loot drops) so progress is felt block-by-block. Scales slowly with depth.
Config.DIG_COINS_BASE = 1
Config.DIG_COINS_DEPTH_DIVISOR = 20 -- +1 coin per 20 blocks of depth

-- Economy
Config.STARTING_COINS = 50
Config.DEFAULT_BACKPACK_CAPACITY = 50
Config.GROUP_BENEFIT_GROUP_ID = 0 -- 0 = use place group owner when CreatorType is Group
Config.GROUP_BENEFIT_COIN_MULTIPLIER = 1.10
Config.GROUP_BENEFIT_DISPLAY_LABEL = "Group Supporter"
Config.GROUP_BENEFIT_DISPLAY_COLOR = Color3.fromRGB(80, 220, 255)
Config.FRIEND_REFERRAL_REWARD_ENABLED = true
Config.FRIEND_REFERRAL_REWARD_COINS = 2000
Config.FRIEND_REFERRAL_REWARD_EGG = "Stone"
Config.GAMEPASS_FOREMAN_ID = 4
Config.GAMEPASS_FOREMAN = "foreman"
Config.GAMEPASS_LUCKY_EGG_ID = 9
Config.GAMEPASS_LUCKY_EGG = "lucky_egg"
Config.GAMEPASS_AUTO_COLLECTOR_ID = 5
Config.GAMEPASS_AUTO_COLLECTOR = "auto_collector"
Config.GAMEPASS_INFINITE_BACKPACK_ID = 6
Config.GAMEPASS_INFINITE_BACKPACK = "infinite_backpack"
Config.GAMEPASS_ARTIFACT_DETECTOR_ID = 7
Config.GAMEPASS_ARTIFACT_DETECTOR = "artifact_detector"
Config.GAMEPASS_REBIRTH_BOOST_ID = 8
Config.GAMEPASS_REBIRTH_BOOST = "rebirth_boost"
Config.UNAVAILABLE_GAMEPASS_IDS = {
	[1] = true,
	[2] = true,
	[3] = true,
	[4] = true,
	[5] = true,
	[6] = true,
	[7] = true,
	[8] = true,
	[9] = true,
}
Config.UNAVAILABLE_GAMEPASS_LABEL = "Coming Soon"
Config.STREAK_REVIVE_PRODUCT_ID = 1234567890 -- Placeholder; not launch-ready. Replace with a real Developer Product ID.
Config.STREAK_REVIVE_PLACEHOLDER_PRODUCT_ID = 1234567890
Config.STREAK_REVIVE_PRICE = 50
Config.OFFLINE_INCOME_COINS_PER_DAMAGE_PER_MINUTE = 6
Config.OFFLINE_INCOME_MIN_SECONDS = 5 * 60
Config.OFFLINE_INCOME_DEFAULT_CAP_SECONDS = 8 * 60 * 60
Config.OFFLINE_INCOME_FOREMAN_CAP_SECONDS = 24 * 60 * 60

function Config.isStreakReviveProductIdValid(productId)
	return type(productId) == "number"
		and productId ~= 0
		and productId ~= Config.STREAK_REVIVE_PLACEHOLDER_PRODUCT_ID
end

function Config.isGamepassIdAvailable(passId)
	return type(passId) == "number"
		and passId > 0
		and Config.UNAVAILABLE_GAMEPASS_IDS[passId] ~= true
end

-- Digging crews
Config.CREW_MAX_SIZE = 10
Config.CREW_INVITE_RANGE = 30
Config.CREW_COOP_RADIUS = 24
Config.CREW_FRAGMENT_BONUS = 1
Config.CREW_XP_PER_COOP_DIG = 1
Config.CREW_LEVEL_THRESHOLDS = { 25, 75, 150 }
Config.CREW_LEVEL_FRAGMENT_BONUSES = { 1, 2, 3, 4 }

-- Admin / testing
-- UserIds in this list (in addition to game.CreatorId) can run /coins, /tool,
-- /maxall etc. via chat. Read by AdminCommands.server.lua.
Config.ADMIN_USERIDS = {}

-- Events
Config.EVENT_CHANCE = 0.02  -- 2% per block broken
Config.SEASONAL_EXCLUSIVE_DROP_CHANCE = 0.025
Config.VOLCANO_VENT_OBSIDIAN_DROP_CHANCE = 0.12
Config.EVENTS = {
	{ name = "Fossil Layer",   duration = 30, effect = "2x_rare",    message = "FOSSIL LAYER EXPOSED! 2x rare finds for 30 seconds!" },
	{ name = "Cave System",    duration = 45, effect = "bonus_loot",  message = "CAVE DISCOVERED! Bonus loot for 45 seconds!" },
	{ name = "Gold Vein",      duration = 20, effect = "gold_rush",   message = "GOLD VEIN! All finds worth 3x for 20 seconds!" },
	{ name = "Lucky Hour",     duration = 120, effect = "lucky_hour", message = "🍀 LUCKY HOUR! Loot drops are extra generous for the next 2 minutes!" },
	{ name = "Echoes from Below", duration = 90, effect = "echo_blocks", message = "👻 Echoes ripple through the dig site... legendary finds twice as likely!" },
	{ name = "Earthquake",     duration = 30, effect = "earthquake",  message = "🌋 EARTHQUAKE! The ground trembles — extra coin drops for 30 seconds!" },
	{ name = "Earthquake",     duration = 5,  effect = "instant_dig", message = "EARTHQUAKE! 5 layers crumble instantly!" },
	{ name = "Volcano Vent",   duration = 35, effect = "volcano_vent", seasonId = "summer", message = "🌋 VOLCANO VENT! Lava cracks glow — obsidian tools surge for 35 seconds!" },
}

return Config
