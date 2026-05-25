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

local ServerEvents = ReplicatedStorage:WaitForChild("ServerEvents")
local PlayerDataReady = ServerEvents:WaitForChild("PlayerDataReady")

-- ═══════════════════════════════════════════════════════════════════
-- Player data access (shared cache from GameManager)
-- ═══════════════════════════════════════════════════════════════════

local function getData(player)
	local cache = _G.DeepDig_playerData
	if not cache then return nil end
	return cache[player.UserId]
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

-- ═══════════════════════════════════════════════════════════════════
-- Equipped pet companion visuals
-- ═══════════════════════════════════════════════════════════════════

local petCompanionsFolder = workspace:FindFirstChild("PetCompanions")
if not petCompanionsFolder then
	petCompanionsFolder = Instance.new("Folder")
	petCompanionsFolder.Name = "PetCompanions"
	petCompanionsFolder.Parent = workspace
end

local companionByUserId = {}

local RARITY_AURA_COLORS = {
	Common = Color3.fromRGB(180, 180, 180),
	Uncommon = Color3.fromRGB(30, 200, 30),
	Rare = Color3.fromRGB(30, 100, 255),
	Epic = Color3.fromRGB(160, 50, 255),
	Legendary = Color3.fromRGB(255, 170, 0),
	Mythic = Color3.fromRGB(255, 50, 50),
}

local RARITY_AURA_INTENSITY = {
	Common = 0.7,
	Uncommon = 0.9,
	Rare = 1.1,
	Epic = 1.35,
	Legendary = 1.65,
	Mythic = 1.9,
}

local function getCompanionName(player)
	return "PetCompanion_" .. tostring(player.UserId)
end

local function removeCompanion(player)
	local userId = player.UserId
	local companion = companionByUserId[userId]
	if companion then
		companion:Destroy()
		companionByUserId[userId] = nil
	end

	local oldCompanion = petCompanionsFolder:FindFirstChild(getCompanionName(player))
	if oldCompanion then
		oldCompanion:Destroy()
	end
end

local function getOwnedPetById(data, petId)
	if type(data.pets) ~= "table" or type(petId) ~= "string" then
		return nil
	end

	for _, record in ipairs(data.pets) do
		if type(record) == "table" and record.id == petId then
			return record
		end
	end

	return nil
end

local function clamp(value, minValue, maxValue)
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function getCompanionAuraProfile(owned, petDef)
	local rarity = tostring(owned.rarity or petDef.rarity or "Common")
	local level = tonumber(owned.level) or 1
	local rarityIntensity = RARITY_AURA_INTENSITY[rarity] or RARITY_AURA_INTENSITY.Common
	local levelBonus = clamp((level - 1) * 0.035, 0, 0.55)
	local intensity = rarityIntensity + levelBonus
	local petColor = petDef.color
	local rarityColor = RARITY_AURA_COLORS[rarity] or petColor

	return {
		color = petColor:Lerp(rarityColor, 0.4),
		brightness = clamp(0.35 + intensity * 0.35, 0.5, 1.35),
		range = clamp(4.5 + intensity * 1.7, 5, 8.5),
		particleRate = math.floor(clamp(2 + intensity * 2.1, 3, 7)),
		particleSize = clamp(0.12 + intensity * 0.035, 0.14, 0.22),
	}
end

local function buildCompanion(player, root, owned, petDef)
	local companion = Instance.new("Part")
	companion.Name = getCompanionName(player)
	companion.Shape = Enum.PartType.Ball
	companion.Size = Vector3.new(1.8, 1.8, 1.8)
	companion.CFrame = root.CFrame * CFrame.new(2.5, 1.1, 1.5)
	companion.Anchored = false
	companion.CanCollide = false
	companion.CanTouch = false
	companion.CanQuery = false
	companion.Massless = true
	companion.Material = Enum.Material.Neon
	companion.Color = petDef.color
	companion.Parent = petCompanionsFolder

	local auraProfile = getCompanionAuraProfile(owned, petDef)

	local glow = Instance.new("PointLight")
	glow.Name = "PetCompanionGlow"
	glow.Color = auraProfile.color
	glow.Brightness = auraProfile.brightness
	glow.Range = auraProfile.range
	glow.Shadows = false
	glow.Parent = companion

	local aura = Instance.new("ParticleEmitter")
	aura.Name = "PetCompanionAura"
	aura.Color = ColorSequence.new(auraProfile.color)
	aura.LightEmission = 0.55
	aura.LightInfluence = 0.25
	aura.Rate = auraProfile.particleRate
	aura.Lifetime = NumberRange.new(0.8, 1.2)
	aura.Speed = NumberRange.new(0.15, 0.55)
	aura.SpreadAngle = Vector2.new(360, 360)
	aura.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, auraProfile.particleSize),
		NumberSequenceKeypoint.new(0.65, auraProfile.particleSize * 0.75),
		NumberSequenceKeypoint.new(1, 0),
	})
	aura.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.7, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	aura.Rotation = NumberRange.new(0, 360)
	aura.RotSpeed = NumberRange.new(-25, 25)
	aura.Drag = 1
	aura.LockedToPart = true
	aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	aura.Parent = companion

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = companion
	weld.Parent = companion

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PetNameplate"
	billboard.Size = UDim2.fromOffset(120, 42)
	billboard.StudsOffset = Vector3.new(0, 1.6, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = companion

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = tostring(owned.rarity or petDef.rarity) .. "\n" .. tostring(owned.name)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	companionByUserId[player.UserId] = companion
end

local function updateCompanion(player)
	removeCompanion(player)

	local data = getData(player)
	if not data then return end
	ensurePetFields(data)

	local owned = getOwnedPetById(data, data.equippedPet)
	if not owned then return end

	local petDef = PetDatabase.getPet(owned.name)
	if not petDef or not petDef.color then return end

	local character = player.Character
	if not character then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	buildCompanion(player, root, owned, petDef)
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
		data.ownedGamepasses[Config.GAMEPASS_LUCKY_EGG_ID] == true
		or data.ownedGamepasses[Config.GAMEPASS_LUCKY_EGG] == true
		or data.ownedGamepasses["Lucky Egg"] == true
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
		multipliers = copyMultipliers(pet.multipliers),
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
		removeCompanion(player)
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
	updateCompanion(player)

	local petDef = PetDatabase.getPet(owned.name)
	local multipliers = type(owned.multipliers) == "table" and owned.multipliers
		or petDef and petDef.multipliers
		or { dig_speed = 1.0, loot_value = 1.0, luck = 1.0 }

	-- Equipped pet payload mirrors the server-side record so fed pets show
	-- their leveled multipliers instead of the base database values.

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

local function onCharacterAdded(player, character)
	removeCompanion(player)

	task.spawn(function()
		character:WaitForChild("HumanoidRootPart", 10)
		if player.Parent and player.Character == character then
			updateCompanion(player)
		end
	end)
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

PlayerDataReady.Event:Connect(function(player)
	updateCompanion(player)
end)

Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	removeCompanion(player)
end)

-- Make sure existing online players (e.g. on hot-reload) get pet fields.
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)

	local data = getData(player)
	if data then
		ensurePetFields(data)
	end

	updateCompanion(player)
end

print(string.format(
	"[PetSystem] Loaded %d pets across %d egg tiers; pads built at %s",
	PetDatabase.count(),
	#EGG_ORDER,
	tostring(PAD_BASE_POSITION)))
