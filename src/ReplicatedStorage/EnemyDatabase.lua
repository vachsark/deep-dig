-- EnemyDatabase.module.lua - Buried enemy definitions
-- Place in: ReplicatedStorage/EnemyDatabase (ModuleScript)

local EnemyDatabase = {}

local ENEMIES = {
	{
		id = "bone_crawler",
		name = "Bone Crawler",
		tier = "Modern",
		hp = 14,
		damage = 3,
		coinDrop = 25,
		fragmentDrop = 1,
		itemDropChance = 0.04,
		color = Color3.fromRGB(210, 205, 180),
		model = "BasicNPC",
		walkSpeed = 8,
		aggroRange = 16,
		spawnWeight = 100,
		display = {
			unlockDepth = 11,
			unlockText = "Depth 11 - Modern Layer",
			hint = "Keep moving and finish it before more crawlers gather.",
		},
		visual = {
			bodySize = Vector3.new(3.8, 2.2, 2.8),
			material = Enum.Material.SmoothPlastic,
			accentColor = Color3.fromRGB(245, 240, 210),
			accentMaterial = Enum.Material.SmoothPlastic,
			featureTags = { "crawler_legs", "back_spines" },
		},
	},
	{
		id = "bronze_sentinel",
		name = "Bronze Sentinel",
		tier = "Industrial",
		hp = 24,
		damage = 5,
		coinDrop = 70,
		fragmentDrop = 2,
		itemDropChance = 0.06,
		color = Color3.fromRGB(170, 105, 45),
		model = "BasicNPC",
		walkSpeed = 9,
		aggroRange = 18,
		spawnWeight = 100,
		display = {
			unlockDepth = 13,
			unlockText = "Depth 13 - Industrial Layer",
			hint = "Its shieldy frame is slow to turn; strike, then back out.",
		},
		visual = {
			bodySize = Vector3.new(3.2, 4.8, 3.2),
			material = Enum.Material.Metal,
			accentColor = Color3.fromRGB(255, 185, 75),
			accentMaterial = Enum.Material.Metal,
			featureTags = { "sentinel_shield", "head_crest" },
		},
	},
	{
		id = "rusted_construct",
		name = "Rusted Construct",
		tier = "Medieval",
		hp = 36,
		damage = 7,
		coinDrop = 130,
		fragmentDrop = 3,
		itemDropChance = 0.08,
		color = Color3.fromRGB(120, 85, 65),
		model = "BasicNPC",
		walkSpeed = 7,
		aggroRange = 18,
		spawnWeight = 100,
		display = {
			unlockDepth = 38,
			unlockText = "Depth 38 - Medieval Layer",
			hint = "Heavy armor means bigger rewards, but longer fights.",
		},
		visual = {
			bodySize = Vector3.new(4, 3.6, 3.8),
			material = Enum.Material.CorrodedMetal,
			accentColor = Color3.fromRGB(210, 95, 45),
			accentMaterial = Enum.Material.CorrodedMetal,
			featureTags = { "construct_shoulders", "scrap_stack" },
		},
	},
	{
		id = "iron_wraith",
		name = "Iron Wraith",
		tier = "Ancient",
		hp = 48,
		damage = 9,
		coinDrop = 210,
		fragmentDrop = 5,
		itemDropChance = 0.1,
		color = Color3.fromRGB(85, 95, 110),
		model = "BasicNPC",
		walkSpeed = 12,
		aggroRange = 22,
		spawnWeight = 100,
		display = {
			unlockDepth = 76,
			unlockText = "Depth 76 - Ancient Layer",
			hint = "Fast and fragile; watch the aggro range before digging.",
		},
		visual = {
			bodySize = Vector3.new(2.4, 5.2, 2.4),
			material = Enum.Material.SmoothPlastic,
			transparency = 0.18,
			accentColor = Color3.fromRGB(170, 210, 255),
			accentMaterial = Enum.Material.Neon,
			featureTags = { "wraith_ribs", "wraith_mist" },
		},
	},
	{
		id = "voidling",
		name = "Voidling",
		tier = "Unknown",
		hp = 70,
		damage = 12,
		coinDrop = 450,
		fragmentDrop = 8,
		itemDropChance = 0.14,
		color = Color3.fromRGB(75, 35, 115),
		model = "BasicNPC",
		walkSpeed = 13,
		aggroRange = 24,
		spawnWeight = 100,
		display = {
			unlockDepth = 188,
			unlockText = "Depth 188 - Unknown Layer",
			hint = "High damage and speed make spacing more important than greed.",
		},
		visual = {
			bodySize = Vector3.new(2.6, 3.2, 2.6),
			material = Enum.Material.SmoothPlastic,
			transparency = 0.08,
			accentColor = Color3.fromRGB(170, 70, 255),
			accentMaterial = Enum.Material.Neon,
			featureTags = { "void_orbit", "void_light" },
		},
	},
	{
		id = "hollow_king",
		name = "Hollow King",
		tier = "Unknown",
		hp = 140,
		damage = 16,
		coinDrop = 1200,
		fragmentDrop = 20,
		itemDropChance = 0.25,
		color = Color3.fromRGB(30, 10, 45),
		model = "BasicNPC",
		walkSpeed = 6,
		aggroRange = 28,
		spawnWeight = 8,
		isMiniboss = true,
		spawnScale = 1.45,
		display = {
			unlockDepth = 188,
			unlockText = "Depth 188 - Unknown Layer",
			hint = "A rare miniboss; save room to retreat before trading hits.",
		},
		visual = {
			bodySize = Vector3.new(4.4, 6.2, 4.4),
			material = Enum.Material.Slate,
			accentColor = Color3.fromRGB(215, 55, 255),
			accentMaterial = Enum.Material.Neon,
			featureTags = { "king_crown", "king_shoulders", "king_aura" },
		},
	},
}

EnemyDatabase.ENEMIES = ENEMIES

local TIER_ALIASES = {
	Stone = "Modern",
	Bronze = "Industrial",
	Iron = "Medieval",
	["Iron+"] = "Ancient",
}

local TIER_ORDER = {
	Modern = 1,
	Industrial = 2,
	Medieval = 3,
	Ancient = 4,
	Prehistoric = 5,
	Unknown = 6,
}

local function enemyTierFor(tierName)
	return TIER_ALIASES[tierName] or tierName
end

local function isBlocked(enemy, blockedEnemyIds)
	return blockedEnemyIds and blockedEnemyIds[enemy.id] == true
end

local function weightedPick(candidates)
	local totalWeight = 0
	for _, enemy in ipairs(candidates) do
		totalWeight = totalWeight + (enemy.spawnWeight or 100)
	end

	if totalWeight <= 0 then
		return candidates[math.random(1, #candidates)]
	end

	local roll = math.random() * totalWeight
	local runningWeight = 0
	for _, enemy in ipairs(candidates) do
		runningWeight = runningWeight + (enemy.spawnWeight or 100)
		if roll <= runningWeight then
			return enemy
		end
	end

	return candidates[#candidates]
end

function EnemyDatabase.getAllEnemies()
	local enemies = {}
	for index, enemy in ipairs(ENEMIES) do
		enemies[index] = enemy
	end

	return enemies
end

function EnemyDatabase.getEnemiesInTier(tierName, options)
	local enemyTier = enemyTierFor(tierName)
	local candidates = {}
	local blockedEnemyIds = options and options.blockedEnemyIds

	for _, enemy in ipairs(ENEMIES) do
		if enemy.tier == enemyTier and not isBlocked(enemy, blockedEnemyIds) then
			table.insert(candidates, enemy)
		end
	end

	return candidates
end

function EnemyDatabase.getEnemiesAllowedForTier(tierName, options)
	local enemyTier = enemyTierFor(tierName)
	local tierRank = TIER_ORDER[enemyTier]
	local candidates = {}
	local blockedEnemyIds = options and options.blockedEnemyIds

	if not tierRank then
		return EnemyDatabase.getEnemiesInTier(tierName, options)
	end

	for _, enemy in ipairs(ENEMIES) do
		local enemyRank = TIER_ORDER[enemy.tier]
		if enemyRank and enemyRank <= tierRank and not isBlocked(enemy, blockedEnemyIds) then
			table.insert(candidates, enemy)
		end
	end

	return candidates
end

function EnemyDatabase.getEnemiesForTier(tierName, options)
	return EnemyDatabase.getEnemiesAllowedForTier(tierName, options)
end

function EnemyDatabase.getEnemyForTier(tierName, options)
	local candidates = EnemyDatabase.getEnemiesForTier(tierName, options)

	if #candidates == 0 then
		return nil
	end

	return weightedPick(candidates)
end

function EnemyDatabase.getEnemyAllowedForTier(tierName, options)
	local candidates = EnemyDatabase.getEnemiesAllowedForTier(tierName, options)

	if #candidates == 0 then
		return nil
	end

	return weightedPick(candidates)
end

function EnemyDatabase.getEnemyById(id)
	for _, enemy in ipairs(ENEMIES) do
		if enemy.id == id then
			return enemy
		end
	end

	return nil
end

return EnemyDatabase
