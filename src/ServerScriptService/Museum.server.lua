-- Museum.server.lua — Personal museum display + collection tracking
-- Place in: ServerScriptService/Museum (Script)
--
-- Each player gets a personal museum instance. Displayed items are
-- removed from inventory and placed on pedestals. Other players can
-- visit and see your collection. Completing a full set (all items
-- in a tier) unlocks a bonus multiplier.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local ItemDatabase = require(ReplicatedStorage:WaitForChild("ItemDatabase"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ServerEvents = ReplicatedStorage:WaitForChild("ServerEvents")
local PlayerDataReady = ServerEvents:WaitForChild("PlayerDataReady")
local ItemFoundBindable = ServerEvents:WaitForChild("ItemFoundBindable")

-- Create museum remotes
local DisplayItemEvent = Instance.new("RemoteEvent")
DisplayItemEvent.Name = "DisplayItem"
DisplayItemEvent.Parent = Remotes

local GetMuseumDataFunc = Instance.new("RemoteFunction")
GetMuseumDataFunc.Name = "GetMuseumData"
GetMuseumDataFunc.Parent = Remotes

local MuseumUpdateEvent = Instance.new("RemoteEvent")
MuseumUpdateEvent.Name = "MuseumUpdate"
MuseumUpdateEvent.Parent = Remotes

-- ═══════════════════════════════════════════════════════════════════
-- Museum Instances (one per player)
-- ═══════════════════════════════════════════════════════════════════

local museumsFolder = Instance.new("Folder")
museumsFolder.Name = "Museums"
museumsFolder.Parent = workspace

local MUSEUM_SPACING = 300 -- studs between museums
local PEDESTAL_SIZE = Vector3.new(3, 4, 3)
local DISPLAY_ITEM_SIZE = Vector3.new(2, 2, 2)
local PEDESTALS_PER_ROW = 8
local PEDESTAL_SPACING = 6

local RARITY_COLORS = {
	Common    = Color3.fromRGB(180, 180, 180),
	Uncommon  = Color3.fromRGB(30, 200, 30),
	Rare      = Color3.fromRGB(30, 100, 255),
	Epic      = Color3.fromRGB(160, 50, 255),
	Legendary = Color3.fromRGB(255, 170, 0),
	Mythic    = Color3.fromRGB(255, 50, 50),
}

-- Collection completion bonuses
local TIER_COMPLETION_BONUS = {
	Modern      = 1.1,  -- 10% sell bonus
	Industrial  = 1.15,
	Medieval    = 1.2,
	Ancient     = 1.3,
	Prehistoric = 1.4,
	Unknown     = 2.0,  -- 2x for completing the hardest tier
}

local playerMuseums = {} -- userId -> { folder, pedestals, displayedItems, position }
local museumIndex = 0

local function countDisplayed(museum)
	local n = 0
	for _ in pairs(museum.displayedItems or {}) do n = n + 1 end
	return n
end

local function getSeasonalExclusiveColor(exclusive)
	local rarityData = ItemDatabase.RARITY[exclusive.rarity]
	return exclusive.tint or (rarityData and rarityData.color) or RARITY_COLORS[exclusive.rarity] or RARITY_COLORS.Common
end

local function getPlayerData(player)
	local cache = _G.DeepDig_playerData
	return cache and cache[player.UserId] or nil
end

local function isSpringDinoEggVariant(itemName)
	for _, egg in pairs(ItemDatabase.SPRING_DINO_EGGS or {}) do
		if egg.displayName == itemName then
			return true
		end
	end

	return false
end

local function isHalloweenGhostFossilVariant(itemName)
	for _, fossil in pairs(ItemDatabase.HALLOWEEN_GHOST_FOSSILS or {}) do
		if fossil.displayName == itemName then
			return true
		end
	end

	return false
end

local function isSummerObsidianToolVariant(itemName)
	for _, tool in pairs(ItemDatabase.SUMMER_OBSIDIAN_TOOLS or {}) do
		if tool.displayName == itemName then
			return true
		end
	end

	return false
end

local function hasCollectedSeasonalExclusive(collections, exclusive)
	if not collections or not exclusive then
		return false
	end

	if exclusive.id == "spring" then
		for _, egg in pairs(ItemDatabase.SPRING_DINO_EGGS or {}) do
			if collections[egg.displayName] == true then
				return true
			end
		end

		return false
	end

	if exclusive.id == "halloween" then
		for _, fossil in pairs(ItemDatabase.HALLOWEEN_GHOST_FOSSILS or {}) do
			if collections[fossil.displayName] == true then
				return true
			end
		end

		return false
	end

	if exclusive.id == "summer" then
		for _, tool in pairs(ItemDatabase.SUMMER_OBSIDIAN_TOOLS or {}) do
			if collections[tool.displayName] == true then
				return true
			end
		end

		return false
	end

	return collections[exclusive.displayName] == true
end

local function setSeasonalVaultState(placeholder, exclusive, unlocked)
	local rarityColor = getSeasonalExclusiveColor(exclusive)
	local lockedColor = Color3.fromRGB(95, 95, 100)
	local relic = placeholder:FindFirstChild("SeasonalRelic")
	local label = placeholder:FindFirstChild("Label")
	local txt = label and label:FindFirstChildOfClass("TextLabel") or nil

	placeholder:SetAttribute("Locked", not unlocked)
	placeholder.Color = unlocked and rarityColor or lockedColor
	placeholder.Material = unlocked and Enum.Material.Marble or Enum.Material.Slate

	if relic then
		relic.Color = unlocked and rarityColor or Color3.fromRGB(120, 120, 130)
		relic.Material = unlocked and Enum.Material.Neon or Enum.Material.Glass
		relic.Transparency = unlocked and 0 or 0.35
	end

	if txt then
		if unlocked then
			txt.Text = exclusive.season .. "\n" .. exclusive.displayName .. "\nUNLOCKED"
			txt.TextColor3 = rarityColor
		else
			txt.Text = exclusive.season .. "\n" .. exclusive.theme .. "\nLOCKED"
			txt.TextColor3 = Color3.fromRGB(180, 180, 190)
		end
	end
end

local function updateSeasonalVault(museum, data)
	if not museum or type(data) ~= "table" or type(data.collections) ~= "table" then
		return
	end

	for _, exclusive in ipairs(ItemDatabase.SEASONAL_EXCLUSIVES or {}) do
		local placeholder = museum.seasonalVaults and museum.seasonalVaults[exclusive.id]
		if not placeholder and museum.folder then
			placeholder = museum.folder:FindFirstChild("SeasonalVault_" .. exclusive.id)
		end

		if placeholder then
			setSeasonalVaultState(placeholder, exclusive, hasCollectedSeasonalExclusive(data.collections, exclusive))
		end
	end
end

local function isSeasonalExclusiveName(itemName)
	for _, exclusive in ipairs(ItemDatabase.SEASONAL_EXCLUSIVES or {}) do
		if exclusive.displayName == itemName then
			return true
		end
	end

	return isSpringDinoEggVariant(itemName)
		or isHalloweenGhostFossilVariant(itemName)
		or isSummerObsidianToolVariant(itemName)
end

local function createMuseumForPlayer(player)
	museumIndex = museumIndex + 1
	local offsetX = museumIndex * MUSEUM_SPACING

	local museumFolder = Instance.new("Folder")
	museumFolder.Name = player.Name .. "_Museum"
	museumFolder.Parent = museumsFolder

	-- Floor
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Size = Vector3.new(60, 1, 60)
	floor.Position = Vector3.new(offsetX, -2, 0)
	floor.Anchored = true
	floor.Material = Enum.Material.Marble
	floor.Color = Color3.fromRGB(230, 225, 215)
	floor.Parent = museumFolder

	-- Walls
	for _, wallDef in ipairs({
		{ Vector3.new(offsetX - 30, 8, 0), Vector3.new(1, 20, 62) },
		{ Vector3.new(offsetX + 30, 8, 0), Vector3.new(1, 20, 62) },
		{ Vector3.new(offsetX, 8, -30), Vector3.new(60, 20, 1) },
		{ Vector3.new(offsetX, 8, 30), Vector3.new(60, 20, 1) },
	}) do
		local wall = Instance.new("Part")
		wall.Size = wallDef[2]
		wall.Position = wallDef[1]
		wall.Anchored = true
		wall.Material = Enum.Material.SmoothPlastic
		wall.Color = Color3.fromRGB(245, 240, 230)
		wall.Parent = museumFolder
	end

	-- Name sign
	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Size = Vector3.new(20, 4, 0.5)
	sign.Position = Vector3.new(offsetX, 15, -29)
	sign.Anchored = true
	sign.Material = Enum.Material.SmoothPlastic
	sign.Color = Color3.fromRGB(40, 35, 30)
	sign.Parent = museumFolder

	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Back
	signGui.Parent = sign

	local signText = Instance.new("TextLabel")
	signText.Size = UDim2.new(1, 0, 1, 0)
	signText.BackgroundTransparency = 1
	signText.Text = player.Name .. "'s Museum"
	signText.TextColor3 = Color3.fromRGB(255, 200, 50)
	signText.TextScaled = true
	signText.Font = Enum.Font.GothamBold
	signText.Parent = signGui

	-- Teleport pad (at the dig site)
	local telepad = Instance.new("Part")
	telepad.Name = player.Name .. "_MuseumPad"
	telepad.Size = Vector3.new(6, 0.5, 6)
	telepad.Position = Vector3.new(-80 + (museumIndex - 1) * 10, 5.5, 0)
	telepad.Anchored = true
	telepad.Material = Enum.Material.Neon
	telepad.Color = Color3.fromRGB(100, 50, 200)
	telepad.Parent = museumsFolder

	local padGui = Instance.new("SurfaceGui")
	padGui.Face = Enum.NormalId.Top
	padGui.Parent = telepad

	local padText = Instance.new("TextLabel")
	padText.Size = UDim2.new(1, 0, 1, 0)
	padText.BackgroundTransparency = 1
	padText.Text = player.Name .. "\nMuseum"
	padText.TextColor3 = Color3.fromRGB(255, 255, 255)
	padText.TextScaled = true
	padText.Font = Enum.Font.GothamBold
	padText.Parent = padGui

	-- Touch to teleport
	telepad.Touched:Connect(function(hit)
		local touchPlayer = Players:GetPlayerFromCharacter(hit.Parent)
		if touchPlayer and touchPlayer.Character then
			local hrp = touchPlayer.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = CFrame.new(offsetX, 2, 0)
			end
		end
	end)

	-- Return pad (inside museum, back to dig site)
	local returnPad = Instance.new("Part")
	returnPad.Name = "ReturnPad"
	returnPad.Size = Vector3.new(4, 0.5, 4)
	returnPad.Position = Vector3.new(offsetX, -1, 25)
	returnPad.Anchored = true
	returnPad.Material = Enum.Material.Neon
	returnPad.Color = Color3.fromRGB(50, 200, 50)
	returnPad.Parent = museumFolder

	local returnGui = Instance.new("SurfaceGui")
	returnGui.Face = Enum.NormalId.Top
	returnGui.Parent = returnPad

	local returnText = Instance.new("TextLabel")
	returnText.Size = UDim2.new(1, 0, 1, 0)
	returnText.BackgroundTransparency = 1
	returnText.Text = "Return to\nDig Site"
	returnText.TextColor3 = Color3.fromRGB(255, 255, 255)
	returnText.TextScaled = true
	returnText.Font = Enum.Font.GothamBold
	returnText.Parent = returnGui

	returnPad.Touched:Connect(function(hit)
		local touchPlayer = Players:GetPlayerFromCharacter(hit.Parent)
		if touchPlayer and touchPlayer.Character then
			local hrp = touchPlayer.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = CFrame.new(0, 8, 0)
			end
		end
	end)

	-- Create pedestal grid
	local pedestals = {}
	local pedestalIndex = 0
	for tierIdx, tier in ipairs(Config.TIERS) do
		local tierItems = ItemDatabase.ITEMS[tier.name]
		if tierItems then
			for itemIdx, _ in ipairs(tierItems) do
				pedestalIndex = pedestalIndex + 1
				local row = math.floor((pedestalIndex - 1) / PEDESTALS_PER_ROW)
				local col = (pedestalIndex - 1) % PEDESTALS_PER_ROW

				local pedestal = Instance.new("Part")
				pedestal.Name = "Pedestal_" .. pedestalIndex
				pedestal.Size = PEDESTAL_SIZE
				pedestal.Position = Vector3.new(
					offsetX - 24 + col * PEDESTAL_SPACING,
					0,
					-20 + row * PEDESTAL_SPACING
				)
				pedestal.Anchored = true
				pedestal.Material = Enum.Material.Marble
				pedestal.Color = Color3.fromRGB(200, 195, 185)
				pedestal:SetAttribute("TierName", tier.name)
				pedestal:SetAttribute("ItemIndex", itemIdx)
				pedestal:SetAttribute("Occupied", false)
				pedestal.Parent = museumFolder

				-- Label (empty until item placed)
				local labelGui = Instance.new("SurfaceGui")
				labelGui.Face = Enum.NormalId.Front
				labelGui.Name = "Label"
				labelGui.Parent = pedestal

				local labelText = Instance.new("TextLabel")
				labelText.Size = UDim2.new(1, 0, 1, 0)
				labelText.BackgroundTransparency = 1
				labelText.Text = "?"
				labelText.TextColor3 = Color3.fromRGB(100, 100, 100)
				labelText.TextScaled = true
				labelText.Font = Enum.Font.Gotham
				labelText.Parent = labelGui

				pedestals[pedestalIndex] = pedestal
			end
		end
	end

	local seasonalHeader = Instance.new("Part")
	seasonalHeader.Name = "SeasonalVaultHeader"
	seasonalHeader.Size = Vector3.new(30, 2, 0.5)
	seasonalHeader.Position = Vector3.new(offsetX, 2, 14.5)
	seasonalHeader.Anchored = true
	seasonalHeader.Material = Enum.Material.SmoothPlastic
	seasonalHeader.Color = Color3.fromRGB(55, 55, 60)
	seasonalHeader.Parent = museumFolder

	local headerGui = Instance.new("SurfaceGui")
	headerGui.Face = Enum.NormalId.Front
	headerGui.Parent = seasonalHeader

	local headerText = Instance.new("TextLabel")
	headerText.Size = UDim2.new(1, 0, 1, 0)
	headerText.BackgroundTransparency = 1
	headerText.Text = "Seasonal Vault"
	headerText.TextColor3 = Color3.fromRGB(200, 200, 210)
	headerText.TextScaled = true
	headerText.Font = Enum.Font.GothamBold
	headerText.Parent = headerGui

	local seasonalVaults = {}
	for seasonalIndex, exclusive in ipairs(ItemDatabase.SEASONAL_EXCLUSIVES or {}) do
		local rowOffset = (seasonalIndex - 2.5) * PEDESTAL_SPACING

		local placeholder = Instance.new("Part")
		placeholder.Name = "SeasonalVault_" .. exclusive.id
		placeholder.Size = PEDESTAL_SIZE
		placeholder.Position = Vector3.new(offsetX + rowOffset, 0, 20)
		placeholder.Anchored = true
		placeholder.Material = Enum.Material.Slate
		placeholder.Color = Color3.fromRGB(95, 95, 100)
		placeholder:SetAttribute("SeasonalVault", true)
		placeholder:SetAttribute("Locked", true)
		placeholder.Parent = museumFolder

		local relic = Instance.new("Part")
		relic.Name = "SeasonalRelic"
		relic.Size = DISPLAY_ITEM_SIZE
		relic.Position = placeholder.Position + Vector3.new(0, PEDESTAL_SIZE.Y / 2 + DISPLAY_ITEM_SIZE.Y / 2, 0)
		relic.Anchored = true
		relic.CanCollide = false
		relic.Material = Enum.Material.Glass
		relic.Transparency = 0.35
		relic.Color = Color3.fromRGB(120, 120, 130)
		relic.Parent = placeholder

		local labelGui = Instance.new("SurfaceGui")
		labelGui.Face = Enum.NormalId.Front
		labelGui.Name = "Label"
		labelGui.Parent = placeholder

		local labelText = Instance.new("TextLabel")
		labelText.Size = UDim2.new(1, 0, 1, 0)
		labelText.BackgroundTransparency = 1
		labelText.Text = exclusive.season .. "\n" .. exclusive.theme .. "\nLOCKED"
		labelText.TextColor3 = Color3.fromRGB(180, 180, 190)
		labelText.TextScaled = true
		labelText.Font = Enum.Font.GothamBold
		labelText.Parent = labelGui

		seasonalVaults[exclusive.id] = placeholder
	end

	local museumData = {
		folder = museumFolder,
		pedestals = pedestals,
		seasonalVaults = seasonalVaults,
		displayedItems = {},
		position = Vector3.new(offsetX, 0, 0),
		telepad = telepad,
	}

	playerMuseums[player.UserId] = museumData
	updateSeasonalVault(museumData, getPlayerData(player))
	return museumData
end

-- ═══════════════════════════════════════════════════════════════════
-- Display Item on Pedestal
-- ═══════════════════════════════════════════════════════════════════

local function findPedestalForItem(museum, itemName)
	-- Find the pedestal that matches this item
	for idx, pedestal in pairs(museum.pedestals) do
		local tierName = pedestal:GetAttribute("TierName")
		local itemIndex = pedestal:GetAttribute("ItemIndex")

		local tierItems = ItemDatabase.ITEMS[tierName]
		if tierItems and tierItems[itemIndex] and tierItems[itemIndex].name == itemName then
			return pedestal, idx
		end
	end
	return nil
end

DisplayItemEvent.OnServerEvent:Connect(function(player, inventoryIndex)
	local museum = playerMuseums[player.UserId]
	if not museum then return end

	local cache = _G.DeepDig_playerData
	if not cache then return end
	local data = cache[player.UserId]
	if not data then return end

	local item = data.inventory[inventoryIndex]
	if not item then return end

	if not data.collections[item.name] then return end

	if museum.displayedItems[item.name] then
		local NotifyEvent = Remotes:FindFirstChild("Notify")
		if NotifyEvent then
			NotifyEvent:FireClient(player, item.name .. " is already on display.", "Common")
		end
		return
	end

	local pedestal = findPedestalForItem(museum, item.name)
	if not pedestal then return end

	local rarityColor = RARITY_COLORS[item.rarity] or RARITY_COLORS.Common
	local display = Instance.new("Part")
	display.Name = "Display_" .. item.name
	display.Size = DISPLAY_ITEM_SIZE
	display.Position = pedestal.Position + Vector3.new(0, PEDESTAL_SIZE.Y / 2 + DISPLAY_ITEM_SIZE.Y / 2, 0)
	display.Anchored = true
	display.CanCollide = false
	display.Material = Enum.Material.Neon
	display.Color = rarityColor
	display.Parent = pedestal

	local label = pedestal:FindFirstChild("Label")
	if label then
		local txt = label:FindFirstChildOfClass("TextLabel")
		if txt then
			txt.Text = item.name
			txt.TextColor3 = rarityColor
		end
	end
	pedestal:SetAttribute("Occupied", true)

	museum.displayedItems[item.name] = {
		rarity = item.rarity,
		sellValue = item.sellValue,
		displayedAt = os.time(),
	}

	table.remove(data.inventory, inventoryIndex)

	local UpdateHUDEvent = Remotes:FindFirstChild("UpdateHUD")
	if UpdateHUDEvent then
		UpdateHUDEvent:FireClient(player, { inventoryCount = #data.inventory })
	end
	MuseumUpdateEvent:FireClient(player, {
		itemName = item.name,
		rarity = item.rarity,
		totalDisplayed = countDisplayed(museum),
	})
end)

-- ═══════════════════════════════════════════════════════════════════
-- Museum Data Query
-- ═══════════════════════════════════════════════════════════════════

GetMuseumDataFunc.OnServerInvoke = function(player, targetUserId)
	local userId = targetUserId or player.UserId
	local museum = playerMuseums[userId]
	if not museum then return nil end

	-- Build collection progress
	local progress = {}
	for _, tier in ipairs(Config.TIERS) do
		local tierItems = ItemDatabase.ITEMS[tier.name]
		if tierItems then
			local found = 0
			local total = #tierItems
			for _, item in ipairs(tierItems) do
				if museum.displayedItems[item.name] then
					found = found + 1
				end
			end
			progress[tier.name] = {
				found = found,
				total = total,
				complete = found == total,
				bonus = found == total and TIER_COMPLETION_BONUS[tier.name] or 1,
			}
		end
	end

	local ok, ownerName = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if not ok or not ownerName then
		ownerName = "Unknown"
	end

	return {
		ownerName = ownerName,
		displayedItems = museum.displayedItems,
		progress = progress,
		totalDisplayed = countDisplayed(museum),
	}
end

-- ═══════════════════════════════════════════════════════════════════
-- Player Join / Leave
-- ═══════════════════════════════════════════════════════════════════

Players.PlayerAdded:Connect(function(player)
	createMuseumForPlayer(player)
end)

PlayerDataReady.Event:Connect(function(player)
	updateSeasonalVault(playerMuseums[player.UserId], getPlayerData(player))
end)

ItemFoundBindable.Event:Connect(function(player, item)
	if item and isSeasonalExclusiveName(item.name) then
		updateSeasonalVault(playerMuseums[player.UserId], getPlayerData(player))
	end
end)

-- Handle players already in the game when the script loads (Studio playtest)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(function() createMuseumForPlayer(p) end)
end

Players.PlayerRemoving:Connect(function(player)
	local museum = playerMuseums[player.UserId]
	if museum then
		if museum.folder then museum.folder:Destroy() end
		if museum.telepad then museum.telepad:Destroy() end
		playerMuseums[player.UserId] = nil
	end
end)

print("[DeepDig] Museum system loaded")
