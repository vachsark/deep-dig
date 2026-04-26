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

function EnemyDatabase.getEnemyForTier(tierName)
	local enemyTier = enemyTierFor(tierName)
	local candidates = {}

	for _, enemy in ipairs(ENEMIES) do
		if enemy.tier == enemyTier then
			table.insert(candidates, enemy)
		end
	end

	if #candidates == 0 then
		return nil
	end

	return candidates[math.random(#candidates)]
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
