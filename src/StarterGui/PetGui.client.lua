-- PetGui.client.lua — Pet inventory + hatchery UI
-- Place in: StarterGui/PetGui (LocalScript)
--
-- Bottom-left "🐾 Pets" toggle opens a panel with two stacked sections:
--   1. Inventory grid — owned pets, equipped pet highlighted, click to equip/unequip
--   2. Hatchery — three egg tier buttons that fire HatchEgg
--
-- Inventory data sourcing — PetSystem now exposes GetPetInventory, so the
-- client fetches authoritative pet data on open, on a 5s refresh cadence, and
-- after hatch/equip actions. NotifyEvent is only used for user-facing status
-- text; it no longer drives inventory state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════════════
-- Remotes (graceful exit if PetSystem isn't loaded)
-- ═══════════════════════════════════════════════════════════════════

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if not Remotes then
	warn("[PetGui] Remotes folder not found — PetSystem not loaded?")
	return
end

local HatchEggEvent = Remotes:WaitForChild("HatchEgg", 5)
local EquipPetEvent = Remotes:WaitForChild("EquipPet", 5)
local GetPetInventoryFunction = Remotes:WaitForChild("GetPetInventory", 5)
local NotifyEvent = Remotes:WaitForChild("Notify", 5)
local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD", 5)

if not (HatchEggEvent and EquipPetEvent and GetPetInventoryFunction and NotifyEvent and UpdateHUDEvent) then
	warn("[PetGui] Required pet remotes missing — exiting cleanly.")
	return
end

-- FeedPet is optional — if PetFeed.server.lua hasn't loaded, the Feed
-- Mode toggle button is hidden so the rest of the UI stays usable.
local FeedPetEvent = Remotes:WaitForChild("FeedPet", 5)

-- PetDatabase lives in ReplicatedStorage and is safe to require from the
-- client. We use it for rarity colors, multiplier lookups, and egg metadata.
local petDatabaseModule = ReplicatedStorage:WaitForChild("PetDatabase", 5)
if not petDatabaseModule then
	warn("[PetGui] PetDatabase module missing — exiting cleanly.")
	return
end
local PetDatabase = require(petDatabaseModule)

-- ═══════════════════════════════════════════════════════════════════
-- Style constants — match HudGui.client.lua visual language
-- ═══════════════════════════════════════════════════════════════════

local RarityColors = {
	Common    = Color3.fromRGB(180, 180, 180),
	Uncommon  = Color3.fromRGB(30, 200, 30),
	Rare      = Color3.fromRGB(30, 100, 255),
	Epic      = Color3.fromRGB(160, 50, 255),
	Legendary = Color3.fromRGB(255, 170, 0),
	Mythic    = Color3.fromRGB(255, 50, 50),
}

local PANEL_BG = Color3.fromRGB(20, 20, 25)
local PANEL_BG_TRANSPARENCY = 0.15
local SECTION_BG = Color3.fromRGB(28, 28, 34)
local CARD_BG = Color3.fromRGB(34, 34, 40)
local TEXT_PRIMARY = Color3.fromRGB(235, 235, 235)
local TEXT_MUTED = Color3.fromRGB(160, 160, 160)
local ACCENT_GOLD = Color3.fromRGB(255, 200, 50)

-- Feed Mode visuals — matches PetFeed.server.lua semantics: green = target,
-- red = sacrifice, gold = same-species candidate to the selected target.
local FEED_TARGET_COLOR = Color3.fromRGB(60, 220, 90)
local FEED_SACRIFICE_COLOR = Color3.fromRGB(240, 70, 70)
local FEED_CANDIDATE_COLOR = Color3.fromRGB(255, 215, 80)
local FEED_HEADER_COLOR = Color3.fromRGB(255, 130, 80)

-- Server caps level at 20 (PetFeed MAX_LEVEL). Mirrored here so we can
-- mark MAX cards in the grid without burning a server round-trip per click.
local MAX_PET_LEVEL = 20

local function xpForLevel(level)
	return 100 + (level - 1) * 50
end

-- ═══════════════════════════════════════════════════════════════════
-- Screen GUI scaffolding
-- ═══════════════════════════════════════════════════════════════════

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeepDigPetGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- ─── Toggle button (bottom-left) ─────────────────────────────────────────────
-- Positioned bottom-left so it doesn't collide with QuestGui (bottom-right)
-- or the Shop button HudGui places elsewhere.

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "PetToggle"
toggleButton.Size = UDim2.new(0, 120, 0, 40)
toggleButton.AnchorPoint = Vector2.new(0, 1)
toggleButton.Position = UDim2.new(0, 20, 1, -20)
toggleButton.BackgroundColor3 = PANEL_BG
toggleButton.BackgroundTransparency = 0.15
toggleButton.BorderSizePixel = 0
toggleButton.Text = "🐾 Pets"
toggleButton.TextColor3 = TEXT_PRIMARY
toggleButton.TextSize = 18
toggleButton.Font = Enum.Font.GothamBold
toggleButton.AutoButtonColor = true
toggleButton.Parent = screenGui

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

local toggleStroke = Instance.new("UIStroke")
toggleStroke.Color = Color3.fromRGB(80, 80, 95)
toggleStroke.Thickness = 1
toggleStroke.Parent = toggleButton

-- Small badge that shows pet count on the toggle button
local toggleBadge = Instance.new("TextLabel")
toggleBadge.Name = "Count"
toggleBadge.Size = UDim2.new(0, 22, 0, 22)
toggleBadge.AnchorPoint = Vector2.new(1, 0)
toggleBadge.Position = UDim2.new(1, -4, 0, 4)
toggleBadge.BackgroundColor3 = ACCENT_GOLD
toggleBadge.BackgroundTransparency = 0
toggleBadge.BorderSizePixel = 0
toggleBadge.Text = "0"
toggleBadge.TextColor3 = Color3.fromRGB(20, 20, 25)
toggleBadge.TextSize = 12
toggleBadge.Font = Enum.Font.GothamBlack
toggleBadge.Visible = false
toggleBadge.Parent = toggleButton

local toggleBadgeCorner = Instance.new("UICorner")
toggleBadgeCorner.CornerRadius = UDim.new(1, 0)
toggleBadgeCorner.Parent = toggleBadge

-- ─── Main panel ──────────────────────────────────────────────────────────────

local panel = Instance.new("Frame")
panel.Name = "PetPanel"
panel.Size = UDim2.new(0, 460, 0, 520)
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 20, 1, -76)
panel.BackgroundColor3 = PANEL_BG
panel.BackgroundTransparency = PANEL_BG_TRANSPARENCY
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(60, 60, 75)
panelStroke.Thickness = 1
panelStroke.Parent = panel

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundTransparency = 1
titleBar.Parent = panel

local titleLabel = Instance.new("TextLabel")
-- Reserve 200px on the right for the Feed-Mode toggle (124px) + close (32px) + padding.
titleLabel.Size = UDim2.new(1, -200, 1, 0)
titleLabel.Position = UDim2.new(0, 15, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "🐾 Pet Collection"
titleLabel.TextColor3 = TEXT_PRIMARY
titleLabel.TextSize = 18
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
titleLabel.Parent = titleBar

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 32, 0, 32)
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, -10, 0.5, 0)
closeButton.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
closeButton.BackgroundTransparency = 0.2
closeButton.BorderSizePixel = 0
closeButton.Text = "×"
closeButton.TextColor3 = TEXT_PRIMARY
closeButton.TextSize = 22
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = titleBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = closeButton

-- ─── Feed Mode toggle button ─────────────────────────────────────────────────
-- Sits to the left of the close button. Hidden if FeedPet remote is missing.

local feedModeButton = Instance.new("TextButton")
feedModeButton.Name = "FeedModeToggle"
feedModeButton.Size = UDim2.new(0, 124, 0, 28)
feedModeButton.AnchorPoint = Vector2.new(1, 0.5)
feedModeButton.Position = UDim2.new(1, -50, 0.5, 0)
feedModeButton.BackgroundColor3 = Color3.fromRGB(50, 30, 30)
feedModeButton.BackgroundTransparency = 0.15
feedModeButton.BorderSizePixel = 0
feedModeButton.Text = "🍖 Feed Mode"
feedModeButton.TextColor3 = TEXT_PRIMARY
feedModeButton.TextSize = 13
feedModeButton.Font = Enum.Font.GothamBold
feedModeButton.AutoButtonColor = true
feedModeButton.Visible = FeedPetEvent ~= nil
feedModeButton.Parent = titleBar

local feedModeCorner = Instance.new("UICorner")
feedModeCorner.CornerRadius = UDim.new(0, 6)
feedModeCorner.Parent = feedModeButton

local feedModeStroke = Instance.new("UIStroke")
feedModeStroke.Color = Color3.fromRGB(120, 60, 60)
feedModeStroke.Thickness = 1
feedModeStroke.Parent = feedModeButton

-- ─── Feed Mode confirmation modal (hidden by default) ────────────────────────
-- Overlays the panel so the player must explicitly confirm an irreversible feed.

local feedConfirm = Instance.new("Frame")
feedConfirm.Name = "FeedConfirm"
feedConfirm.Size = UDim2.new(1, -40, 0, 160)
feedConfirm.Position = UDim2.new(0, 20, 0.5, -80)
feedConfirm.BackgroundColor3 = Color3.fromRGB(28, 22, 22)
feedConfirm.BackgroundTransparency = 0.05
feedConfirm.BorderSizePixel = 0
feedConfirm.Visible = false
feedConfirm.ZIndex = 50
feedConfirm.Parent = panel

local feedConfirmCorner = Instance.new("UICorner")
feedConfirmCorner.CornerRadius = UDim.new(0, 10)
feedConfirmCorner.Parent = feedConfirm

local feedConfirmStroke = Instance.new("UIStroke")
feedConfirmStroke.Color = FEED_HEADER_COLOR
feedConfirmStroke.Thickness = 2
feedConfirmStroke.Parent = feedConfirm

local feedConfirmTitle = Instance.new("TextLabel")
feedConfirmTitle.Name = "Title"
feedConfirmTitle.Size = UDim2.new(1, -20, 0, 26)
feedConfirmTitle.Position = UDim2.new(0, 10, 0, 10)
feedConfirmTitle.BackgroundTransparency = 1
feedConfirmTitle.Text = "🍖 Confirm Feed"
feedConfirmTitle.TextColor3 = FEED_HEADER_COLOR
feedConfirmTitle.TextSize = 17
feedConfirmTitle.Font = Enum.Font.GothamBold
feedConfirmTitle.TextXAlignment = Enum.TextXAlignment.Left
feedConfirmTitle.ZIndex = 51
feedConfirmTitle.Parent = feedConfirm

local feedConfirmText = Instance.new("TextLabel")
feedConfirmText.Name = "Body"
feedConfirmText.Size = UDim2.new(1, -20, 0, 70)
feedConfirmText.Position = UDim2.new(0, 10, 0, 40)
feedConfirmText.BackgroundTransparency = 1
feedConfirmText.Text = ""
feedConfirmText.TextColor3 = TEXT_PRIMARY
feedConfirmText.TextSize = 14
feedConfirmText.Font = Enum.Font.Gotham
feedConfirmText.TextWrapped = true
feedConfirmText.TextXAlignment = Enum.TextXAlignment.Left
feedConfirmText.TextYAlignment = Enum.TextYAlignment.Top
feedConfirmText.ZIndex = 51
feedConfirmText.Parent = feedConfirm

local feedConfirmYes = Instance.new("TextButton")
feedConfirmYes.Name = "Confirm"
feedConfirmYes.Size = UDim2.new(0.5, -16, 0, 34)
feedConfirmYes.Position = UDim2.new(0, 10, 1, -44)
feedConfirmYes.BackgroundColor3 = FEED_TARGET_COLOR
feedConfirmYes.BackgroundTransparency = 0.1
feedConfirmYes.BorderSizePixel = 0
feedConfirmYes.Text = "Confirm"
feedConfirmYes.TextColor3 = Color3.fromRGB(20, 25, 20)
feedConfirmYes.TextSize = 14
feedConfirmYes.Font = Enum.Font.GothamBold
feedConfirmYes.AutoButtonColor = true
feedConfirmYes.ZIndex = 51
feedConfirmYes.Parent = feedConfirm

local feedConfirmYesCorner = Instance.new("UICorner")
feedConfirmYesCorner.CornerRadius = UDim.new(0, 6)
feedConfirmYesCorner.Parent = feedConfirmYes

local feedConfirmNo = Instance.new("TextButton")
feedConfirmNo.Name = "Cancel"
feedConfirmNo.Size = UDim2.new(0.5, -16, 0, 34)
feedConfirmNo.Position = UDim2.new(0.5, 6, 1, -44)
feedConfirmNo.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
feedConfirmNo.BackgroundTransparency = 0.1
feedConfirmNo.BorderSizePixel = 0
feedConfirmNo.Text = "Cancel"
feedConfirmNo.TextColor3 = TEXT_PRIMARY
feedConfirmNo.TextSize = 14
feedConfirmNo.Font = Enum.Font.GothamBold
feedConfirmNo.AutoButtonColor = true
feedConfirmNo.ZIndex = 51
feedConfirmNo.Parent = feedConfirm

local feedConfirmNoCorner = Instance.new("UICorner")
feedConfirmNoCorner.CornerRadius = UDim.new(0, 6)
feedConfirmNoCorner.Parent = feedConfirmNo

-- ─── Inventory section (scrollable grid) ─────────────────────────────────────

local inventorySection = Instance.new("Frame")
inventorySection.Name = "Inventory"
inventorySection.Size = UDim2.new(1, -20, 0, 280)
inventorySection.Position = UDim2.new(0, 10, 0, 50)
inventorySection.BackgroundColor3 = SECTION_BG
inventorySection.BackgroundTransparency = 0.2
inventorySection.BorderSizePixel = 0
inventorySection.Parent = panel

local inventoryCorner = Instance.new("UICorner")
inventoryCorner.CornerRadius = UDim.new(0, 8)
inventoryCorner.Parent = inventorySection

local inventoryHeader = Instance.new("TextLabel")
inventoryHeader.Size = UDim2.new(1, -20, 0, 24)
inventoryHeader.Position = UDim2.new(0, 10, 0, 6)
inventoryHeader.BackgroundTransparency = 1
inventoryHeader.Text = "Your Pets"
inventoryHeader.TextColor3 = TEXT_MUTED
inventoryHeader.TextSize = 13
inventoryHeader.Font = Enum.Font.GothamBold
inventoryHeader.TextXAlignment = Enum.TextXAlignment.Left
inventoryHeader.Parent = inventorySection

local inventoryScroll = Instance.new("ScrollingFrame")
inventoryScroll.Name = "Scroll"
inventoryScroll.Size = UDim2.new(1, -16, 1, -38)
inventoryScroll.Position = UDim2.new(0, 8, 0, 32)
inventoryScroll.BackgroundTransparency = 1
inventoryScroll.BorderSizePixel = 0
inventoryScroll.ScrollBarThickness = 6
inventoryScroll.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 140)
inventoryScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
inventoryScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
inventoryScroll.Parent = inventorySection

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 134, 0, 110)
gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = inventoryScroll

local gridPadding = Instance.new("UIPadding")
gridPadding.PaddingTop = UDim.new(0, 4)
gridPadding.PaddingLeft = UDim.new(0, 4)
gridPadding.PaddingRight = UDim.new(0, 4)
gridPadding.PaddingBottom = UDim.new(0, 4)
gridPadding.Parent = inventoryScroll

local emptyPlaceholder = Instance.new("TextLabel")
emptyPlaceholder.Name = "Empty"
emptyPlaceholder.Size = UDim2.new(1, -20, 0, 60)
emptyPlaceholder.Position = UDim2.new(0, 10, 0.5, -30)
emptyPlaceholder.BackgroundTransparency = 1
emptyPlaceholder.Text = "Hatch your first egg below!"
emptyPlaceholder.TextColor3 = TEXT_MUTED
emptyPlaceholder.TextSize = 16
emptyPlaceholder.Font = Enum.Font.GothamMedium
emptyPlaceholder.TextWrapped = true
emptyPlaceholder.Visible = false
emptyPlaceholder.Parent = inventorySection

-- ─── Hatchery section ────────────────────────────────────────────────────────

local hatcherySection = Instance.new("Frame")
hatcherySection.Name = "Hatchery"
hatcherySection.Size = UDim2.new(1, -20, 0, 168)
hatcherySection.Position = UDim2.new(0, 10, 0, 340)
hatcherySection.BackgroundColor3 = SECTION_BG
hatcherySection.BackgroundTransparency = 0.2
hatcherySection.BorderSizePixel = 0
hatcherySection.Parent = panel

local hatcheryCorner = Instance.new("UICorner")
hatcheryCorner.CornerRadius = UDim.new(0, 8)
hatcheryCorner.Parent = hatcherySection

local hatcheryHeader = Instance.new("TextLabel")
hatcheryHeader.Size = UDim2.new(1, -20, 0, 24)
hatcheryHeader.Position = UDim2.new(0, 10, 0, 6)
hatcheryHeader.BackgroundTransparency = 1
hatcheryHeader.Text = "Hatchery"
hatcheryHeader.TextColor3 = TEXT_MUTED
hatcheryHeader.TextSize = 13
hatcheryHeader.Font = Enum.Font.GothamBold
hatcheryHeader.TextXAlignment = Enum.TextXAlignment.Left
hatcheryHeader.Parent = hatcherySection

local hatcheryStatus = Instance.new("TextLabel")
hatcheryStatus.Name = "Status"
hatcheryStatus.Size = UDim2.new(1, -20, 0, 18)
hatcheryStatus.Position = UDim2.new(0, 10, 1, -22)
hatcheryStatus.BackgroundTransparency = 1
hatcheryStatus.Text = ""
hatcheryStatus.TextColor3 = TEXT_MUTED
hatcheryStatus.TextSize = 12
hatcheryStatus.Font = Enum.Font.Gotham
hatcheryStatus.TextXAlignment = Enum.TextXAlignment.Left
hatcheryStatus.Parent = hatcherySection

-- Three egg tier buttons (Stone / Gem / Void)
local EGG_ORDER = { "Stone", "Gem", "Void" }
local eggButtons = {}
local refreshInventory
local renderInventory

for index, eggType in ipairs(EGG_ORDER) do
	local egg = PetDatabase.EGGS[eggType]
	if egg then
		local button = Instance.new("TextButton")
		button.Name = eggType .. "EggButton"
		button.Size = UDim2.new(0, 132, 0, 92)
		-- Cells laid out left-to-right with 10px gap, 12px left padding
		button.Position = UDim2.new(0, 12 + (index - 1) * 142, 0, 36)
		button.BackgroundColor3 = egg.color
		button.BackgroundTransparency = 0.05
		button.BorderSizePixel = 0
		button.Text = ""
		button.AutoButtonColor = true
		button.Parent = hatcherySection

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 8)
		buttonCorner.Parent = button

		local buttonStroke = Instance.new("UIStroke")
		buttonStroke.Color = Color3.fromRGB(0, 0, 0)
		buttonStroke.Thickness = 1
		buttonStroke.Transparency = 0.5
		buttonStroke.Parent = button

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -10, 0, 26)
		nameLabel.Position = UDim2.new(0, 5, 0, 8)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = egg.name
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextSize = 15
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextStrokeTransparency = 0.5
		nameLabel.Parent = button

		local costLabel = Instance.new("TextLabel")
		costLabel.Size = UDim2.new(1, -10, 0, 22)
		costLabel.Position = UDim2.new(0, 5, 0, 36)
		costLabel.BackgroundTransparency = 1
		costLabel.Text = "🪙 " .. egg.cost
		costLabel.TextColor3 = Color3.fromRGB(255, 230, 110)
		costLabel.TextSize = 14
		costLabel.Font = Enum.Font.GothamBold
		costLabel.TextStrokeTransparency = 0.5
		costLabel.Parent = button

		local hatchLabel = Instance.new("TextLabel")
		hatchLabel.Size = UDim2.new(1, -10, 0, 18)
		hatchLabel.Position = UDim2.new(0, 5, 0, 64)
		hatchLabel.BackgroundTransparency = 1
		hatchLabel.Text = "Tap to hatch"
		hatchLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
		hatchLabel.TextSize = 11
		hatchLabel.Font = Enum.Font.Gotham
		hatchLabel.TextStrokeTransparency = 0.6
		hatchLabel.Parent = button

		eggButtons[eggType] = button

		button.Activated:Connect(function()
			HatchEggEvent:FireServer(eggType)
			hatcheryStatus.Text = "Hatching " .. egg.name .. "..."
			hatcheryStatus.TextColor3 = ACCENT_GOLD

			task.delay(0.75, function()
				refreshInventory()
			end)

			-- Brief visual squeeze on the button to acknowledge the press
			local origSize = button.Size
			local pressTween = TweenService:Create(
				button,
				TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = UDim2.new(0, origSize.X.Offset - 6, 0, origSize.Y.Offset - 4) }
			)
			pressTween:Play()
			pressTween.Completed:Connect(function()
				local releaseTween = TweenService:Create(
					button,
					TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Size = origSize }
				)
				releaseTween:Play()
			end)
		end)
	end
end

local function petMultipliersFromName(name)
	if type(name) ~= "string" or name == "" then
		return { dig_speed = 1.0, loot_value = 1.0, luck = 1.0 }
	end

	local def = PetDatabase.getPet(name)
	if def and def.multipliers then
		return def.multipliers
	end
	return { dig_speed = 1.0, loot_value = 1.0, luck = 1.0 }
end

local inventoryPets = {}
local equippedPetId = nil

-- ─── Feed Mode state ─────────────────────────────────────────────────────────
-- feedMode: bool — toggled via feedModeButton, persisted in PetFeedMode attribute
-- feedTargetId: string|nil — first-clicked pet (the one that gains XP)
-- feedSacrificeId: string|nil — second-clicked same-species pet (gets consumed)
-- feedConfirmActive: bool — modal is open; pet card clicks suppressed
local feedMode = false
local feedTargetId = nil
local feedSacrificeId = nil
local feedConfirmActive = false

local function findPetById(petId)
	if petId == nil then return nil end
	for _, record in ipairs(inventoryPets) do
		if record.id == petId then
			return record
		end
	end
	return nil
end

local function applyInventory(payload)
	if type(payload) ~= "table" then
		return false
	end

	local pets = {}
	if type(payload.pets) == "table" then
		for _, record in ipairs(payload.pets) do
			if type(record) == "table" and record.id ~= nil then
				local name = record.name or ("Pet " .. tostring(record.id))
				local multipliers = record.multipliers
				if multipliers == nil and record.name then
					multipliers = petMultipliersFromName(record.name)
				end
				if multipliers == nil then
					multipliers = { dig_speed = 1.0, loot_value = 1.0, luck = 1.0 }
				end

				table.insert(pets, {
					id = record.id,
					name = name,
					rarity = record.rarity or "Common",
					egg = record.egg,
					level = record.level or 1,
					xp = record.xp or 0,
					acquiredAt = record.acquiredAt,
					multipliers = multipliers,
				})
			end
		end
	end

	inventoryPets = pets

	if payload.equippedPet == nil or payload.equippedPet == false then
		equippedPetId = nil
	else
		equippedPetId = payload.equippedPet
	end

	return true
end

local function updateToggleBadge()
	local count = #inventoryPets
	toggleBadge.Text = tostring(count)
	toggleBadge.Visible = count > 0
end

local function formatMultiplierDelta(multipliers, key)
	local value = multipliers and multipliers[key] or 1
	local delta = math.max(value - 1, 0)
	return string.format("+%d%%", math.floor(delta * 100 + 0.5))
end

local function formatMultiplierRows(multipliers)
	return
		string.format(
			"luck %s  loot %s",
			formatMultiplierDelta(multipliers, "luck"),
			formatMultiplierDelta(multipliers, "loot_value")
		),
		string.format("speed %s", formatMultiplierDelta(multipliers, "dig_speed"))
end

local function formatXpProgress(entry)
	local level = entry.level or 1
	if level >= MAX_PET_LEVEL then
		return "XP MAX"
	end

	return string.format("XP %d / %d", entry.xp or 0, xpForLevel(level))
end

local handleFeedCardClick

local function buildPetCard(entry)
	local card = Instance.new("Frame")
	card.Name = "Pet_" .. tostring(entry.id)
	card.BackgroundColor3 = CARD_BG
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel = 0

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 6)
	cardCorner.Parent = card

	local rarityColor = RarityColors[entry.rarity] or RarityColors.Common
	local isEquipped = (equippedPetId == entry.id)
	local isMaxLevel = (entry.level or 1) >= MAX_PET_LEVEL

	-- Feed mode classification — used for stroke + dimming + click intent.
	local isFeedTarget = feedMode and feedTargetId == entry.id
	local isFeedSacrifice = feedMode and feedSacrificeId == entry.id
	local targetRecord = feedMode and feedTargetId and findPetById(feedTargetId) or nil
	local isSameSpeciesCandidate = feedMode
		and targetRecord
		and not isFeedTarget
		and not isFeedSacrifice
		and targetRecord.name == entry.name
		and not isMaxLevel
	-- Pets that cannot participate in the current feed flow (cross-species
	-- relative to a selected target, or max-level when no target picked yet).
	local isFeedDimmed = false
	if feedMode then
		if targetRecord and not isFeedTarget and not isFeedSacrifice then
			-- Once a target exists, anything that's not same-species + sub-cap is dim.
			isFeedDimmed = not isSameSpeciesCandidate
		elseif isMaxLevel then
			-- No target picked yet: max-level pets can't be targets, dim them.
			isFeedDimmed = true
		end
	end

	local cardStroke = Instance.new("UIStroke")
	if isFeedTarget then
		cardStroke.Color = FEED_TARGET_COLOR
		cardStroke.Thickness = 3
	elseif isFeedSacrifice then
		cardStroke.Color = FEED_SACRIFICE_COLOR
		cardStroke.Thickness = 3
	elseif isSameSpeciesCandidate then
		cardStroke.Color = FEED_CANDIDATE_COLOR
		cardStroke.Thickness = 2
	elseif isEquipped then
		cardStroke.Color = ACCENT_GOLD
		cardStroke.Thickness = 3
	else
		cardStroke.Color = rarityColor
		cardStroke.Thickness = 2
	end
	cardStroke.Parent = card

	if isFeedDimmed then
		card.BackgroundTransparency = 0.6
	end

	-- Rarity tint bar across the top
	local tintBar = Instance.new("Frame")
	tintBar.Size = UDim2.new(1, 0, 0, 6)
	tintBar.Position = UDim2.new(0, 0, 0, 0)
	tintBar.BackgroundColor3 = rarityColor
	tintBar.BackgroundTransparency = isFeedDimmed and 0.5 or 0.1
	tintBar.BorderSizePixel = 0
	tintBar.Parent = card

	local tintCorner = Instance.new("UICorner")
	tintCorner.CornerRadius = UDim.new(0, 4)
	tintCorner.Parent = tintBar

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -10, 0, 18)
	nameLabel.Position = UDim2.new(0, 5, 0, 10)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = entry.name
	nameLabel.TextColor3 = isFeedDimmed and TEXT_MUTED or TEXT_PRIMARY
	nameLabel.TextSize = 13
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Size = UDim2.new(1, -10, 0, 14)
	rarityLabel.Position = UDim2.new(0, 5, 0, 28)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Text = string.format("%s • Lv %d", entry.rarity, entry.level or 1)
	rarityLabel.TextColor3 = rarityColor
	rarityLabel.TextSize = 11
	rarityLabel.Font = Enum.Font.GothamMedium
	rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
	rarityLabel.Parent = card

	local statLine1, statLine2 = formatMultiplierRows(entry.multipliers)

	local statLabel1 = Instance.new("TextLabel")
	statLabel1.Size = UDim2.new(1, -10, 0, 12)
	statLabel1.Position = UDim2.new(0, 5, 0, 43)
	statLabel1.BackgroundTransparency = 1
	statLabel1.Text = statLine1
	statLabel1.TextColor3 = TEXT_MUTED
	statLabel1.TextSize = 9
	statLabel1.Font = Enum.Font.Gotham
	statLabel1.TextXAlignment = Enum.TextXAlignment.Left
	statLabel1.TextTruncate = Enum.TextTruncate.AtEnd
	statLabel1.Parent = card

	local statLabel2 = Instance.new("TextLabel")
	statLabel2.Size = UDim2.new(1, -10, 0, 12)
	statLabel2.Position = UDim2.new(0, 5, 0, 55)
	statLabel2.BackgroundTransparency = 1
	statLabel2.Text = statLine2
	statLabel2.TextColor3 = TEXT_MUTED
	statLabel2.TextSize = 9
	statLabel2.Font = Enum.Font.Gotham
	statLabel2.TextXAlignment = Enum.TextXAlignment.Left
	statLabel2.TextTruncate = Enum.TextTruncate.AtEnd
	statLabel2.Parent = card

	if feedMode then
		local xpLabel = Instance.new("TextLabel")
		xpLabel.Size = UDim2.new(1, -10, 0, 12)
		xpLabel.Position = UDim2.new(0, 5, 0, 67)
		xpLabel.BackgroundTransparency = 1
		xpLabel.Text = formatXpProgress(entry)
		xpLabel.TextColor3 = isMaxLevel and ACCENT_GOLD or TEXT_MUTED
		xpLabel.TextSize = 9
		xpLabel.Font = Enum.Font.GothamMedium
		xpLabel.TextXAlignment = Enum.TextXAlignment.Left
		xpLabel.TextTruncate = Enum.TextTruncate.AtEnd
		xpLabel.Parent = card
	end

	-- MAX badge — only shown in feed mode, since equip mode doesn't care.
	if feedMode and isMaxLevel then
		local maxBadge = Instance.new("TextLabel")
		maxBadge.Name = "MaxBadge"
		maxBadge.Size = UDim2.new(0, 36, 0, 16)
		maxBadge.AnchorPoint = Vector2.new(1, 0)
		maxBadge.Position = UDim2.new(1, -4, 0, 10)
		maxBadge.BackgroundColor3 = ACCENT_GOLD
		maxBadge.BackgroundTransparency = 0.05
		maxBadge.BorderSizePixel = 0
		maxBadge.Text = "MAX"
		maxBadge.TextColor3 = Color3.fromRGB(20, 20, 25)
		maxBadge.TextSize = 10
		maxBadge.Font = Enum.Font.GothamBlack
		maxBadge.Parent = card

		local maxCorner = Instance.new("UICorner")
		maxCorner.CornerRadius = UDim.new(0, 3)
		maxCorner.Parent = maxBadge
	end

	-- Action button — text + behavior depends on mode. In Feed Mode it
	-- doubles as the click-zone for the feed flow.
	local actionButton = Instance.new("TextButton")
	actionButton.Name = "Action"
	actionButton.Size = UDim2.new(1, -10, 0, 22)
	actionButton.Position = UDim2.new(0, 5, 1, -28)
	actionButton.BorderSizePixel = 0
	actionButton.TextSize = 12
	actionButton.Font = Enum.Font.GothamBold
	actionButton.AutoButtonColor = true
	actionButton.Parent = card

	local actionCorner = Instance.new("UICorner")
	actionCorner.CornerRadius = UDim.new(0, 4)
	actionCorner.Parent = actionButton

	if feedMode then
		-- Feed-mode action label reflects what clicking will do next.
		if isFeedTarget then
			actionButton.BackgroundColor3 = FEED_TARGET_COLOR
			actionButton.BackgroundTransparency = 0.1
			actionButton.Text = "TARGET"
			actionButton.TextColor3 = Color3.fromRGB(20, 25, 20)
		elseif isFeedSacrifice then
			actionButton.BackgroundColor3 = FEED_SACRIFICE_COLOR
			actionButton.BackgroundTransparency = 0.1
			actionButton.Text = "SACRIFICE"
			actionButton.TextColor3 = Color3.fromRGB(25, 20, 20)
		elseif isMaxLevel then
			actionButton.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
			actionButton.BackgroundTransparency = 0.3
			actionButton.Text = "MAX"
			actionButton.TextColor3 = TEXT_MUTED
			actionButton.AutoButtonColor = false
		elseif isSameSpeciesCandidate then
			actionButton.BackgroundColor3 = FEED_CANDIDATE_COLOR
			actionButton.BackgroundTransparency = 0.15
			actionButton.Text = "Sacrifice"
			actionButton.TextColor3 = Color3.fromRGB(30, 25, 15)
		elseif targetRecord then
			-- Cross-species while a target is selected — not clickable.
			actionButton.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
			actionButton.BackgroundTransparency = 0.4
			actionButton.Text = "—"
			actionButton.TextColor3 = TEXT_MUTED
			actionButton.AutoButtonColor = false
		else
			-- No target picked yet — every non-max card is a possible target.
			actionButton.BackgroundColor3 = rarityColor
			actionButton.BackgroundTransparency = 0.2
			actionButton.Text = "Select Target"
			actionButton.TextColor3 = Color3.fromRGB(20, 20, 25)
		end

		actionButton.Activated:Connect(function()
			handleFeedCardClick(entry)
		end)
	else
		-- Equip-mode behavior (preserved verbatim from prior implementation).
		actionButton.BackgroundColor3 = isEquipped and ACCENT_GOLD or rarityColor
		actionButton.BackgroundTransparency = 0.1
		actionButton.Text = isEquipped and "EQUIPPED" or "Equip"
		actionButton.TextColor3 = Color3.fromRGB(20, 20, 25)

		actionButton.Activated:Connect(function()
			if equippedPetId == entry.id then
				EquipPetEvent:FireServer(nil)
			else
				EquipPetEvent:FireServer(entry.id)
			end

			task.delay(0.15, function()
				refreshInventory()
			end)
		end)
	end

	return card
end

-- Update header + empty-state text + title to reflect the current mode.
-- Called from renderInventory (mode-aware redraws) and from setFeedMode.
local function refreshHeaderForMode()
	if feedMode then
		titleLabel.Text = "🍖 FEEDING — Pet Collection"
		titleLabel.TextColor3 = FEED_HEADER_COLOR
		feedModeButton.Text = "Equip Mode"
		feedModeButton.BackgroundColor3 = Color3.fromRGB(40, 50, 35)
		feedModeStroke.Color = FEED_HEADER_COLOR
		if feedTargetId then
			local target = findPetById(feedTargetId)
			if target then
				inventoryHeader.Text = string.format(
					"🍖 Feeding %s — pick a same-species sacrifice (gold border)",
					tostring(target.name))
			else
				inventoryHeader.Text = "🍖 Feed Mode — pick a target pet"
			end
		else
			inventoryHeader.Text = "🍖 Feed Mode — pick a target pet"
		end
		inventoryHeader.TextColor3 = FEED_HEADER_COLOR
		emptyPlaceholder.Text = "No pets to feed yet."
	else
		titleLabel.Text = "🐾 Pet Collection"
		titleLabel.TextColor3 = TEXT_PRIMARY
		feedModeButton.Text = "🍖 Feed Mode"
		feedModeButton.BackgroundColor3 = Color3.fromRGB(50, 30, 30)
		feedModeStroke.Color = Color3.fromRGB(120, 60, 60)
		inventoryHeader.Text = "Your Pets"
		inventoryHeader.TextColor3 = TEXT_MUTED
		emptyPlaceholder.Text = "Hatch your first egg below!"
	end
end

renderInventory = function()
	-- Clear existing cards (keep UIGridLayout / UIPadding)
	for _, child in ipairs(inventoryScroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	refreshHeaderForMode()

	if #inventoryPets == 0 then
		emptyPlaceholder.Visible = true
		inventoryScroll.Visible = false
		updateToggleBadge()
		return
	end

	-- Single-pet edge case in feed mode — duplicates are required, so warn.
	if feedMode and #inventoryPets == 1 then
		emptyPlaceholder.Visible = true
		emptyPlaceholder.Text = "Need duplicates to feed."
		inventoryScroll.Visible = true
	else
		emptyPlaceholder.Visible = false
		inventoryScroll.Visible = true
	end

	-- Sort: equipped first, then by rarity strength, then by id
	local rarityRank = {
		Mythic = 6, Legendary = 5, Epic = 4, Rare = 3, Uncommon = 2, Common = 1,
	}
	local pets = table.clone(inventoryPets)
	table.sort(pets, function(a, b)
		if (a.id == equippedPetId) ~= (b.id == equippedPetId) then
			return a.id == equippedPetId
		end
		local ra = rarityRank[a.rarity] or 0
		local rb = rarityRank[b.rarity] or 0
		if ra ~= rb then return ra > rb end
		return a.id < b.id
	end)

	for index, entry in ipairs(pets) do
		local card = buildPetCard(entry)
		card.LayoutOrder = index
		card.Parent = inventoryScroll
	end

	updateToggleBadge()
end

-- ═══════════════════════════════════════════════════════════════════
-- Feed Mode flow
-- ═══════════════════════════════════════════════════════════════════

local function clearFeedSelection()
	feedTargetId = nil
	feedSacrificeId = nil
end

local function hideFeedConfirm()
	feedConfirmActive = false
	feedConfirm.Visible = false
end

local function showFeedConfirm(target, sacrifice)
	feedConfirmActive = true
	feedConfirmText.Text = string.format(
		"Feed %s (Lv %d) to %s (Lv %d)?\nThe target will gain XP and may level up. The sacrifice will be consumed permanently.",
		tostring(sacrifice.name), sacrifice.level or 1,
		tostring(target.name), target.level or 1)
	feedConfirm.Visible = true
end

handleFeedCardClick = function(entry)
	if not feedMode or feedConfirmActive then
		return
	end

	-- No selections yet → set as target (if not maxed).
	if feedTargetId == nil then
		if (entry.level or 1) >= MAX_PET_LEVEL then
			-- Max-level pets can't gain XP; ignore the click silently
			-- (the card is already greyed with the MAX badge).
			return
		end
		feedTargetId = entry.id
		renderInventory()
		return
	end

	-- Clicking the existing target again deselects it (back to step 1).
	if feedTargetId == entry.id then
		clearFeedSelection()
		renderInventory()
		return
	end

	-- Have a target, picking a sacrifice. Must be same-species.
	local target = findPetById(feedTargetId)
	if not target then
		-- Target vanished (e.g. inventory refresh raced) — restart.
		clearFeedSelection()
		renderInventory()
		return
	end

	if entry.name ~= target.name then
		-- Cross-species click while target picked — ignore (server would
		-- reject anyway). Card is already dimmed + non-interactive label.
		return
	end

	feedSacrificeId = entry.id
	renderInventory()
	showFeedConfirm(target, entry)
end

local function commitFeed()
	if not feedTargetId or not feedSacrificeId then
		hideFeedConfirm()
		return
	end

	local targetId = feedTargetId
	local sacrificeId = feedSacrificeId

	if FeedPetEvent then
		FeedPetEvent:FireServer(targetId, sacrificeId)
	end

	-- Reset selection state regardless — a successful feed makes the
	-- sacrifice id stale, and on failure the user can restart cleanly.
	clearFeedSelection()
	hideFeedConfirm()

	task.delay(0.2, function()
		refreshInventory()
	end)
end

local function setFeedMode(enabled)
	if not FeedPetEvent then
		-- Defensive: if the remote was never wired, ignore the toggle.
		feedMode = false
		feedModeButton.Visible = false
		return
	end

	feedMode = enabled and true or false
	clearFeedSelection()
	hideFeedConfirm()
	player:SetAttribute("PetFeedMode", feedMode)

	if panel.Visible then
		renderInventory()
	else
		refreshHeaderForMode()
	end
end

feedModeButton.Activated:Connect(function()
	setFeedMode(not feedMode)
end)

feedConfirmYes.Activated:Connect(function()
	commitFeed()
end)

feedConfirmNo.Activated:Connect(function()
	-- Cancel: drop the sacrifice, keep the target highlighted, stay in mode.
	feedSacrificeId = nil
	hideFeedConfirm()
	renderInventory()
end)

-- ═══════════════════════════════════════════════════════════════════
-- Inventory refresh + event handling
-- ═══════════════════════════════════════════════════════════════════

refreshInventory = function()
	local success, payload = pcall(function()
		return GetPetInventoryFunction:InvokeServer()
	end)
	if not success then
		warn("[PetGui] Failed to fetch pet inventory: " .. tostring(payload))
		return false
	end

	if not applyInventory(payload) then
		warn("[PetGui] Invalid pet inventory payload from server")
		return false
	end

	if panel.Visible then
		renderInventory()
	else
		updateToggleBadge()
	end

	return true
end

NotifyEvent.OnClientEvent:Connect(function(text, rarity)
	if type(text) ~= "string" then return end

	hatcheryStatus.Text = text
	hatcheryStatus.TextColor3 = RarityColors[rarity] or TEXT_MUTED
end)

UpdateHUDEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end

	local changed = false

	if payload.equippedPet ~= nil then
		if payload.equippedPet == false or payload.equippedPet == 0 then
			if equippedPetId ~= nil then
				equippedPetId = nil
				changed = true
			end
		else
			equippedPetId = payload.equippedPet
			changed = true
		end
	end

	if changed and panel.Visible then
		renderInventory()
	end
end)

-- ═══════════════════════════════════════════════════════════════════
-- Panel toggle + persistence + auto-refresh
-- ═══════════════════════════════════════════════════════════════════

local function setPanelVisible(visible)
	panel.Visible = visible
	player:SetAttribute("PetPanelOpen", visible)
	if visible then
		refreshInventory()
	end
end

toggleButton.Activated:Connect(function()
	setPanelVisible(not panel.Visible)
end)

closeButton.Activated:Connect(function()
	setPanelVisible(false)
end)

-- Restore from attribute on script load (preserves across CharacterAdded
-- because ResetOnSpawn = false on the ScreenGui).
local savedOpen = player:GetAttribute("PetPanelOpen")
if savedOpen == true then
	setPanelVisible(true)
end

-- Restore feed-mode preference (only meaningful if the remote loaded).
if FeedPetEvent then
	local savedFeedMode = player:GetAttribute("PetFeedMode")
	if savedFeedMode == true then
		setFeedMode(true)
	end
end

-- Auto-refresh inventory every 5 seconds while open. This keeps the
-- equipped-pet badge fresh in case multiple events landed in quick succession.
task.spawn(function()
	while true do
		task.wait(5)
		if panel.Visible then
			refreshInventory()
		end
	end
end)
