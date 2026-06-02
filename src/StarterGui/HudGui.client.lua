-- HudGui.client.lua — Heads-up display (coins, depth, tool, notifications)
-- Place in: StarterGui/HudGui (LocalScript)
--
-- Added in this version:
--   • Login streak display (top-left, below fragments counter)
--   • Gamepass status badges (row of small icons when passes are active)
--   • Friend dig-speed boost indicator
--   • Group supporter coin bonus indicator
--   • Shop button + gamepass shop panel

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local LOCAL_PLAY_SOUND_NAME = "DeepDigLocalPlaySound"

local LocalPlaySound = SoundService:FindFirstChild(LOCAL_PLAY_SOUND_NAME)
if not LocalPlaySound then
	LocalPlaySound = Instance.new("BindableEvent")
	LocalPlaySound.Name = LOCAL_PLAY_SOUND_NAME
	LocalPlaySound.Parent = SoundService
end

-- ═══════════════════════════════════════════════════════════════════
-- Create HUD
-- ═══════════════════════════════════════════════════════════════════

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeepDigHUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Top bar
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 50)
topBar.Position = UDim2.new(0, 0, 0, 0)
topBar.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
topBar.BackgroundTransparency = 0.3
topBar.BorderSizePixel = 0
topBar.Parent = screenGui

-- Coins display
local coinsLabel = Instance.new("TextLabel")
coinsLabel.Name = "Coins"
coinsLabel.Size = UDim2.new(0, 200, 1, 0)
coinsLabel.Position = UDim2.new(0, 20, 0, 0)
coinsLabel.BackgroundTransparency = 1
coinsLabel.Text = "🪙 50"
coinsLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
coinsLabel.TextSize = 22
coinsLabel.Font = Enum.Font.GothamBold
coinsLabel.TextXAlignment = Enum.TextXAlignment.Left
coinsLabel.Parent = topBar

-- ─── Coin counter pulse ──────────────────────────────────────────────────────
-- Scale-pop the coin label on every gain (gold), red pulse on losses
-- (upgrade purchases). Closure-scoped previousCoins so we only pulse on
-- a real delta, not on every UpdateHUD broadcast.

local COIN_TEXT_BASE_SIZE = coinsLabel.TextSize  -- 22
local previousCoinValue = nil
local coinPulseSequence = 0

local function pulseCoinLabel(direction)
	coinPulseSequence = coinPulseSequence + 1
	local sequence = coinPulseSequence

	-- Snap the label up large + tinted, then ease back to baseline.
	-- EasingStyle.Back gives the satisfying "pop and settle" feel.
	local accentColor = direction == "loss"
		and Color3.fromRGB(255, 90, 90)   -- red — coins spent
		or Color3.fromRGB(255, 230, 110)  -- bright gold — coins gained
	local restColor = Color3.fromRGB(255, 200, 50)

	coinsLabel.TextColor3 = accentColor
	coinsLabel.TextSize = COIN_TEXT_BASE_SIZE + 8

	local settle = TweenService:Create(
		coinsLabel,
		TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ TextSize = COIN_TEXT_BASE_SIZE, TextColor3 = restColor }
	)
	settle:Play()
	settle.Completed:Connect(function()
		if sequence ~= coinPulseSequence then return end
		coinsLabel.TextSize = COIN_TEXT_BASE_SIZE
		coinsLabel.TextColor3 = restColor
	end)
end

-- Depth display
local depthLabel = Instance.new("TextLabel")
depthLabel.Name = "Depth"
depthLabel.Size = UDim2.new(0, 200, 1, 0)
depthLabel.Position = UDim2.new(0.5, -100, 0, 0)
depthLabel.BackgroundTransparency = 1
depthLabel.Text = "⛏️ Surface"
depthLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
depthLabel.TextSize = 20
depthLabel.Font = Enum.Font.GothamMedium
depthLabel.TextXAlignment = Enum.TextXAlignment.Center
depthLabel.Parent = topBar

-- Tool display
local toolLabel = Instance.new("TextLabel")
toolLabel.Name = "Tool"
toolLabel.Size = UDim2.new(0, 250, 1, 0)
toolLabel.Position = UDim2.new(1, -270, 0, 0)
toolLabel.BackgroundTransparency = 1
toolLabel.Text = "🔧 Rusty Shovel"
toolLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
toolLabel.TextSize = 18
toolLabel.Font = Enum.Font.Gotham
toolLabel.TextXAlignment = Enum.TextXAlignment.Right
toolLabel.Parent = topBar

-- Blocks dug counter
local blocksLabel = Instance.new("TextLabel")
blocksLabel.Name = "Blocks"
blocksLabel.Size = UDim2.new(0, 150, 0, 25)
blocksLabel.Position = UDim2.new(0, 20, 0, 52)
blocksLabel.BackgroundTransparency = 1
blocksLabel.Text = "Blocks: 0"
blocksLabel.TextColor3 = Color3.fromRGB(140, 140, 140)
blocksLabel.TextSize = 14
blocksLabel.Font = Enum.Font.Gotham
blocksLabel.TextXAlignment = Enum.TextXAlignment.Left
blocksLabel.Parent = screenGui

-- Inventory count
local invLabel = Instance.new("TextLabel")
invLabel.Name = "Inventory"
invLabel.Size = UDim2.new(0, 150, 0, 25)
invLabel.Position = UDim2.new(0, 20, 0, 74)
invLabel.BackgroundTransparency = 1
invLabel.Text = "Items: 0"
invLabel.TextColor3 = Color3.fromRGB(140, 140, 140)
invLabel.TextSize = 14
invLabel.Font = Enum.Font.Gotham
invLabel.TextXAlignment = Enum.TextXAlignment.Left
invLabel.Parent = screenGui

local pulseSellAllButton = function() end
local setInventoryDisplay
do
	local currentInventoryCount = 0
	local currentInventoryCapacity = Config.DEFAULT_BACKPACK_CAPACITY
	local inventoryWasFull = false
	local normalColor = Color3.fromRGB(140, 140, 140)
	local warningColor = Color3.fromRGB(255, 190, 70)
	local fullColor = Color3.fromRGB(255, 80, 80)

	local function formatInventoryText(count, capacity)
		if capacity == "unlimited" then
			return "Items: " .. tostring(count) .. "/unlimited"
		end

		return "Items: " .. tostring(count) .. "/" .. tostring(capacity or Config.DEFAULT_BACKPACK_CAPACITY)
	end

	function setInventoryDisplay(count, capacity)
		if count ~= nil then
			currentInventoryCount = count
		end
		if capacity ~= nil then
			currentInventoryCapacity = capacity
		end

		invLabel.Text = formatInventoryText(currentInventoryCount, currentInventoryCapacity)

		if currentInventoryCapacity == "unlimited" then
			inventoryWasFull = false
			invLabel.TextColor3 = normalColor
			invLabel.Font = Enum.Font.Gotham
			return
		end

		local countNumber = tonumber(currentInventoryCount) or 0
		local capacityNumber = tonumber(currentInventoryCapacity) or Config.DEFAULT_BACKPACK_CAPACITY
		local isFull = capacityNumber > 0 and countNumber >= capacityNumber
		local isWarning = capacityNumber > 0 and countNumber / capacityNumber >= 0.8

		if isFull then
			invLabel.TextColor3 = fullColor
			invLabel.Font = Enum.Font.GothamBold
		elseif isWarning then
			invLabel.TextColor3 = warningColor
			invLabel.Font = Enum.Font.GothamBold
		else
			invLabel.TextColor3 = normalColor
			invLabel.Font = Enum.Font.Gotham
		end

		if isFull and not inventoryWasFull then
			pulseSellAllButton()
		end
		inventoryWasFull = isFull
	end
end

-- ─── Fragments counter ───────────────────────────────────────────────────────

local fragLabel = Instance.new("TextLabel")
fragLabel.Name = "Fragments"
fragLabel.Size = UDim2.new(0, 150, 0, 25)
fragLabel.Position = UDim2.new(0, 20, 0, 96)
fragLabel.BackgroundTransparency = 1
fragLabel.Text = "Fragments: 0"
fragLabel.TextColor3 = Color3.fromRGB(160, 80, 200)
fragLabel.TextSize = 14
fragLabel.Font = Enum.Font.GothamBold
fragLabel.TextXAlignment = Enum.TextXAlignment.Left
fragLabel.Parent = screenGui

local FRAGMENT_TEXT_BASE_SIZE = fragLabel.TextSize
local FRAGMENT_TEXT_REST_COLOR = Color3.fromRGB(160, 80, 200)
local previousFragmentValue = nil
local fragmentPulseSequence = 0

local function pulseFragmentLabel()
	fragmentPulseSequence = fragmentPulseSequence + 1
	local sequence = fragmentPulseSequence

	fragLabel.TextColor3 = Color3.fromRGB(230, 190, 255)
	fragLabel.TextSize = FRAGMENT_TEXT_BASE_SIZE + 5

	local settle = TweenService:Create(
		fragLabel,
		TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ TextSize = FRAGMENT_TEXT_BASE_SIZE, TextColor3 = FRAGMENT_TEXT_REST_COLOR }
	)
	settle:Play()
	settle.Completed:Connect(function()
		if sequence ~= fragmentPulseSequence then return end
		fragLabel.TextSize = FRAGMENT_TEXT_BASE_SIZE
		fragLabel.TextColor3 = FRAGMENT_TEXT_REST_COLOR
	end)
end

-- ─── Login streak display ────────────────────────────────────────────────────

local streakLabel = Instance.new("TextLabel")
streakLabel.Name = "LoginStreak"
streakLabel.Size = UDim2.new(0, 180, 0, 25)
streakLabel.Position = UDim2.new(0, 20, 0, 118)
streakLabel.BackgroundTransparency = 1
streakLabel.Text = "🔥 Streak: –"
streakLabel.TextColor3 = Color3.fromRGB(255, 140, 40)
streakLabel.TextSize = 14
streakLabel.Font = Enum.Font.GothamBold
streakLabel.TextXAlignment = Enum.TextXAlignment.Left
streakLabel.Parent = screenGui

local RequestStreakReviveEvent = Remotes:WaitForChild("RequestStreakRevive")

local currentLoginStreak = 0
local currentStreakReviveEligible = false
local currentStreakRevivePending = false
local currentStreakReviveBaseStreak = 0
local currentStreakRevivePrice = 50
local currentStreakReviveProductAvailable = Config.isStreakReviveProductIdValid(Config.STREAK_REVIVE_PRODUCT_ID)

local pulseStreakLabel
do
	local STREAK_TEXT_BASE_SIZE = streakLabel.TextSize
	local STREAK_TEXT_REST_COLOR = Color3.fromRGB(255, 140, 40)
	local streakPulseSequence = 0

	function pulseStreakLabel(milestone)
		streakPulseSequence = streakPulseSequence + 1
		local sequence = streakPulseSequence

		streakLabel.TextColor3 = milestone and Color3.fromRGB(255, 230, 110) or Color3.fromRGB(255, 185, 80)
		streakLabel.TextSize = STREAK_TEXT_BASE_SIZE + (milestone and 7 or 5)

		local settle = TweenService:Create(
			streakLabel,
			TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ TextSize = STREAK_TEXT_BASE_SIZE, TextColor3 = STREAK_TEXT_REST_COLOR }
		)
		settle:Play()
		settle.Completed:Connect(function()
			if sequence ~= streakPulseSequence then return end
			streakLabel.TextSize = STREAK_TEXT_BASE_SIZE
			streakLabel.TextColor3 = STREAK_TEXT_REST_COLOR
		end)
	end
end

local refreshEquippedPetChip
do
	local PET_RARITY_COLORS = {
		Common = Color3.fromRGB(205, 215, 210),
		Uncommon = Color3.fromRGB(95, 220, 130),
		Rare = Color3.fromRGB(90, 170, 255),
		Epic = Color3.fromRGB(190, 115, 255),
		Legendary = Color3.fromRGB(255, 205, 80),
		Mythic = Color3.fromRGB(255, 100, 150),
	}

	local petChip = Instance.new("Frame")
	petChip.Name = "EquippedPetBuff"
	petChip.Size = UDim2.new(0, 330, 0, 44)
	petChip.Position = UDim2.new(0, 210, 0, 52)
	petChip.BackgroundColor3 = Color3.fromRGB(28, 24, 34)
	petChip.BackgroundTransparency = 0.08
	petChip.BorderSizePixel = 0
	petChip.Visible = false
	petChip.Parent = screenGui

	local petChipCorner = Instance.new("UICorner")
	petChipCorner.CornerRadius = UDim.new(0, 7)
	petChipCorner.Parent = petChip

	local petChipStroke = Instance.new("UIStroke")
	petChipStroke.Color = Color3.fromRGB(130, 110, 180)
	petChipStroke.Thickness = 1
	petChipStroke.Transparency = 0.2
	petChipStroke.Parent = petChip

	local petNameLabel = Instance.new("TextLabel")
	petNameLabel.Name = "PetName"
	petNameLabel.Size = UDim2.new(1, -18, 0, 20)
	petNameLabel.Position = UDim2.new(0, 9, 0, 4)
	petNameLabel.BackgroundTransparency = 1
	petNameLabel.Text = ""
	petNameLabel.TextColor3 = Color3.fromRGB(235, 230, 245)
	petNameLabel.TextSize = 13
	petNameLabel.Font = Enum.Font.GothamBlack
	petNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	petNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	petNameLabel.Parent = petChip

	local petBonusLabel = Instance.new("TextLabel")
	petBonusLabel.Name = "PetBonuses"
	petBonusLabel.Size = UDim2.new(1, -18, 0, 18)
	petBonusLabel.Position = UDim2.new(0, 9, 0, 23)
	petBonusLabel.BackgroundTransparency = 1
	petBonusLabel.Text = ""
	petBonusLabel.TextColor3 = Color3.fromRGB(220, 210, 235)
	petBonusLabel.TextSize = 12
	petBonusLabel.Font = Enum.Font.GothamBold
	petBonusLabel.TextXAlignment = Enum.TextXAlignment.Left
	petBonusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	petBonusLabel.Parent = petChip

	local function formatBoost(multiplier)
		local boost = math.max(0, math.floor(((tonumber(multiplier) or 1) - 1) * 100 + 0.5))
		return "+" .. tostring(boost) .. "%"
	end

	local equippedPetChipState = {
		equippedPet = nil,
		petName = nil,
		petRarity = nil,
		petLevel = nil,
		petMultipliers = nil,
		petCount = 0,
	}

	function refreshEquippedPetChip(data)
		if not data then
			return
		end

		if data.equippedPet == false then
			equippedPetChipState.equippedPet = nil
			equippedPetChipState.petName = nil
			equippedPetChipState.petRarity = nil
			equippedPetChipState.petLevel = nil
			equippedPetChipState.petMultipliers = nil
			equippedPetChipState.petCount = tonumber(data.petCount) or 0
			petChip.Visible = false
			return
		end

		if data.equippedPet ~= nil then
			equippedPetChipState.equippedPet = data.equippedPet
		end
		if data.petName ~= nil then
			equippedPetChipState.petName = data.petName
		end
		if data.petRarity ~= nil then
			equippedPetChipState.petRarity = data.petRarity
		end
		if data.petLevel ~= nil then
			equippedPetChipState.petLevel = data.petLevel
		end
		if data.petMultipliers ~= nil then
			equippedPetChipState.petMultipliers = data.petMultipliers
		end
		if data.petCount ~= nil then
			equippedPetChipState.petCount = tonumber(data.petCount) or 0
		end

		if type(equippedPetChipState.petName) ~= "string"
			or type(equippedPetChipState.petMultipliers) ~= "table" then
			petChip.Visible = false
			return
		end

		local rarity = equippedPetChipState.petRarity or "Common"
		local level = tonumber(equippedPetChipState.petLevel) or 1
		local count = tonumber(equippedPetChipState.petCount) or 0
		local countSuffix = count > 1 and (" • " .. tostring(count) .. " pets") or ""
		local rarityColor = PET_RARITY_COLORS[rarity] or Color3.fromRGB(235, 230, 245)

		petNameLabel.Text = "🐾 " .. rarity .. " " .. equippedPetChipState.petName
			.. " Lv " .. tostring(level) .. countSuffix
		petNameLabel.TextColor3 = rarityColor
		petBonusLabel.Text = "Dig " .. formatBoost(equippedPetChipState.petMultipliers.dig_speed)
			.. "   Loot " .. formatBoost(equippedPetChipState.petMultipliers.loot_value)
			.. "   Luck " .. formatBoost(equippedPetChipState.petMultipliers.luck)
		petChipStroke.Color = rarityColor
		petChip.Visible = true
	end
end

-- ─── Gamepass badge row ──────────────────────────────────────────────────────
-- Small pills shown when a gamepass is active.

local badgeRow = Instance.new("Frame")
badgeRow.Name = "PassBadges"
badgeRow.Size = UDim2.new(0, 620, 0, 24)
badgeRow.Position = UDim2.new(0, 20, 0, 142)
badgeRow.BackgroundTransparency = 1
badgeRow.Parent = screenGui

local badgeLayout = Instance.new("UIListLayout")
badgeLayout.FillDirection = Enum.FillDirection.Horizontal
badgeLayout.SortOrder = Enum.SortOrder.LayoutOrder
badgeLayout.Padding = UDim.new(0, 4)
badgeLayout.Parent = badgeRow

local friendBoostLabel = Instance.new("TextLabel")
friendBoostLabel.Name = "FriendBoost"
friendBoostLabel.Size = UDim2.new(0, 172, 0, 22)
friendBoostLabel.Position = UDim2.new(0, 20, 0, 168)
friendBoostLabel.BackgroundColor3 = Color3.fromRGB(70, 205, 150)
friendBoostLabel.BackgroundTransparency = 0.15
friendBoostLabel.BorderSizePixel = 0
friendBoostLabel.Text = "Friend Boost +5% Speed"
friendBoostLabel.TextColor3 = Color3.fromRGB(10, 35, 24)
friendBoostLabel.TextSize = 12
friendBoostLabel.Font = Enum.Font.GothamBlack
friendBoostLabel.TextXAlignment = Enum.TextXAlignment.Center
friendBoostLabel.Visible = false
friendBoostLabel.Parent = screenGui

local friendBoostCorner = Instance.new("UICorner")
friendBoostCorner.CornerRadius = UDim.new(0, 5)
friendBoostCorner.Parent = friendBoostLabel

local groupBenefitLabel = Instance.new("TextLabel")
groupBenefitLabel.Name = "GroupBenefit"
groupBenefitLabel.Size = UDim2.new(0, 178, 0, 22)
groupBenefitLabel.Position = UDim2.new(0, 20, 0, 194)
groupBenefitLabel.BackgroundColor3 = Config.GROUP_BENEFIT_DISPLAY_COLOR
groupBenefitLabel.BackgroundTransparency = 0.15
groupBenefitLabel.BorderSizePixel = 0
groupBenefitLabel.Text = "Group +10% Coins"
groupBenefitLabel.TextColor3 = Color3.fromRGB(5, 25, 35)
groupBenefitLabel.TextSize = 12
groupBenefitLabel.Font = Enum.Font.GothamBlack
groupBenefitLabel.TextXAlignment = Enum.TextXAlignment.Center
groupBenefitLabel.Visible = false
groupBenefitLabel.Parent = screenGui

local groupBenefitCorner = Instance.new("UICorner")
groupBenefitCorner.CornerRadius = UDim.new(0, 5)
groupBenefitCorner.Parent = groupBenefitLabel

local SEASON_BADGE_STYLES = {
	halloween_loot = {
		title = "Bone Hunt",
		detail = "Skeletal items boosted",
		background = Color3.fromRGB(70, 38, 24),
		stroke = Color3.fromRGB(255, 130, 45),
		titleColor = Color3.fromRGB(255, 205, 130),
		detailColor = Color3.fromRGB(255, 230, 190),
	},
	winter_loot = {
		title = "Frozen Depths",
		detail = "Ice relics awakened",
		background = Color3.fromRGB(26, 58, 78),
		stroke = Color3.fromRGB(120, 220, 255),
		titleColor = Color3.fromRGB(190, 245, 255),
		detailColor = Color3.fromRGB(220, 250, 255),
	},
	spring_loot = {
		title = "Spring: Fossil Rush",
		detail = "+1 fragment while digging",
		background = Color3.fromRGB(30, 72, 46),
		stroke = Color3.fromRGB(95, 230, 120),
		titleColor = Color3.fromRGB(190, 255, 195),
		detailColor = Color3.fromRGB(225, 255, 220),
	},
	summer_loot = {
		title = "Sun-Drenched Dig",
		detail = "More world events",
		background = Color3.fromRGB(86, 54, 22),
		stroke = Color3.fromRGB(255, 190, 70),
		titleColor = Color3.fromRGB(255, 230, 150),
		detailColor = Color3.fromRGB(255, 240, 205),
	},
}

local seasonBadge = Instance.new("Frame")
seasonBadge.Name = "ActiveSeasonBadge"
seasonBadge.Size = UDim2.new(0, 220, 0, 48)
seasonBadge.Position = UDim2.new(0, 20, 0, 220)
seasonBadge.BackgroundColor3 = Color3.fromRGB(30, 72, 46)
seasonBadge.BackgroundTransparency = 0.1
seasonBadge.BorderSizePixel = 0
seasonBadge.Visible = false
seasonBadge.Parent = screenGui

local seasonBadgeCorner = Instance.new("UICorner")
seasonBadgeCorner.CornerRadius = UDim.new(0, 7)
seasonBadgeCorner.Parent = seasonBadge

local seasonBadgeStroke = Instance.new("UIStroke")
seasonBadgeStroke.Thickness = 2
seasonBadgeStroke.Color = Color3.fromRGB(95, 230, 120)
seasonBadgeStroke.Parent = seasonBadge

local seasonBadgeTitle = Instance.new("TextLabel")
seasonBadgeTitle.Name = "Title"
seasonBadgeTitle.Size = UDim2.new(1, -20, 0, 22)
seasonBadgeTitle.Position = UDim2.new(0, 10, 0, 5)
seasonBadgeTitle.BackgroundTransparency = 1
seasonBadgeTitle.Text = ""
seasonBadgeTitle.TextColor3 = Color3.fromRGB(190, 255, 195)
seasonBadgeTitle.TextSize = 14
seasonBadgeTitle.Font = Enum.Font.GothamBlack
seasonBadgeTitle.TextXAlignment = Enum.TextXAlignment.Left
seasonBadgeTitle.Parent = seasonBadge

local seasonBadgeDetail = Instance.new("TextLabel")
seasonBadgeDetail.Name = "Detail"
seasonBadgeDetail.Size = UDim2.new(1, -20, 0, 18)
seasonBadgeDetail.Position = UDim2.new(0, 10, 0, 26)
seasonBadgeDetail.BackgroundTransparency = 1
seasonBadgeDetail.Text = ""
seasonBadgeDetail.TextColor3 = Color3.fromRGB(225, 255, 220)
seasonBadgeDetail.TextSize = 12
seasonBadgeDetail.Font = Enum.Font.GothamBold
seasonBadgeDetail.TextXAlignment = Enum.TextXAlignment.Left
seasonBadgeDetail.Parent = seasonBadge

DeepDigActiveEventHud = {
	token = 0,
	fadeTween = nil,
	seasonalEffects = {
		halloween_loot = true,
		winter_loot = true,
		spring_loot = true,
		summer_loot = true,
	},
	styles = {
		["2x_rare"] = {
			accent = Color3.fromRGB(115, 175, 255),
			background = Color3.fromRGB(22, 38, 66),
			title = "Fossil Layer",
			detail = "2x rare finds",
		},
		bonus_loot = {
			accent = Color3.fromRGB(130, 230, 180),
			background = Color3.fromRGB(20, 55, 42),
			title = "Cave System",
			detail = "Bonus loot",
		},
		gold_rush = {
			accent = Color3.fromRGB(255, 200, 70),
			background = Color3.fromRGB(72, 48, 18),
			title = "Gold Vein",
			detail = "3x sell value",
		},
		lucky_hour = {
			accent = Color3.fromRGB(120, 235, 95),
			background = Color3.fromRGB(28, 62, 34),
			title = "Lucky Hour",
			detail = "Loot luck boosted",
		},
		echo_blocks = {
			accent = Color3.fromRGB(190, 145, 255),
			background = Color3.fromRGB(44, 34, 66),
			title = "Echoes from Below",
			detail = "Legendary chance up",
		},
		earthquake = {
			accent = Color3.fromRGB(255, 120, 75),
			background = Color3.fromRGB(72, 34, 24),
			title = "Earthquake",
			detail = "Bonus rumble coins",
		},
		instant_dig = {
			accent = Color3.fromRGB(255, 145, 90),
			background = Color3.fromRGB(70, 38, 26),
			title = "Earthquake",
			detail = "Layers crumbling",
		},
		halloween_loot = {
			accent = SEASON_BADGE_STYLES.halloween_loot.stroke,
			background = SEASON_BADGE_STYLES.halloween_loot.background,
			title = SEASON_BADGE_STYLES.halloween_loot.title,
			detail = SEASON_BADGE_STYLES.halloween_loot.detail,
		},
		winter_loot = {
			accent = SEASON_BADGE_STYLES.winter_loot.stroke,
			background = SEASON_BADGE_STYLES.winter_loot.background,
			title = SEASON_BADGE_STYLES.winter_loot.title,
			detail = SEASON_BADGE_STYLES.winter_loot.detail,
		},
		spring_loot = {
			accent = SEASON_BADGE_STYLES.spring_loot.stroke,
			background = SEASON_BADGE_STYLES.spring_loot.background,
			title = SEASON_BADGE_STYLES.spring_loot.title,
			detail = SEASON_BADGE_STYLES.spring_loot.detail,
		},
		summer_loot = {
			accent = SEASON_BADGE_STYLES.summer_loot.stroke,
			background = SEASON_BADGE_STYLES.summer_loot.background,
			title = SEASON_BADGE_STYLES.summer_loot.title,
			detail = SEASON_BADGE_STYLES.summer_loot.detail,
		},
		fallback = {
			accent = Color3.fromRGB(220, 220, 230),
			background = Color3.fromRGB(34, 36, 46),
			title = "World Event",
			detail = "Temporary buff",
		},
	},
}

do
	local activeEventHud = DeepDigActiveEventHud

	activeEventHud.frame = Instance.new("Frame")
	activeEventHud.frame.Name = "ActiveEventPill"
	activeEventHud.frame.Size = UDim2.new(0, 270, 0, 38)
	activeEventHud.frame.Position = UDim2.new(1, -290, 0, 58)
	activeEventHud.frame.BackgroundColor3 = activeEventHud.styles.fallback.background
	activeEventHud.frame.BackgroundTransparency = 0.08
	activeEventHud.frame.BorderSizePixel = 0
	activeEventHud.frame.Visible = false
	activeEventHud.frame.Parent = screenGui

	activeEventHud.corner = Instance.new("UICorner")
	activeEventHud.corner.CornerRadius = UDim.new(0, 7)
	activeEventHud.corner.Parent = activeEventHud.frame

	activeEventHud.stroke = Instance.new("UIStroke")
	activeEventHud.stroke.Thickness = 2
	activeEventHud.stroke.Color = activeEventHud.styles.fallback.accent
	activeEventHud.stroke.Transparency = 0.15
	activeEventHud.stroke.Parent = activeEventHud.frame

	activeEventHud.title = Instance.new("TextLabel")
	activeEventHud.title.Name = "Title"
	activeEventHud.title.Size = UDim2.new(1, -72, 0, 18)
	activeEventHud.title.Position = UDim2.new(0, 11, 0, 4)
	activeEventHud.title.BackgroundTransparency = 1
	activeEventHud.title.Text = ""
	activeEventHud.title.TextColor3 = Color3.fromRGB(255, 255, 255)
	activeEventHud.title.TextSize = 13
	activeEventHud.title.Font = Enum.Font.GothamBlack
	activeEventHud.title.TextXAlignment = Enum.TextXAlignment.Left
	activeEventHud.title.TextTruncate = Enum.TextTruncate.AtEnd
	activeEventHud.title.Parent = activeEventHud.frame

	activeEventHud.detail = Instance.new("TextLabel")
	activeEventHud.detail.Name = "Detail"
	activeEventHud.detail.Size = UDim2.new(1, -72, 0, 15)
	activeEventHud.detail.Position = UDim2.new(0, 11, 0, 21)
	activeEventHud.detail.BackgroundTransparency = 1
	activeEventHud.detail.Text = ""
	activeEventHud.detail.TextColor3 = Color3.fromRGB(220, 225, 235)
	activeEventHud.detail.TextSize = 11
	activeEventHud.detail.Font = Enum.Font.GothamBold
	activeEventHud.detail.TextXAlignment = Enum.TextXAlignment.Left
	activeEventHud.detail.TextTruncate = Enum.TextTruncate.AtEnd
	activeEventHud.detail.Parent = activeEventHud.frame

	activeEventHud.timer = Instance.new("TextLabel")
	activeEventHud.timer.Name = "Timer"
	activeEventHud.timer.Size = UDim2.new(0, 52, 0, 28)
	activeEventHud.timer.Position = UDim2.new(1, -60, 0, 5)
	activeEventHud.timer.BackgroundTransparency = 1
	activeEventHud.timer.Text = "0s"
	activeEventHud.timer.TextColor3 = activeEventHud.styles.fallback.accent
	activeEventHud.timer.TextSize = 16
	activeEventHud.timer.Font = Enum.Font.GothamBlack
	activeEventHud.timer.TextXAlignment = Enum.TextXAlignment.Right
	activeEventHud.timer.Parent = activeEventHud.frame

	local function restoreActiveEventPillTransparency()
		activeEventHud.frame.BackgroundTransparency = 0.08
		activeEventHud.stroke.Transparency = 0.15
		activeEventHud.title.TextTransparency = 0
		activeEventHud.detail.TextTransparency = 0
		activeEventHud.timer.TextTransparency = 0
	end

	local function fadeActiveEventPill(token)
		if token ~= activeEventHud.token then
			return
		end

		activeEventHud.fadeTween = TweenService:Create(
			activeEventHud.frame,
			TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)
		local strokeFade = TweenService:Create(activeEventHud.stroke, TweenInfo.new(0.35), { Transparency = 1 })
		local titleFade = TweenService:Create(activeEventHud.title, TweenInfo.new(0.35), { TextTransparency = 1 })
		local detailFade = TweenService:Create(activeEventHud.detail, TweenInfo.new(0.35), { TextTransparency = 1 })
		local timerFade = TweenService:Create(activeEventHud.timer, TweenInfo.new(0.35), { TextTransparency = 1 })

		activeEventHud.fadeTween:Play()
		strokeFade:Play()
		titleFade:Play()
		detailFade:Play()
		timerFade:Play()
		activeEventHud.fadeTween.Completed:Connect(function()
			if token ~= activeEventHud.token then
				return
			end
			activeEventHud.frame.Visible = false
			restoreActiveEventPillTransparency()
		end)
	end

	function activeEventHud.show(eventName, message, duration, effectId)
		activeEventHud.token = activeEventHud.token + 1
		local token = activeEventHud.token
		local style = activeEventHud.styles[effectId] or activeEventHud.styles.fallback
		local remainingSeconds = math.max(0, math.floor(tonumber(duration) or 0))
		local isSeasonalEffect = activeEventHud.seasonalEffects[effectId] == true

		if activeEventHud.fadeTween then
			activeEventHud.fadeTween:Cancel()
			activeEventHud.fadeTween = nil
		end

		restoreActiveEventPillTransparency()
		activeEventHud.frame.BackgroundColor3 = style.background
		activeEventHud.stroke.Color = style.accent
		activeEventHud.timer.TextColor3 = style.accent
		activeEventHud.title.Text = tostring(eventName or style.title)
		activeEventHud.detail.Text = style.detail or tostring(message or "Temporary buff")
		activeEventHud.timer.TextSize = isSeasonalEffect and 12 or 16
		activeEventHud.timer.Text = isSeasonalEffect and "All month" or tostring(remainingSeconds) .. "s"
		activeEventHud.frame.Visible = true

		if isSeasonalEffect then
			return
		end

		task.spawn(function()
			local endsAt = os.clock() + remainingSeconds
			while token == activeEventHud.token do
				remainingSeconds = math.max(0, math.ceil(endsAt - os.clock()))
				activeEventHud.timer.Text = tostring(remainingSeconds) .. "s"

				if remainingSeconds <= 0 then
					break
				end

				task.wait(0.25)
			end

			fadeActiveEventPill(token)
		end)
	end
end

local halloweenAmbienceLayer = Instance.new("Frame")
halloweenAmbienceLayer.Name = "HalloweenAmbience"
halloweenAmbienceLayer.Size = UDim2.new(1, 0, 1, 0)
halloweenAmbienceLayer.Position = UDim2.new(0, 0, 0, 0)
halloweenAmbienceLayer.BackgroundTransparency = 1
halloweenAmbienceLayer.BorderSizePixel = 0
halloweenAmbienceLayer.Active = false
halloweenAmbienceLayer.Visible = false
halloweenAmbienceLayer.ZIndex = 6
halloweenAmbienceLayer.Parent = screenGui

local halloweenAmbienceEdges = {}

local function createHalloweenAmbienceEdge(name, position, size, color, gradientRotation, targetTransparency)
	local edge = Instance.new("Frame")
	edge.Name = name
	edge.Size = size
	edge.Position = position
	edge.BackgroundColor3 = color
	edge.BackgroundTransparency = 1
	edge.BorderSizePixel = 0
	edge.Active = false
	edge.ZIndex = 6
	edge.Parent = halloweenAmbienceLayer

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = gradientRotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = edge

	table.insert(halloweenAmbienceEdges, {
		frame = edge,
		targetTransparency = targetTransparency,
	})
end

createHalloweenAmbienceEdge(
	"TopPurpleVignette",
	UDim2.new(0, 0, 0, 0),
	UDim2.new(1, 0, 0.18, 0),
	Color3.fromRGB(105, 45, 170),
	90,
	0.78
)
createHalloweenAmbienceEdge(
	"BottomOrangeVignette",
	UDim2.new(0, 0, 0.82, 0),
	UDim2.new(1, 0, 0.18, 0),
	Color3.fromRGB(210, 92, 28),
	-90,
	0.80
)
createHalloweenAmbienceEdge(
	"LeftPurpleVignette",
	UDim2.new(0, 0, 0, 0),
	UDim2.new(0.14, 0, 1, 0),
	Color3.fromRGB(86, 36, 150),
	0,
	0.82
)
createHalloweenAmbienceEdge(
	"RightOrangeVignette",
	UDim2.new(0.86, 0, 0, 0),
	UDim2.new(0.14, 0, 1, 0),
	Color3.fromRGB(190, 74, 24),
	180,
	0.84
)

local setHalloweenAmbienceActive
do
	local effectName = "DeepDigHalloweenAmbience"
	local halloweenAmbienceEffect = Lighting:FindFirstChild(effectName)
	local halloweenAmbienceActive = false
	local halloweenAmbienceSequence = 0
	local halloweenAmbiencePulseWarm = false
	local halloweenAmbienceTweens = {}

	if halloweenAmbienceEffect and not halloweenAmbienceEffect:IsA("ColorCorrectionEffect") then
		halloweenAmbienceEffect = nil
	end

	local function clearHalloweenAmbienceTweens()
		for _, tween in ipairs(halloweenAmbienceTweens) do
			tween:Cancel()
		end
		halloweenAmbienceTweens = {}
	end

	local function tweenHalloweenAmbience(instance, duration, goal)
		local tween = TweenService:Create(
			instance,
			TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			goal
		)
		table.insert(halloweenAmbienceTweens, tween)
		tween:Play()
		return tween
	end

	local function getHalloweenAmbienceEffect(createIfMissing)
		if halloweenAmbienceEffect and halloweenAmbienceEffect.Parent == Lighting then
			return halloweenAmbienceEffect
		end

		halloweenAmbienceEffect = Lighting:FindFirstChild(effectName)
		if halloweenAmbienceEffect and not halloweenAmbienceEffect:IsA("ColorCorrectionEffect") then
			halloweenAmbienceEffect = nil
		end

		if not halloweenAmbienceEffect and createIfMissing then
			halloweenAmbienceEffect = Instance.new("ColorCorrectionEffect")
			halloweenAmbienceEffect.Name = effectName
			halloweenAmbienceEffect.TintColor = Color3.fromRGB(255, 255, 255)
			halloweenAmbienceEffect.Brightness = 0
			halloweenAmbienceEffect.Contrast = 0
			halloweenAmbienceEffect.Saturation = 0
			halloweenAmbienceEffect.Enabled = false
			halloweenAmbienceEffect.Parent = Lighting
		end

		return halloweenAmbienceEffect
	end

	local function scheduleHalloweenAmbiencePulse(sequence)
		task.delay(1.6, function()
			if sequence ~= halloweenAmbienceSequence or not halloweenAmbienceActive then
				return
			end

			clearHalloweenAmbienceTweens()
			halloweenAmbiencePulseWarm = not halloweenAmbiencePulseWarm

			for _, edge in ipairs(halloweenAmbienceEdges) do
				local pulseTransparency = edge.targetTransparency + (halloweenAmbiencePulseWarm and -0.035 or 0.025)
				tweenHalloweenAmbience(edge.frame, 2.2, {
					BackgroundTransparency = math.clamp(pulseTransparency, 0.72, 0.9),
				})
			end

			local effect = getHalloweenAmbienceEffect(true)
			if effect then
				effect.Enabled = true
				local pulse = tweenHalloweenAmbience(effect, 2.2, {
					TintColor = halloweenAmbiencePulseWarm and Color3.fromRGB(255, 230, 214) or Color3.fromRGB(238, 220, 255),
					Brightness = halloweenAmbiencePulseWarm and -0.015 or -0.035,
					Contrast = halloweenAmbiencePulseWarm and 0.035 or 0.02,
					Saturation = halloweenAmbiencePulseWarm and -0.04 or -0.07,
				})
				pulse.Completed:Connect(function(playbackState)
					if playbackState ~= Enum.PlaybackState.Completed or sequence ~= halloweenAmbienceSequence then
						return
					end
					scheduleHalloweenAmbiencePulse(sequence)
				end)
			end
		end)
	end

	function setHalloweenAmbienceActive(active)
		if active == halloweenAmbienceActive and active == false then
			return
		end

		halloweenAmbienceActive = active == true
		halloweenAmbienceSequence = halloweenAmbienceSequence + 1
		local sequence = halloweenAmbienceSequence

		clearHalloweenAmbienceTweens()

		if halloweenAmbienceActive then
			halloweenAmbienceLayer.Visible = true

			for _, edge in ipairs(halloweenAmbienceEdges) do
				tweenHalloweenAmbience(edge.frame, 0.75, {
					BackgroundTransparency = edge.targetTransparency,
				})
			end

			local effect = getHalloweenAmbienceEffect(true)
			if effect then
				effect.Enabled = true
				local fadeIn = tweenHalloweenAmbience(effect, 0.75, {
					TintColor = Color3.fromRGB(246, 226, 255),
					Brightness = -0.025,
					Contrast = 0.025,
					Saturation = -0.05,
				})
				fadeIn.Completed:Connect(function(playbackState)
					if playbackState ~= Enum.PlaybackState.Completed or sequence ~= halloweenAmbienceSequence then
						return
					end
					scheduleHalloweenAmbiencePulse(sequence)
				end)
			end

			return
		end

		for _, edge in ipairs(halloweenAmbienceEdges) do
			tweenHalloweenAmbience(edge.frame, 0.55, {
				BackgroundTransparency = 1,
			})
		end

		local effect = getHalloweenAmbienceEffect(false)
		local fadeOut = nil
		if effect then
			fadeOut = tweenHalloweenAmbience(effect, 0.55, {
				TintColor = Color3.fromRGB(255, 255, 255),
				Brightness = 0,
				Contrast = 0,
				Saturation = 0,
			})
		end

		local function finishFadeOut()
			if sequence ~= halloweenAmbienceSequence then
				return
			end

			halloweenAmbienceLayer.Visible = false
			if effect then
				effect.Enabled = false
			end
		end

		if fadeOut then
			fadeOut.Completed:Connect(function()
				finishFadeOut()
			end)
		else
			task.delay(0.55, finishFadeOut)
		end
	end
end

local function createSpringAmbienceController()
local springAmbienceLayer = Instance.new("Frame")
springAmbienceLayer.Name = "SpringAmbience"
springAmbienceLayer.Size = UDim2.new(1, 0, 1, 0)
springAmbienceLayer.Position = UDim2.new(0, 0, 0, 0)
springAmbienceLayer.BackgroundTransparency = 1
springAmbienceLayer.BorderSizePixel = 0
springAmbienceLayer.Active = false
springAmbienceLayer.Visible = false
springAmbienceLayer.ZIndex = 5
springAmbienceLayer.Parent = screenGui

local springAmbienceEdges = {}

local function createSpringAmbienceEdge(name, position, size, color, gradientRotation, targetTransparency)
	local edge = Instance.new("Frame")
	edge.Name = name
	edge.Size = size
	edge.Position = position
	edge.BackgroundColor3 = color
	edge.BackgroundTransparency = 1
	edge.BorderSizePixel = 0
	edge.Active = false
	edge.ZIndex = 5
	edge.Parent = springAmbienceLayer

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = gradientRotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = edge

	table.insert(springAmbienceEdges, {
		frame = edge,
		targetTransparency = targetTransparency,
	})
end

createSpringAmbienceEdge(
	"TopGoldVignette",
	UDim2.new(0, 0, 0, 0),
	UDim2.new(1, 0, 0.16, 0),
	Color3.fromRGB(245, 214, 92),
	90,
	0.87
)
createSpringAmbienceEdge(
	"BottomGreenVignette",
	UDim2.new(0, 0, 0.84, 0),
	UDim2.new(1, 0, 0.16, 0),
	Color3.fromRGB(94, 198, 86),
	-90,
	0.88
)
createSpringAmbienceEdge(
	"LeftGreenVignette",
	UDim2.new(0, 0, 0, 0),
	UDim2.new(0.12, 0, 1, 0),
	Color3.fromRGB(72, 180, 96),
	0,
	0.90
)
createSpringAmbienceEdge(
	"RightGoldVignette",
	UDim2.new(0.88, 0, 0, 0),
	UDim2.new(0.12, 0, 1, 0),
	Color3.fromRGB(230, 190, 70),
	180,
	0.90
)

	local effectName = "DeepDigSpringAmbience"
	local springAmbienceEffect = Lighting:FindFirstChild(effectName)
	local springAmbienceActive = false
	local springAmbienceSequence = 0
	local springAmbiencePulseGold = false
	local springAmbienceTweens = {}

	if springAmbienceEffect and not springAmbienceEffect:IsA("ColorCorrectionEffect") then
		springAmbienceEffect = nil
	end

	local function clearSpringAmbienceTweens()
		for _, tween in ipairs(springAmbienceTweens) do
			tween:Cancel()
		end
		springAmbienceTweens = {}
	end

	local function tweenSpringAmbience(instance, duration, goal)
		local tween = TweenService:Create(
			instance,
			TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			goal
		)
		table.insert(springAmbienceTweens, tween)
		tween:Play()
		return tween
	end

	local function getSpringAmbienceEffect(createIfMissing)
		if springAmbienceEffect and springAmbienceEffect.Parent == Lighting then
			return springAmbienceEffect
		end

		springAmbienceEffect = Lighting:FindFirstChild(effectName)
		if springAmbienceEffect and not springAmbienceEffect:IsA("ColorCorrectionEffect") then
			springAmbienceEffect = nil
		end

		if not springAmbienceEffect and createIfMissing then
			springAmbienceEffect = Instance.new("ColorCorrectionEffect")
			springAmbienceEffect.Name = effectName
			springAmbienceEffect.TintColor = Color3.fromRGB(255, 255, 255)
			springAmbienceEffect.Brightness = 0
			springAmbienceEffect.Contrast = 0
			springAmbienceEffect.Saturation = 0
			springAmbienceEffect.Enabled = false
			springAmbienceEffect.Parent = Lighting
		end

		return springAmbienceEffect
	end

	local function scheduleSpringAmbiencePulse(sequence)
		task.delay(1.8, function()
			if sequence ~= springAmbienceSequence or not springAmbienceActive then
				return
			end

			clearSpringAmbienceTweens()
			springAmbiencePulseGold = not springAmbiencePulseGold

			for _, edge in ipairs(springAmbienceEdges) do
				local pulseTransparency = edge.targetTransparency + (springAmbiencePulseGold and -0.02 or 0.018)
				tweenSpringAmbience(edge.frame, 2.4, {
					BackgroundTransparency = math.clamp(pulseTransparency, 0.84, 0.94),
				})
			end

			local effect = getSpringAmbienceEffect(true)
			if effect then
				effect.Enabled = true
				local pulse = tweenSpringAmbience(effect, 2.4, {
					TintColor = springAmbiencePulseGold and Color3.fromRGB(255, 246, 214) or Color3.fromRGB(226, 255, 224),
					Brightness = springAmbiencePulseGold and 0.018 or 0.008,
					Contrast = springAmbiencePulseGold and 0.018 or 0.012,
					Saturation = springAmbiencePulseGold and 0.04 or 0.025,
				})
				pulse.Completed:Connect(function(playbackState)
					if playbackState ~= Enum.PlaybackState.Completed or sequence ~= springAmbienceSequence then
						return
					end
					scheduleSpringAmbiencePulse(sequence)
				end)
			end
		end)
	end

	local function setSpringAmbienceActive(active)
		if active == springAmbienceActive and active == false then
			return
		end

		springAmbienceActive = active == true
		springAmbienceSequence = springAmbienceSequence + 1
		local sequence = springAmbienceSequence

		clearSpringAmbienceTweens()

		if springAmbienceActive then
			springAmbienceLayer.Visible = true

			for _, edge in ipairs(springAmbienceEdges) do
				tweenSpringAmbience(edge.frame, 0.75, {
					BackgroundTransparency = edge.targetTransparency,
				})
			end

			local effect = getSpringAmbienceEffect(true)
			if effect then
				effect.Enabled = true
				local fadeIn = tweenSpringAmbience(effect, 0.75, {
					TintColor = Color3.fromRGB(240, 255, 224),
					Brightness = 0.012,
					Contrast = 0.014,
					Saturation = 0.03,
				})
				fadeIn.Completed:Connect(function(playbackState)
					if playbackState ~= Enum.PlaybackState.Completed or sequence ~= springAmbienceSequence then
						return
					end
					scheduleSpringAmbiencePulse(sequence)
				end)
			end

			return
		end

		for _, edge in ipairs(springAmbienceEdges) do
			tweenSpringAmbience(edge.frame, 0.55, {
				BackgroundTransparency = 1,
			})
		end

		local effect = getSpringAmbienceEffect(false)
		local fadeOut = nil
		if effect then
			fadeOut = tweenSpringAmbience(effect, 0.55, {
				TintColor = Color3.fromRGB(255, 255, 255),
				Brightness = 0,
				Contrast = 0,
				Saturation = 0,
			})
		end

		local function finishFadeOut()
			if sequence ~= springAmbienceSequence then
				return
			end

			springAmbienceLayer.Visible = false
			if effect then
				effect.Enabled = false
			end
		end

		if fadeOut then
			fadeOut.Completed:Connect(function()
				finishFadeOut()
			end)
		else
			task.delay(0.55, finishFadeOut)
		end
	end

	return setSpringAmbienceActive
end

local setSpringAmbienceActive = createSpringAmbienceController()

local setSummerAmbienceActive = (function()
	local summerAmbienceLayer = Instance.new("Frame")
	summerAmbienceLayer.Name = "SummerAmbience"
	summerAmbienceLayer.Size = UDim2.new(1, 0, 1, 0)
	summerAmbienceLayer.Position = UDim2.new(0, 0, 0, 0)
	summerAmbienceLayer.BackgroundTransparency = 1
	summerAmbienceLayer.BorderSizePixel = 0
	summerAmbienceLayer.Active = false
	summerAmbienceLayer.Visible = false
	summerAmbienceLayer.ZIndex = 5
	summerAmbienceLayer.Parent = screenGui

	local summerAmbienceEdges = {}

	local function createSummerAmbienceEdge(name, position, size, color, gradientRotation, targetTransparency)
		local edge = Instance.new("Frame")
		edge.Name = name
		edge.Size = size
		edge.Position = position
		edge.BackgroundColor3 = color
		edge.BackgroundTransparency = 1
		edge.BorderSizePixel = 0
		edge.Active = false
		edge.ZIndex = 5
		edge.Parent = summerAmbienceLayer

		local gradient = Instance.new("UIGradient")
		gradient.Rotation = gradientRotation
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = edge

		table.insert(summerAmbienceEdges, {
			frame = edge,
			targetTransparency = targetTransparency,
		})
	end

	createSummerAmbienceEdge(
		"TopAmberHaze",
		UDim2.new(0, 0, 0, 0),
		UDim2.new(1, 0, 0.18, 0),
		Color3.fromRGB(255, 182, 70),
		90,
		0.86
	)
	createSummerAmbienceEdge(
		"BottomEmberHaze",
		UDim2.new(0, 0, 0.82, 0),
		UDim2.new(1, 0, 0.18, 0),
		Color3.fromRGB(236, 94, 34),
		-90,
		0.87
	)
	createSummerAmbienceEdge(
		"LeftHeatHaze",
		UDim2.new(0, 0, 0, 0),
		UDim2.new(0.13, 0, 1, 0),
		Color3.fromRGB(255, 142, 45),
		0,
		0.89
	)
	createSummerAmbienceEdge(
		"RightHeatHaze",
		UDim2.new(0.87, 0, 0, 0),
		UDim2.new(0.13, 0, 1, 0),
		Color3.fromRGB(250, 126, 38),
		180,
		0.89
	)

	local effectName = "DeepDigSummerAmbience"
	local summerAmbienceEffect = Lighting:FindFirstChild(effectName)
	local summerAmbienceActive = false
	local summerAmbienceSequence = 0
	local summerAmbiencePulseHot = false
	local summerAmbienceTweens = {}

	if summerAmbienceEffect and not summerAmbienceEffect:IsA("ColorCorrectionEffect") then
		summerAmbienceEffect = nil
	end

	local function clearSummerAmbienceTweens()
		for _, tween in ipairs(summerAmbienceTweens) do
			tween:Cancel()
		end
		summerAmbienceTweens = {}
	end

	local function tweenSummerAmbience(instance, duration, goal)
		local tween = TweenService:Create(
			instance,
			TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			goal
		)
		table.insert(summerAmbienceTweens, tween)
		tween:Play()
		return tween
	end

	local function getSummerAmbienceEffect(createIfMissing)
		if summerAmbienceEffect and summerAmbienceEffect.Parent == Lighting then
			return summerAmbienceEffect
		end

		summerAmbienceEffect = Lighting:FindFirstChild(effectName)
		if summerAmbienceEffect and not summerAmbienceEffect:IsA("ColorCorrectionEffect") then
			summerAmbienceEffect = nil
		end

		if not summerAmbienceEffect and createIfMissing then
			summerAmbienceEffect = Instance.new("ColorCorrectionEffect")
			summerAmbienceEffect.Name = effectName
			summerAmbienceEffect.TintColor = Color3.fromRGB(255, 255, 255)
			summerAmbienceEffect.Brightness = 0
			summerAmbienceEffect.Contrast = 0
			summerAmbienceEffect.Saturation = 0
			summerAmbienceEffect.Enabled = false
			summerAmbienceEffect.Parent = Lighting
		end

		return summerAmbienceEffect
	end

	local function scheduleSummerAmbiencePulse(sequence)
		task.delay(1.15, function()
			if sequence ~= summerAmbienceSequence or not summerAmbienceActive then
				return
			end

			clearSummerAmbienceTweens()
			summerAmbiencePulseHot = not summerAmbiencePulseHot

			for _, edge in ipairs(summerAmbienceEdges) do
				local pulseTransparency = edge.targetTransparency + (summerAmbiencePulseHot and -0.028 or 0.02)
				tweenSummerAmbience(edge.frame, 1.45, {
					BackgroundTransparency = math.clamp(pulseTransparency, 0.82, 0.93),
				})
			end

			local effect = getSummerAmbienceEffect(true)
			if effect then
				effect.Enabled = true
				local pulse = tweenSummerAmbience(effect, 1.45, {
					TintColor = summerAmbiencePulseHot and Color3.fromRGB(255, 231, 194) or Color3.fromRGB(255, 215, 164),
					Brightness = summerAmbiencePulseHot and 0.022 or 0.008,
					Contrast = summerAmbiencePulseHot and 0.018 or 0.01,
					Saturation = summerAmbiencePulseHot and 0.045 or 0.025,
				})
				pulse.Completed:Connect(function(playbackState)
					if playbackState ~= Enum.PlaybackState.Completed or sequence ~= summerAmbienceSequence then
						return
					end
					scheduleSummerAmbiencePulse(sequence)
				end)
			end
		end)
	end

	return function(active)
		if active == summerAmbienceActive and active == false then
			return
		end

		summerAmbienceActive = active == true
		summerAmbienceSequence = summerAmbienceSequence + 1
		local sequence = summerAmbienceSequence

		clearSummerAmbienceTweens()

		if summerAmbienceActive then
			summerAmbienceLayer.Visible = true

			for _, edge in ipairs(summerAmbienceEdges) do
				tweenSummerAmbience(edge.frame, 0.65, {
					BackgroundTransparency = edge.targetTransparency,
				})
			end

			local effect = getSummerAmbienceEffect(true)
			if effect then
				effect.Enabled = true
				local fadeIn = tweenSummerAmbience(effect, 0.65, {
					TintColor = Color3.fromRGB(255, 225, 176),
					Brightness = 0.014,
					Contrast = 0.012,
					Saturation = 0.032,
				})
				fadeIn.Completed:Connect(function(playbackState)
					if playbackState ~= Enum.PlaybackState.Completed or sequence ~= summerAmbienceSequence then
						return
					end
					scheduleSummerAmbiencePulse(sequence)
				end)
			end

			return
		end

		for _, edge in ipairs(summerAmbienceEdges) do
			tweenSummerAmbience(edge.frame, 0.5, {
				BackgroundTransparency = 1,
			})
		end

		local effect = getSummerAmbienceEffect(false)
		local fadeOut = nil
		if effect then
			fadeOut = tweenSummerAmbience(effect, 0.5, {
				TintColor = Color3.fromRGB(255, 255, 255),
				Brightness = 0,
				Contrast = 0,
				Saturation = 0,
			})
		end

		local function finishFadeOut()
			if sequence ~= summerAmbienceSequence then
				return
			end

			summerAmbienceLayer.Visible = false
			if effect then
				effect.Enabled = false
			end
		end

		if fadeOut then
			fadeOut.Completed:Connect(function()
				finishFadeOut()
			end)
		else
			task.delay(0.5, finishFadeOut)
		end
	end
end)()

local setWinterAmbienceActive = (function()
	local winterAmbienceLayer = Instance.new("Frame")
	winterAmbienceLayer.Name = "WinterAmbience"
	winterAmbienceLayer.Size = UDim2.new(1, 0, 1, 0)
	winterAmbienceLayer.Position = UDim2.new(0, 0, 0, 0)
	winterAmbienceLayer.BackgroundTransparency = 1
	winterAmbienceLayer.BorderSizePixel = 0
	winterAmbienceLayer.Active = false
	winterAmbienceLayer.Visible = false
	winterAmbienceLayer.ZIndex = 5
	winterAmbienceLayer.Parent = screenGui

	local winterAmbienceEdges = {}

	local function createWinterAmbienceEdge(name, position, size, color, gradientRotation, targetTransparency)
		local edge = Instance.new("Frame")
		edge.Name = name
		edge.Size = size
		edge.Position = position
		edge.BackgroundColor3 = color
		edge.BackgroundTransparency = 1
		edge.BorderSizePixel = 0
		edge.Active = false
		edge.ZIndex = 5
		edge.Parent = winterAmbienceLayer

		local gradient = Instance.new("UIGradient")
		gradient.Rotation = gradientRotation
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = edge

		table.insert(winterAmbienceEdges, {
			frame = edge,
			targetTransparency = targetTransparency,
		})
	end

	createWinterAmbienceEdge(
		"TopFrostVignette",
		UDim2.new(0, 0, 0, 0),
		UDim2.new(1, 0, 0.2, 0),
		Color3.fromRGB(205, 240, 255),
		90,
		0.82
	)
	createWinterAmbienceEdge(
		"BottomIceVignette",
		UDim2.new(0, 0, 0.8, 0),
		UDim2.new(1, 0, 0.2, 0),
		Color3.fromRGB(160, 218, 255),
		-90,
		0.84
	)
	createWinterAmbienceEdge(
		"LeftFrostVignette",
		UDim2.new(0, 0, 0, 0),
		UDim2.new(0.14, 0, 1, 0),
		Color3.fromRGB(180, 230, 255),
		0,
		0.86
	)
	createWinterAmbienceEdge(
		"RightSnowVignette",
		UDim2.new(0.86, 0, 0, 0),
		UDim2.new(0.14, 0, 1, 0),
		Color3.fromRGB(225, 248, 255),
		180,
		0.87
	)

	local effectName = "DeepDigWinterAmbience"
	local winterAmbienceEffect = Lighting:FindFirstChild(effectName)
	local winterAmbienceActive = false
	local winterAmbienceSequence = 0
	local winterAmbiencePulseBright = false
	local winterAmbienceTweens = {}

	if winterAmbienceEffect and not winterAmbienceEffect:IsA("ColorCorrectionEffect") then
		winterAmbienceEffect = nil
	end

	local function clearWinterAmbienceTweens()
		for _, tween in ipairs(winterAmbienceTweens) do
			tween:Cancel()
		end
		winterAmbienceTweens = {}
	end

	local function tweenWinterAmbience(instance, duration, goal)
		local tween = TweenService:Create(
			instance,
			TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			goal
		)
		table.insert(winterAmbienceTweens, tween)
		tween:Play()
		return tween
	end

	local function getWinterAmbienceEffect(createIfMissing)
		if winterAmbienceEffect and winterAmbienceEffect.Parent == Lighting then
			return winterAmbienceEffect
		end

		winterAmbienceEffect = Lighting:FindFirstChild(effectName)
		if winterAmbienceEffect and not winterAmbienceEffect:IsA("ColorCorrectionEffect") then
			winterAmbienceEffect = nil
		end

		if not winterAmbienceEffect and createIfMissing then
			winterAmbienceEffect = Instance.new("ColorCorrectionEffect")
			winterAmbienceEffect.Name = effectName
			winterAmbienceEffect.TintColor = Color3.fromRGB(255, 255, 255)
			winterAmbienceEffect.Brightness = 0
			winterAmbienceEffect.Contrast = 0
			winterAmbienceEffect.Saturation = 0
			winterAmbienceEffect.Enabled = false
			winterAmbienceEffect.Parent = Lighting
		end

		return winterAmbienceEffect
	end

	local function scheduleWinterAmbiencePulse(sequence)
		task.delay(1.7, function()
			if sequence ~= winterAmbienceSequence or not winterAmbienceActive then
				return
			end

			clearWinterAmbienceTweens()
			winterAmbiencePulseBright = not winterAmbiencePulseBright

			for _, edge in ipairs(winterAmbienceEdges) do
				local pulseTransparency = edge.targetTransparency + (winterAmbiencePulseBright and -0.025 or 0.018)
				tweenWinterAmbience(edge.frame, 2.1, {
					BackgroundTransparency = math.clamp(pulseTransparency, 0.78, 0.92),
				})
			end

			local effect = getWinterAmbienceEffect(true)
			if effect then
				effect.Enabled = true
				local pulse = tweenWinterAmbience(effect, 2.1, {
					TintColor = winterAmbiencePulseBright and Color3.fromRGB(235, 250, 255) or Color3.fromRGB(210, 238, 255),
					Brightness = winterAmbiencePulseBright and -0.012 or -0.03,
					Contrast = winterAmbiencePulseBright and 0.012 or 0.026,
					Saturation = winterAmbiencePulseBright and -0.1 or -0.16,
				})
				pulse.Completed:Connect(function(playbackState)
					if playbackState ~= Enum.PlaybackState.Completed or sequence ~= winterAmbienceSequence then
						return
					end
					scheduleWinterAmbiencePulse(sequence)
				end)
			end
		end)
	end

	return function(active)
		if active == winterAmbienceActive and active == false then
			return
		end

		winterAmbienceActive = active == true
		winterAmbienceSequence = winterAmbienceSequence + 1
		local sequence = winterAmbienceSequence

		clearWinterAmbienceTweens()

		if winterAmbienceActive then
			winterAmbienceLayer.Visible = true

			for _, edge in ipairs(winterAmbienceEdges) do
				tweenWinterAmbience(edge.frame, 0.7, {
					BackgroundTransparency = edge.targetTransparency,
				})
			end

			local effect = getWinterAmbienceEffect(true)
			if effect then
				effect.Enabled = true
				local fadeIn = tweenWinterAmbience(effect, 0.7, {
					TintColor = Color3.fromRGB(220, 244, 255),
					Brightness = -0.018,
					Contrast = 0.018,
					Saturation = -0.12,
				})
				fadeIn.Completed:Connect(function(playbackState)
					if playbackState ~= Enum.PlaybackState.Completed or sequence ~= winterAmbienceSequence then
						return
					end
					scheduleWinterAmbiencePulse(sequence)
				end)
			end

			return
		end

		for _, edge in ipairs(winterAmbienceEdges) do
			tweenWinterAmbience(edge.frame, 0.55, {
				BackgroundTransparency = 1,
			})
		end

		local effect = getWinterAmbienceEffect(false)
		local fadeOut = nil
		if effect then
			fadeOut = tweenWinterAmbience(effect, 0.55, {
				TintColor = Color3.fromRGB(255, 255, 255),
				Brightness = 0,
				Contrast = 0,
				Saturation = 0,
			})
		end

		local function finishFadeOut()
			if sequence ~= winterAmbienceSequence then
				return
			end

			winterAmbienceLayer.Visible = false
			if effect then
				effect.Enabled = false
			end
		end

		if fadeOut then
			fadeOut.Completed:Connect(function()
				finishFadeOut()
			end)
		else
			task.delay(0.55, finishFadeOut)
		end
	end
end)()

local PASS_UI_STYLES = {
	[1] = { color = Color3.fromRGB(255, 80, 80), label = "2× LOOT" },
	[2] = { color = Color3.fromRGB(255, 200, 0), label = "★ VIP" },
	[3] = { color = Color3.fromRGB(80, 220, 80), label = "🍀 LUCKY" },
	[4] = { color = Color3.fromRGB(90, 170, 255), label = "⛏ FOREMAN" },
	[Config.GAMEPASS_LUCKY_EGG_ID] = { color = Color3.fromRGB(175, 245, 95), label = "🍀 EGG" },
	[Config.GAMEPASS_AUTO_COLLECTOR_ID] = { color = Color3.fromRGB(80, 230, 210), label = "⚙ AUTO" },
	[Config.GAMEPASS_INFINITE_BACKPACK_ID] = { color = Color3.fromRGB(190, 120, 255), label = "∞ BAG" },
	[Config.GAMEPASS_ARTIFACT_DETECTOR_ID] = { color = Color3.fromRGB(60, 210, 255), label = "⌁ SCAN" },
	[Config.GAMEPASS_REBIRTH_BOOST_ID] = { color = Color3.fromRGB(255, 120, 210), label = "⭐ BOOST" },
}

local PASS_UI_ORDER = {
	1,
	2,
	3,
	4,
	Config.GAMEPASS_LUCKY_EGG_ID,
	Config.GAMEPASS_AUTO_COLLECTOR_ID,
	Config.GAMEPASS_INFINITE_BACKPACK_ID,
	Config.GAMEPASS_ARTIFACT_DETECTOR_ID,
	Config.GAMEPASS_REBIRTH_BOOST_ID,
}

local PASS_UI_KEYS = {
	[Config.GAMEPASS_LUCKY_EGG_ID] = Config.GAMEPASS_LUCKY_EGG,
	[Config.GAMEPASS_AUTO_COLLECTOR_ID] = Config.GAMEPASS_AUTO_COLLECTOR,
	[Config.GAMEPASS_INFINITE_BACKPACK_ID] = Config.GAMEPASS_INFINITE_BACKPACK,
	[Config.GAMEPASS_ARTIFACT_DETECTOR_ID] = Config.GAMEPASS_ARTIFACT_DETECTOR,
	[Config.GAMEPASS_REBIRTH_BOOST_ID] = Config.GAMEPASS_REBIRTH_BOOST,
}

local function getPassUiStyle(passId)
	return PASS_UI_STYLES[passId] or { color = Color3.fromRGB(100, 100, 100), label = "PASS" }
end

local function isPassOwnedForUi(ownedGamepasses, passId)
	return ownedGamepasses[passId] == true
		or (PASS_UI_KEYS[passId] and ownedGamepasses[PASS_UI_KEYS[passId]] == true)
end

local function updatePassBadges(ownedGamepasses)
	-- Clear old badges
	for _, child in ipairs(badgeRow:GetChildren()) do
		if child:IsA("TextLabel") then child:Destroy() end
	end
	if not ownedGamepasses then return end

	for _, passId in ipairs(PASS_UI_ORDER) do
		if isPassOwnedForUi(ownedGamepasses, passId) then
			local passUi = getPassUiStyle(passId)
			local badge = Instance.new("TextLabel")
			badge.Size = UDim2.new(0, 72, 0, 20)
			badge.BackgroundColor3 = passUi.color
			badge.BackgroundTransparency = 0.2
			badge.BorderSizePixel = 0
			badge.Text = passUi.label
			badge.TextColor3 = Color3.fromRGB(20, 15, 0)
			badge.TextSize = 11
			badge.Font = Enum.Font.GothamBlack
			badge.TextXAlignment = Enum.TextXAlignment.Center
			badge.LayoutOrder = passId
			badge.Parent = badgeRow

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 4)
			corner.Parent = badge

		end
	end
end

local function updateSeasonBadge(effectId)
	local seasonUi = SEASON_BADGE_STYLES[effectId]
	setHalloweenAmbienceActive(effectId == "halloween_loot" and seasonUi ~= nil)
	setSpringAmbienceActive(effectId == "spring_loot" and seasonUi ~= nil)
	setSummerAmbienceActive(effectId == "summer_loot" and seasonUi ~= nil)
	setWinterAmbienceActive(effectId == "winter_loot" and seasonUi ~= nil)

	if not seasonUi then
		seasonBadge.Visible = false
		return false
	end

	seasonBadge.BackgroundColor3 = seasonUi.background
	seasonBadgeStroke.Color = seasonUi.stroke
	seasonBadgeTitle.Text = seasonUi.title
	seasonBadgeTitle.TextColor3 = seasonUi.titleColor
	seasonBadgeDetail.Text = seasonUi.detail
	seasonBadgeDetail.TextColor3 = seasonUi.detailColor
	seasonBadge.Visible = true

	return true
end

-- ═══════════════════════════════════════════════════════════════════
-- Notification system (item found, events, etc.)
-- ═══════════════════════════════════════════════════════════════════

local notificationFrame = Instance.new("Frame")
notificationFrame.Name = "Notifications"
notificationFrame.Size = UDim2.new(0, 400, 0, 300)
notificationFrame.Position = UDim2.new(0.5, -200, 0.15, 0)
notificationFrame.BackgroundTransparency = 1
notificationFrame.Parent = screenGui

local notifLayout = Instance.new("UIListLayout")
notifLayout.SortOrder = Enum.SortOrder.LayoutOrder
notifLayout.Padding = UDim.new(0, 5)
notifLayout.Parent = notificationFrame

local RARITY_COLORS = {
	Common    = Color3.fromRGB(180, 180, 180),
	Uncommon  = Color3.fromRGB(30, 200, 30),
	Rare      = Color3.fromRGB(30, 100, 255),
	Epic      = Color3.fromRGB(160, 50, 255),
	Legendary = Color3.fromRGB(255, 170, 0),
	Mythic    = Color3.fromRGB(255, 50, 50),
}

local LEGENDARY_FIND_FLASH_RARITIES = {
	Legendary = {
		overlayColor = Color3.fromRGB(255, 218, 82),
		peakTransparency = 0.18,
		flashInDuration = 0.08,
		flashOutDuration = 0.34,
		pulseColor = Color3.fromRGB(255, 238, 146),
		glintColor = Color3.fromRGB(255, 248, 210),
		pulseSize = 155,
		horizontalGlintWidth = 190,
		verticalGlintHeight = 80,
		pulseDuration = 0.36,
		glintExpandDuration = 0.18,
		glintFadeDuration = 0.26,
	},
	Mythic = {
		overlayColor = Color3.fromRGB(255, 34, 64),
		peakTransparency = 0.07,
		flashInDuration = 0.06,
		flashOutDuration = 0.44,
		pulseColor = Color3.fromRGB(255, 246, 246),
		glintColor = Color3.fromRGB(255, 255, 255),
		pulseSize = 220,
		horizontalGlintWidth = 260,
		verticalGlintHeight = 120,
		pulseDuration = 0.44,
		glintExpandDuration = 0.20,
		glintFadeDuration = 0.34,
	},
}

local updateDepthTone

do
	local effectName = "DeepDigDepthTone"
	local profiles = {
		Modern = {
			tint = Color3.fromRGB(255, 255, 255),
			contrast = 0,
			saturation = 0,
		},
		Industrial = {
			tint = Color3.fromRGB(255, 238, 215),
			contrast = 0.03,
			saturation = -0.03,
		},
		Medieval = {
			tint = Color3.fromRGB(224, 236, 255),
			contrast = 0.05,
			saturation = -0.05,
		},
		Ancient = {
			tint = Color3.fromRGB(246, 226, 184),
			contrast = 0.08,
			saturation = -0.09,
		},
		Prehistoric = {
			tint = Color3.fromRGB(214, 236, 194),
			contrast = 0.10,
			saturation = -0.06,
		},
		Unknown = {
			tint = Color3.fromRGB(218, 190, 255),
			contrast = 0.14,
			saturation = -0.14,
		},
	}
	local currentTierName = nil
	local activeTween = nil
	local effect = Lighting:FindFirstChild(effectName)

	if effect and not effect:IsA("ColorCorrectionEffect") then
		effect = nil
	end

	local function getEffect()
		if effect and effect.Parent == Lighting then
			return effect
		end

		effect = Lighting:FindFirstChild(effectName)
		if effect and not effect:IsA("ColorCorrectionEffect") then
			effect = nil
		end

		if not effect then
			effect = Instance.new("ColorCorrectionEffect")
			effect.Name = effectName
			effect.TintColor = profiles.Modern.tint
			effect.Contrast = profiles.Modern.contrast
			effect.Saturation = profiles.Modern.saturation
			effect.Parent = Lighting
		end

		effect.Enabled = true
		return effect
	end

	local function getTierNameFromDepth(depth)
		if type(depth) ~= "number" then
			return nil
		end

		for _, tier in ipairs(Config.TIERS or {}) do
			if depth >= tier.minDepth and depth <= tier.maxDepth then
				return tier.name
			end
		end

		return "Modern"
	end

	local function getTierName(data)
		if data and type(data.tierName) == "string" and data.tierName ~= "" then
			return data.tierName
		end

		if data then
			return getTierNameFromDepth(data.depth)
		end

		return nil
	end

	function updateDepthTone(data)
		local tierName = getTierName(data)
		if not tierName then
			return
		end

		local profile = profiles[tierName] or profiles.Modern
		if tierName == currentTierName then
			return
		end

		currentTierName = tierName

		if activeTween then
			activeTween:Cancel()
		end

		activeTween = TweenService:Create(
			getEffect(),
			TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{
				TintColor = profile.tint,
				Contrast = profile.contrast,
				Saturation = profile.saturation,
			}
		)
		activeTween:Play()
	end
end

updateDepthTone = (function(applyDepthTone)
	local surfaceTiers = {
		Modern = true,
		Surface = true,
	}
	local tierColors = {}
	for _, tier in ipairs(Config.TIERS or {}) do
		tierColors[tier.name] = tier.color
	end

	local banner = Instance.new("Frame")
	banner.Name = "DepthTierArrival"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Size = UDim2.fromOffset(430, 116)
	banner.Position = UDim2.fromScale(0.5, 0.47)
	banner.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	banner.BackgroundTransparency = 1
	banner.BorderSizePixel = 0
	banner.Visible = false
	banner.ZIndex = 84
	banner.Parent = screenGui

	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 12)
	bannerCorner.Parent = banner

	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Color = Color3.fromRGB(255, 230, 150)
	bannerStroke.Thickness = 2
	bannerStroke.Transparency = 1
	bannerStroke.Parent = banner

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -40, 0, 30)
	title.Position = UDim2.fromOffset(20, 18)
	title.BackgroundTransparency = 1
	title.Text = "Layer Reached"
	title.TextColor3 = Color3.fromRGB(255, 240, 210)
	title.TextTransparency = 1
	title.TextSize = 22
	title.Font = Enum.Font.GothamBlack
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.ZIndex = 85
	title.Parent = banner

	local tierLabel = Instance.new("TextLabel")
	tierLabel.Name = "Tier"
	tierLabel.Size = UDim2.new(1, -40, 0, 36)
	tierLabel.Position = UDim2.fromOffset(20, 52)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Text = ""
	tierLabel.TextColor3 = Color3.fromRGB(255, 230, 150)
	tierLabel.TextTransparency = 1
	tierLabel.TextSize = 30
	tierLabel.Font = Enum.Font.GothamBlack
	tierLabel.TextXAlignment = Enum.TextXAlignment.Center
	tierLabel.ZIndex = 85
	tierLabel.Parent = banner

	local seenTierNames = {}
	local lastTierName = nil
	local sequence = 0
	local activeTweens = {}

	local function clearTweens()
		for _, tween in ipairs(activeTweens) do
			tween:Cancel()
		end
		activeTweens = {}
	end

	local function tween(instance, duration, goal, easingStyle, easingDirection)
		local activeTween = TweenService:Create(
			instance,
			TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
			goal
		)
		table.insert(activeTweens, activeTween)
		activeTween:Play()
		return activeTween
	end

	local function getTierNameFromDepth(depth)
		if type(depth) ~= "number" then
			return nil
		end

		for _, tier in ipairs(Config.TIERS or {}) do
			if depth >= tier.minDepth and depth <= tier.maxDepth then
				return tier.name
			end
		end

		return "Modern"
	end

	local function getTierName(data)
		if data and type(data.tierName) == "string" and data.tierName ~= "" then
			return data.tierName
		end

		if data then
			return getTierNameFromDepth(data.depth)
		end

		return nil
	end

	local function getReadableTierColor(tierColor)
		return tierColor:Lerp(Color3.fromRGB(255, 245, 225), 0.42)
	end

	local function playBanner(tierName)
		sequence = sequence + 1
		local currentSequence = sequence
		local tierColor = tierColors[tierName] or Color3.fromRGB(255, 230, 150)
		local readableTierColor = getReadableTierColor(tierColor)

		clearTweens()
		banner.Visible = true
		banner.Size = UDim2.fromOffset(392, 104)
		banner.Position = UDim2.fromScale(0.5, 0.49)
		banner.BackgroundTransparency = 1
		bannerStroke.Color = tierColor
		bannerStroke.Transparency = 1
		title.TextTransparency = 1
		tierLabel.Text = tierName
		tierLabel.TextColor3 = readableTierColor
		tierLabel.TextTransparency = 1

		tween(banner, 0.18, {
			Size = UDim2.fromOffset(430, 116),
			Position = UDim2.fromScale(0.5, 0.47),
			BackgroundTransparency = 0.08,
		}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		tween(bannerStroke, 0.18, { Transparency = 0.05 })
		tween(title, 0.14, { TextTransparency = 0 })
		tween(tierLabel, 0.18, { TextTransparency = 0 })

		if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
			LocalPlaySound:Fire("depth_tier_unlock")
		end

		task.delay(2.2, function()
			if currentSequence ~= sequence then
				return
			end

			tween(banner, 0.22, {
				Position = UDim2.fromScale(0.5, 0.45),
				BackgroundTransparency = 1,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tween(bannerStroke, 0.18, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tween(title, 0.16, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local fadeOut = tween(tierLabel, 0.16, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			fadeOut.Completed:Connect(function(playbackState)
				if currentSequence ~= sequence or playbackState ~= Enum.PlaybackState.Completed then
					return
				end
				banner.Visible = false
			end)
		end)
	end

	return function(data)
		applyDepthTone(data)

		local tierName = getTierName(data)
		if not tierName then
			return
		end

		local wasSeen = seenTierNames[tierName] == true
		seenTierNames[tierName] = true

		if lastTierName == nil then
			lastTierName = tierName
			return
		end

		if tierName == lastTierName then
			return
		end

		lastTierName = tierName
		if surfaceTiers[tierName] or wasSeen then
			return
		end

		playBanner(tierName)
	end
end)(updateDepthTone)

local findFlashLayer = Instance.new("Frame")
findFlashLayer.Name = "LegendaryFindFlash"
findFlashLayer.Size = UDim2.new(1, 0, 1, 0)
findFlashLayer.Position = UDim2.new(0, 0, 0, 0)
findFlashLayer.BackgroundTransparency = 1
findFlashLayer.BorderSizePixel = 0
findFlashLayer.ZIndex = 90
findFlashLayer.Parent = screenGui

local findFlashOverlay = Instance.new("Frame")
findFlashOverlay.Name = "Overlay"
findFlashOverlay.Size = UDim2.new(1, 0, 1, 0)
findFlashOverlay.BackgroundColor3 = Color3.fromRGB(255, 210, 80)
findFlashOverlay.BackgroundTransparency = 1
findFlashOverlay.BorderSizePixel = 0
findFlashOverlay.ZIndex = 90
findFlashOverlay.Parent = findFlashLayer

local findFlashSequence = 0
local findFlashInTween = nil
local findFlashOutTween = nil

local function playLegendaryFindFlash(rarity)
	local flashProfile = LEGENDARY_FIND_FLASH_RARITIES[rarity] or LEGENDARY_FIND_FLASH_RARITIES.Legendary
	findFlashSequence = findFlashSequence + 1
	local sequence = findFlashSequence

	local previousGlint = findFlashLayer:FindFirstChild("Glint")
	if previousGlint then
		previousGlint:Destroy()
	end

	if findFlashInTween then
		findFlashInTween:Cancel()
	end
	if findFlashOutTween then
		findFlashOutTween:Cancel()
	end

	findFlashOverlay.BackgroundTransparency = 1
	findFlashOverlay.BackgroundColor3 = flashProfile.overlayColor

	local glint = Instance.new("Frame")
	glint.Name = "Glint"
	glint.Size = UDim2.new(0, 18, 0, 18)
	glint.AnchorPoint = Vector2.new(0.5, 0.5)
	glint.Position = UDim2.new(0.5, 0, 0.48, 0)
	glint.BackgroundTransparency = 1
	glint.BorderSizePixel = 0
	glint.ZIndex = 92
	glint.Parent = findFlashLayer

	local pulse = Instance.new("Frame")
	pulse.Name = "Pulse"
	pulse.Size = UDim2.new(0, 34, 0, 34)
	pulse.AnchorPoint = Vector2.new(0.5, 0.5)
	pulse.Position = UDim2.new(0.5, 0, 0.5, 0)
	pulse.BackgroundTransparency = 1
	pulse.BorderSizePixel = 0
	pulse.ZIndex = 91
	pulse.Parent = glint

	local pulseCorner = Instance.new("UICorner")
	pulseCorner.CornerRadius = UDim.new(1, 0)
	pulseCorner.Parent = pulse

	local pulseStroke = Instance.new("UIStroke")
	pulseStroke.Color = flashProfile.pulseColor
	pulseStroke.Transparency = 0.05
	pulseStroke.Thickness = 3
	pulseStroke.Parent = pulse

	local horizontalGlint = Instance.new("Frame")
	horizontalGlint.Name = "Horizontal"
	horizontalGlint.Size = UDim2.new(0, 14, 0, 5)
	horizontalGlint.AnchorPoint = Vector2.new(0.5, 0.5)
	horizontalGlint.Position = UDim2.new(0.5, 0, 0.5, 0)
	horizontalGlint.BackgroundColor3 = flashProfile.glintColor
	horizontalGlint.BackgroundTransparency = 0.05
	horizontalGlint.BorderSizePixel = 0
	horizontalGlint.ZIndex = 93
	horizontalGlint.Parent = glint

	local verticalGlint = Instance.new("Frame")
	verticalGlint.Name = "Vertical"
	verticalGlint.Size = UDim2.new(0, 5, 0, 14)
	verticalGlint.AnchorPoint = Vector2.new(0.5, 0.5)
	verticalGlint.Position = UDim2.new(0.5, 0, 0.5, 0)
	verticalGlint.BackgroundColor3 = flashProfile.glintColor
	verticalGlint.BackgroundTransparency = 0.05
	verticalGlint.BorderSizePixel = 0
	verticalGlint.ZIndex = 93
	verticalGlint.Parent = glint

	findFlashInTween = TweenService:Create(findFlashOverlay, TweenInfo.new(flashProfile.flashInDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = flashProfile.peakTransparency,
	})
	findFlashInTween:Play()

	TweenService:Create(pulse, TweenInfo.new(flashProfile.pulseDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, flashProfile.pulseSize, 0, flashProfile.pulseSize),
	}):Play()
	TweenService:Create(pulseStroke, TweenInfo.new(flashProfile.pulseDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Thickness = 1,
	}):Play()
	TweenService:Create(horizontalGlint, TweenInfo.new(flashProfile.glintExpandDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, flashProfile.horizontalGlintWidth, 0, 6),
	}):Play()
	TweenService:Create(verticalGlint, TweenInfo.new(flashProfile.glintExpandDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 6, 0, flashProfile.verticalGlintHeight),
	}):Play()
	TweenService:Create(horizontalGlint, TweenInfo.new(flashProfile.glintFadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	}):Play()
	TweenService:Create(verticalGlint, TweenInfo.new(flashProfile.glintFadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	}):Play()

	findFlashInTween.Completed:Connect(function(playbackState)
		if sequence ~= findFlashSequence or playbackState ~= Enum.PlaybackState.Completed then
			return
		end

		findFlashOutTween = TweenService:Create(findFlashOverlay, TweenInfo.new(flashProfile.flashOutDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		})
		findFlashOutTween:Play()
		findFlashOutTween.Completed:Connect(function(outPlaybackState)
			if sequence ~= findFlashSequence or outPlaybackState ~= Enum.PlaybackState.Completed then
				return
			end

			findFlashOverlay.BackgroundTransparency = 1
			if glint.Parent then
				glint:Destroy()
			end
		end)
	end)
end

-- ─── Lighting pulse on rare finds ────────────────────────────────────────────
-- Briefly tweens Lighting.Brightness up and back. A single guard
-- (lightingPulseSequence + lightingPulseBaseBrightness) ensures two finds in
-- quick succession don't stack — we always restore to the *original* value
-- captured before the first pulse, and the previous tweens are cancelled.

local LIGHTING_PULSE_PROFILES = {
	-- target peak Brightness, total duration in seconds
	Epic      = { peak = 2.4, duration = 0.30 },
	Legendary = { peak = 3.0, duration = 0.40 },
	Mythic    = { peak = 3.5, duration = 0.50 },
}

local lightingPulseSequence = 0
local lightingPulseBaseBrightness = nil
local lightingPulseInTween = nil
local lightingPulseOutTween = nil

local function playLightingPulse(rarity)
	local profile = LIGHTING_PULSE_PROFILES[rarity]
	if not profile then return end

	lightingPulseSequence = lightingPulseSequence + 1
	local sequence = lightingPulseSequence

	if lightingPulseInTween then lightingPulseInTween:Cancel() end
	if lightingPulseOutTween then lightingPulseOutTween:Cancel() end

	-- Capture the baseline brightness only on the first pulse (or after a
	-- previous pulse fully restored it). Otherwise reuse the saved one so
	-- a rapid second hit can't bake the elevated value in as the new base.
	if lightingPulseBaseBrightness == nil then
		lightingPulseBaseBrightness = Lighting.Brightness
	end

	local base = lightingPulseBaseBrightness
	local upTime = profile.duration * 0.4
	local downTime = profile.duration * 0.6

	lightingPulseInTween = TweenService:Create(
		Lighting,
		TweenInfo.new(upTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = profile.peak }
	)
	lightingPulseInTween:Play()
	lightingPulseInTween.Completed:Connect(function(playbackState)
		if sequence ~= lightingPulseSequence or playbackState ~= Enum.PlaybackState.Completed then
			return
		end

		lightingPulseOutTween = TweenService:Create(
			Lighting,
			TweenInfo.new(downTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Brightness = base }
		)
		lightingPulseOutTween:Play()
		lightingPulseOutTween.Completed:Connect(function(outPlaybackState)
			if sequence ~= lightingPulseSequence then return end
			-- Force-restore to the captured baseline regardless of how the
			-- tween ended (cancelled or completed) so we never leave the
			-- world permanently brighter.
			Lighting.Brightness = base
			if outPlaybackState == Enum.PlaybackState.Completed then
				lightingPulseBaseBrightness = nil
			end
		end)
	end)
end

local eventShakeBindingName = "DeepDigEventCameraShake"
local eventShakeSequence = 0
local eventShakeBaseCFrame = nil
local eventShakeBound = false
local eventShakeState = nil

local function normalizeEventKey(value)
	if type(value) ~= "string" then
		return ""
	end

	return string.gsub(string.lower(value), "[^%w]", "")
end

local function isEarthquakeEvent(eventName, message, effectId)
	local effectKey = normalizeEventKey(effectId)
	if effectKey == "earthquake" or effectKey == "instantdig" then
		return true
	end

	local nameKey = normalizeEventKey(eventName)
	if nameKey == "earthquake" then
		return true
	end

	if type(message) ~= "string" then
		return false
	end

	local lowered = string.lower(message)
	return string.find(lowered, "earthquake", 1, true) ~= nil
		or string.find(lowered, "quake", 1, true) ~= nil
		or string.find(lowered, "tremble", 1, true) ~= nil
end

local function clearEventCameraShake(sequence)
	if sequence and sequence ~= eventShakeSequence then
		return
	end

	local camera = workspace.CurrentCamera
	if camera and eventShakeBaseCFrame then
		camera.CFrame = eventShakeBaseCFrame
	end

	eventShakeBaseCFrame = nil
	eventShakeState = nil

	if eventShakeBound then
		RunService:UnbindFromRenderStep(eventShakeBindingName)
		eventShakeBound = false
	end
end

local EVENT_SHAKE_PROFILES = {
	fossillayer = { duration = 0.30, positionStrength = 0.08, rotationStrength = 0.20, noiseFrequency = 18 },
	["2xrare"] = { duration = 0.30, positionStrength = 0.08, rotationStrength = 0.20, noiseFrequency = 18 },
	goldvein = { duration = 0.28, positionStrength = 0.06, rotationStrength = 0.16, noiseFrequency = 24 },
	goldrush = { duration = 0.28, positionStrength = 0.06, rotationStrength = 0.16, noiseFrequency = 24 },
	cavesystem = { duration = 0.38, positionStrength = 0.13, rotationStrength = 0.34, noiseFrequency = 16 },
	bonusloot = { duration = 0.38, positionStrength = 0.13, rotationStrength = 0.34, noiseFrequency = 16 },
	luckyhour = { duration = 0.24, positionStrength = 0.05, rotationStrength = 0.12, noiseFrequency = 30 },
	echoesfrombelow = { duration = 0.46, positionStrength = 0.10, rotationStrength = 0.46, noiseFrequency = 12 },
	echoblocks = { duration = 0.46, positionStrength = 0.10, rotationStrength = 0.46, noiseFrequency = 12 },
}

local DEFAULT_EVENT_SHAKE_PROFILE = { duration = 0.26, positionStrength = 0.10, rotationStrength = 0.24, noiseFrequency = 18 }
local EVENT_SHAKE_MAX_RANDOM_DURATION = 180

for _, configuredEvent in ipairs(Config.EVENTS or {}) do
	if type(configuredEvent.duration) == "number" then
		EVENT_SHAKE_MAX_RANDOM_DURATION = math.max(EVENT_SHAKE_MAX_RANDOM_DURATION, configuredEvent.duration)
	end
end

local function shouldPlayEventCameraShake(duration)
	return type(duration) ~= "number" or duration <= EVENT_SHAKE_MAX_RANDOM_DURATION
end

local function getEventShakeProfile(eventName, effectId)
	return EVENT_SHAKE_PROFILES[normalizeEventKey(effectId)]
		or EVENT_SHAKE_PROFILES[normalizeEventKey(eventName)]
		or DEFAULT_EVENT_SHAKE_PROFILE
end

local function playEventCameraShake(eventName, effectId)
	eventShakeSequence = eventShakeSequence + 1
	local sequence = eventShakeSequence
	local profile = getEventShakeProfile(eventName, effectId)

	eventShakeState = {
		sequence = sequence,
		startTime = os.clock(),
		duration = profile.duration,
		positionStrength = profile.positionStrength,
		rotationStrength = profile.rotationStrength,
		noiseFrequency = profile.noiseFrequency,
		seed = sequence * 37,
	}

	if eventShakeBound then
		return
	end

	eventShakeBound = true
	RunService:BindToRenderStep(eventShakeBindingName, Enum.RenderPriority.Camera.Value + 1, function()
		local camera = workspace.CurrentCamera
		local state = eventShakeState

		if not camera or not state then
			clearEventCameraShake()
			return
		end

		local elapsed = os.clock() - state.startTime
		local progress = elapsed / state.duration
		if progress >= 1 then
			clearEventCameraShake(state.sequence)
			return
		end

		local falloff = 1 - math.clamp(progress, 0, 1)
		local shakeTime = elapsed * state.noiseFrequency
		local seed = state.seed
		local xNoise = math.noise(seed * 0.01, shakeTime, 0)
		local yNoise = math.noise(shakeTime, seed * 0.01, 1)
		local zNoise = math.noise(0, shakeTime, seed * 0.01)
		local rxNoise = math.noise(shakeTime, 2, seed * 0.01)
		local ryNoise = math.noise(seed * 0.01, 3, shakeTime)
		local rzNoise = math.noise(4, seed * 0.01, shakeTime)

		eventShakeBaseCFrame = camera.CFrame

		local positionOffset = Vector3.new(xNoise, yNoise, zNoise) * state.positionStrength * falloff
		local rotationScale = math.rad(state.rotationStrength) * falloff
		local rotationOffset = CFrame.Angles(rxNoise * rotationScale, ryNoise * rotationScale, rzNoise * rotationScale)

		camera.CFrame = eventShakeBaseCFrame * CFrame.new(positionOffset) * rotationOffset
	end)
end

local function showNotification(text, rarity)
	local color = RARITY_COLORS[rarity] or Color3.fromRGB(200, 200, 200)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 30)
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	label.BackgroundTransparency = 0.4
	label.BorderSizePixel = 0
	label.Text = text
	label.TextColor3 = color
	label.TextSize = 16
	label.Font = Enum.Font.GothamBold
	label.TextWrapped = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	label.Parent = notificationFrame

	-- Animate out after 3 seconds
	task.delay(3, function()
		local tween = TweenService:Create(label, TweenInfo.new(0.5), {
			BackgroundTransparency = 1,
			TextTransparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function()
			label:Destroy()
		end)
	end)
end

local function refreshStreakLabel()
	if currentLoginStreak > 0 then
		local day = (currentLoginStreak - 1) % 7 + 1
		local emoji = day == 7 and "🏆" or "🔥"
		local reviveSuffix = ""
		if currentStreakReviveEligible and currentStreakRevivePending then
			reviveSuffix = currentStreakReviveProductAvailable and " • Revive ready" or " • Revive unavailable"
		end
		streakLabel.Text = emoji .. " Streak: Day " .. day .. " (×" .. currentLoginStreak .. ")" .. reviveSuffix
	else
		streakLabel.Text = "🔥 Streak: –"
	end
end

local refreshFriendBoostIndicator

do
	local friendBoostFx = {
		restColor = Color3.fromRGB(70, 205, 150),
		restTextColor = Color3.fromRGB(10, 35, 24),
		restTransparency = 0.15,
		lastActive = nil,
		burstSequence = 0,
		activeBurst = nil,
	}

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(210, 255, 230)
	stroke.Thickness = 1
	stroke.Transparency = 1
	stroke.Parent = friendBoostLabel
	friendBoostFx.stroke = stroke

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = friendBoostLabel
	friendBoostFx.scale = scale

local function clearFriendBoostBurst(sequence)
	if sequence and sequence ~= friendBoostFx.burstSequence then
		return
	end

	if friendBoostFx.activeBurst then
		friendBoostFx.activeBurst:Destroy()
		friendBoostFx.activeBurst = nil
	end
end

local function restoreFriendBoostChip(sequence)
	if sequence and sequence ~= friendBoostFx.burstSequence then
		return
	end

	friendBoostLabel.BackgroundColor3 = friendBoostFx.restColor
	friendBoostLabel.BackgroundTransparency = friendBoostFx.restTransparency
	friendBoostLabel.TextColor3 = friendBoostFx.restTextColor
	friendBoostFx.scale.Scale = 1
	friendBoostFx.stroke.Transparency = 1
end

local function playFriendBoostActivationBurst(percent)
	friendBoostFx.burstSequence = friendBoostFx.burstSequence + 1
	local sequence = friendBoostFx.burstSequence
	clearFriendBoostBurst()

	friendBoostLabel.Visible = true
	friendBoostLabel.BackgroundColor3 = Color3.fromRGB(160, 255, 205)
	friendBoostLabel.BackgroundTransparency = 0
	friendBoostLabel.TextColor3 = Color3.fromRGB(3, 28, 18)
	friendBoostFx.scale.Scale = 0.88
	friendBoostFx.stroke.Transparency = 0.08

	LocalPlaySound:Fire("friend_boost")

	TweenService:Create(friendBoostFx.scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1.12,
	}):Play()
	TweenService:Create(friendBoostLabel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundColor3 = Color3.fromRGB(125, 245, 184),
	}):Play()

	task.delay(0.18, function()
		if sequence ~= friendBoostFx.burstSequence or not friendBoostLabel.Visible then
			return
		end

		TweenService:Create(friendBoostFx.scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
		TweenService:Create(friendBoostLabel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = friendBoostFx.restColor,
			BackgroundTransparency = friendBoostFx.restTransparency,
			TextColor3 = friendBoostFx.restTextColor,
		}):Play()
		TweenService:Create(friendBoostFx.stroke, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
		}):Play()
	end)

	local burstFrame = Instance.new("Frame")
	burstFrame.Name = "FriendBoostBurst"
	burstFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	burstFrame.Position = UDim2.fromScale(0.5, 0.74)
	burstFrame.Size = UDim2.fromOffset(262, 42)
	burstFrame.BackgroundColor3 = Color3.fromRGB(24, 56, 42)
	burstFrame.BackgroundTransparency = 1
	burstFrame.BorderSizePixel = 0
	burstFrame.ZIndex = 32
	burstFrame.Parent = screenGui
	friendBoostFx.activeBurst = burstFrame

	local burstCorner = Instance.new("UICorner")
	burstCorner.CornerRadius = UDim.new(0, 8)
	burstCorner.Parent = burstFrame

	local burstStroke = Instance.new("UIStroke")
	burstStroke.Color = Color3.fromRGB(135, 255, 190)
	burstStroke.Thickness = 1
	burstStroke.Transparency = 1
	burstStroke.Parent = burstFrame

	local burstLabel = Instance.new("TextLabel")
	burstLabel.Name = "Label"
	burstLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	burstLabel.Position = UDim2.fromScale(0.5, 0.5)
	burstLabel.Size = UDim2.new(1, -18, 1, 0)
	burstLabel.BackgroundTransparency = 1
	burstLabel.Text = "Friend Boost Active +" .. tostring(percent) .. "% Speed"
	burstLabel.TextColor3 = Color3.fromRGB(228, 255, 239)
	burstLabel.TextTransparency = 1
	burstLabel.TextSize = 17
	burstLabel.Font = Enum.Font.GothamBlack
	burstLabel.TextXAlignment = Enum.TextXAlignment.Center
	burstLabel.TextYAlignment = Enum.TextYAlignment.Center
	burstLabel.ZIndex = 33
	burstLabel.Parent = burstFrame

	local burstScale = Instance.new("UIScale")
	burstScale.Scale = 0.88
	burstScale.Parent = burstFrame

	TweenService:Create(burstFrame, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.1,
		Position = UDim2.fromScale(0.5, 0.7),
	}):Play()
	TweenService:Create(burstStroke, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 0.16,
	}):Play()
	TweenService:Create(burstLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
	TweenService:Create(burstScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	task.delay(0.5, function()
		if sequence ~= friendBoostFx.burstSequence or friendBoostFx.activeBurst ~= burstFrame then
			return
		end

		TweenService:Create(burstFrame, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.67),
		}):Play()
		TweenService:Create(burstStroke, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
		}):Play()
		TweenService:Create(burstLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		}):Play()
	end)

	task.delay(0.86, function()
		clearFriendBoostBurst(sequence)
		restoreFriendBoostChip(sequence)
	end)
end

function refreshFriendBoostIndicator(data)
	if not data or data.friendBoostActive == nil then
		return
	end

	if data.friendBoostActive ~= true then
		friendBoostFx.lastActive = false
		friendBoostFx.burstSequence = friendBoostFx.burstSequence + 1
		friendBoostLabel.Visible = false
		clearFriendBoostBurst()
		restoreFriendBoostChip()
		return
	end

	local multiplier = data.friendBoostMultiplier or 1.05
	local percent = math.max(1, math.floor(((multiplier - 1) * 100) + 0.5))
	friendBoostLabel.Text = "Friend Boost +" .. tostring(percent) .. "% Speed"
	friendBoostLabel.Visible = true

	if friendBoostFx.lastActive ~= true then
		playFriendBoostActivationBurst(percent)
	end

	friendBoostFx.lastActive = true
end
end

local refreshGroupBenefitIndicator

do
	local groupBenefitFx = {
		restColor = Config.GROUP_BENEFIT_DISPLAY_COLOR,
		restTextColor = Color3.fromRGB(5, 25, 35),
		restTransparency = 0.15,
		lastActive = nil,
		burstSequence = 0,
		activeBurst = nil,
		tweens = {},
	}

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(175, 235, 255)
	stroke.Thickness = 1
	stroke.Transparency = 1
	stroke.Parent = groupBenefitLabel
	groupBenefitFx.stroke = stroke

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = groupBenefitLabel
	groupBenefitFx.scale = scale

	local function clearGroupBenefitBurst(sequence)
		if sequence and sequence ~= groupBenefitFx.burstSequence then
			return
		end

		if groupBenefitFx.activeBurst then
			groupBenefitFx.activeBurst:Destroy()
			groupBenefitFx.activeBurst = nil
		end
	end

	local function clearGroupBenefitTweens()
		for _, tween in ipairs(groupBenefitFx.tweens) do
			tween:Cancel()
		end
		groupBenefitFx.tweens = {}
	end

	local function tweenGroupBenefit(instance, tweenInfo, goal)
		local tween = TweenService:Create(instance, tweenInfo, goal)
		table.insert(groupBenefitFx.tweens, tween)
		tween:Play()
		return tween
	end

	local function restoreGroupBenefitChip(sequence)
		if sequence and sequence ~= groupBenefitFx.burstSequence then
			return
		end

		groupBenefitLabel.BackgroundColor3 = groupBenefitFx.restColor
		groupBenefitLabel.BackgroundTransparency = groupBenefitFx.restTransparency
		groupBenefitLabel.TextColor3 = groupBenefitFx.restTextColor
		groupBenefitFx.scale.Scale = 1
		groupBenefitFx.stroke.Transparency = 1
	end

	local function playGroupBenefitActivationBurst(percent)
		groupBenefitFx.burstSequence = groupBenefitFx.burstSequence + 1
		local sequence = groupBenefitFx.burstSequence
		clearGroupBenefitTweens()
		clearGroupBenefitBurst()

		groupBenefitLabel.Visible = true
		groupBenefitLabel.BackgroundColor3 = Color3.fromRGB(164, 235, 255)
		groupBenefitLabel.BackgroundTransparency = 0
		groupBenefitLabel.TextColor3 = Color3.fromRGB(4, 25, 35)
		groupBenefitFx.scale.Scale = 0.88
		groupBenefitFx.stroke.Transparency = 0.08

		LocalPlaySound:Fire("group_benefit")

		tweenGroupBenefit(groupBenefitFx.scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1.12,
		})
		tweenGroupBenefit(groupBenefitLabel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = Color3.fromRGB(130, 220, 255),
		})

		task.delay(0.18, function()
			if sequence ~= groupBenefitFx.burstSequence or not groupBenefitLabel.Visible then
				return
			end

			tweenGroupBenefit(groupBenefitFx.scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Scale = 1,
			})
			tweenGroupBenefit(groupBenefitLabel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = groupBenefitFx.restColor,
				BackgroundTransparency = groupBenefitFx.restTransparency,
				TextColor3 = groupBenefitFx.restTextColor,
			})
			tweenGroupBenefit(groupBenefitFx.stroke, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
			})
		end)

		local burstFrame = Instance.new("Frame")
		burstFrame.Name = "GroupBenefitBurst"
		burstFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		burstFrame.Position = UDim2.fromScale(0.5, 0.62)
		burstFrame.Size = UDim2.fromOffset(260, 42)
		burstFrame.BackgroundColor3 = Color3.fromRGB(18, 46, 58)
		burstFrame.BackgroundTransparency = 1
		burstFrame.BorderSizePixel = 0
		burstFrame.ZIndex = 32
		burstFrame.Parent = screenGui
		groupBenefitFx.activeBurst = burstFrame

		local burstCorner = Instance.new("UICorner")
		burstCorner.CornerRadius = UDim.new(0, 8)
		burstCorner.Parent = burstFrame

		local burstStroke = Instance.new("UIStroke")
		burstStroke.Color = Color3.fromRGB(128, 226, 255)
		burstStroke.Thickness = 1
		burstStroke.Transparency = 1
		burstStroke.Parent = burstFrame

		local burstLabel = Instance.new("TextLabel")
		burstLabel.Name = "Label"
		burstLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		burstLabel.Position = UDim2.fromScale(0.5, 0.5)
		burstLabel.Size = UDim2.new(1, -18, 1, 0)
		burstLabel.BackgroundTransparency = 1
		burstLabel.Text = "Group Bonus Active +" .. tostring(percent) .. "% Coins"
		burstLabel.TextColor3 = Color3.fromRGB(226, 250, 255)
		burstLabel.TextTransparency = 1
		burstLabel.TextSize = 17
		burstLabel.Font = Enum.Font.GothamBlack
		burstLabel.TextXAlignment = Enum.TextXAlignment.Center
		burstLabel.TextYAlignment = Enum.TextYAlignment.Center
		burstLabel.ZIndex = 33
		burstLabel.Parent = burstFrame

		local burstScale = Instance.new("UIScale")
		burstScale.Scale = 0.88
		burstScale.Parent = burstFrame

		tweenGroupBenefit(burstFrame, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0.1,
			Position = UDim2.fromScale(0.5, 0.58),
		})
		tweenGroupBenefit(burstStroke, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 0.16,
		})
		tweenGroupBenefit(burstLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 0,
		})
		tweenGroupBenefit(burstScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		})

		task.delay(0.5, function()
			if sequence ~= groupBenefitFx.burstSequence or groupBenefitFx.activeBurst ~= burstFrame then
				return
			end

			tweenGroupBenefit(burstFrame, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.5, 0.55),
			})
			tweenGroupBenefit(burstStroke, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1,
			})
			tweenGroupBenefit(burstLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				TextTransparency = 1,
			})
		end)

		task.delay(0.86, function()
			if sequence ~= groupBenefitFx.burstSequence then
				return
			end

			clearGroupBenefitBurst(sequence)
			clearGroupBenefitTweens()
			restoreGroupBenefitChip(sequence)
		end)
	end

	function refreshGroupBenefitIndicator(data)
		if not data or data.groupBenefitActive == nil then
			return
		end

		if data.groupBenefitActive ~= true then
			groupBenefitFx.lastActive = false
			groupBenefitFx.burstSequence = groupBenefitFx.burstSequence + 1
			groupBenefitLabel.Visible = false
			clearGroupBenefitTweens()
			clearGroupBenefitBurst()
			restoreGroupBenefitChip()
			return
		end

		local multiplier = data.groupBenefitMultiplier or Config.GROUP_BENEFIT_COIN_MULTIPLIER
		local percent = math.max(1, math.floor(((multiplier - 1) * 100) + 0.5))
		groupBenefitFx.restColor = data.groupBenefitColor or Config.GROUP_BENEFIT_DISPLAY_COLOR
		if not groupBenefitFx.activeBurst then
			groupBenefitLabel.BackgroundColor3 = groupBenefitFx.restColor
		end
		groupBenefitLabel.Text = "Group +" .. tostring(percent) .. "% Coins"
		groupBenefitLabel.Visible = true

		if groupBenefitFx.lastActive ~= true then
			playGroupBenefitActivationBurst(percent)
		end

		groupBenefitFx.lastActive = true
	end
end

local streakRevivePanel = Instance.new("Frame")
streakRevivePanel.Name = "StreakRevivePrompt"
streakRevivePanel.AnchorPoint = Vector2.new(0.5, 0.5)
streakRevivePanel.Size = UDim2.new(0, 440, 0, 210)
streakRevivePanel.Position = UDim2.new(0.5, 0, 0.42, 0)
streakRevivePanel.BackgroundColor3 = Color3.fromRGB(24, 20, 18)
streakRevivePanel.BackgroundTransparency = 0.05
streakRevivePanel.BorderSizePixel = 0
streakRevivePanel.Visible = false
streakRevivePanel.ZIndex = 70
streakRevivePanel.Parent = screenGui

local streakReviveCorner = Instance.new("UICorner")
streakReviveCorner.CornerRadius = UDim.new(0, 14)
streakReviveCorner.Parent = streakRevivePanel

local streakReviveStroke = Instance.new("UIStroke")
streakReviveStroke.Color = Color3.fromRGB(255, 200, 50)
streakReviveStroke.Thickness = 2
streakReviveStroke.Parent = streakRevivePanel

local streakReviveTitle = Instance.new("TextLabel")
streakReviveTitle.Name = "Title"
streakReviveTitle.Size = UDim2.new(1, -30, 0, 44)
streakReviveTitle.Position = UDim2.new(0, 15, 0, 10)
streakReviveTitle.BackgroundTransparency = 1
streakReviveTitle.Text = "🔥 Streak Revive"
streakReviveTitle.TextColor3 = Color3.fromRGB(255, 200, 50)
streakReviveTitle.TextSize = 24
streakReviveTitle.Font = Enum.Font.GothamBlack
streakReviveTitle.TextXAlignment = Enum.TextXAlignment.Left
streakReviveTitle.ZIndex = 71
streakReviveTitle.Parent = streakRevivePanel

local streakReviveBody = Instance.new("TextLabel")
streakReviveBody.Name = "Body"
streakReviveBody.Size = UDim2.new(1, -30, 0, 68)
streakReviveBody.Position = UDim2.new(0, 15, 0, 54)
streakReviveBody.BackgroundTransparency = 1
streakReviveBody.Text = "You missed one day. Revive your streak for 50 Robux to keep your momentum and today's reward."
streakReviveBody.TextColor3 = Color3.fromRGB(230, 225, 215)
streakReviveBody.TextSize = 16
streakReviveBody.Font = Enum.Font.GothamMedium
streakReviveBody.TextWrapped = true
streakReviveBody.TextXAlignment = Enum.TextXAlignment.Left
streakReviveBody.TextYAlignment = Enum.TextYAlignment.Top
streakReviveBody.ZIndex = 71
streakReviveBody.Parent = streakRevivePanel

local streakReviveDetail = Instance.new("TextLabel")
streakReviveDetail.Name = "Detail"
streakReviveDetail.Size = UDim2.new(1, -30, 0, 24)
streakReviveDetail.Position = UDim2.new(0, 15, 0, 122)
streakReviveDetail.BackgroundTransparency = 1
streakReviveDetail.Text = "Current streak: Day 1 (×1)"
streakReviveDetail.TextColor3 = Color3.fromRGB(180, 170, 150)
streakReviveDetail.TextSize = 14
streakReviveDetail.Font = Enum.Font.Gotham
streakReviveDetail.TextXAlignment = Enum.TextXAlignment.Left
streakReviveDetail.ZIndex = 71
streakReviveDetail.Parent = streakRevivePanel

local streakReviveBuyButton = Instance.new("TextButton")
streakReviveBuyButton.Name = "Buy"
streakReviveBuyButton.Size = UDim2.new(0, 190, 0, 40)
streakReviveBuyButton.Position = UDim2.new(0, 15, 1, -54)
streakReviveBuyButton.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
streakReviveBuyButton.BorderSizePixel = 0
streakReviveBuyButton.Text = "Revive for 50 Robux"
streakReviveBuyButton.TextColor3 = Color3.fromRGB(40, 20, 0)
streakReviveBuyButton.TextSize = 15
streakReviveBuyButton.Font = Enum.Font.GothamBlack
streakReviveBuyButton.ZIndex = 71
streakReviveBuyButton.Parent = streakRevivePanel

local streakReviveBuyCorner = Instance.new("UICorner")
streakReviveBuyCorner.CornerRadius = UDim.new(0, 8)
streakReviveBuyCorner.Parent = streakReviveBuyButton

local streakReviveDeclineButton = Instance.new("TextButton")
streakReviveDeclineButton.Name = "Decline"
streakReviveDeclineButton.Size = UDim2.new(0, 140, 0, 40)
streakReviveDeclineButton.Position = UDim2.new(1, -155, 1, -54)
streakReviveDeclineButton.BackgroundColor3 = Color3.fromRGB(70, 60, 55)
streakReviveDeclineButton.BorderSizePixel = 0
streakReviveDeclineButton.Text = "Start Over"
streakReviveDeclineButton.TextColor3 = Color3.fromRGB(245, 235, 220)
streakReviveDeclineButton.TextSize = 14
streakReviveDeclineButton.Font = Enum.Font.GothamBold
streakReviveDeclineButton.ZIndex = 71
streakReviveDeclineButton.Parent = streakRevivePanel

local streakReviveDeclineCorner = Instance.new("UICorner")
streakReviveDeclineCorner.CornerRadius = UDim.new(0, 8)
streakReviveDeclineCorner.Parent = streakReviveDeclineButton

local showStreakRewardBurst
do
local streakRewardUi = {}
streakRewardUi.panel = Instance.new("Frame")
streakRewardUi.panel.Name = "StreakRewardBurst"
streakRewardUi.panel.AnchorPoint = Vector2.new(0.5, 0.5)
streakRewardUi.panel.Size = UDim2.fromOffset(360, 144)
streakRewardUi.panel.Position = UDim2.fromScale(0.5, 0.38)
streakRewardUi.panel.BackgroundColor3 = Color3.fromRGB(24, 20, 18)
streakRewardUi.panel.BackgroundTransparency = 1
streakRewardUi.panel.BorderSizePixel = 0
streakRewardUi.panel.Visible = false
streakRewardUi.panel.ZIndex = 74
streakRewardUi.panel.Parent = screenGui

streakRewardUi.corner = Instance.new("UICorner")
streakRewardUi.corner.CornerRadius = UDim.new(0, 12)
streakRewardUi.corner.Parent = streakRewardUi.panel

streakRewardUi.stroke = Instance.new("UIStroke")
streakRewardUi.stroke.Color = Color3.fromRGB(255, 180, 70)
streakRewardUi.stroke.Thickness = 2
streakRewardUi.stroke.Transparency = 1
streakRewardUi.stroke.Parent = streakRewardUi.panel

streakRewardUi.title = Instance.new("TextLabel")
streakRewardUi.title.Name = "Title"
streakRewardUi.title.Size = UDim2.new(1, -28, 0, 34)
streakRewardUi.title.Position = UDim2.fromOffset(14, 12)
streakRewardUi.title.BackgroundTransparency = 1
streakRewardUi.title.Text = "🔥 Streak Claimed"
streakRewardUi.title.TextColor3 = Color3.fromRGB(255, 200, 80)
streakRewardUi.title.TextTransparency = 1
streakRewardUi.title.TextSize = 22
streakRewardUi.title.Font = Enum.Font.GothamBlack
streakRewardUi.title.TextXAlignment = Enum.TextXAlignment.Center
streakRewardUi.title.ZIndex = 75
streakRewardUi.title.Parent = streakRewardUi.panel

streakRewardUi.amount = Instance.new("TextLabel")
streakRewardUi.amount.Name = "Reward"
streakRewardUi.amount.Size = UDim2.new(1, -28, 0, 36)
streakRewardUi.amount.Position = UDim2.fromOffset(14, 48)
streakRewardUi.amount.BackgroundTransparency = 1
streakRewardUi.amount.Text = "+200 coins"
streakRewardUi.amount.TextColor3 = Color3.fromRGB(255, 235, 130)
streakRewardUi.amount.TextTransparency = 1
streakRewardUi.amount.TextSize = 25
streakRewardUi.amount.Font = Enum.Font.GothamBlack
streakRewardUi.amount.TextWrapped = true
streakRewardUi.amount.TextXAlignment = Enum.TextXAlignment.Center
streakRewardUi.amount.ZIndex = 75
streakRewardUi.amount.Parent = streakRewardUi.panel

streakRewardUi.detail = Instance.new("TextLabel")
streakRewardUi.detail.Name = "Detail"
streakRewardUi.detail.Size = UDim2.new(1, -28, 0, 30)
streakRewardUi.detail.Position = UDim2.fromOffset(14, 88)
streakRewardUi.detail.BackgroundTransparency = 1
streakRewardUi.detail.Text = "Day 1 • Cycle 1 • Streak ×1"
streakRewardUi.detail.TextColor3 = Color3.fromRGB(220, 210, 190)
streakRewardUi.detail.TextTransparency = 1
streakRewardUi.detail.TextSize = 14
streakRewardUi.detail.Font = Enum.Font.GothamBold
streakRewardUi.detail.TextWrapped = true
streakRewardUi.detail.TextXAlignment = Enum.TextXAlignment.Center
streakRewardUi.detail.ZIndex = 75
streakRewardUi.detail.Parent = streakRewardUi.panel

local streakRewardSequence = 0
local streakRewardTweens = {}

local function clearStreakRewardTweens()
	for _, tween in ipairs(streakRewardTweens) do
		tween:Cancel()
	end
	streakRewardTweens = {}
end

local function playStreakRewardSound(milestone)
	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire(milestone and "streak_milestone" or "streak_reward")
	end
end

local function tweenStreakReward(instance, duration, goal, easingStyle, easingDirection)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
		goal
	)
	table.insert(streakRewardTweens, tween)
	tween:Play()
	return tween
end

function showStreakRewardBurst(payload)
	if type(payload) ~= "table" then
		return
	end

	local day = tonumber(payload.day) or 1
	local cycle = tonumber(payload.cycle) or 1
	local streak = tonumber(payload.streak) or day
	local rewardLabel = tostring(payload.rewardLabel or "Daily reward")
	local milestone = payload.milestone == true or day == 7 or cycle > 1

	streakRewardSequence = streakRewardSequence + 1
	local sequence = streakRewardSequence
	clearStreakRewardTweens()

	streakRewardUi.panel.Visible = true
	streakRewardUi.panel.Size = milestone and UDim2.fromOffset(390, 156) or UDim2.fromOffset(360, 144)
	streakRewardUi.panel.Position = UDim2.fromScale(0.5, 0.40)
	streakRewardUi.panel.BackgroundTransparency = 0.12
	streakRewardUi.stroke.Transparency = 0
	streakRewardUi.stroke.Thickness = milestone and 3 or 2
	streakRewardUi.stroke.Color = milestone and Color3.fromRGB(255, 220, 90) or Color3.fromRGB(255, 180, 70)
	streakRewardUi.title.TextTransparency = 0
	streakRewardUi.amount.TextTransparency = 0
	streakRewardUi.detail.TextTransparency = 0

	if milestone then
		streakRewardUi.panel.BackgroundColor3 = Color3.fromRGB(42, 31, 16)
		streakRewardUi.title.Text = (payload.revived and "🏆 Streak Revived" or "🏆 Milestone Streak")
		streakRewardUi.title.TextColor3 = Color3.fromRGB(255, 230, 110)
		streakRewardUi.amount.TextColor3 = Color3.fromRGB(255, 245, 150)
	else
		streakRewardUi.panel.BackgroundColor3 = Color3.fromRGB(24, 20, 18)
		streakRewardUi.title.Text = (payload.revived and "🔥 Streak Revived" or "🔥 Streak Claimed")
		streakRewardUi.title.TextColor3 = Color3.fromRGB(255, 190, 80)
		streakRewardUi.amount.TextColor3 = Color3.fromRGB(255, 235, 130)
	end

	streakRewardUi.amount.Text = rewardLabel
	streakRewardUi.detail.Text = "Day " .. day .. " • Cycle " .. cycle .. " • Streak ×" .. streak

	pulseStreakLabel(milestone)
	playStreakRewardSound(milestone)

	tweenStreakReward(streakRewardUi.panel, 0.12, {
		Position = UDim2.fromScale(0.5, 0.38),
	}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	task.delay(milestone and 2.8 or 2.2, function()
		if sequence ~= streakRewardSequence then
			return
		end

		tweenStreakReward(streakRewardUi.panel, 0.22, {
			Position = UDim2.fromScale(0.5, 0.36),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenStreakReward(streakRewardUi.stroke, 0.22, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenStreakReward(streakRewardUi.title, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenStreakReward(streakRewardUi.amount, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local detailFade = tweenStreakReward(streakRewardUi.detail, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		detailFade.Completed:Connect(function()
			if sequence ~= streakRewardSequence then
				return
			end
			streakRewardUi.panel.Visible = false
		end)
	end)
end
end

DeepDigShowBadgeUnlockBurst = (function()
	local badgeUnlockUi = {}
badgeUnlockUi.panel = Instance.new("Frame")
badgeUnlockUi.panel.Name = "BadgeUnlockBurst"
badgeUnlockUi.panel.AnchorPoint = Vector2.new(0.5, 0.5)
badgeUnlockUi.panel.Size = UDim2.fromOffset(372, 138)
badgeUnlockUi.panel.Position = UDim2.fromScale(0.5, 0.44)
badgeUnlockUi.panel.BackgroundColor3 = Color3.fromRGB(42, 31, 16)
badgeUnlockUi.panel.BackgroundTransparency = 1
badgeUnlockUi.panel.BorderSizePixel = 0
badgeUnlockUi.panel.Visible = false
badgeUnlockUi.panel.ZIndex = 80
badgeUnlockUi.panel.Parent = screenGui

badgeUnlockUi.corner = Instance.new("UICorner")
badgeUnlockUi.corner.CornerRadius = UDim.new(0, 12)
badgeUnlockUi.corner.Parent = badgeUnlockUi.panel

badgeUnlockUi.stroke = Instance.new("UIStroke")
badgeUnlockUi.stroke.Color = Color3.fromRGB(255, 220, 90)
badgeUnlockUi.stroke.Thickness = 3
badgeUnlockUi.stroke.Transparency = 1
badgeUnlockUi.stroke.Parent = badgeUnlockUi.panel

local function constrainBadgeUnlockText(label, maxTextSize, minTextSize)
	label.TextScaled = true
	label.TextWrapped = true

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxTextSize
	constraint.MinTextSize = minTextSize or 10
	constraint.Parent = label
end

badgeUnlockUi.title = Instance.new("TextLabel")
badgeUnlockUi.title.Name = "Title"
badgeUnlockUi.title.Size = UDim2.new(1, -30, 0, 32)
badgeUnlockUi.title.Position = UDim2.fromOffset(15, 14)
badgeUnlockUi.title.BackgroundTransparency = 1
badgeUnlockUi.title.Text = "🏆 Badge Unlocked"
badgeUnlockUi.title.TextColor3 = Color3.fromRGB(255, 236, 130)
badgeUnlockUi.title.TextTransparency = 1
badgeUnlockUi.title.Font = Enum.Font.GothamBlack
badgeUnlockUi.title.TextXAlignment = Enum.TextXAlignment.Center
badgeUnlockUi.title.ZIndex = 81
constrainBadgeUnlockText(badgeUnlockUi.title, 24, 13)
badgeUnlockUi.title.Parent = badgeUnlockUi.panel

badgeUnlockUi.description = Instance.new("TextLabel")
badgeUnlockUi.description.Name = "Description"
badgeUnlockUi.description.Size = UDim2.new(1, -34, 0, 48)
badgeUnlockUi.description.Position = UDim2.fromOffset(17, 50)
badgeUnlockUi.description.BackgroundTransparency = 1
badgeUnlockUi.description.Text = "Milestone reached"
badgeUnlockUi.description.TextColor3 = Color3.fromRGB(255, 245, 210)
badgeUnlockUi.description.TextTransparency = 1
badgeUnlockUi.description.Font = Enum.Font.GothamBlack
badgeUnlockUi.description.TextXAlignment = Enum.TextXAlignment.Center
badgeUnlockUi.description.TextYAlignment = Enum.TextYAlignment.Center
badgeUnlockUi.description.ZIndex = 81
constrainBadgeUnlockText(badgeUnlockUi.description, 22, 12)
badgeUnlockUi.description.Parent = badgeUnlockUi.panel

badgeUnlockUi.detail = Instance.new("TextLabel")
badgeUnlockUi.detail.Name = "Detail"
badgeUnlockUi.detail.Size = UDim2.new(1, -34, 0, 22)
badgeUnlockUi.detail.Position = UDim2.fromOffset(17, 102)
badgeUnlockUi.detail.BackgroundTransparency = 1
badgeUnlockUi.detail.Text = "Milestone achievement"
badgeUnlockUi.detail.TextColor3 = Color3.fromRGB(225, 195, 115)
badgeUnlockUi.detail.TextTransparency = 1
badgeUnlockUi.detail.Font = Enum.Font.GothamBold
badgeUnlockUi.detail.TextXAlignment = Enum.TextXAlignment.Center
badgeUnlockUi.detail.ZIndex = 81
constrainBadgeUnlockText(badgeUnlockUi.detail, 14, 10)
badgeUnlockUi.detail.Parent = badgeUnlockUi.panel

local badgeUnlockSequence = 0
local badgeUnlockTweens = {}

local function clearBadgeUnlockTweens()
	for _, tween in ipairs(badgeUnlockTweens) do
		tween:Cancel()
	end
	badgeUnlockTweens = {}
end

local function tweenBadgeUnlock(instance, duration, goal, easingStyle, easingDirection)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
		goal
	)
	table.insert(badgeUnlockTweens, tween)
	tween:Play()
	return tween
end

	return function(payload)
	if type(payload) ~= "table" then
		return
	end

	local description = tostring(payload.description or "Milestone reached")

	badgeUnlockSequence = badgeUnlockSequence + 1
	local sequence = badgeUnlockSequence
	clearBadgeUnlockTweens()

	badgeUnlockUi.title.Text = "🏆 Badge Unlocked"
	badgeUnlockUi.description.Text = description
	badgeUnlockUi.detail.Text = "Milestone achievement"

	badgeUnlockUi.panel.Visible = true
	badgeUnlockUi.panel.Size = UDim2.fromOffset(340, 126)
	badgeUnlockUi.panel.Position = UDim2.fromScale(0.5, 0.48)
	badgeUnlockUi.panel.BackgroundTransparency = 1
	badgeUnlockUi.stroke.Transparency = 1
	badgeUnlockUi.title.TextTransparency = 1
	badgeUnlockUi.description.TextTransparency = 1
	badgeUnlockUi.detail.TextTransparency = 1

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("badge_unlock")
	end

	tweenBadgeUnlock(badgeUnlockUi.panel, 0.18, {
		Size = UDim2.fromOffset(372, 138),
		Position = UDim2.fromScale(0.5, 0.42),
		BackgroundTransparency = 0.06,
	}, Enum.EasingStyle.Back)
	tweenBadgeUnlock(badgeUnlockUi.stroke, 0.18, { Transparency = 0 })
	tweenBadgeUnlock(badgeUnlockUi.title, 0.14, { TextTransparency = 0 })
	tweenBadgeUnlock(badgeUnlockUi.description, 0.18, { TextTransparency = 0 })
	tweenBadgeUnlock(badgeUnlockUi.detail, 0.22, { TextTransparency = 0 })

	task.delay(2.8, function()
		if sequence ~= badgeUnlockSequence then
			return
		end

		tweenBadgeUnlock(badgeUnlockUi.panel, 0.24, {
			Position = UDim2.fromScale(0.5, 0.38),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenBadgeUnlock(badgeUnlockUi.stroke, 0.22, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenBadgeUnlock(badgeUnlockUi.title, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenBadgeUnlock(badgeUnlockUi.description, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local detailFade = tweenBadgeUnlock(badgeUnlockUi.detail, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		detailFade.Completed:Connect(function()
			if sequence ~= badgeUnlockSequence then
				return
			end
			badgeUnlockUi.panel.Visible = false
		end)
	end)
	end
end)()

do
local friendReferralRewardUi = {}
friendReferralRewardUi.panel = Instance.new("Frame")
friendReferralRewardUi.panel.Name = "FriendReferralRewardBurst"
friendReferralRewardUi.panel.AnchorPoint = Vector2.new(0.5, 0.5)
friendReferralRewardUi.panel.Size = UDim2.fromOffset(392, 166)
friendReferralRewardUi.panel.Position = UDim2.fromScale(0.5, 0.46)
friendReferralRewardUi.panel.BackgroundColor3 = Color3.fromRGB(18, 42, 38)
friendReferralRewardUi.panel.BackgroundTransparency = 1
friendReferralRewardUi.panel.BorderSizePixel = 0
friendReferralRewardUi.panel.Visible = false
friendReferralRewardUi.panel.ZIndex = 78
friendReferralRewardUi.panel.Parent = screenGui

friendReferralRewardUi.corner = Instance.new("UICorner")
friendReferralRewardUi.corner.CornerRadius = UDim.new(0, 12)
friendReferralRewardUi.corner.Parent = friendReferralRewardUi.panel

friendReferralRewardUi.stroke = Instance.new("UIStroke")
friendReferralRewardUi.stroke.Color = Color3.fromRGB(125, 245, 190)
friendReferralRewardUi.stroke.Thickness = 2
friendReferralRewardUi.stroke.Transparency = 1
friendReferralRewardUi.stroke.Parent = friendReferralRewardUi.panel

local function constrainFriendReferralText(label, maxTextSize, minTextSize)
	label.TextScaled = true
	label.TextWrapped = true

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxTextSize
	constraint.MinTextSize = minTextSize or 10
	constraint.Parent = label
end

friendReferralRewardUi.title = Instance.new("TextLabel")
friendReferralRewardUi.title.Name = "Title"
friendReferralRewardUi.title.Size = UDim2.new(1, -28, 0, 28)
friendReferralRewardUi.title.Position = UDim2.fromOffset(14, 12)
friendReferralRewardUi.title.BackgroundTransparency = 1
friendReferralRewardUi.title.Text = "Friend Reward!"
friendReferralRewardUi.title.TextColor3 = Color3.fromRGB(145, 255, 205)
friendReferralRewardUi.title.TextTransparency = 1
friendReferralRewardUi.title.Font = Enum.Font.GothamBlack
friendReferralRewardUi.title.TextXAlignment = Enum.TextXAlignment.Center
friendReferralRewardUi.title.ZIndex = 79
constrainFriendReferralText(friendReferralRewardUi.title, 23, 13)
friendReferralRewardUi.title.Parent = friendReferralRewardUi.panel

friendReferralRewardUi.friend = Instance.new("TextLabel")
friendReferralRewardUi.friend.Name = "FriendName"
friendReferralRewardUi.friend.Size = UDim2.new(1, -32, 0, 30)
friendReferralRewardUi.friend.Position = UDim2.fromOffset(16, 42)
friendReferralRewardUi.friend.BackgroundTransparency = 1
friendReferralRewardUi.friend.Text = "with a friend"
friendReferralRewardUi.friend.TextColor3 = Color3.fromRGB(235, 255, 246)
friendReferralRewardUi.friend.TextTransparency = 1
friendReferralRewardUi.friend.Font = Enum.Font.GothamBlack
friendReferralRewardUi.friend.TextXAlignment = Enum.TextXAlignment.Center
friendReferralRewardUi.friend.ZIndex = 79
constrainFriendReferralText(friendReferralRewardUi.friend, 21, 11)
friendReferralRewardUi.friend.Parent = friendReferralRewardUi.panel

friendReferralRewardUi.coins = Instance.new("TextLabel")
friendReferralRewardUi.coins.Name = "Coins"
friendReferralRewardUi.coins.Size = UDim2.new(1, -32, 0, 34)
friendReferralRewardUi.coins.Position = UDim2.fromOffset(16, 76)
friendReferralRewardUi.coins.BackgroundTransparency = 1
friendReferralRewardUi.coins.Text = "+0 coins"
friendReferralRewardUi.coins.TextColor3 = Color3.fromRGB(255, 232, 105)
friendReferralRewardUi.coins.TextTransparency = 1
friendReferralRewardUi.coins.Font = Enum.Font.GothamBlack
friendReferralRewardUi.coins.TextXAlignment = Enum.TextXAlignment.Center
friendReferralRewardUi.coins.ZIndex = 79
constrainFriendReferralText(friendReferralRewardUi.coins, 29, 14)
friendReferralRewardUi.coins.Parent = friendReferralRewardUi.panel

friendReferralRewardUi.egg = Instance.new("TextLabel")
friendReferralRewardUi.egg.Name = "Egg"
friendReferralRewardUi.egg.Size = UDim2.new(1, -36, 0, 32)
friendReferralRewardUi.egg.Position = UDim2.fromOffset(18, 114)
friendReferralRewardUi.egg.BackgroundTransparency = 1
friendReferralRewardUi.egg.Text = "Referral Egg"
friendReferralRewardUi.egg.TextColor3 = Color3.fromRGB(210, 235, 230)
friendReferralRewardUi.egg.TextTransparency = 1
friendReferralRewardUi.egg.Font = Enum.Font.GothamBold
friendReferralRewardUi.egg.TextXAlignment = Enum.TextXAlignment.Center
friendReferralRewardUi.egg.ZIndex = 79
constrainFriendReferralText(friendReferralRewardUi.egg, 17, 10)
friendReferralRewardUi.egg.Parent = friendReferralRewardUi.panel

local friendReferralRewardSequence = 0
local friendReferralRewardTweens = {}

local function clearFriendReferralRewardTweens()
	for _, tween in ipairs(friendReferralRewardTweens) do
		tween:Cancel()
	end
	friendReferralRewardTweens = {}
end

local function tweenFriendReferralReward(instance, duration, goal, easingStyle, easingDirection)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
		goal
	)
	table.insert(friendReferralRewardTweens, tween)
	tween:Play()
	return tween
end

local function getFriendReferralEggLabel(eggType)
	eggType = tostring(eggType or Config.FRIEND_REFERRAL_REWARD_EGG or "Stone")
	if eggType == "" then
		eggType = tostring(Config.FRIEND_REFERRAL_REWARD_EGG or "Stone")
	end

	if string.find(string.lower(eggType), "egg", 1, true) then
		return eggType
	end

	return eggType .. " Egg"
end

function showFriendReferralRewardBurst(payload)
	if type(payload) ~= "table" then
		return
	end

	local friendName = tostring(payload.friendName or "your friend")
	local coins = math.floor(tonumber(payload.coins) or Config.FRIEND_REFERRAL_REWARD_COINS or 0)
	local eggLabel = getFriendReferralEggLabel(payload.eggType)
	local eggGranted = payload.eggGranted == true

	friendReferralRewardSequence = friendReferralRewardSequence + 1
	local sequence = friendReferralRewardSequence
	clearFriendReferralRewardTweens()

	friendReferralRewardUi.title.Text = "Friend Reward!"
	friendReferralRewardUi.friend.Text = "with " .. friendName
	friendReferralRewardUi.coins.Text = "+" .. tostring(coins) .. " coins"
	if eggGranted then
		friendReferralRewardUi.egg.Text = eggLabel
		friendReferralRewardUi.egg.TextColor3 = Color3.fromRGB(210, 235, 230)
	else
		friendReferralRewardUi.egg.Text = eggLabel .. " unavailable"
		friendReferralRewardUi.egg.TextColor3 = Color3.fromRGB(255, 170, 130)
	end

	friendReferralRewardUi.panel.Visible = true
	friendReferralRewardUi.panel.Size = UDim2.fromOffset(368, 156)
	friendReferralRewardUi.panel.Position = UDim2.fromScale(0.5, 0.48)
	friendReferralRewardUi.panel.BackgroundTransparency = 1
	friendReferralRewardUi.stroke.Transparency = 1
	friendReferralRewardUi.title.TextTransparency = 1
	friendReferralRewardUi.friend.TextTransparency = 1
	friendReferralRewardUi.coins.TextTransparency = 1
	friendReferralRewardUi.egg.TextTransparency = 1

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("friend_referral_reward")
	end

	tweenFriendReferralReward(friendReferralRewardUi.panel, 0.18, {
		Size = UDim2.fromOffset(392, 166),
		Position = UDim2.fromScale(0.5, 0.44),
		BackgroundTransparency = 0.05,
	}, Enum.EasingStyle.Back)
	tweenFriendReferralReward(friendReferralRewardUi.stroke, 0.18, { Transparency = 0 })
	tweenFriendReferralReward(friendReferralRewardUi.title, 0.14, { TextTransparency = 0 })
	tweenFriendReferralReward(friendReferralRewardUi.friend, 0.17, { TextTransparency = 0 })
	tweenFriendReferralReward(friendReferralRewardUi.coins, 0.2, { TextTransparency = 0 })
	tweenFriendReferralReward(friendReferralRewardUi.egg, 0.22, { TextTransparency = 0 })

	task.delay(3.1, function()
		if sequence ~= friendReferralRewardSequence then
			return
		end

		tweenFriendReferralReward(friendReferralRewardUi.panel, 0.24, {
			Position = UDim2.fromScale(0.5, 0.40),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenFriendReferralReward(friendReferralRewardUi.stroke, 0.22, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenFriendReferralReward(friendReferralRewardUi.title, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenFriendReferralReward(friendReferralRewardUi.friend, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenFriendReferralReward(friendReferralRewardUi.coins, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local eggFade = tweenFriendReferralReward(friendReferralRewardUi.egg, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		eggFade.Completed:Connect(function()
			if sequence ~= friendReferralRewardSequence then
				return
			end
			friendReferralRewardUi.panel.Visible = false
		end)
	end)
end
end

DeepDigAutoCollectedUi = {}
DeepDigAutoCollectedUi.panel = Instance.new("Frame")
DeepDigAutoCollectedUi.panel.Name = "AutoCollectorBurst"
DeepDigAutoCollectedUi.panel.AnchorPoint = Vector2.new(0.5, 0.5)
DeepDigAutoCollectedUi.panel.Size = UDim2.fromOffset(300, 92)
DeepDigAutoCollectedUi.panel.Position = UDim2.fromScale(0.5, 0.34)
DeepDigAutoCollectedUi.panel.BackgroundColor3 = Color3.fromRGB(14, 48, 50)
DeepDigAutoCollectedUi.panel.BackgroundTransparency = 1
DeepDigAutoCollectedUi.panel.BorderSizePixel = 0
DeepDigAutoCollectedUi.panel.Visible = false
DeepDigAutoCollectedUi.panel.ZIndex = 82
DeepDigAutoCollectedUi.panel.Parent = screenGui

DeepDigAutoCollectedUi.corner = Instance.new("UICorner")
DeepDigAutoCollectedUi.corner.CornerRadius = UDim.new(0, 10)
DeepDigAutoCollectedUi.corner.Parent = DeepDigAutoCollectedUi.panel

DeepDigAutoCollectedUi.stroke = Instance.new("UIStroke")
DeepDigAutoCollectedUi.stroke.Color = Color3.fromRGB(70, 235, 215)
DeepDigAutoCollectedUi.stroke.Thickness = 2
DeepDigAutoCollectedUi.stroke.Transparency = 1
DeepDigAutoCollectedUi.stroke.Parent = DeepDigAutoCollectedUi.panel

DeepDigAutoCollectedUi.title = Instance.new("TextLabel")
DeepDigAutoCollectedUi.title.Name = "Title"
DeepDigAutoCollectedUi.title.Size = UDim2.new(1, -24, 0, 24)
DeepDigAutoCollectedUi.title.Position = UDim2.fromOffset(12, 9)
DeepDigAutoCollectedUi.title.BackgroundTransparency = 1
DeepDigAutoCollectedUi.title.Text = "AUTO SOLD"
DeepDigAutoCollectedUi.title.TextColor3 = Color3.fromRGB(94, 255, 224)
DeepDigAutoCollectedUi.title.TextTransparency = 1
DeepDigAutoCollectedUi.title.TextSize = 18
DeepDigAutoCollectedUi.title.Font = Enum.Font.GothamBlack
DeepDigAutoCollectedUi.title.TextXAlignment = Enum.TextXAlignment.Center
DeepDigAutoCollectedUi.title.ZIndex = 83
DeepDigAutoCollectedUi.title.Parent = DeepDigAutoCollectedUi.panel

DeepDigAutoCollectedUi.item = Instance.new("TextLabel")
DeepDigAutoCollectedUi.item.Name = "Item"
DeepDigAutoCollectedUi.item.Size = UDim2.new(1, -24, 0, 24)
DeepDigAutoCollectedUi.item.Position = UDim2.fromOffset(12, 33)
DeepDigAutoCollectedUi.item.BackgroundTransparency = 1
DeepDigAutoCollectedUi.item.Text = "Duplicate find"
DeepDigAutoCollectedUi.item.TextColor3 = Color3.fromRGB(225, 255, 248)
DeepDigAutoCollectedUi.item.TextTransparency = 1
DeepDigAutoCollectedUi.item.TextSize = 15
DeepDigAutoCollectedUi.item.Font = Enum.Font.GothamBold
DeepDigAutoCollectedUi.item.TextWrapped = true
DeepDigAutoCollectedUi.item.TextXAlignment = Enum.TextXAlignment.Center
DeepDigAutoCollectedUi.item.ZIndex = 83
DeepDigAutoCollectedUi.item.Parent = DeepDigAutoCollectedUi.panel

DeepDigAutoCollectedUi.amount = Instance.new("TextLabel")
DeepDigAutoCollectedUi.amount.Name = "Amount"
DeepDigAutoCollectedUi.amount.Size = UDim2.new(1, -24, 0, 28)
DeepDigAutoCollectedUi.amount.Position = UDim2.fromOffset(12, 56)
DeepDigAutoCollectedUi.amount.BackgroundTransparency = 1
DeepDigAutoCollectedUi.amount.Text = "+0 coins"
DeepDigAutoCollectedUi.amount.TextColor3 = Color3.fromRGB(255, 224, 90)
DeepDigAutoCollectedUi.amount.TextTransparency = 1
DeepDigAutoCollectedUi.amount.TextSize = 22
DeepDigAutoCollectedUi.amount.Font = Enum.Font.GothamBlack
DeepDigAutoCollectedUi.amount.TextXAlignment = Enum.TextXAlignment.Center
DeepDigAutoCollectedUi.amount.ZIndex = 83
DeepDigAutoCollectedUi.amount.Parent = DeepDigAutoCollectedUi.panel

DeepDigAutoCollectedSequence = 0
DeepDigAutoCollectedTweens = {}

function DeepDigClearAutoCollectedTweens()
	for _, tween in ipairs(DeepDigAutoCollectedTweens) do
		tween:Cancel()
	end
	DeepDigAutoCollectedTweens = {}
end

function DeepDigTweenAutoCollected(instance, duration, goal, easingStyle, easingDirection)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
		goal
	)
	table.insert(DeepDigAutoCollectedTweens, tween)
	tween:Play()
	return tween
end

function DeepDigShowAutoCollectedBurst(payload)
	if type(payload) ~= "table" then
		return
	end

	local earned = math.floor(tonumber(payload.earned) or 0)
	if earned <= 0 then
		return
	end

	local itemName = tostring(payload.name or "Duplicate find")
	local rarity = tostring(payload.rarity or "Common")

	DeepDigAutoCollectedSequence = DeepDigAutoCollectedSequence + 1
	local sequence = DeepDigAutoCollectedSequence
	DeepDigClearAutoCollectedTweens()

	DeepDigAutoCollectedUi.panel.Visible = true
	DeepDigAutoCollectedUi.panel.Size = UDim2.fromOffset(282, 86)
	DeepDigAutoCollectedUi.panel.Position = UDim2.fromScale(0.5, 0.36)
	DeepDigAutoCollectedUi.panel.BackgroundTransparency = 0.18
	DeepDigAutoCollectedUi.stroke.Transparency = 0
	DeepDigAutoCollectedUi.stroke.Thickness = 2
	DeepDigAutoCollectedUi.title.TextTransparency = 0
	DeepDigAutoCollectedUi.item.TextTransparency = 0
	DeepDigAutoCollectedUi.amount.TextTransparency = 0
	DeepDigAutoCollectedUi.item.Text = itemName .. " - " .. rarity
	DeepDigAutoCollectedUi.amount.Text = "+" .. tostring(earned) .. " coins"

	DeepDigTweenAutoCollected(DeepDigAutoCollectedUi.panel, 0.14, {
		Size = UDim2.fromOffset(318, 98),
		Position = UDim2.fromScale(0.5, 0.34),
		BackgroundTransparency = 0.08,
	}, Enum.EasingStyle.Back)
	DeepDigTweenAutoCollected(DeepDigAutoCollectedUi.stroke, 0.18, {
		Color = Color3.fromRGB(255, 220, 88),
	})

	task.delay(1.35, function()
		if sequence ~= DeepDigAutoCollectedSequence then
			return
		end

		DeepDigTweenAutoCollected(DeepDigAutoCollectedUi.panel, 0.22, {
			Position = UDim2.fromScale(0.5, 0.31),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		DeepDigTweenAutoCollected(DeepDigAutoCollectedUi.stroke, 0.2, {
			Transparency = 1,
			Color = Color3.fromRGB(70, 235, 215),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		DeepDigTweenAutoCollected(DeepDigAutoCollectedUi.title, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		DeepDigTweenAutoCollected(DeepDigAutoCollectedUi.item, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local amountFade = DeepDigTweenAutoCollected(DeepDigAutoCollectedUi.amount, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		amountFade.Completed:Connect(function()
			if sequence ~= DeepDigAutoCollectedSequence then
				return
			end
			DeepDigAutoCollectedUi.panel.Visible = false
		end)
	end)
end

DeepDigArtifactDetectorUi = {}
DeepDigArtifactDetectorUi.panel = Instance.new("Frame")
DeepDigArtifactDetectorUi.panel.Name = "ArtifactDetectorPulse"
DeepDigArtifactDetectorUi.panel.AnchorPoint = Vector2.new(0.5, 0)
DeepDigArtifactDetectorUi.panel.Size = UDim2.fromOffset(286, 64)
DeepDigArtifactDetectorUi.panel.Position = UDim2.fromScale(0.5, 0.105)
DeepDigArtifactDetectorUi.panel.BackgroundColor3 = Color3.fromRGB(8, 28, 38)
DeepDigArtifactDetectorUi.panel.BackgroundTransparency = 1
DeepDigArtifactDetectorUi.panel.BorderSizePixel = 0
DeepDigArtifactDetectorUi.panel.ClipsDescendants = true
DeepDigArtifactDetectorUi.panel.Visible = false
DeepDigArtifactDetectorUi.panel.ZIndex = 74
DeepDigArtifactDetectorUi.panel.Parent = screenGui

DeepDigArtifactDetectorUi.corner = Instance.new("UICorner")
DeepDigArtifactDetectorUi.corner.CornerRadius = UDim.new(0, 8)
DeepDigArtifactDetectorUi.corner.Parent = DeepDigArtifactDetectorUi.panel

DeepDigArtifactDetectorUi.stroke = Instance.new("UIStroke")
DeepDigArtifactDetectorUi.stroke.Color = Color3.fromRGB(70, 235, 215)
DeepDigArtifactDetectorUi.stroke.Thickness = 1.5
DeepDigArtifactDetectorUi.stroke.Transparency = 1
DeepDigArtifactDetectorUi.stroke.Parent = DeepDigArtifactDetectorUi.panel

DeepDigArtifactDetectorUi.sweep = Instance.new("Frame")
DeepDigArtifactDetectorUi.sweep.Name = "Sweep"
DeepDigArtifactDetectorUi.sweep.Size = UDim2.new(0, 34, 1, 0)
DeepDigArtifactDetectorUi.sweep.Position = UDim2.new(0, -42, 0, 0)
DeepDigArtifactDetectorUi.sweep.BackgroundColor3 = Color3.fromRGB(120, 255, 235)
DeepDigArtifactDetectorUi.sweep.BackgroundTransparency = 0.35
DeepDigArtifactDetectorUi.sweep.BorderSizePixel = 0
DeepDigArtifactDetectorUi.sweep.ZIndex = 75
DeepDigArtifactDetectorUi.sweep.Parent = DeepDigArtifactDetectorUi.panel

DeepDigArtifactDetectorUi.sweepGradient = Instance.new("UIGradient")
DeepDigArtifactDetectorUi.sweepGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.45, 0.25),
	NumberSequenceKeypoint.new(1, 1),
})
DeepDigArtifactDetectorUi.sweepGradient.Parent = DeepDigArtifactDetectorUi.sweep

DeepDigArtifactDetectorUi.title = Instance.new("TextLabel")
DeepDigArtifactDetectorUi.title.Name = "Title"
DeepDigArtifactDetectorUi.title.Size = UDim2.new(1, -24, 0, 20)
DeepDigArtifactDetectorUi.title.Position = UDim2.fromOffset(12, 8)
DeepDigArtifactDetectorUi.title.BackgroundTransparency = 1
DeepDigArtifactDetectorUi.title.Text = "DETECTOR PING"
DeepDigArtifactDetectorUi.title.TextColor3 = Color3.fromRGB(110, 255, 232)
DeepDigArtifactDetectorUi.title.TextTransparency = 1
DeepDigArtifactDetectorUi.title.TextSize = 14
DeepDigArtifactDetectorUi.title.Font = Enum.Font.GothamBlack
DeepDigArtifactDetectorUi.title.TextXAlignment = Enum.TextXAlignment.Center
DeepDigArtifactDetectorUi.title.ZIndex = 76
DeepDigArtifactDetectorUi.title.Parent = DeepDigArtifactDetectorUi.panel

DeepDigArtifactDetectorUi.item = Instance.new("TextLabel")
DeepDigArtifactDetectorUi.item.Name = "Item"
DeepDigArtifactDetectorUi.item.Size = UDim2.new(1, -24, 0, 24)
DeepDigArtifactDetectorUi.item.Position = UDim2.fromOffset(12, 31)
DeepDigArtifactDetectorUi.item.BackgroundTransparency = 1
DeepDigArtifactDetectorUi.item.Text = "Rare artifact"
DeepDigArtifactDetectorUi.item.TextColor3 = Color3.fromRGB(225, 255, 248)
DeepDigArtifactDetectorUi.item.TextTransparency = 1
DeepDigArtifactDetectorUi.item.TextSize = 16
DeepDigArtifactDetectorUi.item.Font = Enum.Font.GothamBold
DeepDigArtifactDetectorUi.item.TextWrapped = true
DeepDigArtifactDetectorUi.item.TextXAlignment = Enum.TextXAlignment.Center
DeepDigArtifactDetectorUi.item.ZIndex = 76
DeepDigArtifactDetectorUi.item.Parent = DeepDigArtifactDetectorUi.panel

DeepDigArtifactDetectorSequence = 0
DeepDigArtifactDetectorTweens = {}

function DeepDigClearArtifactDetectorTweens()
	for _, tween in ipairs(DeepDigArtifactDetectorTweens) do
		tween:Cancel()
	end
	DeepDigArtifactDetectorTweens = {}
end

function DeepDigTweenArtifactDetector(instance, duration, goal, easingStyle, easingDirection)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
		goal
	)
	table.insert(DeepDigArtifactDetectorTweens, tween)
	tween:Play()
	return tween
end

function DeepDigShowArtifactDetectorPulse(payload)
	if type(payload) ~= "table" then
		return
	end

	local itemName = tostring(payload.name or "Rare artifact")
	local rarity = tostring(payload.rarity or "Rare")
	local rarityColor = RARITY_COLORS[rarity] or Color3.fromRGB(110, 255, 232)

	DeepDigArtifactDetectorSequence = DeepDigArtifactDetectorSequence + 1
	local sequence = DeepDigArtifactDetectorSequence
	DeepDigClearArtifactDetectorTweens()

	DeepDigArtifactDetectorUi.panel.Visible = true
	DeepDigArtifactDetectorUi.panel.Size = UDim2.fromOffset(286, 64)
	DeepDigArtifactDetectorUi.panel.Position = UDim2.fromScale(0.5, 0.105)
	DeepDigArtifactDetectorUi.panel.BackgroundTransparency = 0.16
	DeepDigArtifactDetectorUi.stroke.Color = rarityColor
	DeepDigArtifactDetectorUi.stroke.Transparency = 0.08
	DeepDigArtifactDetectorUi.sweep.Position = UDim2.new(0, -42, 0, 0)
	DeepDigArtifactDetectorUi.sweep.BackgroundTransparency = 0.28
	DeepDigArtifactDetectorUi.title.TextTransparency = 0
	DeepDigArtifactDetectorUi.item.TextTransparency = 0
	DeepDigArtifactDetectorUi.item.TextColor3 = rarityColor
	DeepDigArtifactDetectorUi.item.Text = itemName .. " - " .. rarity

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("artifact_detector_ping")
	end

	DeepDigTweenArtifactDetector(DeepDigArtifactDetectorUi.panel, 0.12, {
		Size = UDim2.fromOffset(304, 68),
		Position = UDim2.fromScale(0.5, 0.112),
		BackgroundTransparency = 0.06,
	}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	DeepDigTweenArtifactDetector(DeepDigArtifactDetectorUi.sweep, 0.42, {
		Position = UDim2.new(1, 8, 0, 0),
	}, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	DeepDigTweenArtifactDetector(DeepDigArtifactDetectorUi.stroke, 0.22, {
		Thickness = 2.5,
	}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	task.delay(0.58, function()
		if sequence ~= DeepDigArtifactDetectorSequence then
			return
		end

		DeepDigTweenArtifactDetector(DeepDigArtifactDetectorUi.panel, 0.2, {
			Size = UDim2.fromOffset(286, 64),
			BackgroundTransparency = 0.16,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		DeepDigTweenArtifactDetector(DeepDigArtifactDetectorUi.stroke, 0.2, {
			Thickness = 1.5,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end)

	task.delay(1.2, function()
		if sequence ~= DeepDigArtifactDetectorSequence then
			return
		end

		DeepDigTweenArtifactDetector(DeepDigArtifactDetectorUi.panel, 0.22, {
			Position = UDim2.fromScale(0.5, 0.095),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		DeepDigTweenArtifactDetector(DeepDigArtifactDetectorUi.stroke, 0.18, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		DeepDigTweenArtifactDetector(DeepDigArtifactDetectorUi.sweep, 0.18, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		DeepDigTweenArtifactDetector(DeepDigArtifactDetectorUi.title, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local itemFade = DeepDigTweenArtifactDetector(DeepDigArtifactDetectorUi.item, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		itemFade.Completed:Connect(function()
			if sequence ~= DeepDigArtifactDetectorSequence then
				return
			end
			DeepDigArtifactDetectorUi.panel.Visible = false
		end)
	end)
end

local offlineIncomePanel = Instance.new("Frame")
offlineIncomePanel.Name = "OfflineIncomeReward"
offlineIncomePanel.AnchorPoint = Vector2.new(0.5, 0.5)
offlineIncomePanel.Size = UDim2.new(0, 390, 0, 190)
offlineIncomePanel.Position = UDim2.new(0.5, 0, 0.5, 0)
offlineIncomePanel.BackgroundColor3 = Color3.fromRGB(24, 20, 18)
offlineIncomePanel.BackgroundTransparency = 0.04
offlineIncomePanel.BorderSizePixel = 0
offlineIncomePanel.Visible = false
offlineIncomePanel.ZIndex = 76
offlineIncomePanel.Parent = screenGui

local offlineIncomeCorner = Instance.new("UICorner")
offlineIncomeCorner.CornerRadius = UDim.new(0, 14)
offlineIncomeCorner.Parent = offlineIncomePanel

local offlineIncomeStroke = Instance.new("UIStroke")
offlineIncomeStroke.Color = Color3.fromRGB(255, 200, 50)
offlineIncomeStroke.Thickness = 2
offlineIncomeStroke.Transparency = 1
offlineIncomeStroke.Parent = offlineIncomePanel

local offlineIncomeTitle = Instance.new("TextLabel")
offlineIncomeTitle.Name = "Title"
offlineIncomeTitle.Size = UDim2.new(1, -28, 0, 36)
offlineIncomeTitle.Position = UDim2.new(0, 14, 0, 12)
offlineIncomeTitle.BackgroundTransparency = 1
offlineIncomeTitle.Text = "Welcome back!"
offlineIncomeTitle.TextColor3 = Color3.fromRGB(255, 200, 50)
offlineIncomeTitle.TextSize = 24
offlineIncomeTitle.Font = Enum.Font.GothamBlack
offlineIncomeTitle.TextXAlignment = Enum.TextXAlignment.Center
offlineIncomeTitle.ZIndex = 77
offlineIncomeTitle.Parent = offlineIncomePanel

local offlineIncomeReward = Instance.new("TextLabel")
offlineIncomeReward.Name = "Reward"
offlineIncomeReward.Size = UDim2.new(1, -28, 0, 38)
offlineIncomeReward.Position = UDim2.new(0, 14, 0, 50)
offlineIncomeReward.BackgroundTransparency = 1
offlineIncomeReward.Text = "+0 coins"
offlineIncomeReward.TextColor3 = Color3.fromRGB(255, 230, 110)
offlineIncomeReward.TextSize = 28
offlineIncomeReward.Font = Enum.Font.GothamBlack
offlineIncomeReward.TextXAlignment = Enum.TextXAlignment.Center
offlineIncomeReward.ZIndex = 77
offlineIncomeReward.Parent = offlineIncomePanel

local offlineIncomeBody = Instance.new("TextLabel")
offlineIncomeBody.Name = "Body"
offlineIncomeBody.Size = UDim2.new(1, -36, 0, 44)
offlineIncomeBody.Position = UDim2.new(0, 18, 0, 88)
offlineIncomeBody.BackgroundTransparency = 1
offlineIncomeBody.Text = "Your crew kept digging while you were away."
offlineIncomeBody.TextColor3 = Color3.fromRGB(230, 225, 215)
offlineIncomeBody.TextSize = 15
offlineIncomeBody.Font = Enum.Font.GothamMedium
offlineIncomeBody.TextWrapped = true
offlineIncomeBody.TextXAlignment = Enum.TextXAlignment.Center
offlineIncomeBody.TextYAlignment = Enum.TextYAlignment.Center
offlineIncomeBody.ZIndex = 77
offlineIncomeBody.Parent = offlineIncomePanel

local offlineIncomeCap = Instance.new("TextLabel")
offlineIncomeCap.Name = "Cap"
offlineIncomeCap.Size = UDim2.new(1, -36, 0, 22)
offlineIncomeCap.Position = UDim2.new(0, 18, 0, 130)
offlineIncomeCap.BackgroundTransparency = 1
offlineIncomeCap.Text = "Counted 0m of 8h cap"
offlineIncomeCap.TextColor3 = Color3.fromRGB(180, 170, 150)
offlineIncomeCap.TextSize = 13
offlineIncomeCap.Font = Enum.Font.Gotham
offlineIncomeCap.TextXAlignment = Enum.TextXAlignment.Center
offlineIncomeCap.ZIndex = 77
offlineIncomeCap.Parent = offlineIncomePanel

local offlineIncomeClaim = Instance.new("TextButton")
offlineIncomeClaim.Name = "Claim"
offlineIncomeClaim.Size = UDim2.new(0, 150, 0, 34)
offlineIncomeClaim.Position = UDim2.new(0.5, -75, 1, -44)
offlineIncomeClaim.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
offlineIncomeClaim.BorderSizePixel = 0
offlineIncomeClaim.Text = "Collect"
offlineIncomeClaim.TextColor3 = Color3.fromRGB(40, 20, 0)
offlineIncomeClaim.TextSize = 15
offlineIncomeClaim.Font = Enum.Font.GothamBlack
offlineIncomeClaim.ZIndex = 77
offlineIncomeClaim.Parent = offlineIncomePanel

local offlineIncomeClaimCorner = Instance.new("UICorner")
offlineIncomeClaimCorner.CornerRadius = UDim.new(0, 8)
offlineIncomeClaimCorner.Parent = offlineIncomeClaim

(function(button)
	button.Name = "ForemanPass"
	button.Size = UDim2.new(0, 150, 0, 34)
	button.Position = UDim2.new(0.5, -75, 1, -44)
	button.BackgroundColor3 = Color3.fromRGB(95, 205, 160)
	button.BorderSizePixel = 0
	button.Text = "Foreman's Pass"
	button.TextColor3 = Color3.fromRGB(8, 35, 24)
	button.TextSize = 14
	button.Font = Enum.Font.GothamBlack
	button.Visible = false
	button.ZIndex = 77
	button.Parent = offlineIncomePanel

	(function(corner)
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button
	end)(Instance.new("UICorner"))
end)(Instance.new("TextButton"))

local showOfflineIncomePopup

do
	local offlineIncomeState = {
		sequence = 0,
		lastKey = nil,
		tweens = {},
		foremanUpsellActive = false,
		foremanUpsellAvailable = false,
	}
	offlineIncomeState.foremanUpsell = offlineIncomePanel:WaitForChild("ForemanPass")

	offlineIncomeState.formatDuration = function(seconds)
		seconds = math.max(0, math.floor(seconds or 0))

		local hours = math.floor(seconds / 3600)
		local minutes = math.floor((seconds % 3600) / 60)

		if hours > 0 and minutes > 0 then
			return hours .. "h " .. minutes .. "m"
		end

		if hours > 0 then
			return hours .. "h"
		end

		return minutes .. "m"
	end

	offlineIncomeState.normalCapDuration = offlineIncomeState.formatDuration(Config.OFFLINE_INCOME_DEFAULT_CAP_SECONDS)
	offlineIncomeState.foremanCapDuration = offlineIncomeState.formatDuration(Config.OFFLINE_INCOME_FOREMAN_CAP_SECONDS)

	local function clearOfflineIncomeTweens()
		for _, tween in ipairs(offlineIncomeState.tweens) do
			tween:Cancel()
		end
		offlineIncomeState.tweens = {}
	end

	local function tweenOfflineIncome(instance, duration, goal, easingStyle, easingDirection)
		local tween = TweenService:Create(
			instance,
			TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
			goal
		)
		table.insert(offlineIncomeState.tweens, tween)
		tween:Play()
		return tween
	end

	local function hideOfflineIncomePopup()
		if not offlineIncomePanel.Visible then
			return
		end

		offlineIncomeState.sequence = offlineIncomeState.sequence + 1
		local sequence = offlineIncomeState.sequence
		clearOfflineIncomeTweens()

		tweenOfflineIncome(offlineIncomePanel, 0.22, {
			Position = UDim2.new(0.5, 0, 0.47, 0),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenOfflineIncome(offlineIncomeStroke, 0.2, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenOfflineIncome(offlineIncomeTitle, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenOfflineIncome(offlineIncomeReward, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenOfflineIncome(offlineIncomeBody, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenOfflineIncome(offlineIncomeCap, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		if offlineIncomeState.foremanUpsell.Visible then
			tweenOfflineIncome(offlineIncomeState.foremanUpsell, 0.18, {
				BackgroundTransparency = 1,
				TextTransparency = 1,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		tweenOfflineIncome(offlineIncomeClaim, 0.18, {
			BackgroundTransparency = 1,
			TextTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Connect(function()
			if sequence ~= offlineIncomeState.sequence then
				return
			end

			offlineIncomePanel.Visible = false
		end)
	end

	function showOfflineIncomePopup(summary)
		local reward = summary and math.floor(tonumber(summary.reward) or 0) or 0
		if reward <= 0 then
			return
		end

		local countedDuration = summary.countedDuration or "0m"
		local capDuration = summary.capDuration or "8h"
		local popupKey = tostring(reward) .. "|" .. tostring(countedDuration) .. "|" .. tostring(capDuration) .. "|" .. tostring(summary.hitCap == true)
		local showForemanUpsell = summary.hitCap == true and tostring(capDuration) == offlineIncomeState.normalCapDuration
		local foremanPassAvailable = Config.isGamepassIdAvailable(Config.GAMEPASS_FOREMAN_ID)
		if popupKey == offlineIncomeState.lastKey then
			return
		end

		offlineIncomeState.lastKey = popupKey
		offlineIncomeState.sequence = offlineIncomeState.sequence + 1
		local sequence = offlineIncomeState.sequence
		offlineIncomeState.foremanUpsellActive = showForemanUpsell
		offlineIncomeState.foremanUpsellAvailable = foremanPassAvailable
		clearOfflineIncomeTweens()

		offlineIncomeReward.Text = "+" .. tostring(reward) .. " coins"
		offlineIncomeClaim.Text = "Collect"
		offlineIncomeClaim.Size = UDim2.new(0, 150, 0, 34)
		offlineIncomeClaim.Position = UDim2.new(0.5, -75, 1, -44)
		offlineIncomeClaim.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
		offlineIncomeClaim.TextColor3 = Color3.fromRGB(40, 20, 0)
		offlineIncomeState.foremanUpsell.Visible = false
		offlineIncomeState.foremanUpsell.Active = false
		offlineIncomeState.foremanUpsell.AutoButtonColor = false
		offlineIncomeState.foremanUpsell.BackgroundColor3 = Color3.fromRGB(95, 205, 160)
		offlineIncomeState.foremanUpsell.TextColor3 = Color3.fromRGB(8, 35, 24)
		offlineIncomeState.foremanUpsell.Text = "Foreman's Pass"

		if showForemanUpsell then
			offlineIncomeBody.Text = "You hit the " .. offlineIncomeState.normalCapDuration .. " offline cap. Foreman's Pass extends offline earnings to " .. offlineIncomeState.foremanCapDuration .. "."
			offlineIncomeCap.Text = "Offline time counted: " .. countedDuration .. " of " .. offlineIncomeState.normalCapDuration
			offlineIncomeClaim.Size = UDim2.new(0, 130, 0, 34)
			offlineIncomeClaim.Position = UDim2.new(0.5, -140, 1, -44)
			offlineIncomeState.foremanUpsell.Position = UDim2.new(0.5, -5, 1, -44)
			offlineIncomeState.foremanUpsell.Visible = true
			if foremanPassAvailable then
				offlineIncomeState.foremanUpsell.Active = true
				offlineIncomeState.foremanUpsell.AutoButtonColor = true
			else
				offlineIncomeState.foremanUpsell.Text = Config.UNAVAILABLE_GAMEPASS_LABEL or "Coming Soon"
				offlineIncomeState.foremanUpsell.BackgroundColor3 = Color3.fromRGB(80, 76, 70)
				offlineIncomeState.foremanUpsell.TextColor3 = Color3.fromRGB(190, 184, 170)
			end
		else
			offlineIncomeBody.Text = "Offline time counted: " .. countedDuration
		end
		if summary.hitCap == true and not showForemanUpsell then
			offlineIncomeCap.Text = "You hit the " .. capDuration .. " offline cap."
		elseif not showForemanUpsell then
			offlineIncomeCap.Text = "Cap window: " .. capDuration .. " (not reached)."
		end

		offlineIncomePanel.Visible = true
		offlineIncomePanel.Size = showForemanUpsell and UDim2.new(0, 400, 0, 196) or UDim2.new(0, 370, 0, 182)
		offlineIncomePanel.Position = UDim2.new(0.5, 0, 0.53, 0)
		offlineIncomePanel.BackgroundTransparency = 1
		offlineIncomeStroke.Transparency = 1
		offlineIncomeTitle.TextTransparency = 1
		offlineIncomeReward.TextTransparency = 1
		offlineIncomeBody.TextTransparency = 1
		offlineIncomeCap.TextTransparency = 1
		offlineIncomeClaim.BackgroundTransparency = 1
		offlineIncomeClaim.TextTransparency = 1
		offlineIncomeState.foremanUpsell.BackgroundTransparency = 1
		offlineIncomeState.foremanUpsell.TextTransparency = 1

		tweenOfflineIncome(offlineIncomePanel, 0.18, {
			Size = showForemanUpsell and UDim2.new(0, 420, 0, 204) or UDim2.new(0, 390, 0, 190),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			BackgroundTransparency = 0.04,
		}, Enum.EasingStyle.Back)
		tweenOfflineIncome(offlineIncomeStroke, 0.18, { Transparency = 0 })
		tweenOfflineIncome(offlineIncomeTitle, 0.16, { TextTransparency = 0 })
		tweenOfflineIncome(offlineIncomeReward, 0.2, { TextTransparency = 0 })
		tweenOfflineIncome(offlineIncomeBody, 0.2, { TextTransparency = 0 })
		tweenOfflineIncome(offlineIncomeCap, 0.22, { TextTransparency = 0 })
		tweenOfflineIncome(offlineIncomeClaim, 0.2, {
			BackgroundTransparency = 0,
			TextTransparency = 0,
		})
		if showForemanUpsell then
			tweenOfflineIncome(offlineIncomeState.foremanUpsell, 0.2, {
				BackgroundTransparency = 0,
				TextTransparency = 0,
			})
		end

		if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
			LocalPlaySound:Fire("sell_coins")
		end

		task.delay(7, function()
			if sequence ~= offlineIncomeState.sequence then
				return
			end

			hideOfflineIncomePopup()
		end)
	end

	offlineIncomeClaim.MouseButton1Click:Connect(function()
		hideOfflineIncomePopup()
	end)

	offlineIncomeState.foremanUpsell.MouseButton1Click:Connect(function()
		if not offlineIncomeState.foremanUpsellActive or not offlineIncomeState.foremanUpsellAvailable then
			return
		end
		if Remotes:FindFirstChild("PromptGamepass") then
			Remotes.PromptGamepass:FireServer(Config.GAMEPASS_FOREMAN_ID)
		end
	end)
end

local function refreshStreakRevivePrompt(data)
	if data then
		if data.loginStreak ~= nil then
			currentLoginStreak = data.loginStreak
		end
		if data.streakReviveEligible ~= nil then
			currentStreakReviveEligible = data.streakReviveEligible
		end
		if data.streakRevivePending ~= nil then
			currentStreakRevivePending = data.streakRevivePending
		end
		if data.streakReviveBaseStreak ~= nil then
			currentStreakReviveBaseStreak = data.streakReviveBaseStreak
		end
		if data.streakRevivePrice ~= nil then
			currentStreakRevivePrice = data.streakRevivePrice
		end
		if data.streakReviveProductAvailable ~= nil then
			currentStreakReviveProductAvailable = data.streakReviveProductAvailable == true
		end
	end

	refreshStreakLabel()

	local shouldShow = currentStreakReviveEligible and currentStreakRevivePending
	streakRevivePanel.Visible = shouldShow

	if not shouldShow then
		return
	end

	local streak = math.max(currentStreakReviveBaseStreak, currentLoginStreak)
	local day = streak > 0 and ((streak - 1) % 7 + 1) or 1
	local cycle = streak > 0 and math.floor((streak - 1) / 7) + 1 or 1

	streakReviveTitle.Text = "🔥 Streak Revive"
	if currentStreakReviveProductAvailable then
		streakReviveBody.Text = "You missed one day. Revive your streak for " .. currentStreakRevivePrice .. " Robux to keep your momentum and today's reward."
	else
		streakReviveBody.Text = "You missed one day. Streak revive purchases are unavailable right now. Start over to claim today's reward."
	end
	streakReviveDetail.Text = "Current streak: Day " .. day .. " (×" .. streak .. ", Cycle " .. cycle .. ")"
	if currentStreakReviveProductAvailable then
		streakReviveBuyButton.Text = "Revive for " .. currentStreakRevivePrice .. " Robux"
		streakReviveBuyButton.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
		streakReviveBuyButton.TextColor3 = Color3.fromRGB(40, 20, 0)
	else
		streakReviveBuyButton.Text = "Revive unavailable"
		streakReviveBuyButton.BackgroundColor3 = Color3.fromRGB(90, 85, 78)
		streakReviveBuyButton.TextColor3 = Color3.fromRGB(210, 205, 195)
	end
end

streakReviveBuyButton.MouseButton1Click:Connect(function()
	if not currentStreakReviveEligible or not currentStreakRevivePending then
		return
	end

	RequestStreakReviveEvent:FireServer("buy")
end)

streakReviveDeclineButton.MouseButton1Click:Connect(function()
	if not currentStreakRevivePending then
		return
	end

	RequestStreakReviveEvent:FireServer("decline")
end)

-- ═══════════════════════════════════════════════════════════════════
-- Sell All Button
-- ═══════════════════════════════════════════════════════════════════

local sellButton = Instance.new("TextButton")
sellButton.Name = "SellAll"
sellButton.Size = UDim2.new(0, 120, 0, 40)
sellButton.Position = UDim2.new(1, -140, 1, -60)
sellButton.BackgroundColor3 = Color3.fromRGB(40, 160, 40)
sellButton.BorderSizePixel = 0
sellButton.Text = "💰 Sell All"
sellButton.TextColor3 = Color3.fromRGB(255, 255, 255)
sellButton.TextSize = 16
sellButton.Font = Enum.Font.GothamBold
sellButton.Parent = screenGui

local sellCorner = Instance.new("UICorner")
sellCorner.CornerRadius = UDim.new(0, 8)
sellCorner.Parent = sellButton

do
	local sellGlow = Instance.new("UIStroke")
	sellGlow.Name = "FullBackpackGlow"
	sellGlow.Color = Color3.fromRGB(255, 230, 110)
	sellGlow.Thickness = 2
	sellGlow.Transparency = 1
	sellGlow.Parent = sellButton

	local restColor = sellButton.BackgroundColor3
	local restTextColor = sellButton.TextColor3
	local activeSellButtonTween = nil
	local activeSellGlowTween = nil
	local sellPulseSequence = 0

	pulseSellAllButton = function()
		sellPulseSequence = sellPulseSequence + 1
		local sequence = sellPulseSequence

		if activeSellButtonTween then
			activeSellButtonTween:Cancel()
		end
		if activeSellGlowTween then
			activeSellGlowTween:Cancel()
		end

		sellButton.BackgroundColor3 = Color3.fromRGB(75, 220, 75)
		sellButton.TextColor3 = Color3.fromRGB(255, 255, 210)
		sellGlow.Transparency = 0.05

		activeSellButtonTween = TweenService:Create(
			sellButton,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				BackgroundColor3 = restColor,
				TextColor3 = restTextColor,
			}
		)
		activeSellGlowTween = TweenService:Create(
			sellGlow,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 1 }
		)

		activeSellButtonTween:Play()
		activeSellGlowTween:Play()
		activeSellButtonTween.Completed:Connect(function()
			if sequence ~= sellPulseSequence then return end
			sellButton.BackgroundColor3 = restColor
			sellButton.TextColor3 = restTextColor
			sellGlow.Transparency = 1
		end)
	end
end

sellButton.MouseButton1Click:Connect(function()
	Remotes.SellAll:FireServer()
end)

-- ═══════════════════════════════════════════════════════════════════
-- Recycle Duplicates Button
-- ═══════════════════════════════════════════════════════════════════

local recycleButton = Instance.new("TextButton")
recycleButton.Name = "RecycleDupes"
recycleButton.Size = UDim2.new(0, 140, 0, 40)
recycleButton.Position = UDim2.new(1, -290, 1, -110)
recycleButton.BackgroundColor3 = Color3.fromRGB(160, 80, 200)
recycleButton.BorderSizePixel = 0
recycleButton.Text = "♻️ Recycle Dupes"
recycleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
recycleButton.TextSize = 14
recycleButton.Font = Enum.Font.GothamBold
recycleButton.Parent = screenGui

local recycleCorner = Instance.new("UICorner")
recycleCorner.CornerRadius = UDim.new(0, 8)
recycleCorner.Parent = recycleButton

recycleButton.MouseButton1Click:Connect(function()
	Remotes.RecycleAllDupes:FireServer()
end)

-- ═══════════════════════════════════════════════════════════════════
-- Upgrade Tool Button
-- ═══════════════════════════════════════════════════════════════════

local upgradeButton = Instance.new("TextButton")
upgradeButton.Name = "UpgradeTool"
upgradeButton.Size = UDim2.new(0, 180, 0, 40)
upgradeButton.Position = UDim2.new(1, -340, 1, -60)
upgradeButton.BackgroundColor3 = Color3.fromRGB(40, 80, 200)
upgradeButton.BorderSizePixel = 0
upgradeButton.Text = "⬆️ Upgrade: ???"
upgradeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
upgradeButton.TextSize = 14
upgradeButton.Font = Enum.Font.GothamBold
upgradeButton.Parent = screenGui

local upCorner = Instance.new("UICorner")
upCorner.CornerRadius = UDim.new(0, 8)
upCorner.Parent = upgradeButton

local currentToolTier = 1
local updateUpgradeAffordance = function() end

do
	local upgradeStroke = Instance.new("UIStroke")
	upgradeStroke.Color = Color3.fromRGB(85, 130, 245)
	upgradeStroke.Thickness = 1
	upgradeStroke.Transparency = 0.55
	upgradeStroke.Parent = upgradeButton

	local upgradeAffordance = {
		currentCoins = 0,
		currentNextToolCost = nil,
		atMaxLevel = false,
		ready = false,
		sequence = 0,
		tween = nil,
		strokeTween = nil,
		normalColor = Color3.fromRGB(40, 80, 200),
		normalStrokeColor = Color3.fromRGB(85, 130, 245),
		readyColor = Color3.fromRGB(225, 145, 35),
		readyPulseColor = Color3.fromRGB(255, 190, 65),
		readyStrokeColor = Color3.fromRGB(255, 220, 115),
		maxColor = Color3.fromRGB(80, 80, 80),
		maxStrokeColor = Color3.fromRGB(120, 120, 120),
	}

	local function stopUpgradeAffordanceTweens()
		if upgradeAffordance.tween then
			upgradeAffordance.tween:Cancel()
			upgradeAffordance.tween = nil
		end
		if upgradeAffordance.strokeTween then
			upgradeAffordance.strokeTween:Cancel()
			upgradeAffordance.strokeTween = nil
		end
	end

	local function scheduleUpgradeReadyPulse(sequence)
		task.delay(0.65, function()
			if sequence ~= upgradeAffordance.sequence or not upgradeAffordance.ready or upgradeAffordance.atMaxLevel then
				return
			end

			stopUpgradeAffordanceTweens()
			upgradeButton.BackgroundColor3 = upgradeAffordance.readyPulseColor
			upgradeStroke.Color = upgradeAffordance.readyStrokeColor
			upgradeStroke.Transparency = 0.02

			upgradeAffordance.tween = TweenService:Create(
				upgradeButton,
				TweenInfo.new(0.42, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ BackgroundColor3 = upgradeAffordance.readyColor }
			)
			upgradeAffordance.strokeTween = TweenService:Create(
				upgradeStroke,
				TweenInfo.new(0.42, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ Transparency = 0.12 }
			)

			upgradeAffordance.tween:Play()
			upgradeAffordance.strokeTween:Play()
			upgradeAffordance.tween.Completed:Connect(function(playbackState)
				if playbackState ~= Enum.PlaybackState.Completed
					or sequence ~= upgradeAffordance.sequence
					or not upgradeAffordance.ready then
					return
				end
				scheduleUpgradeReadyPulse(sequence)
			end)
		end)
	end

	function updateUpgradeAffordance(coins, nextToolCost, atMaxLevel)
		if coins ~= nil then
			upgradeAffordance.currentCoins = coins
		end
		if nextToolCost ~= nil then
			upgradeAffordance.currentNextToolCost = nextToolCost
		end
		if atMaxLevel ~= nil then
			upgradeAffordance.atMaxLevel = atMaxLevel
			if atMaxLevel then
				upgradeAffordance.currentNextToolCost = nil
			end
		end

		upgradeAffordance.sequence = upgradeAffordance.sequence + 1
		local sequence = upgradeAffordance.sequence
		stopUpgradeAffordanceTweens()

		if upgradeAffordance.atMaxLevel then
			upgradeAffordance.ready = false
			upgradeButton.BackgroundColor3 = upgradeAffordance.maxColor
			upgradeStroke.Color = upgradeAffordance.maxStrokeColor
			upgradeStroke.Transparency = 0.45
			return
		end

		local canAfford = upgradeAffordance.currentNextToolCost ~= nil
			and upgradeAffordance.currentCoins >= upgradeAffordance.currentNextToolCost
		upgradeAffordance.ready = canAfford

		if canAfford then
			upgradeButton.BackgroundColor3 = upgradeAffordance.readyColor
			upgradeStroke.Color = upgradeAffordance.readyStrokeColor
			upgradeStroke.Transparency = 0.12
			scheduleUpgradeReadyPulse(sequence)
		else
			upgradeButton.BackgroundColor3 = upgradeAffordance.normalColor
			upgradeStroke.Color = upgradeAffordance.normalStrokeColor
			upgradeStroke.Transparency = 0.55
		end
	end
end

upgradeButton.MouseButton1Click:Connect(function()
	Remotes.BuyTool:FireServer(currentToolTier + 1)
end)

-- ═══════════════════════════════════════════════════════════════════
-- FTUE arrow guide — nudges fresh players through dig → sell → upgrade.
-- ═══════════════════════════════════════════════════════════════════

local FTUE_STAGE_NONE = 0
local FTUE_STAGE_DIG = 1
local FTUE_STAGE_SELL = 2
local FTUE_STAGE_UPGRADE = 3
local FTUE_STAGE_DONE = 4

local ftueGuideEnabled = false
local ftueGuideStage = FTUE_STAGE_NONE
local ftueGuideCoins = 0
local ftueGuideInventoryCount = 0
local ftueGuideToolTier = 1
local ftueGuideNextToolCost = nil

local ftuePulseValue = Instance.new("NumberValue")
ftuePulseValue.Name = "FTUEPulse"
ftuePulseValue.Value = 0
ftuePulseValue.Parent = screenGui

local ftueGuideLayer = Instance.new("Frame")
ftueGuideLayer.Name = "FTUEGuide"
ftueGuideLayer.Size = UDim2.new(1, 0, 1, 0)
ftueGuideLayer.BackgroundTransparency = 1
ftueGuideLayer.Visible = false
ftueGuideLayer.ZIndex = 55
ftueGuideLayer.Parent = screenGui

local ftuePulse = Instance.new("Frame")
ftuePulse.Name = "Pulse"
ftuePulse.AnchorPoint = Vector2.new(0.5, 0.5)
ftuePulse.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
ftuePulse.BackgroundTransparency = 0.88
ftuePulse.BorderSizePixel = 0
ftuePulse.Visible = false
ftuePulse.ZIndex = 56
ftuePulse.Parent = ftueGuideLayer

local ftuePulseCorner = Instance.new("UICorner")
ftuePulseCorner.CornerRadius = UDim.new(0, 14)
ftuePulseCorner.Parent = ftuePulse

local ftuePulseStroke = Instance.new("UIStroke")
ftuePulseStroke.Color = Color3.fromRGB(255, 220, 120)
ftuePulseStroke.Thickness = 2
ftuePulseStroke.Transparency = 0.25
ftuePulseStroke.Parent = ftuePulse

local ftueArrow = Instance.new("TextLabel")
ftueArrow.Name = "Arrow"
ftueArrow.AnchorPoint = Vector2.new(0.5, 1)
ftueArrow.Size = UDim2.new(0, 240, 0, 34)
ftueArrow.BackgroundTransparency = 1
ftueArrow.Text = ""
ftueArrow.TextColor3 = Color3.fromRGB(255, 220, 100)
ftueArrow.TextStrokeColor3 = Color3.fromRGB(45, 25, 0)
ftueArrow.TextStrokeTransparency = 0.35
ftueArrow.TextSize = 18
ftueArrow.Font = Enum.Font.GothamBlack
ftueArrow.Visible = false
ftueArrow.ZIndex = 57
ftueArrow.Parent = ftueGuideLayer

local ftueStageTitles = {
	[FTUE_STAGE_DIG] = "⬇ DIG HERE",
	[FTUE_STAGE_SELL] = "⬇ SELL ALL",
	[FTUE_STAGE_UPGRADE] = "⬇ UPGRADE",
}

local function hideFtueGuide()
	ftueGuideEnabled = false
	ftueGuideStage = FTUE_STAGE_DONE
	ftueGuideLayer.Visible = false
	ftuePulse.Visible = false
	ftueArrow.Visible = false
end

local function getFtueTarget()
	if ftueGuideStage == FTUE_STAGE_DIG then
		local digSite = workspace:FindFirstChild("DigSite")
		if not digSite then
			return nil
		end

		return digSite:FindFirstChild("SpawnPlatform") or digSite:FindFirstChildWhichIsA("BasePart")
	elseif ftueGuideStage == FTUE_STAGE_SELL then
		return sellButton
	elseif ftueGuideStage == FTUE_STAGE_UPGRADE then
		return upgradeButton
	end

	return nil
end

local function getFtueTargetAnchor(target)
	if not target then
		return nil
	end

	if target:IsA("GuiObject") then
		return target.AbsolutePosition + (target.AbsoluteSize / 2), target.AbsoluteSize
	end

	if target:IsA("BasePart") then
		local camera = workspace.CurrentCamera
		if not camera then
			return nil
		end

		local screenPoint, onScreen = camera:WorldToScreenPoint(target.Position)
		local viewportSize = camera.ViewportSize
		local x = math.clamp(screenPoint.X, 80, math.max(80, viewportSize.X - 80))
		local y = math.clamp(screenPoint.Y, 90, math.max(90, viewportSize.Y - 90))

		if not onScreen then
			x = math.floor(viewportSize.X * 0.5)
			y = math.floor(viewportSize.Y * 0.42)
		end

		return Vector2.new(x, y), Vector2.new(108, 108)
	end

	return nil
end

local function applyFtueGuide()
	if not ftueGuideEnabled or ftueGuideStage >= FTUE_STAGE_DONE then
		ftueGuideLayer.Visible = false
		ftuePulse.Visible = false
		ftueArrow.Visible = false
		return
	end

	local target = getFtueTarget()
	local center, size = getFtueTargetAnchor(target)
	if not center or not size then
		ftueGuideLayer.Visible = false
		ftuePulse.Visible = false
		ftueArrow.Visible = false
		return
	end

	local pulsePadding = 20 + math.floor(ftuePulseValue.Value * 10)
	local pulseWidth = math.max(size.X + pulsePadding, 120)
	local pulseHeight = math.max(size.Y + pulsePadding, 54)

	ftuePulse.Size = UDim2.fromOffset(pulseWidth, pulseHeight)
	ftuePulse.Position = UDim2.fromOffset(center.X, center.Y)
	ftuePulse.Visible = true

	ftueArrow.Text = ftueStageTitles[ftueGuideStage] or "⬇ DIG HERE"
	ftueArrow.Position = UDim2.fromOffset(center.X, center.Y - (pulseHeight / 2) - 12)
	ftueArrow.Visible = true
	ftueGuideLayer.Visible = true
end

local ftuePulseTween = TweenService:Create(
	ftuePulseValue,
	TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Value = 1 }
)
ftuePulseTween:Play()

RunService.RenderStepped:Connect(function()
	applyFtueGuide()
end)

local function refreshFtueGuideState()
	if not ftueGuideEnabled then
		return
	end

	if ftueGuideToolTier > 1 then
		hideFtueGuide()
		return
	end

	if ftueGuideStage < FTUE_STAGE_SELL and ftueGuideInventoryCount > 0 then
		ftueGuideStage = FTUE_STAGE_SELL
	end

	if ftueGuideStage >= FTUE_STAGE_SELL and ftueGuideInventoryCount == 0 and ftueGuideNextToolCost and ftueGuideCoins >= ftueGuideNextToolCost then
		ftueGuideStage = FTUE_STAGE_UPGRADE
	end

	applyFtueGuide()
end

local function initializeFtueGuide(data)
	local inventoryCount = #(data.inventory or {})
	local freshProfile = (data.toolTier or 1) == 1
		and (data.totalBlocksDug or 0) == 0
		and inventoryCount == 0
		and (data.rebirths or 0) == 0

	ftueGuideEnabled = freshProfile
	ftueGuideCoins = math.floor(data.coins or 0)
	ftueGuideInventoryCount = inventoryCount
	ftueGuideToolTier = data.toolTier or 1
	ftueGuideNextToolCost = data.nextToolCost
	ftueGuideStage = ftueGuideEnabled and FTUE_STAGE_DIG or FTUE_STAGE_DONE

	if ftueGuideEnabled then
		refreshFtueGuideState()
	else
		hideFtueGuide()
	end
end

local function updateFtueGuideFromHUD(data)
	if not ftueGuideEnabled then
		return
	end

	if data.coins ~= nil then
		ftueGuideCoins = math.floor(data.coins)
	end
	if data.inventoryCount ~= nil then
		ftueGuideInventoryCount = data.inventoryCount
	end
	if data.toolTier ~= nil then
		ftueGuideToolTier = data.toolTier
	end
	if data.nextToolCost ~= nil then
		ftueGuideNextToolCost = data.nextToolCost
	end

	refreshFtueGuideState()
end

-- ═══════════════════════════════════════════════════════════════════
-- Shop Button + Gamepass Shop Panel
-- ═══════════════════════════════════════════════════════════════════

local shopButton = Instance.new("TextButton")
shopButton.Name = "ShopButton"
shopButton.Size = UDim2.new(0, 90, 0, 35)
shopButton.Position = UDim2.new(0, 130, 1, -60)
shopButton.BackgroundColor3 = Color3.fromRGB(200, 80, 200)
shopButton.BorderSizePixel = 0
shopButton.Text = "🛒 Shop"
shopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
shopButton.TextSize = 14
shopButton.Font = Enum.Font.GothamBold
shopButton.Parent = screenGui

local shopCorner = Instance.new("UICorner")
shopCorner.CornerRadius = UDim.new(0, 8)
shopCorner.Parent = shopButton

-- ─── Shop panel ──────────────────────────────────────────────────────────────

local shopPanel = Instance.new("Frame")
shopPanel.Name = "ShopPanel"
shopPanel.Size = UDim2.new(0, 420, 0, 320)
shopPanel.Position = UDim2.new(0.5, -210, 0.5, -160)
shopPanel.BackgroundColor3 = Color3.fromRGB(18, 16, 28)
shopPanel.BackgroundTransparency = 0.05
shopPanel.BorderSizePixel = 0
shopPanel.Visible = false
shopPanel.ZIndex = 10
shopPanel.Parent = screenGui

local shopPanelCorner = Instance.new("UICorner")
shopPanelCorner.CornerRadius = UDim.new(0, 14)
shopPanelCorner.Parent = shopPanel

-- Panel title bar
local shopTitleBar = Instance.new("Frame")
shopTitleBar.Size = UDim2.new(1, 0, 0, 48)
shopTitleBar.BackgroundColor3 = Color3.fromRGB(100, 40, 160)
shopTitleBar.BackgroundTransparency = 0
shopTitleBar.BorderSizePixel = 0
shopTitleBar.ZIndex = 11
shopTitleBar.Parent = shopPanel

local shopTitleCorner = Instance.new("UICorner")
shopTitleCorner.CornerRadius = UDim.new(0, 14)
shopTitleCorner.Parent = shopTitleBar

-- Clip bottom corners of title bar (fake it with an overlapping frame)
local titleBarFix = Instance.new("Frame")
titleBarFix.Size = UDim2.new(1, 0, 0, 14)
titleBarFix.Position = UDim2.new(0, 0, 1, -14)
titleBarFix.BackgroundColor3 = Color3.fromRGB(100, 40, 160)
titleBarFix.BorderSizePixel = 0
titleBarFix.ZIndex = 11
titleBarFix.Parent = shopTitleBar

local shopTitle = Instance.new("TextLabel")
shopTitle.Size = UDim2.new(1, -50, 1, 0)
shopTitle.Position = UDim2.new(0, 16, 0, 0)
shopTitle.BackgroundTransparency = 1
shopTitle.Text = "🛒  Gamepass Shop"
shopTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
shopTitle.TextSize = 20
shopTitle.Font = Enum.Font.GothamBlack
shopTitle.TextXAlignment = Enum.TextXAlignment.Left
shopTitle.ZIndex = 12
shopTitle.Parent = shopTitleBar

local shopClose = Instance.new("TextButton")
shopClose.Size = UDim2.new(0, 36, 0, 36)
shopClose.Position = UDim2.new(1, -44, 0, 6)
shopClose.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
shopClose.BorderSizePixel = 0
shopClose.Text = "✕"
shopClose.TextColor3 = Color3.fromRGB(255, 255, 255)
shopClose.TextSize = 16
shopClose.Font = Enum.Font.GothamBold
shopClose.ZIndex = 12
shopClose.Parent = shopTitleBar

local shopCloseCorner = Instance.new("UICorner")
shopCloseCorner.CornerRadius = UDim.new(0, 6)
shopCloseCorner.Parent = shopClose

-- Pass cards container
local cardsFrame = Instance.new("ScrollingFrame")
cardsFrame.Name = "Cards"
cardsFrame.Size = UDim2.new(1, -20, 1, -60)
cardsFrame.Position = UDim2.new(0, 10, 0, 54)
cardsFrame.BackgroundTransparency = 1
cardsFrame.BorderSizePixel = 0
cardsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
cardsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
cardsFrame.ScrollBarThickness = 6
cardsFrame.ZIndex = 11
cardsFrame.Parent = shopPanel

local cardsLayout = Instance.new("UIListLayout")
cardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardsLayout.Padding = UDim.new(0, 8)
cardsLayout.Parent = cardsFrame

local passCards = {} -- passId → { frame, buyBtn, statusLabel }

local function isPassInfoAvailable(passInfo)
	return passInfo.available ~= false and passInfo.status ~= "unavailable"
end

local function setCardButtonState(card)
	if not card.available then
		card.buyBtn.Text = card.unavailableReason or Config.UNAVAILABLE_GAMEPASS_LABEL
		card.buyBtn.BackgroundColor3 = Color3.fromRGB(78, 76, 88)
		card.buyBtn.TextColor3 = Color3.fromRGB(180, 176, 195)
		card.buyBtn.Active = false
		card.buyBtn.AutoButtonColor = false
		card.buyBtn.Selectable = false
		return
	end

	if card.owned then
		card.buyBtn.Text = "✓ Owned"
		card.buyBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 40)
		card.buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		card.buyBtn.Active = false
		card.buyBtn.AutoButtonColor = false
		card.buyBtn.Selectable = false
	else
		card.buyBtn.Text = "R$ " .. tostring(card.price)
		card.buyBtn.BackgroundColor3 = card.color
		card.buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		card.buyBtn.Active = true
		card.buyBtn.AutoButtonColor = true
		card.buyBtn.Selectable = true
	end
end

local function buildPassCard(passInfo)
	local passUi = getPassUiStyle(passInfo.id)
	local available = isPassInfoAvailable(passInfo)

	local card = Instance.new("Frame")
	card.Name = "Card_" .. passInfo.id
	card.Size = UDim2.new(1, 0, 0, 70)
	card.BackgroundColor3 = available and Color3.fromRGB(28, 24, 40) or Color3.fromRGB(32, 31, 38)
	card.BackgroundTransparency = 0
	card.BorderSizePixel = 0
	card.LayoutOrder = passInfo.id
	card.ZIndex = 11
	card.Parent = cardsFrame

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 10)
	cardCorner.Parent = card

	-- Left accent strip
	local strip = Instance.new("Frame")
	strip.Size = UDim2.new(0, 6, 1, 0)
	strip.BackgroundColor3 = available and passUi.color or Color3.fromRGB(92, 90, 104)
	strip.BorderSizePixel = 0
	strip.ZIndex = 12
	strip.Parent = card

	local stripCorner = Instance.new("UICorner")
	stripCorner.CornerRadius = UDim.new(0, 10)
	stripCorner.Parent = strip

	-- Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.55, 0, 0, 26)
	nameLabel.Position = UDim2.new(0, 14, 0, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = passInfo.name
	nameLabel.TextColor3 = available and Color3.fromRGB(240, 230, 255) or Color3.fromRGB(190, 186, 205)
	nameLabel.TextSize = 16
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 12
	nameLabel.Parent = card

	-- Description
	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(0.6, 0, 0, 30)
	descLabel.Position = UDim2.new(0, 14, 0, 32)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = passInfo.description
	descLabel.TextColor3 = available and Color3.fromRGB(170, 160, 190) or Color3.fromRGB(135, 132, 150)
	descLabel.TextSize = 12
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextWrapped = true
	descLabel.ZIndex = 12
	descLabel.Parent = card

	-- Buy button / owned indicator
	local buyBtn = Instance.new("TextButton")
	buyBtn.Name = "BuyBtn"
	buyBtn.Size = UDim2.new(0, 110, 0, 40)
	buyBtn.Position = UDim2.new(1, -120, 0.5, -20)
	buyBtn.BackgroundColor3 = passUi.color
	buyBtn.BorderSizePixel = 0
	buyBtn.Text = "R$ " .. passInfo.price
	buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	buyBtn.TextSize = 15
	buyBtn.Font = Enum.Font.GothamBold
	buyBtn.ZIndex = 13
	buyBtn.Parent = card

	local buyBtnCorner = Instance.new("UICorner")
	buyBtnCorner.CornerRadius = UDim.new(0, 8)
	buyBtnCorner.Parent = buyBtn

	local cardState = {
		frame = card,
		buyBtn = buyBtn,
		available = available,
		owned = passInfo.owned == true,
		price = passInfo.price,
		color = passUi.color,
		unavailableReason = passInfo.unavailableReason,
	}
	passCards[passInfo.id] = cardState
	setCardButtonState(cardState)

	buyBtn.MouseButton1Click:Connect(function()
		if not cardState.available or cardState.owned then
			return
		end
		if Remotes:FindFirstChild("PromptGamepass") then
			Remotes.PromptGamepass:FireServer(passInfo.id)
		end
	end)

	return card
end

local function setCardOwned(passId, owned)
	local card = passCards[passId]
	if not card then return end

	card.owned = owned == true
	setCardButtonState(card)
end

-- Toggle shop panel
shopButton.MouseButton1Click:Connect(function()
	shopPanel.Visible = not shopPanel.Visible
	if shopPanel.Visible then
		-- Populate cards if not yet built
		if #cardsFrame:GetChildren() <= 1 then -- only layout child
			task.spawn(function()
				local GetPassInfo = Remotes:FindFirstChild("GetGamepassInfo")
				if not GetPassInfo then return end
				local info = GetPassInfo:InvokeServer()
				if not info then return end
				for _, passInfo in ipairs(info) do
					buildPassCard(passInfo)
					setCardOwned(passInfo.id, passInfo.owned)
				end
			end)
		end
	end
end)

shopClose.MouseButton1Click:Connect(function()
	shopPanel.Visible = false
end)

-- ═══════════════════════════════════════════════════════════════════
-- Code Redemption UI
-- ═══════════════════════════════════════════════════════════════════

local codeButton = Instance.new("TextButton")
codeButton.Name = "CodeButton"
codeButton.Size = UDim2.new(0, 100, 0, 35)
codeButton.Position = UDim2.new(0, 20, 1, -60)
codeButton.BackgroundColor3 = Color3.fromRGB(200, 160, 40)
codeButton.BorderSizePixel = 0
codeButton.Text = "🎁 Codes"
codeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
codeButton.TextSize = 14
codeButton.Font = Enum.Font.GothamBold
codeButton.Parent = screenGui

local codeCorner = Instance.new("UICorner")
codeCorner.CornerRadius = UDim.new(0, 8)
codeCorner.Parent = codeButton

-- Code input popup
local codePopup = Instance.new("Frame")
codePopup.Name = "CodePopup"
codePopup.Size = UDim2.new(0, 300, 0, 120)
codePopup.Position = UDim2.new(0.5, -150, 0.5, -60)
codePopup.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
codePopup.BorderSizePixel = 0
codePopup.Visible = false
codePopup.Parent = screenGui

local popupCorner = Instance.new("UICorner")
popupCorner.CornerRadius = UDim.new(0, 10)
popupCorner.Parent = codePopup

local codeTitle = Instance.new("TextLabel")
codeTitle.Size = UDim2.new(1, 0, 0, 30)
codeTitle.BackgroundTransparency = 1
codeTitle.Text = "Enter Code"
codeTitle.TextColor3 = Color3.fromRGB(255, 200, 50)
codeTitle.TextSize = 16
codeTitle.Font = Enum.Font.GothamBold
codeTitle.Parent = codePopup

local codeInput = Instance.new("TextBox")
codeInput.Name = "CodeInput"
codeInput.Size = UDim2.new(0.7, 0, 0, 35)
codeInput.Position = UDim2.new(0.05, 0, 0.35, 0)
codeInput.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
codeInput.BorderSizePixel = 0
codeInput.PlaceholderText = "Type code here..."
codeInput.Text = ""
codeInput.TextColor3 = Color3.fromRGB(255, 255, 255)
codeInput.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
codeInput.TextSize = 14
codeInput.Font = Enum.Font.Gotham
codeInput.ClearTextOnFocus = true
codeInput.Parent = codePopup

local inputCorner = Instance.new("UICorner")
inputCorner.CornerRadius = UDim.new(0, 6)
inputCorner.Parent = codeInput

local redeemBtn = Instance.new("TextButton")
redeemBtn.Size = UDim2.new(0.2, 0, 0, 35)
redeemBtn.Position = UDim2.new(0.77, 0, 0.35, 0)
redeemBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 40)
redeemBtn.BorderSizePixel = 0
redeemBtn.Text = "✓"
redeemBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
redeemBtn.TextSize = 18
redeemBtn.Font = Enum.Font.GothamBold
redeemBtn.Parent = codePopup

local redeemCorner = Instance.new("UICorner")
redeemCorner.CornerRadius = UDim.new(0, 6)
redeemCorner.Parent = redeemBtn

local codeStatus = Instance.new("TextLabel")
codeStatus.Size = UDim2.new(0.9, 0, 0, 25)
codeStatus.Position = UDim2.new(0.05, 0, 0.72, 0)
codeStatus.BackgroundTransparency = 1
codeStatus.Text = ""
codeStatus.TextColor3 = Color3.fromRGB(140, 140, 140)
codeStatus.TextSize = 12
codeStatus.Font = Enum.Font.Gotham
codeStatus.TextWrapped = true
codeStatus.Parent = codePopup

codeButton.MouseButton1Click:Connect(function()
	codePopup.Visible = not codePopup.Visible
	if codePopup.Visible then
		codeInput:CaptureFocus()
	end
end)

local function submitCode()
	local code = codeInput.Text
	if code == "" then return end
	codeStatus.Text = "Redeeming..."
	codeStatus.TextColor3 = Color3.fromRGB(200, 200, 200)
	Remotes.RedeemCode:FireServer(code)
end

redeemBtn.MouseButton1Click:Connect(submitCode)
codeInput.FocusLost:Connect(function(enterPressed)
	if enterPressed then submitCode() end
end)

-- Handle code result
if Remotes:FindFirstChild("CodeResult") then
	Remotes.CodeResult.OnClientEvent:Connect(function(success, message)
		codeStatus.Text = message
		codeStatus.TextColor3 = success and Color3.fromRGB(50, 200, 50) or Color3.fromRGB(255, 80, 80)
		if success then
			codeInput.Text = ""
			task.delay(3, function() codePopup.Visible = false end)
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════════
-- Event Handlers
-- ═══════════════════════════════════════════════════════════════════

-- Forward-declared so the UpdateHUD listener below can call into the
-- resurface-eligibility cache that's defined later in this file.
local ingestResurfaceFields

Remotes.UpdateHUD.OnClientEvent:Connect(function(data)
	local upgradeAffordanceChanged = false
	local affordanceCoins = nil
	local affordanceNextToolCost = nil
	local affordanceAtMaxLevel = nil

	if data.coins then
		local newCoins = math.floor(data.coins)
		coinsLabel.Text = "🪙 " .. tostring(newCoins)
		if previousCoinValue ~= nil and newCoins ~= previousCoinValue then
			-- gain → gold pulse; loss (upgrade purchase) → red pulse
			pulseCoinLabel(newCoins > previousCoinValue and "gain" or "loss")
		end
		previousCoinValue = newCoins
		affordanceCoins = newCoins
		upgradeAffordanceChanged = true
	end
	if data.depth then
		local tierText = data.tierName or "Surface"
		depthLabel.Text = "⛏️ " .. tierText .. " (Depth: " .. data.depth .. ")"
	end
	if data.depth or data.tierName then
		updateDepthTone(data)
	end
	if data.toolName then
		toolLabel.Text = "🔧 " .. data.toolName
	end
	if data.toolTier then
		currentToolTier = data.toolTier
	end
	if data.blocksDug then
		blocksLabel.Text = "Blocks: " .. tostring(data.blocksDug)
	end
	if data.inventoryCount ~= nil or data.inventoryCapacity ~= nil then
		setInventoryDisplay(data.inventoryCount, data.inventoryCapacity)
	end
	if data.fragments ~= nil then
		local newFragments = math.floor(data.fragments)
		fragLabel.Text = "Fragments: " .. tostring(newFragments)
		if previousFragmentValue ~= nil and newFragments > previousFragmentValue then
			pulseFragmentLabel()
		end
		previousFragmentValue = newFragments
	end
	if data.nextToolCost ~= nil and data.nextToolName then
		upgradeButton.Text = "⬆️ " .. data.nextToolName .. " ($" .. data.nextToolCost .. ")"
		affordanceNextToolCost = tonumber(data.nextToolCost)
		affordanceAtMaxLevel = false
		upgradeAffordanceChanged = true
	elseif data.nextToolCost == nil and data.toolTier then
		upgradeButton.Text = "⬆️ MAX LEVEL"
		affordanceAtMaxLevel = true
		upgradeAffordanceChanged = true
	end
	if upgradeAffordanceChanged then
		updateUpgradeAffordance(affordanceCoins, affordanceNextToolCost, affordanceAtMaxLevel)
	end
	if data.ownedGamepasses then
		updatePassBadges(data.ownedGamepasses)
		-- Sync shop card owned states if panel is open
		for passId, owned in pairs(data.ownedGamepasses) do
			setCardOwned(passId, owned)
		end
	end
	if data.personalBest then
		-- Could show a star or depth update — handled by notification
	end
	if data.offlineIncome then
		showOfflineIncomePopup(data.offlineIncome)
	end
	if data.friendReferralReward then
		showFriendReferralRewardBurst(data.friendReferralReward)
	end
	if data.badgeUnlock then
		DeepDigShowBadgeUnlockBurst(data.badgeUnlock)
	end
	if data.autoCollected then
		DeepDigShowAutoCollectedBurst(data.autoCollected)
	end
	if data.artifactDetected then
		DeepDigShowArtifactDetectorPulse(data.artifactDetected)
	end

	refreshStreakRevivePrompt(data)
	refreshFriendBoostIndicator(data)
	refreshGroupBenefitIndicator(data)
	refreshEquippedPetChip(data)
	updateFtueGuideFromHUD(data)
	ingestResurfaceFields(data)
end)

do
	local offlineIncomeRewardEvent = Remotes:WaitForChild("OfflineIncomeReward", 5)
	if offlineIncomeRewardEvent then
		offlineIncomeRewardEvent.OnClientEvent:Connect(showOfflineIncomePopup)
	end
end

Remotes.ItemFound.OnClientEvent:Connect(function(item)
	if item and LEGENDARY_FIND_FLASH_RARITIES[item.rarity] then
		playLegendaryFindFlash(item.rarity)
	end

	if item and LIGHTING_PULSE_PROFILES[item.rarity] then
		playLightingPulse(item.rarity)
	end

	showNotification("Found: " .. item.name .. " (+" .. item.sellValue .. " coins)", item.rarity)
end)

Remotes.EventTriggered.OnClientEvent:Connect(function(eventName, message, duration, effectId)
	local seasonBadgeUpdated = updateSeasonBadge(effectId)
	DeepDigActiveEventHud.show(eventName, message, duration, effectId)

	if seasonBadgeUpdated and LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("event_alarm")
	end

	if shouldPlayEventCameraShake(duration) and not isEarthquakeEvent(eventName, message, effectId) then
		playEventCameraShake(eventName, effectId)
	end

	showNotification("⚡ " .. tostring(message or ""), "Legendary")
end)

Remotes.Notify.OnClientEvent:Connect(function(message, rarity)
	showNotification(message, rarity)
end)

Remotes:WaitForChild("StreakRewardResult").OnClientEvent:Connect(function(payload)
	showStreakRewardBurst(payload)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Museum button — teleport to player's personal museum from any depth.
-- Mirrors the in-world telepad; HUD button makes it discoverable from anywhere.
-- ═══════════════════════════════════════════════════════════════════

local museumButton = Instance.new("TextButton")
museumButton.Name = "MuseumButton"
museumButton.Size = UDim2.new(0, 100, 0, 35)
museumButton.Position = UDim2.new(0, 370, 1, -60)
museumButton.BackgroundColor3 = Color3.fromRGB(80, 100, 180)
museumButton.BorderSizePixel = 0
museumButton.Text = "🏛️ Museum"
museumButton.TextColor3 = Color3.fromRGB(255, 255, 255)
museumButton.TextSize = 14
museumButton.Font = Enum.Font.GothamBold
museumButton.Parent = screenGui

local museumCorner = Instance.new("UICorner")
museumCorner.CornerRadius = UDim.new(0, 8)
museumCorner.Parent = museumButton

museumButton.MouseButton1Click:Connect(function()
	-- Look for the player's MuseumPad in workspace and teleport HRP onto it.
	-- If the pad isn't built yet (very first second of play), nudge the user.
	local museums = workspace:FindFirstChild("Museums")
	local pad = museums and museums:FindFirstChild(player.Name .. "_MuseumPad")
	if not pad then
		showNotification("Museum loading… try again in a sec.", "Common")
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = CFrame.new(pad.Position + Vector3.new(0, 4, 0))
	end
end)

-- ═══════════════════════════════════════════════════════════════════
-- First-time tutorial popup — fires once when a fresh profile joins.
-- ═══════════════════════════════════════════════════════════════════

local function showTutorial()
	local frame = Instance.new("Frame")
	frame.Name = "Tutorial"
	frame.Size = UDim2.new(0, 420, 0, 220)
	frame.Position = UDim2.new(0.5, -210, 0.5, -110)
	frame.BackgroundColor3 = Color3.fromRGB(20, 18, 28)
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.ZIndex = 50
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 200, 50)
	stroke.Thickness = 2
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 50)
	title.BackgroundTransparency = 1
	title.Text = "⛏️ Welcome to Deep Dig"
	title.TextColor3 = Color3.fromRGB(255, 200, 50)
	title.TextSize = 24
	title.Font = Enum.Font.GothamBlack
	title.ZIndex = 51
	title.Parent = frame

	local body = Instance.new("TextLabel")
	body.Size = UDim2.new(1, -32, 1, -110)
	body.Position = UDim2.new(0, 16, 0, 50)
	body.BackgroundTransparency = 1
	body.Text = "1.  Equip your Excavator (1 key) and click on a block.\n2.  Find ancient artifacts as you dig deeper.\n3.  Use 💰 Sell All to convert finds to coins.\n4.  Buy a better tool with the ⬆️ Upgrade button.\n5.  Display rare finds in 🏛️ Museum for bonuses."
	body.TextColor3 = Color3.fromRGB(220, 220, 230)
	body.TextSize = 15
	body.Font = Enum.Font.Gotham
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.ZIndex = 51
	body.Parent = frame

	local ok = Instance.new("TextButton")
	ok.Size = UDim2.new(0, 160, 0, 36)
	ok.Position = UDim2.new(0.5, -80, 1, -50)
	ok.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
	ok.BorderSizePixel = 0
	ok.Text = "DIG IN"
	ok.TextColor3 = Color3.fromRGB(40, 20, 0)
	ok.TextSize = 16
	ok.Font = Enum.Font.GothamBlack
	ok.ZIndex = 51
	ok.Parent = frame

	local okCorner = Instance.new("UICorner")
	okCorner.CornerRadius = UDim.new(0, 8)
	okCorner.Parent = ok

	ok.MouseButton1Click:Connect(function()
		frame:Destroy()
	end)
end

-- ═══════════════════════════════════════════════════════════════════
-- Resurface (prestige) button — visible only when eligible.
-- Server validates everything; the button is a hint + one-click action.
-- ═══════════════════════════════════════════════════════════════════

-- Derive resurface min depth from Config (Tier 6 = Unknown). 188 is the
-- last-known fallback in case Config or its TIERS table is missing.
local resurfaceTier = (Config and Config.TIERS and Config.TIERS[6]) or nil
local RESURFACE_MIN_DEPTH = (resurfaceTier and resurfaceTier.minDepth) or 188
local RESURFACE_BASE_COST = 1000000

local resurfaceButton = Instance.new("TextButton")
resurfaceButton.Name = "ResurfaceButton"
resurfaceButton.Size = UDim2.new(0, 130, 0, 35)
resurfaceButton.Position = UDim2.new(0, 230, 1, -60)
resurfaceButton.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
resurfaceButton.BorderSizePixel = 0
resurfaceButton.Text = "⭐ Resurface"
resurfaceButton.TextColor3 = Color3.fromRGB(40, 20, 0)
resurfaceButton.TextSize = 14
resurfaceButton.Font = Enum.Font.GothamBlack
resurfaceButton.Visible = false
resurfaceButton.Parent = screenGui

local resurfaceCorner = Instance.new("UICorner")
resurfaceCorner.CornerRadius = UDim.new(0, 8)
resurfaceCorner.Parent = resurfaceButton

resurfaceButton.MouseButton1Click:Connect(function()
	Remotes.Resurface:FireServer()
end)

-- Cached resurface-eligibility inputs. Server pushes totalEarned/rebirths in
-- every UpdateHUD payload; depth comes from the dig handler. We store last-seen
-- values so partial payloads from other systems (PetSystem, Museum, …) don't
-- clobber eligibility state.
local cachedDeepestBlock = 0
local cachedTotalEarned = 0
local cachedRebirths = 0

local function evaluateResurfaceEligibility()
	local cost = math.floor(RESURFACE_BASE_COST * (1.08 ^ cachedRebirths))
	if cachedDeepestBlock >= RESURFACE_MIN_DEPTH and cachedTotalEarned >= cost then
		resurfaceButton.Visible = true
		resurfaceButton.Text = "⭐ Resurface (" .. (cachedRebirths + 1) .. ")"
	else
		resurfaceButton.Visible = false
	end
end

function ingestResurfaceFields(data)
	if not data then return end
	local changed = false
	-- deepestBlock comes from the initial GetPlayerData snapshot; depth (current
	-- depth from dig events) is monotonically tracked here so we never need a
	-- second round-trip just to refresh eligibility.
	if data.deepestBlock and data.deepestBlock > cachedDeepestBlock then
		cachedDeepestBlock = data.deepestBlock
		changed = true
	end
	if data.depth and data.depth > cachedDeepestBlock then
		cachedDeepestBlock = data.depth
		changed = true
	end
	if data.totalEarned ~= nil then
		cachedTotalEarned = data.totalEarned
		changed = true
	end
	if data.rebirths ~= nil then
		cachedRebirths = data.rebirths
		changed = true
	end
	if changed then
		evaluateResurfaceEligibility()
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Initial load
-- ═══════════════════════════════════════════════════════════════════

task.spawn(function()
	local data = Remotes.GetPlayerData:InvokeServer()
	if data then
		coinsLabel.Text = "🪙 " .. tostring(math.floor(data.coins))
		previousCoinValue = math.floor(data.coins)
		toolLabel.Text = "🔧 " .. data.toolName
		blocksLabel.Text = "Blocks: " .. tostring(data.totalBlocksDug)
		setInventoryDisplay(#data.inventory, data.inventoryCapacity)
		if data.fragments ~= nil then
			previousFragmentValue = math.floor(data.fragments)
			fragLabel.Text = "Fragments: " .. tostring(previousFragmentValue)
		end
		currentToolTier = data.toolTier
		initializeFtueGuide(data)
		refreshStreakRevivePrompt(data)
		refreshFriendBoostIndicator(data)
		refreshGroupBenefitIndicator(data)
		refreshEquippedPetChip(data)
		updateDepthTone(data)

		-- First-time tutorial: only on truly fresh profile (zero blocks dug, no inventory).
		if (data.totalBlocksDug or 0) == 0 and #data.inventory == 0 then
			task.delay(2, showTutorial)
		end

		if data.nextToolCost ~= nil and data.nextToolName then
			upgradeButton.Text = "⬆️ " .. data.nextToolName .. " ($" .. data.nextToolCost .. ")"
			updateUpgradeAffordance(previousCoinValue, tonumber(data.nextToolCost), false)
		elseif data.nextToolCost == nil and data.toolTier then
			upgradeButton.Text = "⬆️ MAX LEVEL"
			updateUpgradeAffordance(previousCoinValue, nil, true)
		else
			updateUpgradeAffordance(previousCoinValue, nil, nil)
		end

		if data.ownedGamepasses then
			updatePassBadges(data.ownedGamepasses)
		end

		-- Seed cached eligibility inputs from the initial snapshot, then evaluate.
		-- After this, all updates flow reactively through UpdateHUD payloads —
		-- no more 20s GetPlayerData polling.
		ingestResurfaceFields({
			deepestBlock = data.deepestBlock,
			totalEarned = data.totalEarned,
			rebirths = data.rebirths,
		})
		evaluateResurfaceEligibility()
	end
end)

print("[DeepDig] HUD loaded")
