-- PetSystem.server.lua — Egg hatching, pet equipping, hatch pads
-- Place in: ServerScriptService/PetSystem (Script)
--
-- Phase 2 #8 from ROADMAP.md. Builds 3 egg hatch pads in workspace,
-- listens for HatchEgg / EquipPet / GetPetInventory remotes, mutates
-- player data via the shared _G.DeepDig_playerData table (NEVER edits
-- GameManager directly).
--
-- Out of scope (TODOs):
--   * Applying pet multipliers to BlockBrokenEvent — lives in GameManager.
--   * HUD UI for pet inventory + equip — lives in StarterGui (HudGui).
--   * Pet leveling / fragment-based feeding — Phase 2 #8 follow-up.
--   * Persistence of `pets` and `equippedPet` lives in GameManager's
--     DEFAULT_DATA merge; it auto-fills missing fields on reload, but new
--     players are initialized lazily here on first egg interaction.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local PetDatabase = require(ReplicatedStorage:WaitForChild("PetDatabase"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- ═══════════════════════════════════════════════════════════════════
-- Remote events
-- ═══════════════════════════════════════════════════════════════════

local HatchEggEvent = Instance.new("RemoteEvent")
HatchEggEvent.Name = "HatchEgg"
HatchEggEvent.Parent = Remotes

local EquipPetEvent = Instance.new("RemoteEvent")
EquipPetEvent.Name = "EquipPet"
EquipPetEvent.Parent = Remotes

local GetPetInventoryFunction = Remotes:FindFirstChild("GetPetInventory")
if not GetPetInventoryFunction then
	GetPetInventoryFunction = Instance.new("RemoteFunction")
	GetPetInventoryFunction.Name = "GetPetInventory"
	GetPetInventoryFunction.Parent = Remotes
end

local NotifyEvent = Remotes:WaitForChild("Notify")
local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD")

-- ═══════════════════════════════════════════════════════════════════
-- Player data access (shared cache from GameManager)
-- ═══════════════════════════════════════════════════════════════════

local function getData(player)
	local cache = _G.DeepDig_playerData
	if not cache then return nil end
	return cache[player.UserId]
end

-- New players won't have `pets` / `equippedPet` until DEFAULT_DATA is
-- updated in GameManager. Initialize lazily so we don't depend on edits
-- to GameManager landing first (multi-agent safe).
local function ensurePetFields(data)
	if not data then return end
	if data.pets == nil then
		data.pets = {}
	end
	if data.equippedPet == nil then
		data.equippedPet = false -- false = none equipped (nil-safe sentinel)
	end

	local equippedPet = data.equippedPet
	for _, record in ipairs(data.pets) do
		if type(record) == "table" then
			local oldId = record.id
			if type(record.id) ~= "string" or record.id == "" then
				record.id = HttpService:GenerateGUID(false)
				if equippedPet == oldId then
					equippedPet = record.id
				end
			end
		end
	end

	if type(equippedPet) == "string" then
		data.equippedPet = equippedPet
	else
		data.equippedPet = false
	end
end

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

local function rollFromEgg(eggType, player)
	local egg = PetDatabase.EGGS[eggType]
	if not egg then return nil end

	local eggDrops = egg.dropRates
	local weights = eggDrops

	local data = _G.DeepDig_playerData and player and _G.DeepDig_playerData[player.UserId]
	local hasLuckyEgg = data and data.ownedGamepasses and (
		data.ownedGamepasses[Config.GAMEPASS_LUCKY_EGG]
		or data.ownedGamepasses["Lucky Egg"]
		or data.ownedGamepasses[0]
	)

	if hasLuckyEgg then
		weights = {}
		for rarity, weight in pairs(eggDrops) do
			if rarity == "Legendary" or rarity == "Mythic" then
				weights[rarity] = weight * 2
			else
				weights[rarity] = weight
			end
		end
	end

	local total = 0
	for _, weight in pairs(weights) do
		total = total + weight
	end
	if total <= 0 then return nil end

	local roll = math.random() * total
	local chosenRarity
	local accum = 0
	for rarity, weight in pairs(weights) do
		accum = accum + weight
		if roll <= accum then
			chosenRarity = rarity
			break
		end
	end
	if not chosenRarity then return nil end

	local pool = petsByEggAndRarity[eggType] and petsByEggAndRarity[eggType][chosenRarity]
	if not pool or #pool == 0 then
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

GetPetInventoryFunction.OnServerInvoke = function(player)
	local data = getData(player)
	if not data then
		return { pets = {}, equippedPet = nil }
	end

	ensurePetFields(data)

	return {
		pets = data.pets or {},
		equippedPet = (data.equippedPet == false and nil) or data.equippedPet,
	}
end

-- ═══════════════════════════════════════════════════════════════════
-- Hatch egg pads in workspace
-- ═══════════════════════════════════════════════════════════════════

-- Forward-declared so buildPad's ProximityPrompt callback can call it; the
-- actual function body lives in the "Hatch handler" section below.
local rollAndAward
local awardHatch

local petPadsFolder = Instance.new("Folder")
petPadsFolder.Name = "PetEggPads"
petPadsFolder.Parent = workspace

-- Pads are placed in a row near the dig spawn area. Y=5 is roughly the
-- floor surface level shared with Museum/Trading pads.
local PAD_BASE_POSITION = Vector3.new(40, 5, -15)
local PAD_SPACING = 12
local PAD_SIZE = Vector3.new(8, 1, 8)

-- Visible order (left → right): Stone, Gem, Void.
local EGG_ORDER = { "Stone", "Gem", "Void" }

local function buildPad(eggType, index)
	local egg = PetDatabase.EGGS[eggType]
	if not egg then return end

	local pad = Instance.new("Part")
	pad.Name = eggType .. "EggPad"
	pad.Size = PAD_SIZE
	pad.Position = PAD_BASE_POSITION + Vector3.new((index - 1) * PAD_SPACING, 0, 0)
	pad.Anchored = true
	pad.Material = Enum.Material.Neon
	pad.Color = egg.color
	pad.Parent = petPadsFolder

	-- Surface label
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.Parent = pad

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = egg.name .. "\n" .. egg.cost .. " coins"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = gui

	-- Floating egg visual on top of the pad — purely decorative.
	local eggVisual = Instance.new("Part")
	eggVisual.Name = "EggVisual"
	eggVisual.Shape = Enum.PartType.Ball
	eggVisual.Size = Vector3.new(3, 3, 3)
	eggVisual.Position = pad.Position + Vector3.new(0, 3, 0)
	eggVisual.Anchored = true
	eggVisual.CanCollide = false
	eggVisual.Material = Enum.Material.Neon
	eggVisual.Color = egg.color
	eggVisual.Parent = pad

	-- ProximityPrompt — fires HatchEgg with eggType when activated.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Hatch"
	prompt.ObjectText = egg.name
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad

	prompt.Triggered:Connect(function(triggeringPlayer)
		-- ProximityPrompt.Triggered fires on the server with the activating
		-- player. Route through rollAndAward directly (no remote round-trip).
		if triggeringPlayer then
			rollAndAward(triggeringPlayer, eggType)
		end
	end)

	-- Server-side: ProximityPrompt fires on the server already, so route
	-- through a direct call rather than the RemoteEvent round-trip.
	-- (Listening on the same RemoteEvent below for client-driven calls.)
end

for index, eggType in ipairs(EGG_ORDER) do
	buildPad(eggType, index)
end

-- ═══════════════════════════════════════════════════════════════════
-- Hatch handler
-- ═══════════════════════════════════════════════════════════════════

function awardHatch(player, eggType, options)
	options = options or {}

	local egg = PetDatabase.EGGS[eggType]
	if not egg then
		NotifyEvent:FireClient(player, "Unknown egg type: " .. tostring(eggType), "Common")
		return false
	end

	local data = getData(player)
	if not data then
		NotifyEvent:FireClient(player, "Player data not loaded — try again.", "Common")
		return false
	end
	ensurePetFields(data)

	-- Cost gate
	local shouldChargeCoins = options.chargeCoins ~= false
	if shouldChargeCoins and (data.coins or 0) < egg.cost then
		NotifyEvent:FireClient(player,
			string.format("Need %d coins to hatch a %s (you have %d).",
				egg.cost, egg.name, math.floor(data.coins or 0)),
			"Common")
		return false
	end

	-- Deduct + roll
	if shouldChargeCoins then
		data.coins = data.coins - egg.cost
	end

	local pet = rollFromEgg(eggType, player)
	if not pet then
		-- Refund on roller failure (shouldn't happen but defensive).
		if shouldChargeCoins then
			data.coins = data.coins + egg.cost
		end
		NotifyEvent:FireClient(player, "Hatch failed — refunded.", "Common")
		return false
	end

	-- Append to player's pet list. Pet record is the player's instance —
	-- store enough to reconstruct without leaning on PetDatabase at read
	-- time (so renames in the db don't orphan saved records).
	local petRecord = {
		id = HttpService:GenerateGUID(false),
		name = pet.name,
		rarity = pet.rarity,
		egg = pet.egg,
		level = 1,
		acquiredAt = os.time(),
	}
	table.insert(data.pets, petRecord)

	-- Notify the player
	if options.notifyPlayer ~= false then
		local message = options.successMessage
			or ("You hatched a " .. pet.rarity .. " " .. pet.name .. "!")
		NotifyEvent:FireClient(player, message, pet.rarity)
	end

	-- Server-wide announcement on Legendary or Mythic hatches
	if pet.rarity == "Legendary" or pet.rarity == "Mythic" then
		NotifyEvent:FireAllClients(
			player.Name .. " hatched a " .. pet.rarity .. " " .. pet.name .. "!",
			pet.rarity)
	end

	-- Push updated coin count to HUD
	UpdateHUDEvent:FireClient(player, {
		coins = data.coins,
		petCount = #data.pets,
		equippedPet = data.equippedPet == false and nil or data.equippedPet,
	})

	return true, petRecord
end

function rollAndAward(player, eggType)
	return awardHatch(player, eggType, {
		chargeCoins = true,
	})
end

_G.DeepDig_grantFreeEggPet = function(player, eggType, successMessage)
	return awardHatch(player, eggType, {
		chargeCoins = false,
		successMessage = successMessage,
	})
end

HatchEggEvent.OnServerEvent:Connect(function(player, eggType)
	-- Type guard — clients can send anything.
	if type(eggType) ~= "string" then return end
	rollAndAward(player, eggType)
end)

-- ProximityPrompt.Triggered fires server-side, but for symmetry we also
-- accept client → server invocation (useful for HUD-driven hatch buttons
-- in a future pet shop UI). The handler is the same path.

-- ═══════════════════════════════════════════════════════════════════
-- Equip handler
-- ═══════════════════════════════════════════════════════════════════

EquipPetEvent.OnServerEvent:Connect(function(player, petId)
	local data = getData(player)
	if not data then return end
	ensurePetFields(data)

	-- Allow nil/false to clear equip
	if petId == nil or petId == false or petId == 0 then
		data.equippedPet = false
		UpdateHUDEvent:FireClient(player, {
			equippedPet = false,
			petCount = #data.pets,
			petMultipliers = { dig_speed = 1.0, loot_value = 1.0, luck = 1.0 },
		})
		NotifyEvent:FireClient(player, "Unequipped pet.", "Common")
		return
	end

	if type(petId) ~= "string" then return end

	-- Validate the pet is owned
	local owned
	for _, record in ipairs(data.pets) do
		if record.id == petId then
			owned = record
			break
		end
	end

	if not owned then
		NotifyEvent:FireClient(player, "You don't own that pet.", "Common")
		return
	end

	data.equippedPet = petId

	local petDef = PetDatabase.getPet(owned.name)
	local multipliers = petDef and petDef.multipliers
		or { dig_speed = 1.0, loot_value = 1.0, luck = 1.0 }

	-- TODO: GameManager's BlockBrokenEvent must read data.equippedPet and
	-- apply petDef.multipliers to dropChance (luck), tool dig speed, and
	-- sellValue (loot_value). Out of scope for this scaffold.

	UpdateHUDEvent:FireClient(player, {
		equippedPet = petId,
		petName = owned.name,
		petRarity = owned.rarity,
		petMultipliers = multipliers,
		petCount = #data.pets,
	})
	NotifyEvent:FireClient(player,
		"Equipped " .. owned.rarity .. " " .. owned.name .. ".",
		owned.rarity)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Init
-- ═══════════════════════════════════════════════════════════════════

-- Make sure existing online players (e.g. on hot-reload) get pet fields.
for _, player in ipairs(Players:GetPlayers()) do
	local data = getData(player)
	if data then
		ensurePetFields(data)
	end
end

print(string.format(
	"[PetSystem] Loaded %d pets across %d egg tiers; pads built at %s",
	PetDatabase.count(),
	#EGG_ORDER,
	tostring(PAD_BASE_POSITION)))
