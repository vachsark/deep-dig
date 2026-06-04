-- PetFeed.server.lua — duplicate-feed pet leveling
-- Place in: ServerScriptService/PetFeed (Script)
--
-- Players feed duplicate pets of the same species to a target pet,
-- consuming the sacrifice and scaling the target's multipliers.
-- Lazy-init data.pets per pet record (level/xp fields are added on
-- first feed if absent).
--
-- Wire-shape: FeedPet:FireServer(targetPetId, sacrificePetId)
-- Server is the authority on inventory; client-supplied ids are
-- looked up in data.pets and ignored if unresolved.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetDatabase = require(ReplicatedStorage:WaitForChild("PetDatabase"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local FeedPetEvent = Remotes:FindFirstChild("FeedPet")
if not FeedPetEvent then
	FeedPetEvent = Instance.new("RemoteEvent")
	FeedPetEvent.Name = "FeedPet"
	FeedPetEvent.Parent = Remotes
end

local PetFeedResultEvent = Remotes:FindFirstChild("PetFeedResult")
if not PetFeedResultEvent then
	PetFeedResultEvent = Instance.new("RemoteEvent")
	PetFeedResultEvent.Name = "PetFeedResult"
	PetFeedResultEvent.Parent = Remotes
end

local NotifyEvent = Remotes:WaitForChild("Notify")
local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD")

-- ═══════════════════════════════════════════════════════════════════
-- Tunables
-- ═══════════════════════════════════════════════════════════════════

local MAX_LEVEL = 20
local MULTIPLIER_PER_LEVEL = 0.05 -- +5% per level to existing multipliers
local MULTIPLIER_CAP = 5          -- defensive ceiling on individual multipliers

-- Quadratic-ish xp curve: cheap early levels, slow grind near cap.
-- Level 1→2 = 100xp, 2→3 = 150xp, 3→4 = 200xp, ... 19→20 = 1000xp.
local function xpForLevel(lvl)
	return 100 + (lvl - 1) * 50
end

-- xp gain table — same-species only for v1, but rarity factors matter
-- because future versions may allow cross-rarity feeding. For now the
-- server enforces target.name == sacrifice.name so rarities will always
-- match (same species → same rarity). The table is here so the rule is
-- documented and tweakable without rewriting the call site.
--
-- Indexed by sacrifice.rarity → flat xp granted.
local XP_BY_RARITY = {
	Common    = 100,
	Uncommon  = 125,
	Rare      = 175,
	Epic      = 250,
	Legendary = 400,
	Mythic    = 700,
}

local function xpGainFor(sacrifice)
	return XP_BY_RARITY[sacrifice.rarity] or 100
end

local function copyMultipliers(multipliers)
	local copy = {}
	if type(multipliers) ~= "table" then
		return copy
	end

	for key, value in pairs(multipliers) do
		if type(value) == "number" then
			copy[key] = value
		end
	end

	return copy
end

local function bumpMultipliersForLevel(multipliers, levels)
	if type(multipliers) ~= "table" then
		return
	end

	for _ = 1, levels do
		for key, value in pairs(multipliers) do
			if type(value) == "number" then
				multipliers[key] = math.min(value + MULTIPLIER_PER_LEVEL, MULTIPLIER_CAP)
			end
		end
	end
end

local function ensurePetMultipliers(record)
	if type(record.multipliers) == "table" then
		return
	end

	local petDef = PetDatabase.getPet(record.name)
	record.multipliers = copyMultipliers(petDef and petDef.multipliers)
	bumpMultipliersForLevel(record.multipliers, math.max((record.level or 1) - 1, 0))
end

-- ═══════════════════════════════════════════════════════════════════
-- Data access
-- ═══════════════════════════════════════════════════════════════════

local function getData(player)
	local cache = _G.DeepDig_playerData
	if not cache then return nil end
	return cache[player.UserId]
end

local function findPetIndex(pets, petId)
	for index, record in ipairs(pets) do
		if type(record) == "table" and record.id == petId then
			return index, record
		end
	end
	return nil, nil
end

-- ═══════════════════════════════════════════════════════════════════
-- Feed handler
-- ═══════════════════════════════════════════════════════════════════

FeedPetEvent.OnServerEvent:Connect(function(player, targetPetId, sacrificePetId)
	-- Type guards — clients can send anything.
	if type(targetPetId) ~= "string" or type(sacrificePetId) ~= "string" then
		return
	end

	-- Can't feed a pet to itself.
	if targetPetId == sacrificePetId then
		NotifyEvent:FireClient(player, "Can't feed a pet to itself.", "Common")
		return
	end

	local data = getData(player)
	if not data then
		-- Data not loaded yet — silent return, client can retry.
		return
	end

	if type(data.pets) ~= "table" or #data.pets == 0 then
		-- Empty inventory — no-op.
		return
	end

	local _, target = findPetIndex(data.pets, targetPetId)
	local sacrificeIndex, sacrifice = findPetIndex(data.pets, sacrificePetId)

	if not target or not sacrifice then
		-- One or both ids missing from inventory (race during equip,
		-- stale client cache, etc.). Server is the authority — silent
		-- reject so the client refreshes on next inventory pull.
		return
	end

	-- Same-species rule (v1). Cross-species feeding may be added later
	-- with reduced xp gain — see XP_BY_RARITY for the gain table hook.
	if target.name ~= sacrifice.name then
		NotifyEvent:FireClient(player,
			"Must feed same-species duplicates (got " ..
				tostring(sacrifice.name) .. " → " .. tostring(target.name) .. ").",
			"Common")
		return
	end

	-- Lazy-init level/xp on the target. Older pet records (hatched
	-- before PetFeed shipped) only have level=1 set by PetSystem.
	target.level = target.level or 1
	target.xp = target.xp or 0
	ensurePetMultipliers(target)
	local oldLevel = target.level

	-- Already capped — refuse the consume so players don't accidentally
	-- delete a duplicate they could trade or save for a fragment system.
	if target.level >= MAX_LEVEL then
		NotifyEvent:FireClient(player,
			tostring(target.name) .. " is at MAX level!",
			"Common")
		return
	end

	-- Apply xp + level-up loop.
	local xpGain = xpGainFor(sacrifice)
	target.xp = target.xp + xpGain

	while target.level < MAX_LEVEL and target.xp >= xpForLevel(target.level) do
		target.xp = target.xp - xpForLevel(target.level)
		target.level = target.level + 1

		-- Each level adds +5% to all existing multipliers (capped at 5x).
		bumpMultipliersForLevel(target.multipliers, 1)
	end

	-- Clamp leftover xp at the cap so the bar reads "MAX" cleanly.
	if target.level >= MAX_LEVEL then
		target.xp = 0
	end

	-- Consume the sacrifice.
	table.remove(data.pets, sacrificeIndex)

	-- If the sacrifice was the equipped pet, unequip it. Equipped state
	-- uses `false` as the nil-safe sentinel (see PetSystem.ensurePetFields).
	if data.equippedPet == sacrificePetId then
		data.equippedPet = false
	end

	if data.equippedPet == targetPetId then
		local refreshCompanion = _G.DeepDig_refreshEquippedPetCompanion
		if refreshCompanion then
			refreshCompanion(player)
		end

		UpdateHUDEvent:FireClient(player, {
			equippedPet = targetPetId,
			petName = target.name,
			petRarity = target.rarity,
			petLevel = tonumber(target.level) or 1,
			petMultipliers = target.multipliers,
			petCount = #data.pets,
		})
	elseif data.equippedPet == false then
		UpdateHUDEvent:FireClient(player, {
			equippedPet = false,
			petCount = #data.pets,
		})
	else
		UpdateHUDEvent:FireClient(player, {
			petCount = #data.pets,
		})
	end

	local targetName = tostring(target.name)
	PetFeedResultEvent:FireClient(player, {
		targetPetId = targetPetId,
		targetName = targetName,
		rarity = target.rarity or "Common",
		xpGain = xpGain,
		oldLevel = oldLevel,
		newLevel = target.level,
		leveledUp = target.level > oldLevel,
	})

	-- Notify the player.
	local sacName = tostring(sacrifice.name)
	NotifyEvent:FireClient(player,
		string.format("🍖 Fed %s to %s! Now level %d.",
			sacName, targetName, target.level),
		target.rarity or "Common")
end)

print("[DeepDig] PetFeed loaded — same-species duplicate consumption with quadratic xp curve")
