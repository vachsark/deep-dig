-- PetDatabase.module.lua — Pet definitions, egg tiers, drop rate tables
-- Place in: ReplicatedStorage/PetDatabase (ModuleScript)
--
-- Pets give passive multipliers (dig_speed, loot_value, luck) that stack
-- multiplicatively on top of the base gameplay loop. Players hatch pets
-- from eggs at the egg pads (see PetSystem.server.lua).
--
-- Multipliers are read by GameManager when a pet is equipped — actual
-- application happens in BlockBrokenEvent (see PetSystem.server.lua TODO).

local PetDatabase = {}

-- ═══════════════════════════════════════════════════════════════════
-- Egg tier definitions: cost + drop rate table
-- ═══════════════════════════════════════════════════════════════════
--
-- Drop rates per egg tier (must sum to ~100). The roller picks a rarity
-- first, then uniformly samples a pet of that rarity from the egg's pool.

PetDatabase.EGGS = {
	Stone = {
		name = "Stone Egg",
		cost = 1000,
		color = Color3.fromRGB(140, 140, 140),
		dropRates = {
			Common   = 70,
			Uncommon = 25,
			Rare     = 5,
		},
	},
	Gem = {
		name = "Gem Egg",
		cost = 10000,
		color = Color3.fromRGB(80, 200, 255),
		dropRates = {
			Uncommon = 50,
			Rare     = 35,
			Epic     = 15,
		},
	},
	Void = {
		name = "Void Egg",
		cost = 100000,
		color = Color3.fromRGB(60, 20, 80),
		dropRates = {
			Rare      = 50,
			Epic      = 35,
			Legendary = 13,
			Mythic    = 2,
		},
	},
}

-- ═══════════════════════════════════════════════════════════════════
-- Pet roster — 12 pets total, distributed across egg pools
-- ═══════════════════════════════════════════════════════════════════
--
-- Each pet has an `egg` field declaring which egg can drop it. Multipliers
-- are 1.0 baseline; values >1 buff that stat. Color is the visual aura.

PetDatabase.PETS = {
	-- Stone Egg pool (Common / Uncommon / Rare)
	{
		name = "Pebble Pup",
		rarity = "Common",
		egg = "Stone",
		multipliers = { dig_speed = 1.05, loot_value = 1.00, luck = 1.00 },
		color = Color3.fromRGB(180, 180, 180),
	},
	{
		name = "Mossy Mole",
		rarity = "Common",
		egg = "Stone",
		multipliers = { dig_speed = 1.03, loot_value = 1.05, luck = 1.00 },
		color = Color3.fromRGB(120, 160, 100),
	},
	{
		name = "Quartz Quokka",
		rarity = "Uncommon",
		egg = "Stone",
		multipliers = { dig_speed = 1.10, loot_value = 1.05, luck = 1.02 },
		color = Color3.fromRGB(220, 220, 240),
	},
	{
		name = "Iron Ibex",
		rarity = "Rare",
		egg = "Stone",
		multipliers = { dig_speed = 1.15, loot_value = 1.10, luck = 1.05 },
		color = Color3.fromRGB(120, 130, 145),
	},

	-- Gem Egg pool (Uncommon / Rare / Epic)
	{
		name = "Sapphire Slime",
		rarity = "Uncommon",
		egg = "Gem",
		multipliers = { dig_speed = 1.08, loot_value = 1.10, luck = 1.03 },
		color = Color3.fromRGB(50, 100, 220),
	},
	{
		name = "Ruby Rabbit",
		rarity = "Rare",
		egg = "Gem",
		multipliers = { dig_speed = 1.12, loot_value = 1.15, luck = 1.05 },
		color = Color3.fromRGB(220, 50, 80),
	},
	{
		name = "Emerald Eagle",
		rarity = "Rare",
		egg = "Gem",
		multipliers = { dig_speed = 1.10, loot_value = 1.20, luck = 1.05 },
		color = Color3.fromRGB(40, 200, 100),
	},
	{
		name = "Diamond Drake",
		rarity = "Epic",
		egg = "Gem",
		multipliers = { dig_speed = 1.20, loot_value = 1.25, luck = 1.10 },
		color = Color3.fromRGB(200, 240, 255),
	},

	-- Void Egg pool (Rare / Epic / Legendary / Mythic)
	{
		name = "Shadow Stalker",
		rarity = "Rare",
		egg = "Void",
		multipliers = { dig_speed = 1.15, loot_value = 1.20, luck = 1.08 },
		color = Color3.fromRGB(60, 40, 80),
	},
	{
		name = "Nebula Newt",
		rarity = "Epic",
		egg = "Void",
		multipliers = { dig_speed = 1.20, loot_value = 1.30, luck = 1.12 },
		color = Color3.fromRGB(140, 60, 200),
	},
	{
		name = "Cosmic Chimera",
		rarity = "Legendary",
		egg = "Void",
		multipliers = { dig_speed = 1.35, loot_value = 1.50, luck = 1.20 },
		color = Color3.fromRGB(255, 170, 0),
	},
	{
		name = "Singularity Serpent",
		rarity = "Mythic",
		egg = "Void",
		multipliers = { dig_speed = 1.50, loot_value = 2.00, luck = 1.35 },
		color = Color3.fromRGB(255, 50, 50),
	},
}

-- ═══════════════════════════════════════════════════════════════════
-- Helpers
-- ═══════════════════════════════════════════════════════════════════

-- Build a name → pet lookup for O(1) access.
local petsByName = {}
for _, pet in ipairs(PetDatabase.PETS) do
	petsByName[pet.name] = pet
end

-- Build per-egg, per-rarity pet pools so the roller can sample within rarity.
local petsByEggAndRarity = {}
for _, pet in ipairs(PetDatabase.PETS) do
	local eggBucket = petsByEggAndRarity[pet.egg]
	if not eggBucket then
		eggBucket = {}
		petsByEggAndRarity[pet.egg] = eggBucket
	end
	local rarityBucket = eggBucket[pet.rarity]
	if not rarityBucket then
		rarityBucket = {}
		eggBucket[pet.rarity] = rarityBucket
	end
	table.insert(rarityBucket, pet)
end

-- Pick a rarity from the egg's drop-rate table, then uniformly pick a pet
-- from that rarity's pool within the egg. Returns the pet table (NOT a copy
-- of the player record) — caller is responsible for shaping the player record.
function PetDatabase.rollFromEgg(eggType)
	local egg = PetDatabase.EGGS[eggType]
	if not egg then return nil end

	-- Cumulative-weight roll across the egg's rarity table.
	local total = 0
	for _, weight in pairs(egg.dropRates) do
		total = total + weight
	end
	if total <= 0 then return nil end

	local roll = math.random() * total
	local chosenRarity
	local accum = 0
	for rarity, weight in pairs(egg.dropRates) do
		accum = accum + weight
		if roll <= accum then
			chosenRarity = rarity
			break
		end
	end
	if not chosenRarity then return nil end

	local pool = petsByEggAndRarity[eggType] and petsByEggAndRarity[eggType][chosenRarity]
	if not pool or #pool == 0 then
		-- Fallback: roster is incomplete for this rarity in this egg.
		-- Return any pet from this egg as a graceful degrade.
		local eggBucket = petsByEggAndRarity[eggType]
		if eggBucket then
			for _, rarityPool in pairs(eggBucket) do
				if #rarityPool > 0 then
					return rarityPool[math.random(#rarityPool)]
				end
			end
		end
		return nil
	end

	return pool[math.random(#pool)]
end

-- Look up a pet by its canonical name (case-sensitive).
function PetDatabase.getPet(name)
	return petsByName[name]
end

-- Number of distinct pets in the database (for diagnostics / logs).
function PetDatabase.count()
	return #PetDatabase.PETS
end

return PetDatabase
