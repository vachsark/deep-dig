-- EnemyDatabase.module.lua - Buried enemy definitions
-- Place in: ReplicatedStorage/EnemyDatabase (ModuleScript)

local EnemyDatabase = {}

local ENEMIES = {
	{
		id = "bone_crawler",
		name = "Bone Crawler",
		tier = "Stone",
		hp = 12,
		damage = 4,
		coinDrop = 35,
		fragmentDrop = 1,
		itemDropChance = 0.05,
		color = Color3.fromRGB(210, 205, 180),
		walkSpeed = 8,
		aggroRange = 16,
		spawnWeight = 100,
	},
	{
		id = "bronze_sentinel",
		name = "Bronze Sentinel",
		tier = "Bronze",
		hp = 24,
		damage = 6,
		coinDrop = 90,
		fragmentDrop = 2,
		itemDropChance = 0.08,
		color = Color3.fromRGB(170, 105, 45),
		walkSpeed = 9,
		aggroRange = 18,
		spawnWeight = 100,
	},
	{
		id = "rusted_construct",
		name = "Rusted Construct",
		tier = "Iron",
		hp = 42,
		damage = 8,
		coinDrop = 180,
		fragmentDrop = 4,
		itemDropChance = 0.1,
		color = Color3.fromRGB(120, 85, 65),
		walkSpeed = 7,
		aggroRange = 18,
		spawnWeight = 100,
	},
	{
		id = "iron_wraith",
		name = "Iron Wraith",
		tier = "Iron",
		hp = 36,
		damage = 10,
		coinDrop = 220,
		fragmentDrop = 5,
		itemDropChance = 0.12,
		color = Color3.fromRGB(85, 95, 110),
		walkSpeed = 12,
		aggroRange = 22,
		spawnWeight = 100,
	},
	{
		id = "voidling",
		name = "Voidling",
		tier = "Unknown",
		hp = 70,
		damage = 14,
		coinDrop = 650,
		fragmentDrop = 10,
		itemDropChance = 0.18,
		color = Color3.fromRGB(75, 35, 115),
		walkSpeed = 13,
		aggroRange = 24,
		spawnWeight = 100,
	},
	{
		id = "hollow_king",
		name = "Hollow King",
		tier = "Unknown",
		hp = 180,
		damage = 22,
		coinDrop = 2500,
		fragmentDrop = 35,
		itemDropChance = 0.35,
		color = Color3.fromRGB(30, 10, 45),
		walkSpeed = 6,
		aggroRange = 28,
		spawnWeight = 8,
		isMiniboss = true,
		spawnScale = 1.45,
	},
}

EnemyDatabase.ENEMIES = ENEMIES

local TIER_ALIASES = {
	Modern = "Stone",
	Industrial = "Bronze",
	Medieval = "Iron",
	Ancient = "Iron",
	Prehistoric = "Iron",
}

local function enemyTierFor(tierName)
	return TIER_ALIASES[tierName] or tierName
end

local function isBlocked(enemy, blockedEnemyIds)
	return blockedEnemyIds and blockedEnemyIds[enemy.id] == true
end

function EnemyDatabase.getEnemyForTier(tierName, options)
	local enemyTier = enemyTierFor(tierName)
	local candidates = {}
	local totalWeight = 0
	local blockedEnemyIds = options and options.blockedEnemyIds

	for _, enemy in ipairs(ENEMIES) do
		if enemy.tier == enemyTier and not isBlocked(enemy, blockedEnemyIds) then
			table.insert(candidates, enemy)
			totalWeight = totalWeight + (enemy.spawnWeight or 100)
		end
	end

	if #candidates == 0 then
		return nil
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

function EnemyDatabase.getEnemyById(id)
	for _, enemy in ipairs(ENEMIES) do
		if enemy.id == id then
			return enemy
		end
	end

	return nil
end

return EnemyDatabase
