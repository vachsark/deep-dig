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
function DeepDigClearFullBackpackPressure() end
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
			DeepDigClearFullBackpackPressure()
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

-- ─── Rare pity meter ─────────────────────────────────────────────────────────

do
local rareMeterFrame = Instance.new("Frame")
rareMeterFrame.Name = "RareMeter"
rareMeterFrame.Size = UDim2.new(0, 184, 0, 34)
rareMeterFrame.Position = UDim2.new(0, 20, 0, 122)
rareMeterFrame.BackgroundColor3 = Color3.fromRGB(24, 28, 36)
rareMeterFrame.BackgroundTransparency = 0.08
rareMeterFrame.BorderSizePixel = 0
rareMeterFrame.Parent = screenGui

local rareMeterCorner = Instance.new("UICorner")
rareMeterCorner.CornerRadius = UDim.new(0, 7)
rareMeterCorner.Parent = rareMeterFrame

local rareMeterStroke = Instance.new("UIStroke")
rareMeterStroke.Color = Color3.fromRGB(70, 130, 220)
rareMeterStroke.Thickness = 1
rareMeterStroke.Transparency = 0.15
rareMeterStroke.Parent = rareMeterFrame

local rareMeterLabel = Instance.new("TextLabel")
rareMeterLabel.Name = "Label"
rareMeterLabel.Size = UDim2.new(1, -16, 0, 20)
rareMeterLabel.Position = UDim2.new(0, 8, 0, 4)
rareMeterLabel.BackgroundTransparency = 1
rareMeterLabel.Text = "Rare Meter: 0/" .. tostring(Config.RARE_PITY_THRESHOLD or 8)
rareMeterLabel.TextColor3 = Color3.fromRGB(210, 225, 255)
rareMeterLabel.TextSize = 12
rareMeterLabel.Font = Enum.Font.GothamBlack
rareMeterLabel.TextXAlignment = Enum.TextXAlignment.Left
rareMeterLabel.TextTruncate = Enum.TextTruncate.AtEnd
rareMeterLabel.Parent = rareMeterFrame

local rareMeterTrack = Instance.new("Frame")
rareMeterTrack.Name = "Track"
rareMeterTrack.Size = UDim2.new(1, -16, 0, 5)
rareMeterTrack.Position = UDim2.new(0, 8, 1, -9)
rareMeterTrack.BackgroundColor3 = Color3.fromRGB(45, 50, 62)
rareMeterTrack.BorderSizePixel = 0
rareMeterTrack.Parent = rareMeterFrame

local rareMeterTrackCorner = Instance.new("UICorner")
rareMeterTrackCorner.CornerRadius = UDim.new(0, 3)
rareMeterTrackCorner.Parent = rareMeterTrack

local rareMeterFill = Instance.new("Frame")
rareMeterFill.Name = "Fill"
rareMeterFill.Size = UDim2.new(0, 0, 1, 0)
rareMeterFill.BackgroundColor3 = Color3.fromRGB(80, 160, 255)
rareMeterFill.BorderSizePixel = 0
rareMeterFill.Parent = rareMeterTrack

local rareMeterFillCorner = Instance.new("UICorner")
rareMeterFillCorner.CornerRadius = UDim.new(0, 3)
rareMeterFillCorner.Parent = rareMeterFill

local previousRarePityValue = nil
local currentRarePityThreshold = Config.RARE_PITY_THRESHOLD or 8
local rareMeterPulseSequence = 0

local function pulseRareMeter(triggered)
	rareMeterPulseSequence = rareMeterPulseSequence + 1
	local sequence = rareMeterPulseSequence
	local accent = triggered and Color3.fromRGB(255, 210, 80) or Color3.fromRGB(115, 185, 255)

	rareMeterFrame.Size = triggered and UDim2.new(0, 194, 0, 38) or UDim2.new(0, 188, 0, 36)
	rareMeterStroke.Color = accent
	rareMeterStroke.Thickness = triggered and 3 or 2
	rareMeterFill.BackgroundColor3 = accent

	local settleFrame = TweenService:Create(
		rareMeterFrame,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 184, 0, 34) }
	)
	local settleStroke = TweenService:Create(
		rareMeterStroke,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Color = Color3.fromRGB(70, 130, 220),
			Thickness = 1,
		}
	)
	settleFrame:Play()
	settleStroke:Play()
	settleFrame.Completed:Connect(function()
		if sequence ~= rareMeterPulseSequence then return end
		rareMeterFrame.Size = UDim2.new(0, 184, 0, 34)
		rareMeterStroke.Color = Color3.fromRGB(70, 130, 220)
		rareMeterStroke.Thickness = 1
	end)
end

function DeepDigUpdateRareMeter(value, threshold, triggered)
	local nextThreshold = math.max(1, math.floor(tonumber(threshold) or currentRarePityThreshold or 8))
	local nextValue = math.max(0, math.min(nextThreshold, math.floor(tonumber(value) or 0)))
	local progress = nextValue / nextThreshold

	currentRarePityThreshold = nextThreshold
	rareMeterFill.Size = UDim2.new(progress, 0, 1, 0)
	rareMeterFill.BackgroundColor3 = progress >= 1
		and Color3.fromRGB(255, 210, 80)
		or Color3.fromRGB(80, 160, 255)
	rareMeterLabel.Text = triggered and "Rare Meter: Rare+!" or "Rare Meter: " .. tostring(nextValue) .. "/" .. tostring(nextThreshold)

	if previousRarePityValue ~= nil and (triggered or nextValue > previousRarePityValue) then
		pulseRareMeter(triggered)
	end
	previousRarePityValue = nextValue
end
end

-- ─── Daily quest side panel ──────────────────────────────────────────────────

(function()
local QuestDatabase = require(ReplicatedStorage:WaitForChild("QuestDatabase"))
local QUEST_SIDE_PANEL_MAX_ROWS = 4
local QUEST_SIDE_PANEL_ROW_HEIGHT = 43
local QUEST_SIDE_PANEL_WIDTH = 234
local questSideDefinitions = {}

local function addQuestSideDefinition(quest)
	if type(quest) == "table" and type(quest.id) == "string" then
		questSideDefinitions[quest.id] = quest
	end
end

for _, quest in ipairs(QuestDatabase) do
	addQuestSideDefinition(quest)
end

addQuestSideDefinition(QuestDatabase.weeklyQuest)
if type(QuestDatabase.weeklyQuests) == "table" then
	for _, quest in ipairs(QuestDatabase.weeklyQuests) do
		addQuestSideDefinition(quest)
	end
end

local questSidePanel = Instance.new("Frame")
questSidePanel.Name = "DailyQuestSidePanel"
questSidePanel.Size = UDim2.new(0, QUEST_SIDE_PANEL_WIDTH, 0, 40)
questSidePanel.Position = UDim2.new(1, -254, 0, 66)
questSidePanel.BackgroundColor3 = Color3.fromRGB(22, 25, 31)
questSidePanel.BackgroundTransparency = 0.08
questSidePanel.BorderSizePixel = 0
questSidePanel.Visible = false
questSidePanel.ZIndex = 6
questSidePanel.Parent = screenGui

local questSidePanelCorner = Instance.new("UICorner")
questSidePanelCorner.CornerRadius = UDim.new(0, 8)
questSidePanelCorner.Parent = questSidePanel

local questSidePanelStroke = Instance.new("UIStroke")
questSidePanelStroke.Color = Color3.fromRGB(78, 87, 104)
questSidePanelStroke.Thickness = 1
questSidePanelStroke.Transparency = 0.25
questSidePanelStroke.Parent = questSidePanel

local questSideTitle = Instance.new("TextLabel")
questSideTitle.Name = "Title"
questSideTitle.Size = UDim2.new(1, -18, 0, 24)
questSideTitle.Position = UDim2.new(0, 9, 0, 4)
questSideTitle.BackgroundTransparency = 1
questSideTitle.Text = "Daily Quests"
questSideTitle.TextColor3 = Color3.fromRGB(255, 210, 85)
questSideTitle.TextSize = 13
questSideTitle.Font = Enum.Font.GothamBlack
questSideTitle.TextXAlignment = Enum.TextXAlignment.Left
questSideTitle.ZIndex = 7
questSideTitle.Parent = questSidePanel

local questSideList = Instance.new("Frame")
questSideList.Name = "Rows"
questSideList.Size = UDim2.new(1, -18, 1, -32)
questSideList.Position = UDim2.new(0, 9, 0, 29)
questSideList.BackgroundTransparency = 1
questSideList.ZIndex = 7
questSideList.Parent = questSidePanel

local questSideListLayout = Instance.new("UIListLayout")
questSideListLayout.FillDirection = Enum.FillDirection.Vertical
questSideListLayout.SortOrder = Enum.SortOrder.LayoutOrder
questSideListLayout.Padding = UDim.new(0, 5)
questSideListLayout.Parent = questSideList

local questSideRows = {}

local function createQuestSideRow(index)
	local row = Instance.new("Frame")
	row.Name = "QuestRow" .. tostring(index)
	row.Size = UDim2.new(1, 0, 0, QUEST_SIDE_PANEL_ROW_HEIGHT)
	row.BackgroundTransparency = 1
	row.LayoutOrder = index
	row.Visible = false
	row.ZIndex = 7
	row.Parent = questSideList

	local description = Instance.new("TextLabel")
	description.Name = "Description"
	description.Size = UDim2.new(1, -54, 0, 18)
	description.Position = UDim2.new(0, 0, 0, 0)
	description.BackgroundTransparency = 1
	description.Text = ""
	description.TextColor3 = Color3.fromRGB(235, 238, 245)
	description.TextSize = 11
	description.Font = Enum.Font.GothamBold
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextTruncate = Enum.TextTruncate.AtEnd
	description.ZIndex = 8
	description.Parent = row

	local reward = Instance.new("TextLabel")
	reward.Name = "Reward"
	reward.Size = UDim2.new(1, -54, 0, 14)
	reward.Position = UDim2.new(0, 0, 0, 16)
	reward.BackgroundTransparency = 1
	reward.Text = ""
	reward.TextColor3 = Color3.fromRGB(255, 214, 118)
	reward.TextSize = 10
	reward.Font = Enum.Font.GothamMedium
	reward.TextXAlignment = Enum.TextXAlignment.Left
	reward.TextTruncate = Enum.TextTruncate.AtEnd
	reward.ZIndex = 8
	reward.Parent = row

	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "Progress"
	progressLabel.Size = UDim2.new(0, 50, 0, 18)
	progressLabel.Position = UDim2.new(1, -50, 0, 0)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Text = ""
	progressLabel.TextColor3 = Color3.fromRGB(174, 181, 196)
	progressLabel.TextSize = 11
	progressLabel.Font = Enum.Font.GothamMedium
	progressLabel.TextXAlignment = Enum.TextXAlignment.Right
	progressLabel.ZIndex = 8
	progressLabel.Parent = row

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 7)
	track.Position = UDim2.new(0, 0, 0, 33)
	track.BackgroundColor3 = Color3.fromRGB(44, 49, 59)
	track.BorderSizePixel = 0
	track.ZIndex = 8
	track.Parent = row

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 4)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(255, 196, 72)
	fill.BorderSizePixel = 0
	fill.ZIndex = 9
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	questSideRows[index] = {
		row = row,
		description = description,
		reward = reward,
		progressLabel = progressLabel,
		fill = fill,
	}
end

for index = 1, QUEST_SIDE_PANEL_MAX_ROWS do
	createQuestSideRow(index)
end

local function questSideSafeNumber(value)
	if type(value) == "number" then
		return value
	end
	return tonumber(value) or 0
end

local function questSideProgressRatio(progress, target)
	if target <= 0 then
		return 0
	end

	local ratio = progress / target
	if ratio < 0 then
		return 0
	end
	if ratio > 1 then
		return 1
	end
	return ratio
end

local function questSideAccentColor(questType, complete, weekly)
	if complete then
		return Color3.fromRGB(80, 200, 105)
	end
	if weekly then
		return Color3.fromRGB(190, 122, 255)
	end
	if questType == "kill_enemies" then
		return Color3.fromRGB(255, 105, 85)
	end
	if questType == "miniboss_kills" then
		return Color3.fromRGB(215, 85, 255)
	end
	if questType == "coins_earned" then
		return Color3.fromRGB(90, 210, 125)
	end
	if questType == "rarity_found" or questType == "items_found" then
		return Color3.fromRGB(135, 170, 255)
	end
	if questType == "depth_reached" then
		return Color3.fromRGB(180, 140, 255)
	end
	return Color3.fromRGB(255, 196, 72)
end

local function hideQuestSideRows()
	for _, rowParts in ipairs(questSideRows) do
		rowParts.row.Visible = false
	end
end

local function questSideDisplayText(quest, definition, fieldName, fallbackName)
	local value = quest[fieldName]
	if type(value) == "string" and value ~= "" then
		return value
	end

	value = definition and definition[fieldName]
	if type(value) == "string" and value ~= "" then
		return value
	end

	value = quest[fallbackName]
	if type(value) == "string" then
		return value
	end
	return ""
end

local function questSideRewardText(quest, definition)
	local text = questSideDisplayText(quest, definition, "rewardText", "rewardText")
	if text ~= "" then
		return text
	end

	local reward = quest.reward
	if type(reward) ~= "table" and definition then
		reward = definition.reward
	end
	if type(reward) ~= "table" then
		return ""
	end

	local coins = math.floor(questSideSafeNumber(reward.coins))
	local fragments = math.floor(questSideSafeNumber(reward.fragments))
	if coins > 0 and fragments > 0 then
		return "+" .. tostring(coins) .. " coins, +" .. tostring(fragments) .. " fragments"
	end
	if coins > 0 then
		return "+" .. tostring(coins) .. " coins"
	end
	if fragments > 0 then
		return "+" .. tostring(fragments) .. " fragments"
	end
	return ""
end

function DeepDigUpdateQuestSidePanel(summary)
	if type(summary) ~= "table" or type(summary.quests) ~= "table" then
		questSidePanel.Visible = false
		hideQuestSideRows()
		return
	end

	local quests = {}
	local hasWeeklyQuest = false
	for _, quest in ipairs(summary.quests) do
		if type(quest) == "table" then
			local target = questSideSafeNumber(quest.target)
			local definition = questSideDefinitions[quest.id]
			local description = questSideDisplayText(quest, definition, "shortName", "description")
			if target > 0 and description ~= "" then
				quests[#quests + 1] = quest
			end
		end
	end
	if type(summary.weekly) == "table" then
		local weeklyQuest = summary.weekly
		local target = questSideSafeNumber(weeklyQuest.target)
		local definition = questSideDefinitions[weeklyQuest.id]
		if target <= 0 and definition then
			target = questSideSafeNumber(definition.target)
		end
		local description = questSideDisplayText(weeklyQuest, definition, "shortName", "description")
		if target > 0 and description ~= "" then
			quests[#quests + 1] = {
				definition = definition,
				quest = weeklyQuest,
				weekly = true,
			}
			hasWeeklyQuest = true
		end
	end

	if #quests == 0 then
		questSidePanel.Visible = false
		hideQuestSideRows()
		return
	end

	local visibleCount = math.min(#quests, QUEST_SIDE_PANEL_MAX_ROWS)
	questSideTitle.Text = hasWeeklyQuest and "Quests" or "Daily Quests"
	questSidePanel.Size = UDim2.new(
		0,
		QUEST_SIDE_PANEL_WIDTH,
		0,
		34 + (visibleCount * QUEST_SIDE_PANEL_ROW_HEIGHT) + ((visibleCount - 1) * 5)
	)
	questSidePanel.Visible = true

	for index, rowParts in ipairs(questSideRows) do
		local questEntry = quests[index]
		if index <= visibleCount and questEntry then
			local quest = questEntry.quest or questEntry
			local definition = questEntry.definition or questSideDefinitions[quest.id]
			local weekly = questEntry.weekly == true
			local progress = math.floor(questSideSafeNumber(quest.progress))
			local target = questSideSafeNumber(quest.target)
			if target <= 0 and definition then
				target = questSideSafeNumber(definition.target)
			end
			target = math.max(1, math.floor(target))
			local complete = quest.complete == true or progress >= target
			local color = questSideAccentColor(quest.type, complete, weekly)
			local rewardText = questSideRewardText(quest, definition)

			rowParts.description.Text = questSideDisplayText(quest, definition, "shortName", "description")
			rowParts.description.TextColor3 = (complete or weekly) and color or Color3.fromRGB(235, 238, 245)
			rowParts.reward.Text = rewardText
			rowParts.reward.TextColor3 = complete and Color3.fromRGB(154, 235, 171) or (weekly and Color3.fromRGB(220, 190, 255) or Color3.fromRGB(255, 214, 118))
			rowParts.progressLabel.Text = complete and "Done" or tostring(math.min(progress, target)) .. "/" .. tostring(target)
			rowParts.progressLabel.TextColor3 = complete and color or Color3.fromRGB(174, 181, 196)
			rowParts.fill.Size = UDim2.new(questSideProgressRatio(progress, target), 0, 1, 0)
			rowParts.fill.BackgroundColor3 = color
			rowParts.row.Visible = true
		else
			rowParts.row.Visible = false
		end
	end
end
end)()

-- ─── Enemy defeat counter ───────────────────────────────────────────────────

(function()
local COMBAT_COUNTER_WIDTH = 184
local COMBAT_COUNTER_HEIGHT = 54
local COMBAT_UNLOCK_DEPTH = 11

local combatCounterPanel = Instance.new("Frame")
combatCounterPanel.Name = "EnemyDefeatCounter"
combatCounterPanel.Size = UDim2.new(0, COMBAT_COUNTER_WIDTH, 0, COMBAT_COUNTER_HEIGHT)
combatCounterPanel.Position = UDim2.new(0, 20, 0, 286)
combatCounterPanel.BackgroundColor3 = Color3.fromRGB(34, 22, 24)
combatCounterPanel.BackgroundTransparency = 0.08
combatCounterPanel.BorderSizePixel = 0
combatCounterPanel.Visible = false
combatCounterPanel.ZIndex = 6
combatCounterPanel.Parent = screenGui

local combatCounterCorner = Instance.new("UICorner")
combatCounterCorner.CornerRadius = UDim.new(0, 7)
combatCounterCorner.Parent = combatCounterPanel

local combatCounterStroke = Instance.new("UIStroke")
combatCounterStroke.Color = Color3.fromRGB(255, 116, 92)
combatCounterStroke.Thickness = 1
combatCounterStroke.Transparency = 0.18
combatCounterStroke.Parent = combatCounterPanel

local combatCounterTitle = Instance.new("TextLabel")
combatCounterTitle.Name = "Title"
combatCounterTitle.Size = UDim2.new(1, -14, 0, 16)
combatCounterTitle.Position = UDim2.new(0, 7, 0, 5)
combatCounterTitle.BackgroundTransparency = 1
combatCounterTitle.Text = "Combat"
combatCounterTitle.TextColor3 = Color3.fromRGB(255, 144, 116)
combatCounterTitle.TextSize = 12
combatCounterTitle.Font = Enum.Font.GothamBlack
combatCounterTitle.TextXAlignment = Enum.TextXAlignment.Left
combatCounterTitle.TextTruncate = Enum.TextTruncate.AtEnd
combatCounterTitle.ZIndex = 7
combatCounterTitle.Parent = combatCounterPanel

local combatCounterCount = Instance.new("TextLabel")
combatCounterCount.Name = "DefeatCount"
combatCounterCount.Size = UDim2.new(0, 86, 0, 16)
combatCounterCount.Position = UDim2.new(1, -93, 0, 5)
combatCounterCount.BackgroundTransparency = 1
combatCounterCount.Text = "Defeats: 0"
combatCounterCount.TextColor3 = Color3.fromRGB(255, 226, 214)
combatCounterCount.TextSize = 12
combatCounterCount.Font = Enum.Font.GothamBold
combatCounterCount.TextXAlignment = Enum.TextXAlignment.Right
combatCounterCount.TextTruncate = Enum.TextTruncate.AtEnd
combatCounterCount.ZIndex = 7
combatCounterCount.Parent = combatCounterPanel

local combatCounterMilestone = Instance.new("TextLabel")
combatCounterMilestone.Name = "Milestone"
combatCounterMilestone.Size = UDim2.new(1, -14, 0, 16)
combatCounterMilestone.Position = UDim2.new(0, 7, 0, 22)
combatCounterMilestone.BackgroundTransparency = 1
combatCounterMilestone.Text = "Next: First defeat"
combatCounterMilestone.TextColor3 = Color3.fromRGB(236, 190, 174)
combatCounterMilestone.TextSize = 11
combatCounterMilestone.Font = Enum.Font.GothamBold
combatCounterMilestone.TextXAlignment = Enum.TextXAlignment.Left
combatCounterMilestone.TextTruncate = Enum.TextTruncate.AtEnd
combatCounterMilestone.ZIndex = 7
combatCounterMilestone.Parent = combatCounterPanel

local combatCounterTrack = Instance.new("Frame")
combatCounterTrack.Name = "Track"
combatCounterTrack.Size = UDim2.new(1, -14, 0, 6)
combatCounterTrack.Position = UDim2.new(0, 7, 1, -11)
combatCounterTrack.BackgroundColor3 = Color3.fromRGB(58, 42, 45)
combatCounterTrack.BorderSizePixel = 0
combatCounterTrack.ZIndex = 7
combatCounterTrack.Parent = combatCounterPanel

local combatCounterTrackCorner = Instance.new("UICorner")
combatCounterTrackCorner.CornerRadius = UDim.new(0, 3)
combatCounterTrackCorner.Parent = combatCounterTrack

local combatCounterFill = Instance.new("Frame")
combatCounterFill.Name = "Fill"
combatCounterFill.Size = UDim2.new(0, 0, 1, 0)
combatCounterFill.BackgroundColor3 = Color3.fromRGB(255, 116, 92)
combatCounterFill.BorderSizePixel = 0
combatCounterFill.ZIndex = 8
combatCounterFill.Parent = combatCounterTrack

local combatCounterFillCorner = Instance.new("UICorner")
combatCounterFillCorner.CornerRadius = UDim.new(0, 3)
combatCounterFillCorner.Parent = combatCounterFill

local previousCombatDefeats = nil
local combatCounterPulseSequence = 0

local function countEnemyDefeatsFromBreakdown(enemyKillCounts)
	if type(enemyKillCounts) ~= "table" then
		return nil
	end

	local total = 0
	local foundCount = false
	for _, count in pairs(enemyKillCounts) do
		local normalizedCount = math.floor(tonumber(count) or 0)
		if normalizedCount > 0 then
			total = total + normalizedCount
			foundCount = true
		end
	end

	return foundCount and total or nil
end

local function getCombatMilestone(defeats)
	if defeats < 1 then
		return 0, 1, "Next: First defeat"
	end
	if defeats < 100 then
		return 0, 100, "Next: 100 defeats"
	end

	local currentHundred = math.floor(defeats / 100) * 100
	local nextHundred = currentHundred + 100
	return currentHundred, nextHundred, "Next: " .. tostring(nextHundred) .. " defeats"
end

local function pulseCombatCounter()
	combatCounterPulseSequence = combatCounterPulseSequence + 1
	local sequence = combatCounterPulseSequence

	combatCounterPanel.Size = UDim2.new(0, COMBAT_COUNTER_WIDTH + 6, 0, COMBAT_COUNTER_HEIGHT + 4)
	combatCounterStroke.Thickness = 2
	combatCounterStroke.Color = Color3.fromRGB(255, 196, 122)
	combatCounterFill.BackgroundColor3 = Color3.fromRGB(255, 196, 122)

	local settlePanel = TweenService:Create(
		combatCounterPanel,
		TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, COMBAT_COUNTER_WIDTH, 0, COMBAT_COUNTER_HEIGHT) }
	)
	local settleStroke = TweenService:Create(
		combatCounterStroke,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Thickness = 1,
			Color = Color3.fromRGB(255, 116, 92),
		}
	)
	settlePanel:Play()
	settleStroke:Play()
	settlePanel.Completed:Connect(function()
		if sequence ~= combatCounterPulseSequence then return end
		combatCounterPanel.Size = UDim2.new(0, COMBAT_COUNTER_WIDTH, 0, COMBAT_COUNTER_HEIGHT)
		combatCounterStroke.Thickness = 1
		combatCounterStroke.Color = Color3.fromRGB(255, 116, 92)
		combatCounterFill.BackgroundColor3 = Color3.fromRGB(255, 116, 92)
	end)
end

function DeepDigUpdateEnemyDefeatPanel(data)
	if type(data) ~= "table" then
		return
	end

	local defeats = data.enemyKills
	if defeats == nil then
		defeats = countEnemyDefeatsFromBreakdown(data.enemyKillCounts)
	end
	if defeats == nil then
		return
	end

	defeats = math.max(0, math.floor(tonumber(defeats) or 0))
	local depth = math.max(tonumber(data.depth) or 0, tonumber(data.deepestBlock) or 0)
	local shouldShow = defeats > 0 or depth >= COMBAT_UNLOCK_DEPTH or data.enemyDangerUnlocked ~= nil
	if not shouldShow then
		combatCounterPanel.Visible = false
		previousCombatDefeats = defeats
		return
	end

	local milestoneStart, milestoneTarget, milestoneText = getCombatMilestone(defeats)
	local progressSpan = math.max(1, milestoneTarget - milestoneStart)
	local progress = math.max(0, math.min(1, (defeats - milestoneStart) / progressSpan))

	combatCounterCount.Text = "Defeats: " .. tostring(defeats)
	combatCounterMilestone.Text = milestoneText
	combatCounterFill.Size = UDim2.new(progress, 0, 1, 0)
	combatCounterPanel.Visible = true

	if previousCombatDefeats ~= nil and defeats > previousCombatDefeats then
		pulseCombatCounter()
	end
	previousCombatDefeats = defeats
end
end)()

-- ─── Login streak display ────────────────────────────────────────────────────

local streakLabel = Instance.new("TextLabel")
streakLabel.Name = "LoginStreak"
streakLabel.Size = UDim2.new(0, 180, 0, 25)
streakLabel.Position = UDim2.new(0, 20, 0, 158)
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
local currentStreakReviveProductAvailable = false

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
badgeRow.Position = UDim2.new(0, 20, 0, 182)
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
friendBoostLabel.Position = UDim2.new(0, 20, 0, 208)
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
groupBenefitLabel.Position = UDim2.new(0, 20, 0, 234)
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
		title = "The Bone Age",
		detail = "+50% loot drop chance",
		background = Color3.fromRGB(70, 38, 24),
		stroke = Color3.fromRGB(255, 130, 45),
		titleColor = Color3.fromRGB(255, 205, 130),
		detailColor = Color3.fromRGB(255, 230, 190),
	},
	winter_loot = {
		title = "The Ice Age",
		detail = "25% rarity promotion",
		background = Color3.fromRGB(26, 58, 78),
		stroke = Color3.fromRGB(120, 220, 255),
		titleColor = Color3.fromRGB(190, 245, 255),
		detailColor = Color3.fromRGB(220, 250, 255),
	},
	spring_loot = {
		title = "Fossil Rush",
		detail = "+1 fragment while digging",
		background = Color3.fromRGB(30, 72, 46),
		stroke = Color3.fromRGB(95, 230, 120),
		titleColor = Color3.fromRGB(190, 255, 195),
		detailColor = Color3.fromRGB(225, 255, 220),
	},
	summer_loot = {
		title = "Volcano Event",
		detail = "2x world event chance",
		background = Color3.fromRGB(86, 54, 22),
		stroke = Color3.fromRGB(255, 190, 70),
		titleColor = Color3.fromRGB(255, 230, 150),
		detailColor = Color3.fromRGB(255, 240, 205),
	},
}

local seasonBadge = Instance.new("Frame")
seasonBadge.Name = "ActiveSeasonBadge"
seasonBadge.Size = UDim2.new(0, 220, 0, 48)
seasonBadge.Position = UDim2.new(0, 20, 0, 260)
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
		volcano_vent = {
			accent = Color3.fromRGB(255, 84, 34),
			background = Color3.fromRGB(76, 28, 18),
			title = "Volcano Vent",
			detail = "Obsidian tools surging",
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

	function activeEventHud.getStyle(effectId)
		return activeEventHud.styles[effectId] or activeEventHud.styles.fallback
	end

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

	activeEventHud.scale = Instance.new("UIScale")
	activeEventHud.scale.Scale = 1
	activeEventHud.scale.Parent = activeEventHud.frame

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
	activeEventHud.detail.Size = UDim2.new(1, -72, 0, 13)
	activeEventHud.detail.Position = UDim2.new(0, 11, 0, 22)
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

	activeEventHud.progressTrack = Instance.new("Frame")
	activeEventHud.progressTrack.Name = "DurationTrack"
	activeEventHud.progressTrack.Size = UDim2.new(1, -22, 0, 3)
	activeEventHud.progressTrack.Position = UDim2.new(0, 11, 0, 34)
	activeEventHud.progressTrack.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	activeEventHud.progressTrack.BackgroundTransparency = 0.82
	activeEventHud.progressTrack.BorderSizePixel = 0
	activeEventHud.progressTrack.Visible = false
	activeEventHud.progressTrack.ClipsDescendants = true
	activeEventHud.progressTrack.Parent = activeEventHud.frame

	activeEventHud.progressCorner = Instance.new("UICorner")
	activeEventHud.progressCorner.CornerRadius = UDim.new(0, 2)
	activeEventHud.progressCorner.Parent = activeEventHud.progressTrack

	activeEventHud.progressFill = Instance.new("Frame")
	activeEventHud.progressFill.Name = "DurationFill"
	activeEventHud.progressFill.Size = UDim2.new(1, 0, 1, 0)
	activeEventHud.progressFill.Position = UDim2.new(0, 0, 0, 0)
	activeEventHud.progressFill.BackgroundColor3 = activeEventHud.styles.fallback.accent
	activeEventHud.progressFill.BackgroundTransparency = 0
	activeEventHud.progressFill.BorderSizePixel = 0
	activeEventHud.progressFill.Parent = activeEventHud.progressTrack

	activeEventHud.progressFillCorner = Instance.new("UICorner")
	activeEventHud.progressFillCorner.CornerRadius = UDim.new(0, 2)
	activeEventHud.progressFillCorner.Parent = activeEventHud.progressFill

	local function restoreActiveEventPulseVisuals()
		local accent = activeEventHud.accentColor or activeEventHud.styles.fallback.accent

		activeEventHud.scale.Scale = 1
		activeEventHud.stroke.Thickness = 2
		activeEventHud.stroke.Color = accent
		activeEventHud.timer.TextColor3 = accent
	end

	local function restoreActiveEventPillTransparency()
		activeEventHud.frame.BackgroundTransparency = 0.08
		activeEventHud.stroke.Transparency = 0.15
		activeEventHud.title.TextTransparency = 0
		activeEventHud.detail.TextTransparency = 0
		activeEventHud.timer.TextTransparency = 0
		activeEventHud.progressTrack.BackgroundTransparency = 0.82
		activeEventHud.progressFill.BackgroundTransparency = 0
	end

	local function cancelActiveEventPulseTweens()
		activeEventHud.pulseSequence = (activeEventHud.pulseSequence or 0) + 1
		if activeEventHud.pulseTweens then
			for _, tween in ipairs(activeEventHud.pulseTweens) do
				tween:Cancel()
			end
			activeEventHud.pulseTweens = nil
		end
		restoreActiveEventPulseVisuals()
	end

	local function cancelActiveEventFadeTweens()
		if activeEventHud.fadeTweens then
			for _, tween in ipairs(activeEventHud.fadeTweens) do
				tween:Cancel()
			end
			activeEventHud.fadeTweens = nil
		end
	end

	local function fadeActiveEventPill(token)
		if token ~= activeEventHud.token then
			return
		end

		cancelActiveEventPulseTweens()
		activeEventHud.fadeTween = TweenService:Create(
			activeEventHud.frame,
			TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)
		local strokeFade = TweenService:Create(activeEventHud.stroke, TweenInfo.new(0.35), { Transparency = 1 })
		local titleFade = TweenService:Create(activeEventHud.title, TweenInfo.new(0.35), { TextTransparency = 1 })
		local detailFade = TweenService:Create(activeEventHud.detail, TweenInfo.new(0.35), { TextTransparency = 1 })
		local timerFade = TweenService:Create(activeEventHud.timer, TweenInfo.new(0.35), { TextTransparency = 1 })
		local trackFade = TweenService:Create(activeEventHud.progressTrack, TweenInfo.new(0.35), { BackgroundTransparency = 1 })
		local fillFade = TweenService:Create(activeEventHud.progressFill, TweenInfo.new(0.35), { BackgroundTransparency = 1 })
		activeEventHud.fadeTweens = {
			activeEventHud.fadeTween,
			strokeFade,
			titleFade,
			detailFade,
			timerFade,
			trackFade,
			fillFade,
		}

		activeEventHud.fadeTween:Play()
		strokeFade:Play()
		titleFade:Play()
		detailFade:Play()
		timerFade:Play()
		trackFade:Play()
		fillFade:Play()
		activeEventHud.fadeTween.Completed:Connect(function()
			if token ~= activeEventHud.token then
				return
			end
			activeEventHud.frame.Visible = false
			activeEventHud.progressTrack.Visible = false
			activeEventHud.fadeTweens = nil
			restoreActiveEventPillTransparency()
		end)
	end

	local function pulseActiveEventFinalSecond(token, accent)
		if token ~= activeEventHud.token or not activeEventHud.frame.Visible then
			return
		end

		cancelActiveEventPulseTweens()
		activeEventHud.pulseSequence = (activeEventHud.pulseSequence or 0) + 1
		local sequence = activeEventHud.pulseSequence
		local pulseColor = Color3.fromRGB(255, 245, 170)

		activeEventHud.scale.Scale = 1.06
		activeEventHud.stroke.Thickness = 3
		activeEventHud.stroke.Color = pulseColor
		activeEventHud.timer.TextColor3 = pulseColor

		local scaleSettle = TweenService:Create(
			activeEventHud.scale,
			TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		)
		local strokeSettle = TweenService:Create(
			activeEventHud.stroke,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Thickness = 2,
				Color = accent,
			}
		)
		local timerSettle = TweenService:Create(
			activeEventHud.timer,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ TextColor3 = accent }
		)

		activeEventHud.pulseTweens = {
			scaleSettle,
			strokeSettle,
			timerSettle,
		}
		scaleSettle:Play()
		strokeSettle:Play()
		timerSettle:Play()
		scaleSettle.Completed:Connect(function()
			if sequence ~= activeEventHud.pulseSequence or token ~= activeEventHud.token then
				return
			end
			activeEventHud.pulseTweens = nil
			restoreActiveEventPulseVisuals()
		end)
	end

	function activeEventHud.show(eventName, message, duration, effectId)
		activeEventHud.token = activeEventHud.token + 1
		local token = activeEventHud.token
		local style = activeEventHud.getStyle(effectId)
		local remainingSeconds = math.max(0, math.floor(tonumber(duration) or 0))
		local isSeasonalEffect = activeEventHud.seasonalEffects[effectId] == true

		if activeEventHud.fadeTween then
			activeEventHud.fadeTween:Cancel()
			activeEventHud.fadeTween = nil
		end
		cancelActiveEventFadeTweens()

		activeEventHud.accentColor = style.accent
		cancelActiveEventPulseTweens()

		if activeEventHud.progressTween then
			activeEventHud.progressTween:Cancel()
			activeEventHud.progressTween = nil
		end

		restoreActiveEventPillTransparency()
		activeEventHud.frame.BackgroundColor3 = style.background
		activeEventHud.stroke.Color = style.accent
		activeEventHud.timer.TextColor3 = style.accent
		activeEventHud.progressFill.BackgroundColor3 = style.accent
		activeEventHud.title.Text = tostring(eventName or style.title)
		activeEventHud.detail.Text = style.detail or tostring(message or "Temporary buff")
		activeEventHud.timer.TextSize = isSeasonalEffect and 12 or 16
		activeEventHud.timer.Text = isSeasonalEffect and "All month" or tostring(remainingSeconds) .. "s"
		activeEventHud.progressFill.Size = UDim2.new(1, 0, 1, 0)
		activeEventHud.progressTrack.Visible = not isSeasonalEffect
		activeEventHud.frame.Visible = true

		if isSeasonalEffect then
			return
		end

		if remainingSeconds > 0 then
			activeEventHud.progressTween = TweenService:Create(
				activeEventHud.progressFill,
				TweenInfo.new(remainingSeconds, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
				{ Size = UDim2.new(0, 0, 1, 0) }
			)
			activeEventHud.progressTween:Play()
		else
			activeEventHud.progressFill.Size = UDim2.new(0, 0, 1, 0)
		end

		task.spawn(function()
			local endsAt = os.clock() + remainingSeconds
			local lastPulsedSecond = nil
			while token == activeEventHud.token do
				remainingSeconds = math.max(0, math.ceil(endsAt - os.clock()))
				activeEventHud.timer.Text = tostring(remainingSeconds) .. "s"

				if remainingSeconds <= 0 then
					break
				end

				if remainingSeconds <= 5 and remainingSeconds ~= lastPulsedSecond then
					lastPulsedSecond = remainingSeconds
					pulseActiveEventFinalSecond(token, style.accent)
				end

				task.wait(0.25)
			end

			fadeActiveEventPill(token)
		end)
	end
end

DeepDigEventStartFlash = {
	tweens = {},
	sequence = 0,
}

DeepDigEventStartFlash.overlay = Instance.new("Frame")
DeepDigEventStartFlash.overlay.Name = "EventStartFlash"
DeepDigEventStartFlash.overlay.Size = UDim2.new(1, 0, 1, 0)
DeepDigEventStartFlash.overlay.Position = UDim2.new(0, 0, 0, 0)
DeepDigEventStartFlash.overlay.BackgroundColor3 = DeepDigActiveEventHud.styles.fallback.accent
DeepDigEventStartFlash.overlay.BackgroundTransparency = 1
DeepDigEventStartFlash.overlay.BorderSizePixel = 0
DeepDigEventStartFlash.overlay.Active = false
DeepDigEventStartFlash.overlay.Visible = false
DeepDigEventStartFlash.overlay.ZIndex = 80
DeepDigEventStartFlash.overlay.Parent = screenGui

DeepDigEventStartFlash.glint = Instance.new("Frame")
DeepDigEventStartFlash.glint.Name = "EventStartGlint"
DeepDigEventStartFlash.glint.Size = UDim2.new(0.18, 0, 1.2, 0)
DeepDigEventStartFlash.glint.Position = UDim2.new(-0.28, 0, -0.1, 0)
DeepDigEventStartFlash.glint.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
DeepDigEventStartFlash.glint.BackgroundTransparency = 1
DeepDigEventStartFlash.glint.BorderSizePixel = 0
DeepDigEventStartFlash.glint.Active = false
DeepDigEventStartFlash.glint.Rotation = 8
DeepDigEventStartFlash.glint.ZIndex = 81
DeepDigEventStartFlash.glint.Parent = DeepDigEventStartFlash.overlay

DeepDigEventStartFlash.gradient = Instance.new("UIGradient")
DeepDigEventStartFlash.gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(1, DeepDigActiveEventHud.styles.fallback.accent),
})
DeepDigEventStartFlash.gradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(1, 1),
})
DeepDigEventStartFlash.gradient.Parent = DeepDigEventStartFlash.glint

function DeepDigEventStartFlash.cancelTweens()
	for _, tween in ipairs(DeepDigEventStartFlash.tweens) do
		tween:Cancel()
	end
	DeepDigEventStartFlash.tweens = {}
end

function DeepDigEventStartFlash.reset()
	DeepDigEventStartFlash.overlay.Visible = false
	DeepDigEventStartFlash.overlay.BackgroundTransparency = 1
	DeepDigEventStartFlash.glint.BackgroundTransparency = 1
	DeepDigEventStartFlash.glint.Position = UDim2.new(-0.28, 0, -0.1, 0)
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
	if not seasonUi then
		return false
	end

	setHalloweenAmbienceActive(effectId == "halloween_loot")
	setSpringAmbienceActive(effectId == "spring_loot")
	setSummerAmbienceActive(effectId == "summer_loot")
	setWinterAmbienceActive(effectId == "winter_loot")

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

DeepDigRareRevealSound = {
	rarityRank = {
		Common = 1,
		Uncommon = 2,
		Rare = 3,
		Epic = 4,
		Legendary = 5,
		Mythic = 6,
	},
	minRank = 5,
	lowRarities = {
		Common = true,
		Uncommon = true,
		Rare = true,
		Epic = true,
	},
	cooldown = 0.45,
	lastPlayedAt = -math.huge,
}

DeepDigItemFoundSound = {
	cooldown = 0.35,
	lastSignature = nil,
	lastPlayedAt = -math.huge,
}

function DeepDigShouldPlayRareRevealForRarity(rarity)
	if typeof(rarity) ~= "string" then
		return false
	end

	local rank = DeepDigRareRevealSound.rarityRank[rarity]
	if rank then
		return rank >= DeepDigRareRevealSound.minRank
	end

	return DeepDigRareRevealSound.lowRarities[rarity] ~= true
end

function DeepDigPlayRareRevealSound()
	local now = os.clock()
	if now - DeepDigRareRevealSound.lastPlayedAt < DeepDigRareRevealSound.cooldown then
		return
	end

	DeepDigRareRevealSound.lastPlayedAt = now
	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("rare_reveal")
	end
end

function DeepDigIsValidItemFoundPayload(item)
	return type(item) == "table"
		and typeof(item.name) == "string"
		and item.name ~= ""
		and typeof(item.rarity) == "string"
		and item.rarity ~= ""
end

function DeepDigPlayItemFoundSound(item)
	local now = os.clock()
	local signature = table.concat({
		tostring(item.name),
		tostring(item.rarity),
		tostring(item.sellValue),
		tostring(item.worldPosition),
	}, "|")

	if signature == DeepDigItemFoundSound.lastSignature
		and now - DeepDigItemFoundSound.lastPlayedAt < DeepDigItemFoundSound.cooldown then
		return false
	end

	DeepDigItemFoundSound.lastSignature = signature
	DeepDigItemFoundSound.lastPlayedAt = now
	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("item_found")
	end

	return true
end

local LEGENDARY_FIND_FLASH_RARITIES = {
	Legendary = {
		overlayColor = Color3.fromRGB(255, 218, 82),
		peakTransparency = 0.18,
		flashInDuration = 0.08,
		flashOutDuration = 0.34,
		edgeGlowColors = {
			top = Color3.fromRGB(255, 230, 130),
			bottom = Color3.fromRGB(255, 166, 46),
			left = Color3.fromRGB(255, 198, 74),
			right = Color3.fromRGB(255, 198, 74),
		},
		edgeGlowPeakTransparency = 0.36,
		edgeGlowInDuration = 0.10,
		edgeGlowHoldDuration = 0.10,
		edgeGlowOutDuration = 0.68,
		edgeGlowThickness = 136,
		pulseColor = Color3.fromRGB(255, 238, 146),
		glintColor = Color3.fromRGB(255, 248, 210),
		pulseSize = 155,
		horizontalGlintWidth = 190,
		verticalGlintHeight = 80,
		pulseDuration = 0.36,
		glintExpandDuration = 0.18,
		glintFadeDuration = 0.26,
		hapticSmallStrength = 0.08,
		hapticLargeStrength = 0.14,
		hapticDuration = 0.12,
	},
	Mythic = {
		overlayColor = Color3.fromRGB(255, 218, 82),
		peakTransparency = 0.07,
		flashInDuration = 0.06,
		flashOutDuration = 0.44,
		edgeGlowColors = {
			top = Color3.fromRGB(190, 68, 255),
			bottom = Color3.fromRGB(255, 218, 82),
			left = Color3.fromRGB(255, 70, 186),
			right = Color3.fromRGB(255, 196, 64),
		},
		edgeGlowPeakTransparency = 0.18,
		edgeGlowInDuration = 0.08,
		edgeGlowHoldDuration = 0.14,
		edgeGlowOutDuration = 0.76,
		edgeGlowThickness = 174,
		pulseColor = Color3.fromRGB(255, 246, 246),
		glintColor = Color3.fromRGB(255, 255, 255),
		pulseSize = 220,
		horizontalGlintWidth = 260,
		verticalGlintHeight = 120,
		pulseDuration = 0.44,
		glintExpandDuration = 0.20,
		glintFadeDuration = 0.34,
		hapticSmallStrength = 0.12,
		hapticLargeStrength = 0.24,
		hapticDuration = 0.18,
	},
}

LEGENDARY_FIND_FLASH_RARITIES._haptics = {
	service = nil,
	supportChecked = false,
	supported = false,
	motorSupport = {},
	sequence = 0,
}

do
	local ok, service = pcall(function()
		return game:GetService("HapticService")
	end)

	if ok then
		LEGENDARY_FIND_FLASH_RARITIES._haptics.service = service
	end
end

function LEGENDARY_FIND_FLASH_RARITIES.PlayHaptics(rarity)
	local profile = LEGENDARY_FIND_FLASH_RARITIES[rarity]
	if not profile or not profile.hapticDuration then
		return
	end

	local state = LEGENDARY_FIND_FLASH_RARITIES._haptics
	local inputType = Enum.UserInputType.Gamepad1
	local smallMotor = Enum.VibrationMotor.Small
	local largeMotor = Enum.VibrationMotor.Large

	local function canUseHaptics()
		if state.supportChecked then
			return state.supported
		end

		state.supportChecked = true
		if not state.service then
			return false
		end

		local ok, supported = pcall(function()
			return state.service:IsVibrationSupported(inputType)
		end)
		state.supported = ok and supported == true
		return state.supported
	end

	local function canUseHapticMotor(motor)
		if not canUseHaptics() then
			return false
		end

		if state.motorSupport[motor] ~= nil then
			return state.motorSupport[motor]
		end

		local ok, supported = pcall(function()
			return state.service:IsMotorSupported(inputType, motor)
		end)
		state.motorSupport[motor] = ok and supported == true
		return state.motorSupport[motor]
	end

	local function setHapticMotor(motor, strength)
		if not canUseHapticMotor(motor) then
			return
		end

		pcall(function()
			state.service:SetMotor(inputType, motor, strength)
		end)
	end

	local function clearHapticPulse(sequence)
		if sequence and sequence ~= state.sequence then
			return
		end

		setHapticMotor(smallMotor, 0)
		setHapticMotor(largeMotor, 0)
	end

	state.sequence = state.sequence + 1
	local sequence = state.sequence

	setHapticMotor(smallMotor, profile.hapticSmallStrength)
	setHapticMotor(largeMotor, profile.hapticLargeStrength)

	task.delay(profile.hapticDuration, function()
		clearHapticPulse(sequence)
	end)
end

DeepDigSeasonalRevealStyles = {
	halloween = {
		season = "Halloween",
		theme = "The Bone Age",
		symbol = "🎃",
		background = Color3.fromRGB(44, 24, 48),
		panel = Color3.fromRGB(74, 38, 24),
		accent = Color3.fromRGB(255, 130, 45),
		text = Color3.fromRGB(255, 224, 176),
		detail = Color3.fromRGB(214, 255, 230),
	},
	winter = {
		season = "Winter",
		theme = "The Ice Age",
		symbol = "❄",
		background = Color3.fromRGB(18, 44, 64),
		panel = Color3.fromRGB(24, 62, 86),
		accent = Color3.fromRGB(120, 220, 255),
		text = Color3.fromRGB(224, 250, 255),
		detail = Color3.fromRGB(188, 236, 255),
	},
	spring = {
		season = "Spring",
		theme = "Fossil Rush",
		symbol = "🌱",
		background = Color3.fromRGB(24, 58, 36),
		panel = Color3.fromRGB(30, 78, 48),
		accent = Color3.fromRGB(95, 230, 120),
		text = Color3.fromRGB(224, 255, 222),
		detail = Color3.fromRGB(250, 230, 120),
	},
	summer = {
		season = "Summer",
		theme = "Volcano Event",
		symbol = "☀",
		background = Color3.fromRGB(70, 36, 20),
		panel = Color3.fromRGB(88, 44, 24),
		accent = Color3.fromRGB(255, 190, 70),
		text = Color3.fromRGB(255, 238, 184),
		detail = Color3.fromRGB(255, 124, 72),
	},
	fallback = {
		season = "Seasonal",
		theme = "Limited-Time Find",
		symbol = "✦",
		background = Color3.fromRGB(32, 34, 48),
		panel = Color3.fromRGB(42, 44, 62),
		accent = Color3.fromRGB(220, 220, 230),
		text = Color3.fromRGB(246, 246, 255),
		detail = Color3.fromRGB(195, 230, 255),
	},
}

DeepDigSeasonalRevealState = {
	token = 0,
	frame = nil,
}

function DeepDigGetSeasonalRevealStyle(seasonId)
	local key = string.lower(tostring(seasonId or ""))
	local normalizedKey = string.gsub(key, "_loot$", "")
	return DeepDigSeasonalRevealStyles[key]
		or DeepDigSeasonalRevealStyles[normalizedKey]
		or DeepDigSeasonalRevealStyles.fallback
end

function DeepDigFadeSeasonalRevealDescendants(root, duration)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			TweenService:Create(descendant, TweenInfo.new(duration), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
		elseif descendant:IsA("Frame") then
			TweenService:Create(descendant, TweenInfo.new(duration), {
				BackgroundTransparency = 1,
			}):Play()
		elseif descendant:IsA("UIStroke") then
			TweenService:Create(descendant, TweenInfo.new(duration), {
				Transparency = 1,
			}):Play()
		end
	end
end

function DeepDigPlaySeasonalExclusiveReveal(item)
	DeepDigSeasonalRevealState.token = DeepDigSeasonalRevealState.token + 1
	local token = DeepDigSeasonalRevealState.token

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("seasonal_exclusive_reveal")
	end

	if DeepDigSeasonalRevealState.frame then
		DeepDigSeasonalRevealState.frame:Destroy()
		DeepDigSeasonalRevealState.frame = nil
	end

	local style = DeepDigGetSeasonalRevealStyle(item.seasonId)
	local rarity = tostring(item.rarity or "Rare")
	local rarityColor = RARITY_COLORS[rarity] or style.accent
	local itemName = tostring(item.name or "Seasonal Artifact")
	local coinValue = tostring(item.sellValue or item.baseValue or 0)

	local layer = Instance.new("Frame")
	layer.Name = "SeasonalExclusiveRevealBurst"
	layer.Size = UDim2.new(1, 0, 1, 0)
	layer.Position = UDim2.new(0, 0, 0, 0)
	layer.BackgroundColor3 = style.background
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.Active = false
	layer.ZIndex = 96
	layer.Parent = screenGui
	DeepDigSeasonalRevealState.frame = layer

	local burstCenter = Instance.new("Frame")
	burstCenter.Name = "BurstCenter"
	burstCenter.Size = UDim2.new(0, 1, 0, 1)
	burstCenter.AnchorPoint = Vector2.new(0.5, 0.5)
	burstCenter.Position = UDim2.new(0.5, 0, 0.46, 0)
	burstCenter.BackgroundTransparency = 1
	burstCenter.ZIndex = 97
	burstCenter.Parent = layer

	for i = 1, 10 do
		local ray = Instance.new("Frame")
		ray.Name = "Ray"
		ray.Size = UDim2.new(0, i % 2 == 0 and 172 or 118, 0, i % 2 == 0 and 5 or 3)
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.new(0.5, 0, 0.5, 0)
		ray.Rotation = i * 36
		ray.BackgroundColor3 = style.accent
		ray.BackgroundTransparency = 0.22
		ray.BorderSizePixel = 0
		ray.ZIndex = 97
		ray.Parent = burstCenter
		TweenService:Create(ray, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, i % 2 == 0 and 260 or 190, 0, 1),
			BackgroundTransparency = 0.82,
		}):Play()
	end

	local card = Instance.new("Frame")
	card.Name = "SeasonalCard"
	card.Size = UDim2.new(0, 430, 0, 178)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0.5, 0, 0.46, 0)
	card.BackgroundColor3 = style.panel
	card.BackgroundTransparency = 0.04
	card.BorderSizePixel = 0
	card.ZIndex = 98
	card.Parent = layer

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 8)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = style.accent
	cardStroke.Thickness = 3
	cardStroke.Transparency = 0
	cardStroke.Parent = card

	local cardScale = Instance.new("UIScale")
	cardScale.Scale = 0.82
	cardScale.Parent = card

	local symbolLabel = Instance.new("TextLabel")
	symbolLabel.Name = "SeasonSymbol"
	symbolLabel.Size = UDim2.new(0, 66, 0, 66)
	symbolLabel.Position = UDim2.new(0.5, -33, 0, -28)
	symbolLabel.BackgroundTransparency = 1
	symbolLabel.Text = style.symbol
	symbolLabel.TextColor3 = style.accent
	symbolLabel.TextSize = 46
	symbolLabel.TextStrokeColor3 = Color3.fromRGB(20, 20, 24)
	symbolLabel.TextStrokeTransparency = 0.25
	symbolLabel.Font = Enum.Font.GothamBlack
	symbolLabel.ZIndex = 100
	symbolLabel.Parent = card

	local seasonLabel = Instance.new("TextLabel")
	seasonLabel.Name = "Season"
	seasonLabel.Size = UDim2.new(1, -36, 0, 24)
	seasonLabel.Position = UDim2.new(0, 18, 0, 28)
	seasonLabel.BackgroundTransparency = 1
	seasonLabel.Text = style.season .. " Exclusive"
	seasonLabel.TextColor3 = style.accent
	seasonLabel.TextSize = 17
	seasonLabel.Font = Enum.Font.GothamBlack
	seasonLabel.TextXAlignment = Enum.TextXAlignment.Center
	seasonLabel.ZIndex = 99
	seasonLabel.Parent = card

	local themeLabel = Instance.new("TextLabel")
	themeLabel.Name = "Theme"
	themeLabel.Size = UDim2.new(1, -36, 0, 20)
	themeLabel.Position = UDim2.new(0, 18, 0, 52)
	themeLabel.BackgroundTransparency = 1
	themeLabel.Text = style.theme
	themeLabel.TextColor3 = style.detail
	themeLabel.TextSize = 14
	themeLabel.Font = Enum.Font.GothamBold
	themeLabel.TextXAlignment = Enum.TextXAlignment.Center
	themeLabel.ZIndex = 99
	themeLabel.Parent = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "ItemName"
	nameLabel.Size = UDim2.new(1, -36, 0, 42)
	nameLabel.Position = UDim2.new(0, 18, 0, 78)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = itemName
	nameLabel.TextColor3 = rarityColor
	nameLabel.TextSize = 27
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.ZIndex = 99
	nameLabel.Parent = card

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "Value"
	valueLabel.Size = UDim2.new(1, -36, 0, 24)
	valueLabel.Position = UDim2.new(0, 18, 0, 124)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text = rarity .. "  •  +" .. coinValue .. " coins"
	valueLabel.TextColor3 = style.text
	valueLabel.TextSize = 16
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextXAlignment = Enum.TextXAlignment.Center
	valueLabel.ZIndex = 99
	valueLabel.Parent = card

	TweenService:Create(layer, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.30,
	}):Play()
	TweenService:Create(cardScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1.06,
	}):Play()
	task.delay(0.18, function()
		if token ~= DeepDigSeasonalRevealState.token or not cardScale.Parent then
			return
		end
		TweenService:Create(cardScale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end)

	task.delay(1.35, function()
		if token ~= DeepDigSeasonalRevealState.token or not layer.Parent then
			return
		end

		TweenService:Create(layer, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(card, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0.43, 0),
		}):Play()
		DeepDigFadeSeasonalRevealDescendants(layer, 0.28)

		task.delay(0.30, function()
			if token ~= DeepDigSeasonalRevealState.token then
				return
			end
			if layer.Parent then
				layer:Destroy()
			end
			DeepDigSeasonalRevealState.frame = nil
		end)
	end)
end

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

local showDepthTierUnlockedBurst

updateDepthTone = (function(applyDepthTone)

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
	title.Text = "Layer Discovered"
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

	local depthRangeLabel = Instance.new("TextLabel")
	depthRangeLabel.Name = "DepthRange"
	depthRangeLabel.Size = UDim2.new(1, -40, 0, 22)
	depthRangeLabel.Position = UDim2.fromOffset(20, 88)
	depthRangeLabel.BackgroundTransparency = 1
	depthRangeLabel.Text = ""
	depthRangeLabel.TextColor3 = Color3.fromRGB(230, 220, 205)
	depthRangeLabel.TextTransparency = 1
	depthRangeLabel.TextSize = 15
	depthRangeLabel.Font = Enum.Font.GothamBold
	depthRangeLabel.TextXAlignment = Enum.TextXAlignment.Center
	depthRangeLabel.ZIndex = 85
	depthRangeLabel.Parent = banner

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

	local function getTierRecordFromPayload(payload)
		if type(payload) ~= "table" then
			return nil
		end

		local payloadTierName = type(payload.tierName) == "string" and payload.tierName or nil
		local payloadDepth = tonumber(payload.depth)
		for _, tier in ipairs(Config.TIERS or {}) do
			if payloadTierName and tier.name == payloadTierName then
				return tier
			end
		end

		if payloadDepth then
			for _, tier in ipairs(Config.TIERS or {}) do
				if payloadDepth >= tier.minDepth and payloadDepth <= tier.maxDepth then
					return tier
				end
			end
		end

		return nil
	end

	local function getReadableTierColor(tierColor)
		return tierColor:Lerp(Color3.fromRGB(255, 245, 225), 0.42)
	end

	local function formatDepthRange(tier)
		return "Depth " .. tostring(tier.minDepth) .. "-" .. tostring(tier.maxDepth)
	end

	function showDepthTierUnlockedBurst(payload)
		local tier = getTierRecordFromPayload(payload)
		if not tier then
			return
		end

		sequence = sequence + 1
		local currentSequence = sequence
		local tierColor = tier.color or Color3.fromRGB(255, 230, 150)
		local readableTierColor = getReadableTierColor(tierColor)

		clearTweens()
		banner.Visible = true
		banner.Size = UDim2.fromOffset(392, 112)
		banner.Position = UDim2.fromScale(0.5, 0.49)
		banner.BackgroundTransparency = 1
		bannerStroke.Color = tierColor
		bannerStroke.Transparency = 1
		title.TextTransparency = 1
		tierLabel.Text = tier.name
		tierLabel.TextColor3 = readableTierColor
		tierLabel.TextTransparency = 1
		depthRangeLabel.Text = formatDepthRange(tier)
		depthRangeLabel.TextColor3 = readableTierColor:Lerp(Color3.fromRGB(255, 255, 255), 0.12)
		depthRangeLabel.TextTransparency = 1

		tween(banner, 0.18, {
			Size = UDim2.fromOffset(440, 128),
			Position = UDim2.fromScale(0.5, 0.47),
			BackgroundTransparency = 0.08,
		}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		tween(bannerStroke, 0.18, { Transparency = 0.05 })
		tween(title, 0.14, { TextTransparency = 0 })
		tween(tierLabel, 0.18, { TextTransparency = 0 })
		tween(depthRangeLabel, 0.22, { TextTransparency = 0 })

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
			tween(tierLabel, 0.16, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local fadeOut = tween(depthRangeLabel, 0.16, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
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
	end
end)(updateDepthTone)

DeepDigDepthMilestoneUi = {}
DeepDigDepthMilestoneTweens = {}
DeepDigDepthMilestoneSequence = 0

DeepDigDepthMilestoneUi.burst = Instance.new("Frame")
DeepDigDepthMilestoneUi.burst.Name = "DepthMilestoneBurst"
DeepDigDepthMilestoneUi.burst.AnchorPoint = Vector2.new(0.5, 0)
DeepDigDepthMilestoneUi.burst.Size = UDim2.fromOffset(242, 34)
DeepDigDepthMilestoneUi.burst.Position = UDim2.new(0.5, 0, 0, 52)
DeepDigDepthMilestoneUi.burst.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
DeepDigDepthMilestoneUi.burst.BackgroundTransparency = 1
DeepDigDepthMilestoneUi.burst.BorderSizePixel = 0
DeepDigDepthMilestoneUi.burst.Visible = false
DeepDigDepthMilestoneUi.burst.ZIndex = 82
DeepDigDepthMilestoneUi.burst.Parent = screenGui

DeepDigDepthMilestoneUi.corner = Instance.new("UICorner")
DeepDigDepthMilestoneUi.corner.CornerRadius = UDim.new(0, 8)
DeepDigDepthMilestoneUi.corner.Parent = DeepDigDepthMilestoneUi.burst

DeepDigDepthMilestoneUi.stroke = Instance.new("UIStroke")
DeepDigDepthMilestoneUi.stroke.Color = Color3.fromRGB(255, 230, 150)
DeepDigDepthMilestoneUi.stroke.Thickness = 1.5
DeepDigDepthMilestoneUi.stroke.Transparency = 1
DeepDigDepthMilestoneUi.stroke.Parent = DeepDigDepthMilestoneUi.burst

DeepDigDepthMilestoneUi.label = Instance.new("TextLabel")
DeepDigDepthMilestoneUi.label.Name = "Label"
DeepDigDepthMilestoneUi.label.Size = UDim2.new(1, -18, 1, 0)
DeepDigDepthMilestoneUi.label.Position = UDim2.fromOffset(9, 0)
DeepDigDepthMilestoneUi.label.BackgroundTransparency = 1
DeepDigDepthMilestoneUi.label.Text = ""
DeepDigDepthMilestoneUi.label.TextColor3 = Color3.fromRGB(255, 245, 210)
DeepDigDepthMilestoneUi.label.TextTransparency = 1
DeepDigDepthMilestoneUi.label.TextSize = 16
DeepDigDepthMilestoneUi.label.Font = Enum.Font.GothamBlack
DeepDigDepthMilestoneUi.label.TextXAlignment = Enum.TextXAlignment.Center
DeepDigDepthMilestoneUi.label.ZIndex = 83
DeepDigDepthMilestoneUi.label.Parent = DeepDigDepthMilestoneUi.burst

function DeepDigClearDepthMilestoneTweens()
	for _, tween in ipairs(DeepDigDepthMilestoneTweens) do
		tween:Cancel()
	end
	DeepDigDepthMilestoneTweens = {}
end

function DeepDigTweenDepthMilestone(instance, duration, goal, easingStyle, easingDirection)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
		goal
	)
	table.insert(DeepDigDepthMilestoneTweens, tween)
	tween:Play()
	return tween
end

function DeepDigGetDepthMilestoneColor(payload)
	if type(payload) == "table" and typeof(payload.color) == "Color3" then
		return payload.color
	end

	local depth = type(payload) == "table" and tonumber(payload.depth) or nil
	if depth then
		for _, tier in ipairs(Config.TIERS or {}) do
			if depth >= tier.minDepth and depth <= tier.maxDepth then
				return tier.color
			end
		end
	end

	return Color3.fromRGB(255, 230, 150)
end

function DeepDigShowDepthMilestoneBurst(payload)
	if type(payload) ~= "table" then
		return
	end

	local depth = math.floor(tonumber(payload.depth) or 0)
	if depth <= 0 then
		return
	end

	DeepDigDepthMilestoneSequence = DeepDigDepthMilestoneSequence + 1
	local currentSequence = DeepDigDepthMilestoneSequence
	local tierColor = DeepDigGetDepthMilestoneColor(payload)
	local readableColor = tierColor:Lerp(Color3.fromRGB(255, 255, 255), 0.36)

	DeepDigClearDepthMilestoneTweens()
	DeepDigDepthMilestoneUi.burst.Visible = true
	DeepDigDepthMilestoneUi.burst.Position = UDim2.new(0.5, 0, 0, 50)
	DeepDigDepthMilestoneUi.burst.BackgroundTransparency = 1
	DeepDigDepthMilestoneUi.stroke.Color = tierColor
	DeepDigDepthMilestoneUi.stroke.Transparency = 1
	DeepDigDepthMilestoneUi.label.Text = "Depth " .. tostring(depth) .. " reached"
	DeepDigDepthMilestoneUi.label.TextColor3 = readableColor
	DeepDigDepthMilestoneUi.label.TextTransparency = 1

	DeepDigTweenDepthMilestone(DeepDigDepthMilestoneUi.burst, 0.16, {
		Position = UDim2.new(0.5, 0, 0, 56),
		BackgroundTransparency = 0.08,
	}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	DeepDigTweenDepthMilestone(DeepDigDepthMilestoneUi.stroke, 0.16, { Transparency = 0.08 })
	DeepDigTweenDepthMilestone(DeepDigDepthMilestoneUi.label, 0.14, { TextTransparency = 0 })

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("depth_milestone")
	end

	task.delay(1.35, function()
		if currentSequence ~= DeepDigDepthMilestoneSequence then
			return
		end

		DeepDigTweenDepthMilestone(DeepDigDepthMilestoneUi.burst, 0.2, {
			Position = UDim2.new(0.5, 0, 0, 48),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		DeepDigTweenDepthMilestone(DeepDigDepthMilestoneUi.stroke, 0.18, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local fade = DeepDigTweenDepthMilestone(DeepDigDepthMilestoneUi.label, 0.16, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		fade.Completed:Connect(function(playbackState)
			if currentSequence ~= DeepDigDepthMilestoneSequence or playbackState ~= Enum.PlaybackState.Completed then
				return
			end
			DeepDigDepthMilestoneUi.burst.Visible = false
		end)
	end)
end

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

LEGENDARY_FIND_FLASH_RARITIES._edgeGlow = {
	frame = Instance.new("Frame"),
	edges = {},
	tweens = {},
}
LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.frame.Name = "EdgeGlowVignette"
LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.frame.Size = UDim2.new(1, 0, 1, 0)
LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.frame.Position = UDim2.new(0, 0, 0, 0)
LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.frame.BackgroundTransparency = 1
LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.frame.BorderSizePixel = 0
LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.frame.Visible = false
LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.frame.ZIndex = 91
LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.frame.Parent = findFlashLayer

function LEGENDARY_FIND_FLASH_RARITIES.CreateEdgeGlowFrame(name, size, position, rotation)
	local edge = Instance.new("Frame")
	edge.Name = name
	edge.Size = size
	edge.Position = position
	edge.BackgroundColor3 = Color3.fromRGB(255, 210, 80)
	edge.BackgroundTransparency = 1
	edge.BorderSizePixel = 0
	edge.ZIndex = 91
	edge.Parent = LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.frame

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = edge

	LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.edges[name] = edge
	return edge
end

LEGENDARY_FIND_FLASH_RARITIES.CreateEdgeGlowFrame("top", UDim2.new(1, 0, 0, 136), UDim2.new(0, 0, 0, 0), 90)
LEGENDARY_FIND_FLASH_RARITIES.CreateEdgeGlowFrame("bottom", UDim2.new(1, 0, 0, 136), UDim2.new(0, 0, 1, -136), 270)
LEGENDARY_FIND_FLASH_RARITIES.CreateEdgeGlowFrame("left", UDim2.new(0, 136, 1, 0), UDim2.new(0, 0, 0, 0), 0)
LEGENDARY_FIND_FLASH_RARITIES.CreateEdgeGlowFrame("right", UDim2.new(0, 136, 1, 0), UDim2.new(1, -136, 0, 0), 180)

local findFlashSequence = 0
local findFlashInTween = nil
local findFlashOutTween = nil

function LEGENDARY_FIND_FLASH_RARITIES.ClearEdgeGlowTweens()
	for _, tween in ipairs(LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.tweens) do
		tween:Cancel()
	end
	LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.tweens = {}
end

function LEGENDARY_FIND_FLASH_RARITIES.SetEdgeGlowTransparency(transparency)
	for _, edge in pairs(LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.edges) do
		edge.BackgroundTransparency = transparency
	end
end

function LEGENDARY_FIND_FLASH_RARITIES.TweenEdgeGlow(transparency, duration, easingStyle, easingDirection)
	LEGENDARY_FIND_FLASH_RARITIES.ClearEdgeGlowTweens()

	local lastTween = nil
	for _, edge in pairs(LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.edges) do
		local tween = TweenService:Create(
			edge,
			TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
			{ BackgroundTransparency = transparency }
		)
		table.insert(LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.tweens, tween)
		lastTween = tween
		tween:Play()
	end

	return lastTween
end

function LEGENDARY_FIND_FLASH_RARITIES.PlayEdgeGlow(flashProfile, sequence)
	local edgeColors = flashProfile.edgeGlowColors
	if not edgeColors then
		return
	end

	LEGENDARY_FIND_FLASH_RARITIES.ClearEdgeGlowTweens()
	LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.frame.Visible = true
	LEGENDARY_FIND_FLASH_RARITIES.SetEdgeGlowTransparency(1)

	local thickness = flashProfile.edgeGlowThickness or 136
	LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.edges.top.Size = UDim2.new(1, 0, 0, thickness)
	LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.edges.top.Position = UDim2.new(0, 0, 0, 0)
	LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.edges.bottom.Size = UDim2.new(1, 0, 0, thickness)
	LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.edges.bottom.Position = UDim2.new(0, 0, 1, -thickness)
	LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.edges.left.Size = UDim2.new(0, thickness, 1, 0)
	LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.edges.left.Position = UDim2.new(0, 0, 0, 0)
	LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.edges.right.Size = UDim2.new(0, thickness, 1, 0)
	LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.edges.right.Position = UDim2.new(1, -thickness, 0, 0)

	for edgeName, edge in pairs(LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.edges) do
		edge.BackgroundColor3 = edgeColors[edgeName] or flashProfile.overlayColor
	end

	LEGENDARY_FIND_FLASH_RARITIES.TweenEdgeGlow(
		flashProfile.edgeGlowPeakTransparency or 0.36,
		flashProfile.edgeGlowInDuration or 0.10,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	task.delay((flashProfile.edgeGlowInDuration or 0.10) + (flashProfile.edgeGlowHoldDuration or 0.10), function()
		if sequence ~= findFlashSequence then
			return
		end

		local fadeOutTween = LEGENDARY_FIND_FLASH_RARITIES.TweenEdgeGlow(
			1,
			flashProfile.edgeGlowOutDuration or 0.68,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)

		if fadeOutTween then
			fadeOutTween.Completed:Connect(function(playbackState)
				if sequence ~= findFlashSequence or playbackState ~= Enum.PlaybackState.Completed then
					return
				end

				LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.frame.Visible = false
				LEGENDARY_FIND_FLASH_RARITIES.SetEdgeGlowTransparency(1)
				LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.tweens = {}
			end)
		end
	end)
end

function LEGENDARY_FIND_FLASH_RARITIES.FadeRareFindRevealDescendants(root, transparency, duration)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			TweenService:Create(descendant, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				TextTransparency = transparency,
				TextStrokeTransparency = transparency == 0 and 0.75 or 1,
			}):Play()
		elseif descendant:IsA("Frame") then
			local targetTransparency = transparency
			if descendant.Name == "RevealPanel" then
				targetTransparency = transparency == 0 and 0.08 or 1
			elseif descendant.Name == "AccentBar" then
				targetTransparency = transparency == 0 and 0.12 or 1
			end
			TweenService:Create(descendant, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = targetTransparency,
			}):Play()
		elseif descendant:IsA("UIStroke") then
			TweenService:Create(descendant, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = transparency == 0 and 0.08 or 1,
			}):Play()
		end
	end
end

function LEGENDARY_FIND_FLASH_RARITIES.ShowRareFindRevealBanner(item, rarity, flashProfile, sequence)
	if type(item) ~= "table" then
		return
	end

	local itemName = tostring(item.name or "Rare Artifact")
	local coinValue = tostring(item.sellValue or item.baseValue or 0)
	local rarityColor = RARITY_COLORS[rarity] or flashProfile.overlayColor

	local banner = Instance.new("Frame")
	banner.Name = "RareFindReveal"
	banner.Size = UDim2.new(0.82, 0, 0, 116)
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.new(0.5, 0, 0.44, 0)
	banner.BackgroundTransparency = 1
	banner.BorderSizePixel = 0
	banner.ZIndex = 95
	banner.Parent = findFlashLayer

	local bannerSize = Instance.new("UISizeConstraint")
	bannerSize.MinSize = Vector2.new(260, 104)
	bannerSize.MaxSize = Vector2.new(560, 126)
	bannerSize.Parent = banner

	local scale = Instance.new("UIScale")
	scale.Scale = 0.9
	scale.Parent = banner

	local panel = Instance.new("Frame")
	panel.Name = "RevealPanel"
	panel.Size = UDim2.new(1, 0, 1, 0)
	panel.BackgroundColor3 = Color3.fromRGB(18, 16, 22)
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.ZIndex = 95
	panel.Parent = banner

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 8)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = rarityColor
	panelStroke.Thickness = rarity == "Mythic" and 3 or 2
	panelStroke.Transparency = 1
	panelStroke.Parent = panel

	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.Size = UDim2.new(1, -22, 0, 4)
	accentBar.Position = UDim2.new(0, 11, 0, 10)
	accentBar.BackgroundColor3 = flashProfile.overlayColor
	accentBar.BackgroundTransparency = 1
	accentBar.BorderSizePixel = 0
	accentBar.ZIndex = 96
	accentBar.Parent = panel

	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(1, 0)
	accentCorner.Parent = accentBar

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Name = "Rarity"
	rarityLabel.Size = UDim2.new(1, -28, 0, 26)
	rarityLabel.Position = UDim2.new(0, 14, 0, 20)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Text = rarity .. " FIND"
	rarityLabel.TextColor3 = rarityColor
	rarityLabel.TextTransparency = 1
	rarityLabel.TextStrokeTransparency = 1
	rarityLabel.TextSize = 20
	rarityLabel.TextScaled = true
	rarityLabel.Font = Enum.Font.GothamBlack
	rarityLabel.TextXAlignment = Enum.TextXAlignment.Center
	rarityLabel.TextTruncate = Enum.TextTruncate.AtEnd
	rarityLabel.ZIndex = 97
	rarityLabel.Parent = panel

	local rarityTextSize = Instance.new("UITextSizeConstraint")
	rarityTextSize.MinTextSize = 11
	rarityTextSize.MaxTextSize = 20
	rarityTextSize.Parent = rarityLabel

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "ItemName"
	nameLabel.Size = UDim2.new(1, -32, 0, 40)
	nameLabel.Position = UDim2.new(0, 16, 0, 45)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = itemName
	nameLabel.TextColor3 = Color3.fromRGB(255, 250, 230)
	nameLabel.TextTransparency = 1
	nameLabel.TextStrokeTransparency = 1
	nameLabel.TextSize = 30
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.ZIndex = 97
	nameLabel.Parent = panel

	local nameTextSize = Instance.new("UITextSizeConstraint")
	nameTextSize.MinTextSize = 16
	nameTextSize.MaxTextSize = 30
	nameTextSize.Parent = nameLabel

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "CoinValue"
	valueLabel.Size = UDim2.new(1, -32, 0, 22)
	valueLabel.Position = UDim2.new(0, 16, 1, -30)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text = "+" .. coinValue .. " coins"
	valueLabel.TextColor3 = Color3.fromRGB(255, 218, 92)
	valueLabel.TextTransparency = 1
	valueLabel.TextStrokeTransparency = 1
	valueLabel.TextSize = 18
	valueLabel.TextScaled = true
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextXAlignment = Enum.TextXAlignment.Center
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
	valueLabel.ZIndex = 97
	valueLabel.Parent = panel

	local valueTextSize = Instance.new("UITextSizeConstraint")
	valueTextSize.MinTextSize = 10
	valueTextSize.MaxTextSize = 18
	valueTextSize.Parent = valueLabel

	LEGENDARY_FIND_FLASH_RARITIES.FadeRareFindRevealDescendants(banner, 0, 0.12)
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = rarity == "Mythic" and 1.05 or 1,
	}):Play()

	task.delay(1.28, function()
		if sequence ~= findFlashSequence or not banner.Parent then
			return
		end

		LEGENDARY_FIND_FLASH_RARITIES.FadeRareFindRevealDescendants(banner, 1, 0.22)
		local shrink = TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Scale = 0.96,
		})
		shrink:Play()
		shrink.Completed:Connect(function(playbackState)
			if sequence ~= findFlashSequence or playbackState ~= Enum.PlaybackState.Completed then
				return
			end
			if banner.Parent then
				banner:Destroy()
			end
		end)
	end)
end

local function playLegendaryFindFlash(rarity, item)
	local flashProfile = LEGENDARY_FIND_FLASH_RARITIES[rarity] or LEGENDARY_FIND_FLASH_RARITIES.Legendary
	LEGENDARY_FIND_FLASH_RARITIES.PlayHaptics(rarity)

	findFlashSequence = findFlashSequence + 1
	local sequence = findFlashSequence

	local previousGlint = findFlashLayer:FindFirstChild("Glint")
	if previousGlint then
		previousGlint:Destroy()
	end
	local previousReveal = findFlashLayer:FindFirstChild("RareFindReveal")
	if previousReveal then
		previousReveal:Destroy()
	end

	if findFlashInTween then
		findFlashInTween:Cancel()
		findFlashInTween = nil
	end
	if findFlashOutTween then
		findFlashOutTween:Cancel()
		findFlashOutTween = nil
	end
	LEGENDARY_FIND_FLASH_RARITIES.ClearEdgeGlowTweens()
	LEGENDARY_FIND_FLASH_RARITIES._edgeGlow.frame.Visible = false
	LEGENDARY_FIND_FLASH_RARITIES.SetEdgeGlowTransparency(1)

	findFlashOverlay.BackgroundColor3 = flashProfile.overlayColor
	findFlashOverlay.BackgroundTransparency = 1
	LEGENDARY_FIND_FLASH_RARITIES.PlayEdgeGlow(flashProfile, sequence)
	LEGENDARY_FIND_FLASH_RARITIES.ShowRareFindRevealBanner(item, rarity, flashProfile, sequence)

	findFlashInTween = TweenService:Create(
		findFlashOverlay,
		TweenInfo.new(flashProfile.flashInDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = flashProfile.peakTransparency }
	)
	findFlashInTween:Play()
	findFlashInTween.Completed:Connect(function(playbackState)
		if sequence ~= findFlashSequence or playbackState ~= Enum.PlaybackState.Completed then
			return
		end

		findFlashOutTween = TweenService:Create(
			findFlashOverlay,
			TweenInfo.new(flashProfile.flashOutDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)
		findFlashOutTween:Play()
		findFlashOutTween.Completed:Connect(function(outPlaybackState)
			if sequence ~= findFlashSequence or outPlaybackState ~= Enum.PlaybackState.Completed then
				return
			end

			findFlashOverlay.BackgroundTransparency = 1
			findFlashOutTween = nil
		end)
	end)

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

	task.delay(math.max(flashProfile.pulseDuration, flashProfile.glintFadeDuration) + 0.05, function()
		if sequence ~= findFlashSequence then
			return
		end

		if glint.Parent then
			glint:Destroy()
		end
	end)
end

do
	LEGENDARY_FIND_FLASH_RARITIES._anchoredGlint = {
		sequence = 0,
		frame = nil,
	}

	function LEGENDARY_FIND_FLASH_RARITIES.PlayAnchoredGlint(item)
		if type(item) ~= "table" or not LEGENDARY_FIND_FLASH_RARITIES[item.rarity] then
			return false
		end
		if typeof(item.worldPosition) ~= "Vector3" then
			return false
		end

		local camera = workspace.CurrentCamera
		if not camera then
			return false
		end

		local ok, viewportPoint, onScreen = pcall(function()
			return camera:WorldToViewportPoint(item.worldPosition)
		end)
		if not ok or not onScreen or viewportPoint.Z <= 0 then
			return false
		end

		local viewportSize = camera.ViewportSize
		if viewportSize.X <= 0 or viewportSize.Y <= 0 then
			return false
		end
		if viewportPoint.X < 0 or viewportPoint.X > viewportSize.X
			or viewportPoint.Y < 0 or viewportPoint.Y > viewportSize.Y then
			return false
		end

		local state = LEGENDARY_FIND_FLASH_RARITIES._anchoredGlint
		state.sequence = state.sequence + 1
		local sequence = state.sequence
		if state.frame and state.frame.Parent then
			state.frame:Destroy()
		end

		local accentColor = item.rarity == "Mythic"
			and Color3.fromRGB(255, 82, 164)
			or Color3.fromRGB(255, 218, 82)
		local glintColor = item.rarity == "Mythic"
			and Color3.fromRGB(255, 248, 248)
			or Color3.fromRGB(255, 248, 210)
		local targetSize = item.rarity == "Mythic" and 118 or 88
		local maxX = math.max(18, viewportSize.X - 18)
		local maxY = math.max(18, viewportSize.Y - 18)

		local marker = Instance.new("Frame")
		marker.Name = "AnchoredFindGlint"
		marker.Size = UDim2.fromOffset(1, 1)
		marker.AnchorPoint = Vector2.new(0.5, 0.5)
		marker.Position = UDim2.fromOffset(
			math.clamp(viewportPoint.X, 18, maxX),
			math.clamp(viewportPoint.Y, 18, maxY)
		)
		marker.BackgroundTransparency = 1
		marker.BorderSizePixel = 0
		marker.ZIndex = 94
		marker.Parent = findFlashLayer
		state.frame = marker

		local ring = Instance.new("Frame")
		ring.Name = "Ring"
		ring.Size = UDim2.fromOffset(24, 24)
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.BackgroundTransparency = 1
		ring.BorderSizePixel = 0
		ring.ZIndex = 94
		ring.Parent = marker

		local ringCorner = Instance.new("UICorner")
		ringCorner.CornerRadius = UDim.new(1, 0)
		ringCorner.Parent = ring

		local ringStroke = Instance.new("UIStroke")
		ringStroke.Color = accentColor
		ringStroke.Thickness = item.rarity == "Mythic" and 4 or 3
		ringStroke.Transparency = 0
		ringStroke.Parent = ring

		local horizontalGlint = Instance.new("Frame")
		horizontalGlint.Name = "Horizontal"
		horizontalGlint.Size = UDim2.fromOffset(10, 4)
		horizontalGlint.AnchorPoint = Vector2.new(0.5, 0.5)
		horizontalGlint.Position = UDim2.fromScale(0.5, 0.5)
		horizontalGlint.BackgroundColor3 = glintColor
		horizontalGlint.BackgroundTransparency = 0.02
		horizontalGlint.BorderSizePixel = 0
		horizontalGlint.ZIndex = 95
		horizontalGlint.Parent = marker

		local verticalGlint = Instance.new("Frame")
		verticalGlint.Name = "Vertical"
		verticalGlint.Size = UDim2.fromOffset(4, 10)
		verticalGlint.AnchorPoint = Vector2.new(0.5, 0.5)
		verticalGlint.Position = UDim2.fromScale(0.5, 0.5)
		verticalGlint.BackgroundColor3 = glintColor
		verticalGlint.BackgroundTransparency = 0.02
		verticalGlint.BorderSizePixel = 0
		verticalGlint.ZIndex = 95
		verticalGlint.Parent = marker

		TweenService:Create(ring, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(targetSize, targetSize),
		}):Play()
		TweenService:Create(ringStroke, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
			Thickness = 1,
		}):Play()
		TweenService:Create(horizontalGlint, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(targetSize + 36, 5),
		}):Play()
		TweenService:Create(verticalGlint, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(5, targetSize),
		}):Play()
		TweenService:Create(horizontalGlint, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(verticalGlint, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()

		task.delay(0.30, function()
			if sequence ~= state.sequence then
				return
			end
			if marker.Parent then
				marker:Destroy()
			end
			state.frame = nil
		end)

		return true
	end
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
	if nameKey == "earthquake" or nameKey == "instantdig" then
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
	local state = eventShakeState
	if camera and state and state.appliedOffset then
		camera.CFrame = camera.CFrame * state.appliedOffset:Inverse()
	end

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
	earthquake = { duration = 0.56, positionStrength = 0.24, rotationStrength = 0.78, noiseFrequency = 17 },
	instantdig = { duration = 0.50, positionStrength = 0.22, rotationStrength = 0.68, noiseFrequency = 20 },
	luckyhour = { duration = 0.24, positionStrength = 0.05, rotationStrength = 0.12, noiseFrequency = 30 },
	echoesfrombelow = { duration = 0.46, positionStrength = 0.10, rotationStrength = 0.46, noiseFrequency = 12 },
	echoblocks = { duration = 0.46, positionStrength = 0.10, rotationStrength = 0.46, noiseFrequency = 12 },
	volcanovent = { duration = 0.48, positionStrength = 0.12, rotationStrength = 0.42, noiseFrequency = 20 },
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

function DeepDigEventStartFlash.shouldPlay(eventName, message, duration, effectId)
	if isEarthquakeEvent(eventName, message, effectId) then
		return false
	end

	if DeepDigActiveEventHud.seasonalEffects[effectId] == true then
		return false
	end

	return type(duration) ~= "number" or duration <= EVENT_SHAKE_MAX_RANDOM_DURATION
end

function DeepDigEventStartFlash.play(eventName, message, duration, effectId)
	if not DeepDigEventStartFlash.shouldPlay(eventName, message, duration, effectId) then
		return
	end

	DeepDigEventStartFlash.sequence = DeepDigEventStartFlash.sequence + 1
	local sequence = DeepDigEventStartFlash.sequence
	local style = DeepDigActiveEventHud.getStyle(effectId)
	local accent = style.accent or DeepDigActiveEventHud.styles.fallback.accent

	DeepDigEventStartFlash.cancelTweens()
	DeepDigEventStartFlash.overlay.Visible = true
	DeepDigEventStartFlash.overlay.BackgroundColor3 = accent
	DeepDigEventStartFlash.overlay.BackgroundTransparency = 0.76
	DeepDigEventStartFlash.glint.BackgroundTransparency = 0.52
	DeepDigEventStartFlash.glint.Position = UDim2.new(-0.28, 0, -0.1, 0)
	DeepDigEventStartFlash.gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, accent),
	})

	local tintFade = TweenService:Create(
		DeepDigEventStartFlash.overlay,
		TweenInfo.new(0.46, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	local glintSweep = TweenService:Create(
		DeepDigEventStartFlash.glint,
		TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			BackgroundTransparency = 1,
			Position = UDim2.new(1.1, 0, -0.1, 0),
		}
	)

	DeepDigEventStartFlash.tweens = { tintFade, glintSweep }
	tintFade:Play()
	glintSweep:Play()
	tintFade.Completed:Connect(function()
		if sequence ~= DeepDigEventStartFlash.sequence then
			return
		end
		DeepDigEventStartFlash.tweens = {}
		DeepDigEventStartFlash.reset()
	end)
end

local function getEventShakeProfile(eventName, effectId)
	return EVENT_SHAKE_PROFILES[normalizeEventKey(effectId)]
		or EVENT_SHAKE_PROFILES[normalizeEventKey(eventName)]
		or DEFAULT_EVENT_SHAKE_PROFILE
end

local function hasEventCameraShakeTarget()
	local camera = workspace.CurrentCamera
	local character = player.Character
	return camera ~= nil
		and character ~= nil
		and character.Parent ~= nil
		and character:FindFirstChildOfClass("Humanoid") ~= nil
end

local function playEventCameraShake(eventName, effectId)
	if not hasEventCameraShakeTarget() then
		return
	end

	clearEventCameraShake()
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
		appliedOffset = nil,
	}

	eventShakeBound = true
	RunService:BindToRenderStep(eventShakeBindingName, Enum.RenderPriority.Camera.Value + 1, function()
		local camera = workspace.CurrentCamera
		local state = eventShakeState

		if not camera or not state or not hasEventCameraShakeTarget() then
			clearEventCameraShake()
			return
		end

		if state.appliedOffset then
			camera.CFrame = camera.CFrame * state.appliedOffset:Inverse()
			state.appliedOffset = nil
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
		local offset = CFrame.new(positionOffset) * rotationOffset

		state.appliedOffset = offset
		camera.CFrame = camera.CFrame * offset
	end)
end

LEGENDARY_FIND_FLASH_RARITIES._cameraBump = {
	bindingName = "DeepDigLegendaryFindCameraBump",
	sequence = 0,
	bound = false,
	state = nil,
}

function LEGENDARY_FIND_FLASH_RARITIES._cameraBump.clear(sequence)
	local bump = LEGENDARY_FIND_FLASH_RARITIES._cameraBump
	if sequence and sequence ~= bump.sequence then
		return
	end

	local camera = workspace.CurrentCamera
	local state = bump.state
	if camera and state and state.appliedOffset then
		camera.CFrame = camera.CFrame * state.appliedOffset:Inverse()
	end

	bump.state = nil

	if bump.bound then
		RunService:UnbindFromRenderStep(bump.bindingName)
		bump.bound = false
	end
end

function LEGENDARY_FIND_FLASH_RARITIES._cameraBump.play(rarity)
	local bump = LEGENDARY_FIND_FLASH_RARITIES._cameraBump
	local isMythic = rarity == "Mythic"

	bump.clear()
	bump.sequence = bump.sequence + 1

	local sequence = bump.sequence
	bump.state = {
		sequence = sequence,
		startTime = os.clock(),
		duration = isMythic and 0.20 or 0.16,
		positionStrength = isMythic and 0.045 or 0.035,
		rotationStrength = isMythic and 0.11 or 0.08,
		appliedOffset = nil,
	}

	bump.bound = true
	RunService:BindToRenderStep(
		bump.bindingName,
		Enum.RenderPriority.Camera.Value + 2,
		function()
			local camera = workspace.CurrentCamera
			local state = bump.state

			if not camera or not state then
				bump.clear()
				return
			end

			if state.appliedOffset then
				camera.CFrame = camera.CFrame * state.appliedOffset:Inverse()
				state.appliedOffset = nil
			end

			local progress = (os.clock() - state.startTime) / state.duration
			if progress >= 1 then
				bump.clear(state.sequence)
				return
			end

			local punch = math.sin(math.clamp(progress, 0, 1) * math.pi) * (1 - math.clamp(progress, 0, 1) * 0.35)
			local positionOffset = Vector3.new(0, 0, -state.positionStrength * punch)
			local rotationOffset = CFrame.Angles(math.rad(-state.rotationStrength * punch), 0, 0)
			local offset = CFrame.new(positionOffset) * rotationOffset

			state.appliedOffset = offset
			camera.CFrame = camera.CFrame * offset
		end
	)
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
		if currentStreakReviveEligible and currentStreakRevivePending and currentStreakReviveProductAvailable then
			reviveSuffix = " • Revive ready"
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
	local reset = payload.reset == true
	local previousStreak = tonumber(payload.previousStreak) or 0
	local milestone = not reset and (payload.milestone == true or day == 7 or cycle > 1)

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

	if reset then
		streakRewardUi.panel.BackgroundColor3 = Color3.fromRGB(38, 25, 22)
		streakRewardUi.stroke.Color = Color3.fromRGB(255, 120, 80)
		streakRewardUi.title.Text = "🔥 Streak Reset"
		streakRewardUi.title.TextColor3 = Color3.fromRGB(255, 145, 95)
		streakRewardUi.amount.TextColor3 = Color3.fromRGB(255, 230, 150)
	elseif milestone then
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
	if reset then
		streakRewardUi.detail.Text = "Previous streak: " .. previousStreak .. " days • Day " .. day .. " reward claimed"
	else
		streakRewardUi.detail.Text = "Day " .. day .. " • Cycle " .. cycle .. " • Streak ×" .. streak
	end

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

do
local sellAllSummaryUi = {}
sellAllSummaryUi.panel = Instance.new("Frame")
sellAllSummaryUi.panel.Name = "SellAllSummaryBurst"
sellAllSummaryUi.panel.AnchorPoint = Vector2.new(0.5, 0.5)
sellAllSummaryUi.panel.Size = UDim2.fromOffset(360, 132)
sellAllSummaryUi.panel.Position = UDim2.fromScale(0.5, 0.48)
sellAllSummaryUi.panel.BackgroundColor3 = Color3.fromRGB(40, 32, 18)
sellAllSummaryUi.panel.BackgroundTransparency = 1
sellAllSummaryUi.panel.BorderSizePixel = 0
sellAllSummaryUi.panel.Visible = false
sellAllSummaryUi.panel.ZIndex = 78
sellAllSummaryUi.panel.Parent = screenGui

sellAllSummaryUi.corner = Instance.new("UICorner")
sellAllSummaryUi.corner.CornerRadius = UDim.new(0, 12)
sellAllSummaryUi.corner.Parent = sellAllSummaryUi.panel

sellAllSummaryUi.stroke = Instance.new("UIStroke")
sellAllSummaryUi.stroke.Color = Color3.fromRGB(255, 216, 92)
sellAllSummaryUi.stroke.Thickness = 2
sellAllSummaryUi.stroke.Transparency = 1
sellAllSummaryUi.stroke.Parent = sellAllSummaryUi.panel

local function constrainSellAllSummaryText(label, maxTextSize, minTextSize)
	label.TextScaled = true
	label.TextWrapped = true

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxTextSize
	constraint.MinTextSize = minTextSize or 10
	constraint.Parent = label
end

sellAllSummaryUi.title = Instance.new("TextLabel")
sellAllSummaryUi.title.Name = "Title"
sellAllSummaryUi.title.Size = UDim2.new(1, -28, 0, 28)
sellAllSummaryUi.title.Position = UDim2.fromOffset(14, 12)
sellAllSummaryUi.title.BackgroundTransparency = 1
sellAllSummaryUi.title.Text = "Backpack Sold"
sellAllSummaryUi.title.TextColor3 = Color3.fromRGB(255, 224, 110)
sellAllSummaryUi.title.TextTransparency = 1
sellAllSummaryUi.title.Font = Enum.Font.GothamBlack
sellAllSummaryUi.title.TextXAlignment = Enum.TextXAlignment.Center
sellAllSummaryUi.title.ZIndex = 79
constrainSellAllSummaryText(sellAllSummaryUi.title, 24, 13)
sellAllSummaryUi.title.Parent = sellAllSummaryUi.panel

sellAllSummaryUi.coins = Instance.new("TextLabel")
sellAllSummaryUi.coins.Name = "Coins"
sellAllSummaryUi.coins.Size = UDim2.new(1, -28, 0, 42)
sellAllSummaryUi.coins.Position = UDim2.fromOffset(14, 44)
sellAllSummaryUi.coins.BackgroundTransparency = 1
sellAllSummaryUi.coins.Text = "+0 coins"
sellAllSummaryUi.coins.TextColor3 = Color3.fromRGB(255, 238, 124)
sellAllSummaryUi.coins.TextTransparency = 1
sellAllSummaryUi.coins.Font = Enum.Font.GothamBlack
sellAllSummaryUi.coins.TextXAlignment = Enum.TextXAlignment.Center
sellAllSummaryUi.coins.ZIndex = 79
constrainSellAllSummaryText(sellAllSummaryUi.coins, 34, 15)
sellAllSummaryUi.coins.Parent = sellAllSummaryUi.panel

sellAllSummaryUi.detail = Instance.new("TextLabel")
sellAllSummaryUi.detail.Name = "Detail"
sellAllSummaryUi.detail.Size = UDim2.new(1, -32, 0, 28)
sellAllSummaryUi.detail.Position = UDim2.fromOffset(16, 90)
sellAllSummaryUi.detail.BackgroundTransparency = 1
sellAllSummaryUi.detail.Text = "0 items sold"
sellAllSummaryUi.detail.TextColor3 = Color3.fromRGB(232, 218, 180)
sellAllSummaryUi.detail.TextTransparency = 1
sellAllSummaryUi.detail.Font = Enum.Font.GothamBold
sellAllSummaryUi.detail.TextXAlignment = Enum.TextXAlignment.Center
sellAllSummaryUi.detail.ZIndex = 79
constrainSellAllSummaryText(sellAllSummaryUi.detail, 17, 10)
sellAllSummaryUi.detail.Parent = sellAllSummaryUi.panel
sellAllSummaryUi.particles = {}
sellAllSummaryUi.maxFlyoutParticles = 14

local sellAllSummarySequence = 0
local sellAllSummaryTweens = {}

local function clearSellAllSummaryParticles()
	for _, particle in ipairs(sellAllSummaryUi.particles) do
		if particle and particle.Parent then
			particle:Destroy()
		end
	end
	sellAllSummaryUi.particles = {}
end

local function clearSellAllSummaryTweens()
	for _, tween in ipairs(sellAllSummaryTweens) do
		tween:Cancel()
	end
	sellAllSummaryTweens = {}
	clearSellAllSummaryParticles()
end

local function tweenSellAllSummary(instance, duration, goal, easingStyle, easingDirection)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
		goal
	)
	table.insert(sellAllSummaryTweens, tween)
	tween:Play()
	return tween
end

local function playSellAllCoinFlyout(coinsEarned, sequence)
	clearSellAllSummaryParticles()

	if coinsEarned <= 0 then
		return
	end

	local panelPosition = sellAllSummaryUi.panel.AbsolutePosition
	local panelSize = sellAllSummaryUi.panel.AbsoluteSize
	local coinPosition = coinsLabel.AbsolutePosition
	local coinSize = coinsLabel.AbsoluteSize
	local startCenter = panelPosition + Vector2.new(panelSize.X * 0.5, panelSize.Y * 0.56)
	local endCenter = coinPosition + Vector2.new(math.min(34, coinSize.X * 0.22), coinSize.Y * 0.5)
	local particleCount = 8

	if coinsEarned >= 250 then
		particleCount = particleCount + 2
	end
	if coinsEarned >= 1000 then
		particleCount = particleCount + 2
	end
	if coinsEarned >= 5000 then
		particleCount = particleCount + 2
	end
	particleCount = math.min(sellAllSummaryUi.maxFlyoutParticles, particleCount)

	for index = 1, particleCount do
		local particle = Instance.new("Frame")
		local size = math.random(6, 11)
		local startOffset = Vector2.new(math.random(-96, 96), math.random(-18, 54))
		local endOffset = Vector2.new(math.random(-8, 18), math.random(-9, 9))
		local target = endCenter + endOffset
		local delayTime = (index - 1) * 0.025

		particle.Name = "SellAllCoinFlyout"
		particle.AnchorPoint = Vector2.new(0.5, 0.5)
		particle.Size = UDim2.fromOffset(size, size)
		particle.Position = UDim2.fromOffset(startCenter.X + startOffset.X, startCenter.Y + startOffset.Y)
		particle.BackgroundColor3 = index % 4 == 0 and Color3.fromRGB(255, 247, 170) or Color3.fromRGB(255, 205, 54)
		particle.BackgroundTransparency = 0.06
		particle.BorderSizePixel = 0
		particle.Active = false
		particle.Rotation = math.random(-18, 18)
		particle.ZIndex = 82
		particle.Parent = screenGui
		table.insert(sellAllSummaryUi.particles, particle)

		(function(corner)
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = particle
		end)(Instance.new("UICorner"))

		task.delay(delayTime, function()
			if sequence ~= sellAllSummarySequence or not particle.Parent then
				return
			end

			local tween = tweenSellAllSummary(particle, 0.52 + math.random() * 0.16, {
				Position = UDim2.fromOffset(target.X, target.Y),
				Size = UDim2.fromOffset(math.max(3, size - 3), math.max(3, size - 3)),
				BackgroundTransparency = 1,
				Rotation = particle.Rotation + math.random(70, 145),
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

			tween.Completed:Connect(function()
				if sequence ~= sellAllSummarySequence then
					return
				end
				if particle.Parent then
					particle:Destroy()
				end
			end)
		end)
	end
end

function showSellAllSummaryBurst(payload)
	if type(payload) ~= "table" then
		return
	end

	local itemsSold = math.floor(tonumber(payload.itemsSold) or 0)
	local coinsEarned = math.floor(tonumber(payload.coinsEarned) or 0)
	if itemsSold <= 0 then
		return
	end

	local wasBackpackFull = payload.wasBackpackFull == true
	local itemLabel = itemsSold == 1 and "item" or "items"

	sellAllSummarySequence = sellAllSummarySequence + 1
	local sequence = sellAllSummarySequence
	clearSellAllSummaryTweens()

	sellAllSummaryUi.title.Text = wasBackpackFull and "Full Backpack Cashout!" or "Backpack Sold"
	sellAllSummaryUi.coins.Text = "+" .. tostring(coinsEarned) .. " coins"
	sellAllSummaryUi.detail.Text = tostring(itemsSold) .. " " .. itemLabel .. " sold"
	sellAllSummaryUi.panel.BackgroundColor3 = wasBackpackFull and Color3.fromRGB(48, 36, 14) or Color3.fromRGB(36, 32, 22)
	sellAllSummaryUi.stroke.Color = wasBackpackFull and Color3.fromRGB(255, 226, 82) or Color3.fromRGB(255, 196, 86)
	sellAllSummaryUi.stroke.Thickness = wasBackpackFull and 3 or 2

	sellAllSummaryUi.panel.Visible = true
	sellAllSummaryUi.panel.Size = UDim2.fromOffset(338, 124)
	sellAllSummaryUi.panel.Position = UDim2.fromScale(0.5, 0.48)
	sellAllSummaryUi.panel.BackgroundTransparency = 1
	sellAllSummaryUi.stroke.Transparency = 1
	sellAllSummaryUi.title.TextTransparency = 1
	sellAllSummaryUi.coins.TextTransparency = 1
	sellAllSummaryUi.detail.TextTransparency = 1

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("sell_all_bonus")
	end

	tweenSellAllSummary(sellAllSummaryUi.panel, 0.18, {
		Size = wasBackpackFull and UDim2.fromOffset(390, 144) or UDim2.fromOffset(368, 132),
		Position = UDim2.fromScale(0.5, 0.42),
		BackgroundTransparency = 0.05,
	}, Enum.EasingStyle.Back)
	tweenSellAllSummary(sellAllSummaryUi.stroke, 0.18, { Transparency = 0 })
	tweenSellAllSummary(sellAllSummaryUi.title, 0.14, { TextTransparency = 0 })
	tweenSellAllSummary(sellAllSummaryUi.coins, 0.18, { TextTransparency = 0 })
	tweenSellAllSummary(sellAllSummaryUi.detail, 0.22, { TextTransparency = 0 })
	task.delay(0.1, function()
		if sequence ~= sellAllSummarySequence then
			return
		end
		playSellAllCoinFlyout(coinsEarned, sequence)
	end)

	task.delay(wasBackpackFull and 2.8 or 2.3, function()
		if sequence ~= sellAllSummarySequence then
			return
		end

		tweenSellAllSummary(sellAllSummaryUi.panel, 0.24, {
			Position = UDim2.fromScale(0.5, 0.37),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenSellAllSummary(sellAllSummaryUi.stroke, 0.22, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenSellAllSummary(sellAllSummaryUi.title, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenSellAllSummary(sellAllSummaryUi.coins, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local detailFade = tweenSellAllSummary(sellAllSummaryUi.detail, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		detailFade.Completed:Connect(function()
			if sequence ~= sellAllSummarySequence then
				return
			end
			sellAllSummaryUi.panel.Visible = false
		end)
	end)
end
end

DeepDigShowBackpackFullBurst = (function()
local backpackFullUi = {}
backpackFullUi.panel = Instance.new("Frame")
backpackFullUi.panel.Name = "BackpackFullBurst"
backpackFullUi.panel.AnchorPoint = Vector2.new(0.5, 0.5)
backpackFullUi.panel.Size = UDim2.fromOffset(334, 112)
backpackFullUi.panel.Position = UDim2.fromScale(0.5, 0.50)
backpackFullUi.panel.BackgroundColor3 = Color3.fromRGB(42, 24, 20)
backpackFullUi.panel.BackgroundTransparency = 1
backpackFullUi.panel.BorderSizePixel = 0
backpackFullUi.panel.Visible = false
backpackFullUi.panel.ZIndex = 82
backpackFullUi.panel.Parent = screenGui

backpackFullUi.corner = Instance.new("UICorner")
backpackFullUi.corner.CornerRadius = UDim.new(0, 11)
backpackFullUi.corner.Parent = backpackFullUi.panel

backpackFullUi.stroke = Instance.new("UIStroke")
backpackFullUi.stroke.Color = Color3.fromRGB(255, 112, 82)
backpackFullUi.stroke.Thickness = 2
backpackFullUi.stroke.Transparency = 1
backpackFullUi.stroke.Parent = backpackFullUi.panel

local function constrainBackpackFullText(label, maxTextSize, minTextSize)
	label.TextScaled = true
	label.TextWrapped = true

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxTextSize
	constraint.MinTextSize = minTextSize or 10
	constraint.Parent = label
end

backpackFullUi.title = Instance.new("TextLabel")
backpackFullUi.title.Name = "Title"
backpackFullUi.title.Size = UDim2.new(1, -28, 0, 26)
backpackFullUi.title.Position = UDim2.fromOffset(14, 10)
backpackFullUi.title.BackgroundTransparency = 1
backpackFullUi.title.Text = "BACKPACK FULL"
backpackFullUi.title.TextColor3 = Color3.fromRGB(255, 142, 104)
backpackFullUi.title.TextTransparency = 1
backpackFullUi.title.Font = Enum.Font.GothamBlack
backpackFullUi.title.TextXAlignment = Enum.TextXAlignment.Center
backpackFullUi.title.ZIndex = 83
constrainBackpackFullText(backpackFullUi.title, 22, 12)
backpackFullUi.title.Parent = backpackFullUi.panel

backpackFullUi.item = Instance.new("TextLabel")
backpackFullUi.item.Name = "Item"
backpackFullUi.item.Size = UDim2.new(1, -32, 0, 32)
backpackFullUi.item.Position = UDim2.fromOffset(16, 39)
backpackFullUi.item.BackgroundTransparency = 1
backpackFullUi.item.Text = "Found item blocked"
backpackFullUi.item.TextColor3 = Color3.fromRGB(255, 238, 220)
backpackFullUi.item.TextTransparency = 1
backpackFullUi.item.Font = Enum.Font.GothamBlack
backpackFullUi.item.TextXAlignment = Enum.TextXAlignment.Center
backpackFullUi.item.ZIndex = 83
constrainBackpackFullText(backpackFullUi.item, 20, 11)
backpackFullUi.item.Parent = backpackFullUi.panel

backpackFullUi.action = Instance.new("TextLabel")
backpackFullUi.action.Name = "Action"
backpackFullUi.action.Size = UDim2.new(1, -32, 0, 26)
backpackFullUi.action.Position = UDim2.fromOffset(16, 75)
backpackFullUi.action.BackgroundTransparency = 1
backpackFullUi.action.Text = "Use Sell All to make room"
backpackFullUi.action.TextColor3 = Color3.fromRGB(255, 214, 120)
backpackFullUi.action.TextTransparency = 1
backpackFullUi.action.Font = Enum.Font.GothamBold
backpackFullUi.action.TextXAlignment = Enum.TextXAlignment.Center
backpackFullUi.action.ZIndex = 83
constrainBackpackFullText(backpackFullUi.action, 16, 10)
backpackFullUi.action.Parent = backpackFullUi.panel

local backpackFullFx = {
	sequence = 0,
	tweens = {},
}

local function clearBackpackFullTweens()
	for _, tween in ipairs(backpackFullFx.tweens) do
		tween:Cancel()
	end
	backpackFullFx.tweens = {}
end

local function tweenBackpackFull(instance, duration, goal, easingStyle, easingDirection)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
		goal
	)
	table.insert(backpackFullFx.tweens, tween)
	tween:Play()
	return tween
end

function DeepDigClearBackpackFullBurst()
	backpackFullFx.sequence = backpackFullFx.sequence + 1
	clearBackpackFullTweens()
	backpackFullUi.panel.Visible = false
	backpackFullUi.panel.BackgroundTransparency = 1
	backpackFullUi.stroke.Transparency = 1
	backpackFullUi.title.TextTransparency = 1
	backpackFullUi.item.TextTransparency = 1
	backpackFullUi.action.TextTransparency = 1
end

return function(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.inventoryCapacity == "unlimited" then
		DeepDigClearBackpackFullBurst()
		return
	end

	local itemName = tostring(payload.name or "item")
	local rarity = tostring(payload.rarity or "Common")
	local capacity = tonumber(payload.inventoryCapacity)
	local count = math.floor(tonumber(payload.inventoryCount) or capacity or 0)
	local capacityText = capacity and (tostring(count) .. "/" .. tostring(capacity)) or "full"

	backpackFullFx.sequence = backpackFullFx.sequence + 1
	local sequence = backpackFullFx.sequence
	clearBackpackFullTweens()

	backpackFullUi.item.Text = rarity .. " " .. itemName .. " could not fit"
	backpackFullUi.action.Text = "Backpack " .. capacityText .. " - use Sell All"
	backpackFullUi.panel.Visible = true
	backpackFullUi.panel.Size = UDim2.fromOffset(306, 102)
	backpackFullUi.panel.Position = UDim2.fromScale(0.5, 0.52)
	backpackFullUi.panel.BackgroundTransparency = 1
	backpackFullUi.stroke.Transparency = 1
	backpackFullUi.stroke.Thickness = 2
	backpackFullUi.title.TextTransparency = 1
	backpackFullUi.item.TextTransparency = 1
	backpackFullUi.action.TextTransparency = 1

	pulseSellAllButton()
	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("enemy_blocked")
	end

	tweenBackpackFull(backpackFullUi.panel, 0.16, {
		Size = UDim2.fromOffset(352, 118),
		Position = UDim2.fromScale(0.5, 0.44),
		BackgroundTransparency = 0.04,
	}, Enum.EasingStyle.Back)
	tweenBackpackFull(backpackFullUi.stroke, 0.16, {
		Transparency = 0,
		Thickness = 3,
	})
	tweenBackpackFull(backpackFullUi.title, 0.12, { TextTransparency = 0 })
	tweenBackpackFull(backpackFullUi.item, 0.16, { TextTransparency = 0 })
	tweenBackpackFull(backpackFullUi.action, 0.2, { TextTransparency = 0 })

	task.delay(2.2, function()
		if sequence ~= backpackFullFx.sequence then
			return
		end

		tweenBackpackFull(backpackFullUi.panel, 0.22, {
			Position = UDim2.fromScale(0.5, 0.39),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenBackpackFull(backpackFullUi.stroke, 0.2, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenBackpackFull(backpackFullUi.title, 0.16, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenBackpackFull(backpackFullUi.item, 0.16, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local actionFade = tweenBackpackFull(backpackFullUi.action, 0.16, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		actionFade.Completed:Connect(function()
			if sequence ~= backpackFullFx.sequence then
				return
			end
			backpackFullUi.panel.Visible = false
		end)
	end)
end
end)()

DeepDigShowInfiniteBackpackUnlockBurst = (function()
local uncappedUi = {}
uncappedUi.panel = Instance.new("Frame")
uncappedUi.panel.Name = "InfiniteBackpackUnlockBurst"
uncappedUi.panel.AnchorPoint = Vector2.new(0.5, 0.5)
uncappedUi.panel.Size = UDim2.fromOffset(304, 86)
uncappedUi.panel.Position = UDim2.fromScale(0.5, 0.44)
uncappedUi.panel.BackgroundColor3 = Color3.fromRGB(30, 24, 44)
uncappedUi.panel.BackgroundTransparency = 1
uncappedUi.panel.BorderSizePixel = 0
uncappedUi.panel.Visible = false
uncappedUi.panel.ZIndex = 82
uncappedUi.panel.Parent = screenGui

uncappedUi.corner = Instance.new("UICorner")
uncappedUi.corner.CornerRadius = UDim.new(0, 10)
uncappedUi.corner.Parent = uncappedUi.panel

uncappedUi.stroke = Instance.new("UIStroke")
uncappedUi.stroke.Color = Color3.fromRGB(202, 145, 255)
uncappedUi.stroke.Thickness = 2
uncappedUi.stroke.Transparency = 1
uncappedUi.stroke.Parent = uncappedUi.panel

uncappedUi.title = Instance.new("TextLabel")
uncappedUi.title.Name = "Title"
uncappedUi.title.Size = UDim2.new(1, -28, 0, 28)
uncappedUi.title.Position = UDim2.fromOffset(14, 10)
uncappedUi.title.BackgroundTransparency = 1
uncappedUi.title.Text = "Backpack Uncapped"
uncappedUi.title.TextColor3 = Color3.fromRGB(235, 218, 255)
uncappedUi.title.TextTransparency = 1
uncappedUi.title.Font = Enum.Font.GothamBlack
uncappedUi.title.TextScaled = true
uncappedUi.title.TextWrapped = true
uncappedUi.title.TextXAlignment = Enum.TextXAlignment.Center
uncappedUi.title.ZIndex = 83
uncappedUi.title.Parent = uncappedUi.panel

local titleConstraint = Instance.new("UITextSizeConstraint")
titleConstraint.MaxTextSize = 23
titleConstraint.MinTextSize = 12
titleConstraint.Parent = uncappedUi.title

uncappedUi.detail = Instance.new("TextLabel")
uncappedUi.detail.Name = "Detail"
uncappedUi.detail.Size = UDim2.new(1, -32, 0, 24)
uncappedUi.detail.Position = UDim2.fromOffset(16, 48)
uncappedUi.detail.BackgroundTransparency = 1
uncappedUi.detail.Text = "Inventory: unlimited"
uncappedUi.detail.TextColor3 = Color3.fromRGB(150, 236, 210)
uncappedUi.detail.TextTransparency = 1
uncappedUi.detail.Font = Enum.Font.GothamBold
uncappedUi.detail.TextScaled = true
uncappedUi.detail.TextWrapped = true
uncappedUi.detail.TextXAlignment = Enum.TextXAlignment.Center
uncappedUi.detail.ZIndex = 83
uncappedUi.detail.Parent = uncappedUi.panel

local detailConstraint = Instance.new("UITextSizeConstraint")
detailConstraint.MaxTextSize = 16
detailConstraint.MinTextSize = 10
detailConstraint.Parent = uncappedUi.detail

local uncappedFx = {
	sequence = 0,
	tweens = {},
	playedMarkers = {},
}

local function clearUncappedTweens()
	for _, tween in ipairs(uncappedFx.tweens) do
		tween:Cancel()
	end
	uncappedFx.tweens = {}
end

local function tweenUncapped(instance, duration, goal, easingStyle, easingDirection)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
		goal
	)
	table.insert(uncappedFx.tweens, tween)
	tween:Play()
	return tween
end

return function(payload)
	if type(payload) ~= "table" then
		return
	end

	local marker = tostring(payload.marker or payload.reason or "sync")
	if uncappedFx.playedMarkers[marker] then
		return
	end
	uncappedFx.playedMarkers[marker] = true

	uncappedFx.sequence = uncappedFx.sequence + 1
	local sequence = uncappedFx.sequence
	clearUncappedTweens()
	DeepDigClearFullBackpackPressure()

	uncappedUi.panel.Visible = true
	uncappedUi.panel.Size = UDim2.fromOffset(286, 78)
	uncappedUi.panel.Position = UDim2.fromScale(0.5, 0.47)
	uncappedUi.panel.BackgroundTransparency = 1
	uncappedUi.stroke.Transparency = 1
	uncappedUi.stroke.Thickness = 2
	uncappedUi.title.TextTransparency = 1
	uncappedUi.detail.TextTransparency = 1

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("infinite_backpack_unlock")
	end

	tweenUncapped(uncappedUi.panel, 0.16, {
		Size = UDim2.fromOffset(320, 92),
		Position = UDim2.fromScale(0.5, 0.42),
		BackgroundTransparency = 0.06,
	}, Enum.EasingStyle.Back)
	tweenUncapped(uncappedUi.stroke, 0.16, {
		Transparency = 0,
		Thickness = 3,
	})
	tweenUncapped(uncappedUi.title, 0.12, { TextTransparency = 0 })
	tweenUncapped(uncappedUi.detail, 0.18, { TextTransparency = 0 })

	task.delay(1.65, function()
		if sequence ~= uncappedFx.sequence then
			return
		end

		tweenUncapped(uncappedUi.panel, 0.22, {
			Position = UDim2.fromScale(0.5, 0.38),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenUncapped(uncappedUi.stroke, 0.2, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenUncapped(uncappedUi.title, 0.16, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local detailFade = tweenUncapped(uncappedUi.detail, 0.16, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		detailFade.Completed:Connect(function()
			if sequence ~= uncappedFx.sequence then
				return
			end
			uncappedUi.panel.Visible = false
		end)
	end)
end
end)()

DeepDigShowMuseumTierCompleteBurst = (function()
local museumTierCompleteUi = {}
museumTierCompleteUi.panel = Instance.new("Frame")
museumTierCompleteUi.panel.Name = "MuseumTierCompleteBurst"
museumTierCompleteUi.panel.AnchorPoint = Vector2.new(0.5, 0.5)
museumTierCompleteUi.panel.Size = UDim2.fromOffset(390, 142)
museumTierCompleteUi.panel.Position = UDim2.fromScale(0.5, 0.44)
museumTierCompleteUi.panel.BackgroundColor3 = Color3.fromRGB(28, 31, 36)
museumTierCompleteUi.panel.BackgroundTransparency = 1
museumTierCompleteUi.panel.BorderSizePixel = 0
museumTierCompleteUi.panel.Visible = false
museumTierCompleteUi.panel.ZIndex = 82
museumTierCompleteUi.panel.Parent = screenGui

museumTierCompleteUi.corner = Instance.new("UICorner")
museumTierCompleteUi.corner.CornerRadius = UDim.new(0, 12)
museumTierCompleteUi.corner.Parent = museumTierCompleteUi.panel

museumTierCompleteUi.stroke = Instance.new("UIStroke")
museumTierCompleteUi.stroke.Color = Color3.fromRGB(255, 216, 92)
museumTierCompleteUi.stroke.Thickness = 2
museumTierCompleteUi.stroke.Transparency = 1
museumTierCompleteUi.stroke.Parent = museumTierCompleteUi.panel

local function constrainMuseumTierCompleteText(label, maxTextSize, minTextSize)
	label.TextScaled = true
	label.TextWrapped = true

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxTextSize
	constraint.MinTextSize = minTextSize or 10
	constraint.Parent = label
end

museumTierCompleteUi.title = Instance.new("TextLabel")
museumTierCompleteUi.title.Name = "Title"
museumTierCompleteUi.title.Size = UDim2.new(1, -30, 0, 30)
museumTierCompleteUi.title.Position = UDim2.fromOffset(15, 12)
museumTierCompleteUi.title.BackgroundTransparency = 1
museumTierCompleteUi.title.Text = "Museum Tier Complete"
museumTierCompleteUi.title.TextColor3 = Color3.fromRGB(255, 224, 110)
museumTierCompleteUi.title.TextTransparency = 1
museumTierCompleteUi.title.Font = Enum.Font.GothamBlack
museumTierCompleteUi.title.TextXAlignment = Enum.TextXAlignment.Center
museumTierCompleteUi.title.ZIndex = 83
constrainMuseumTierCompleteText(museumTierCompleteUi.title, 25, 13)
museumTierCompleteUi.title.Parent = museumTierCompleteUi.panel

museumTierCompleteUi.tier = Instance.new("TextLabel")
museumTierCompleteUi.tier.Name = "Tier"
museumTierCompleteUi.tier.Size = UDim2.new(1, -30, 0, 36)
museumTierCompleteUi.tier.Position = UDim2.fromOffset(15, 46)
museumTierCompleteUi.tier.BackgroundTransparency = 1
museumTierCompleteUi.tier.Text = "Modern Collection"
museumTierCompleteUi.tier.TextColor3 = Color3.fromRGB(236, 242, 255)
museumTierCompleteUi.tier.TextTransparency = 1
museumTierCompleteUi.tier.Font = Enum.Font.GothamBlack
museumTierCompleteUi.tier.TextXAlignment = Enum.TextXAlignment.Center
museumTierCompleteUi.tier.ZIndex = 83
constrainMuseumTierCompleteText(museumTierCompleteUi.tier, 30, 15)
museumTierCompleteUi.tier.Parent = museumTierCompleteUi.panel

museumTierCompleteUi.bonus = Instance.new("TextLabel")
museumTierCompleteUi.bonus.Name = "Bonus"
museumTierCompleteUi.bonus.Size = UDim2.new(1, -30, 0, 30)
museumTierCompleteUi.bonus.Position = UDim2.fromOffset(15, 88)
museumTierCompleteUi.bonus.BackgroundTransparency = 1
museumTierCompleteUi.bonus.Text = "+10% loot value"
museumTierCompleteUi.bonus.TextColor3 = Color3.fromRGB(255, 236, 132)
museumTierCompleteUi.bonus.TextTransparency = 1
museumTierCompleteUi.bonus.Font = Enum.Font.GothamBold
museumTierCompleteUi.bonus.TextXAlignment = Enum.TextXAlignment.Center
museumTierCompleteUi.bonus.ZIndex = 83
constrainMuseumTierCompleteText(museumTierCompleteUi.bonus, 20, 11)
museumTierCompleteUi.bonus.Parent = museumTierCompleteUi.panel

local museumTierCompleteFx = {
	sequence = 0,
	tweens = {},
}

local function clearMuseumTierCompleteTweens()
	for _, tween in ipairs(museumTierCompleteFx.tweens) do
		tween:Cancel()
	end
	museumTierCompleteFx.tweens = {}
end

local function tweenMuseumTierComplete(instance, duration, goal, easingStyle, easingDirection)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
		goal
	)
	table.insert(museumTierCompleteFx.tweens, tween)
	tween:Play()
	return tween
end

local function formatMuseumBonusPercent(bonus)
	local percent = math.floor(((tonumber(bonus) or 1) - 1) * 100 + 0.5)
	return math.max(0, percent)
end

return function(payload)
	if type(payload) ~= "table" or payload.complete ~= true then
		return
	end

	local tierName = tostring(payload.tierName or "")
	local bonusPercent = formatMuseumBonusPercent(payload.bonus)
	if tierName == "" or bonusPercent <= 0 then
		return
	end

	museumTierCompleteFx.sequence = museumTierCompleteFx.sequence + 1
	local sequence = museumTierCompleteFx.sequence
	clearMuseumTierCompleteTweens()

	museumTierCompleteUi.title.Text = "Museum Tier Complete"
	museumTierCompleteUi.tier.Text = tierName .. " Collection"
	museumTierCompleteUi.bonus.Text = "+" .. tostring(bonusPercent) .. "% loot value unlocked"

	museumTierCompleteUi.panel.Visible = true
	museumTierCompleteUi.panel.Size = UDim2.fromOffset(348, 126)
	museumTierCompleteUi.panel.Position = UDim2.fromScale(0.5, 0.48)
	museumTierCompleteUi.panel.BackgroundTransparency = 1
	museumTierCompleteUi.stroke.Transparency = 1
	museumTierCompleteUi.stroke.Thickness = 2
	museumTierCompleteUi.title.TextTransparency = 1
	museumTierCompleteUi.tier.TextTransparency = 1
	museumTierCompleteUi.bonus.TextTransparency = 1

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("rare_reveal")
	end

	tweenMuseumTierComplete(museumTierCompleteUi.panel, 0.2, {
		Size = UDim2.fromOffset(408, 148),
		Position = UDim2.fromScale(0.5, 0.42),
		BackgroundTransparency = 0.06,
	}, Enum.EasingStyle.Back)
	tweenMuseumTierComplete(museumTierCompleteUi.stroke, 0.16, { Transparency = 0, Thickness = 3 })
	tweenMuseumTierComplete(museumTierCompleteUi.title, 0.16, { TextTransparency = 0 })
	tweenMuseumTierComplete(museumTierCompleteUi.tier, 0.2, { TextTransparency = 0 })
	tweenMuseumTierComplete(museumTierCompleteUi.bonus, 0.24, { TextTransparency = 0 })

	task.delay(2.65, function()
		if sequence ~= museumTierCompleteFx.sequence then
			return
		end

		tweenMuseumTierComplete(museumTierCompleteUi.panel, 0.24, {
			Position = UDim2.fromScale(0.5, 0.36),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenMuseumTierComplete(museumTierCompleteUi.stroke, 0.22, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenMuseumTierComplete(museumTierCompleteUi.title, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenMuseumTierComplete(museumTierCompleteUi.tier, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local bonusFade = tweenMuseumTierComplete(museumTierCompleteUi.bonus, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		bonusFade.Completed:Connect(function()
			if sequence ~= museumTierCompleteFx.sequence then
				return
			end
			museumTierCompleteUi.panel.Visible = false
		end)
	end)
end
end)()

do
local enemyDangerUnlockedUi = {}
enemyDangerUnlockedUi.panel = Instance.new("Frame")
enemyDangerUnlockedUi.panel.Name = "EnemyDangerUnlockedBurst"
enemyDangerUnlockedUi.panel.AnchorPoint = Vector2.new(0.5, 0.5)
enemyDangerUnlockedUi.panel.Size = UDim2.fromOffset(410, 178)
enemyDangerUnlockedUi.panel.Position = UDim2.fromScale(0.5, 0.48)
enemyDangerUnlockedUi.panel.BackgroundColor3 = Color3.fromRGB(38, 20, 18)
enemyDangerUnlockedUi.panel.BackgroundTransparency = 1
enemyDangerUnlockedUi.panel.BorderSizePixel = 0
enemyDangerUnlockedUi.panel.Visible = false
enemyDangerUnlockedUi.panel.ZIndex = 84
enemyDangerUnlockedUi.panel.Parent = screenGui

enemyDangerUnlockedUi.corner = Instance.new("UICorner")
enemyDangerUnlockedUi.corner.CornerRadius = UDim.new(0, 12)
enemyDangerUnlockedUi.corner.Parent = enemyDangerUnlockedUi.panel

enemyDangerUnlockedUi.stroke = Instance.new("UIStroke")
enemyDangerUnlockedUi.stroke.Color = Color3.fromRGB(255, 92, 76)
enemyDangerUnlockedUi.stroke.Thickness = 3
enemyDangerUnlockedUi.stroke.Transparency = 1
enemyDangerUnlockedUi.stroke.Parent = enemyDangerUnlockedUi.panel

local function constrainEnemyDangerText(label, maxTextSize, minTextSize)
	label.TextScaled = true
	label.TextWrapped = true

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxTextSize
	constraint.MinTextSize = minTextSize or 10
	constraint.Parent = label
end

enemyDangerUnlockedUi.title = Instance.new("TextLabel")
enemyDangerUnlockedUi.title.Name = "Title"
enemyDangerUnlockedUi.title.Size = UDim2.new(1, -28, 0, 30)
enemyDangerUnlockedUi.title.Position = UDim2.fromOffset(14, 12)
enemyDangerUnlockedUi.title.BackgroundTransparency = 1
enemyDangerUnlockedUi.title.Text = "COMBAT UNLOCKED"
enemyDangerUnlockedUi.title.TextColor3 = Color3.fromRGB(255, 120, 96)
enemyDangerUnlockedUi.title.TextTransparency = 1
enemyDangerUnlockedUi.title.Font = Enum.Font.GothamBlack
enemyDangerUnlockedUi.title.TextXAlignment = Enum.TextXAlignment.Center
enemyDangerUnlockedUi.title.ZIndex = 85
constrainEnemyDangerText(enemyDangerUnlockedUi.title, 25, 13)
enemyDangerUnlockedUi.title.Parent = enemyDangerUnlockedUi.panel

enemyDangerUnlockedUi.warning = Instance.new("TextLabel")
enemyDangerUnlockedUi.warning.Name = "Warning"
enemyDangerUnlockedUi.warning.Size = UDim2.new(1, -34, 0, 72)
enemyDangerUnlockedUi.warning.Position = UDim2.fromOffset(17, 46)
enemyDangerUnlockedUi.warning.BackgroundTransparency = 1
enemyDangerUnlockedUi.warning.Text = "Enemies can emerge now.\nClick or tap them with your equipped tool."
enemyDangerUnlockedUi.warning.TextColor3 = Color3.fromRGB(255, 238, 220)
enemyDangerUnlockedUi.warning.TextTransparency = 1
enemyDangerUnlockedUi.warning.Font = Enum.Font.GothamBlack
enemyDangerUnlockedUi.warning.TextXAlignment = Enum.TextXAlignment.Center
enemyDangerUnlockedUi.warning.TextYAlignment = Enum.TextYAlignment.Center
enemyDangerUnlockedUi.warning.ZIndex = 85
constrainEnemyDangerText(enemyDangerUnlockedUi.warning, 20, 11)
enemyDangerUnlockedUi.warning.Parent = enemyDangerUnlockedUi.panel

enemyDangerUnlockedUi.detail = Instance.new("TextLabel")
enemyDangerUnlockedUi.detail.Name = "Detail"
enemyDangerUnlockedUi.detail.Size = UDim2.new(1, -34, 0, 44)
enemyDangerUnlockedUi.detail.Position = UDim2.fromOffset(17, 124)
enemyDangerUnlockedUi.detail.BackgroundTransparency = 1
enemyDangerUnlockedUi.detail.Text = "Depth 11 - Stone layer"
enemyDangerUnlockedUi.detail.TextColor3 = Color3.fromRGB(245, 170, 130)
enemyDangerUnlockedUi.detail.TextTransparency = 1
enemyDangerUnlockedUi.detail.Font = Enum.Font.GothamBold
enemyDangerUnlockedUi.detail.TextXAlignment = Enum.TextXAlignment.Center
enemyDangerUnlockedUi.detail.TextYAlignment = Enum.TextYAlignment.Center
enemyDangerUnlockedUi.detail.ZIndex = 85
constrainEnemyDangerText(enemyDangerUnlockedUi.detail, 15, 9)
enemyDangerUnlockedUi.detail.Parent = enemyDangerUnlockedUi.panel

local enemyDangerUnlockedSequence = 0
local enemyDangerUnlockedTweens = {}

local function clearEnemyDangerUnlockedTweens()
	for _, tween in ipairs(enemyDangerUnlockedTweens) do
		tween:Cancel()
	end
	enemyDangerUnlockedTweens = {}
end

local function tweenEnemyDangerUnlocked(instance, duration, goal, easingStyle, easingDirection)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
		goal
	)
	table.insert(enemyDangerUnlockedTweens, tween)
	tween:Play()
	return tween
end

function showEnemyDangerUnlockedBurst(payload)
	if type(payload) ~= "table" then
		return
	end

	local depth = math.floor(tonumber(payload.depth) or 11)
	local tierName = tostring(payload.tierName or "Stone")

	enemyDangerUnlockedSequence = enemyDangerUnlockedSequence + 1
	local sequence = enemyDangerUnlockedSequence
	clearEnemyDangerUnlockedTweens()

	enemyDangerUnlockedUi.detail.Text = "Depth " .. tostring(depth) .. " " .. tierName .. ": enemies drop coins + fragments\nDeath: surface respawn, inventory kept"
	enemyDangerUnlockedUi.panel.Visible = true
	enemyDangerUnlockedUi.panel.Size = UDim2.fromOffset(366, 156)
	enemyDangerUnlockedUi.panel.Position = UDim2.fromScale(0.5, 0.50)
	enemyDangerUnlockedUi.panel.BackgroundTransparency = 1
	enemyDangerUnlockedUi.stroke.Transparency = 1
	enemyDangerUnlockedUi.stroke.Thickness = 2
	enemyDangerUnlockedUi.title.TextTransparency = 1
	enemyDangerUnlockedUi.warning.TextTransparency = 1
	enemyDangerUnlockedUi.detail.TextTransparency = 1

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("enemy_aggro")
	end

	tweenEnemyDangerUnlocked(enemyDangerUnlockedUi.panel, 0.18, {
		Size = UDim2.fromOffset(428, 190),
		Position = UDim2.fromScale(0.5, 0.43),
		BackgroundTransparency = 0.04,
	}, Enum.EasingStyle.Back)
	tweenEnemyDangerUnlocked(enemyDangerUnlockedUi.stroke, 0.18, {
		Transparency = 0,
		Thickness = 4,
	})
	tweenEnemyDangerUnlocked(enemyDangerUnlockedUi.title, 0.14, { TextTransparency = 0 })
	tweenEnemyDangerUnlocked(enemyDangerUnlockedUi.warning, 0.18, { TextTransparency = 0 })
	tweenEnemyDangerUnlocked(enemyDangerUnlockedUi.detail, 0.22, { TextTransparency = 0 })

	task.delay(0.35, function()
		if sequence ~= enemyDangerUnlockedSequence then
			return
		end

		tweenEnemyDangerUnlocked(enemyDangerUnlockedUi.stroke, 0.22, {
			Thickness = 2.5,
			Color = Color3.fromRGB(255, 170, 90),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		tweenEnemyDangerUnlocked(enemyDangerUnlockedUi.panel, 0.2, {
			Size = UDim2.fromOffset(410, 178),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end)

	task.delay(3.0, function()
		if sequence ~= enemyDangerUnlockedSequence then
			return
		end

		tweenEnemyDangerUnlocked(enemyDangerUnlockedUi.panel, 0.24, {
			Position = UDim2.fromScale(0.5, 0.37),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenEnemyDangerUnlocked(enemyDangerUnlockedUi.stroke, 0.22, {
			Transparency = 1,
			Color = Color3.fromRGB(255, 92, 76),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenEnemyDangerUnlocked(enemyDangerUnlockedUi.title, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenEnemyDangerUnlocked(enemyDangerUnlockedUi.warning, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local detailFade = tweenEnemyDangerUnlocked(enemyDangerUnlockedUi.detail, 0.18, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		detailFade.Completed:Connect(function()
			if sequence ~= enemyDangerUnlockedSequence then
				return
			end
			enemyDangerUnlockedUi.panel.Visible = false
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
DeepDigAutoCollectedUi.particles = {}
DeepDigAutoCollectedUi.maxCoinParticles = 7

function DeepDigClearAutoCollectedTweens()
	for _, tween in ipairs(DeepDigAutoCollectedTweens) do
		tween:Cancel()
	end
	DeepDigAutoCollectedTweens = {}

	for _, particle in ipairs(DeepDigAutoCollectedUi.particles) do
		if particle and particle.Parent then
			particle:Destroy()
		end
	end
	DeepDigAutoCollectedUi.particles = {}
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

function DeepDigPlayAutoCollectedCoinFlyout(earned, sequence)
	if earned <= 0 then
		return
	end

	for _, particle in ipairs(DeepDigAutoCollectedUi.particles) do
		if particle and particle.Parent then
			particle:Destroy()
		end
	end
	DeepDigAutoCollectedUi.particles = {}

	local panelPosition = DeepDigAutoCollectedUi.panel.AbsolutePosition
	local panelSize = DeepDigAutoCollectedUi.panel.AbsoluteSize
	local coinPosition = coinsLabel.AbsolutePosition
	local coinSize = coinsLabel.AbsoluteSize
	local startCenter = panelPosition + Vector2.new(panelSize.X * 0.5, panelSize.Y * 0.7)
	local endCenter = coinPosition + Vector2.new(math.min(34, coinSize.X * 0.22), coinSize.Y * 0.5)
	local particleCount = 4

	if earned >= 250 then
		particleCount = particleCount + 1
	end
	if earned >= 1000 then
		particleCount = particleCount + 1
	end
	if earned >= 5000 then
		particleCount = particleCount + 1
	end
	particleCount = math.min(DeepDigAutoCollectedUi.maxCoinParticles, particleCount)

	for index = 1, particleCount do
		local particle = Instance.new("Frame")
		local size = math.random(5, 9)
		local startOffset = Vector2.new(math.random(-56, 56), math.random(-4, 36))
		local endOffset = Vector2.new(math.random(-6, 14), math.random(-7, 7))
		local target = endCenter + endOffset
		local delayTime = (index - 1) * 0.028

		particle.Name = "AutoCollectorCoinFlyout"
		particle.AnchorPoint = Vector2.new(0.5, 0.5)
		particle.Size = UDim2.fromOffset(size, size)
		particle.Position = UDim2.fromOffset(startCenter.X + startOffset.X, startCenter.Y + startOffset.Y)
		particle.BackgroundColor3 = index % 3 == 0 and Color3.fromRGB(255, 244, 152) or Color3.fromRGB(255, 207, 58)
		particle.BackgroundTransparency = 0.08
		particle.BorderSizePixel = 0
		particle.Active = false
		particle.Rotation = math.random(-16, 16)
		particle.ZIndex = 84
		particle.Parent = screenGui
		table.insert(DeepDigAutoCollectedUi.particles, particle)

		(function(corner)
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = particle
		end)(Instance.new("UICorner"))

		task.delay(delayTime, function()
			if sequence ~= DeepDigAutoCollectedSequence or not particle.Parent then
				return
			end

			local tween = DeepDigTweenAutoCollected(particle, 0.42 + math.random() * 0.12, {
				Position = UDim2.fromOffset(target.X, target.Y),
				Size = UDim2.fromOffset(math.max(3, size - 2), math.max(3, size - 2)),
				BackgroundTransparency = 1,
				Rotation = particle.Rotation + math.random(58, 116),
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

			tween.Completed:Connect(function()
				if sequence ~= DeepDigAutoCollectedSequence then
					return
				end
				if particle.Parent then
					particle:Destroy()
				end
			end)
		end)
	end
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

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("auto_collector_cashout")
	end

	DeepDigTweenAutoCollected(DeepDigAutoCollectedUi.panel, 0.14, {
		Size = UDim2.fromOffset(318, 98),
		Position = UDim2.fromScale(0.5, 0.34),
		BackgroundTransparency = 0.08,
	}, Enum.EasingStyle.Back)
	DeepDigTweenAutoCollected(DeepDigAutoCollectedUi.stroke, 0.18, {
		Color = Color3.fromRGB(255, 220, 88),
	})
	task.delay(0.08, function()
		if sequence ~= DeepDigAutoCollectedSequence then
			return
		end
		DeepDigPlayAutoCollectedCoinFlyout(earned, sequence)
	end)

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
		sparkles = {},
		coinParticles = {},
		maxSparkles = 14,
		maxCoinParticles = 12,
		foremanUpsellActive = false,
		foremanUpsellAvailable = false,
		foremanPassId = Config.GAMEPASS_FOREMAN_ID,
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

	local function clearOfflineIncomeSparkles()
		for _, sparkle in ipairs(offlineIncomeState.sparkles) do
			if sparkle and sparkle.Parent then
				sparkle:Destroy()
			end
		end
		offlineIncomeState.sparkles = {}
		for _, particle in ipairs(offlineIncomeState.coinParticles) do
			if particle and particle.Parent then
				particle:Destroy()
			end
		end
		offlineIncomeState.coinParticles = {}
	end

	local function playOfflineIncomeSparkleBurst(reward, sequence)
		clearOfflineIncomeSparkles()

		local sparkleCount = 6
		if reward >= 1000 then
			sparkleCount = sparkleCount + 2
		end
		if reward >= 5000 then
			sparkleCount = sparkleCount + 2
		end
		if reward >= 20000 then
			sparkleCount = sparkleCount + 2
		end
		if reward >= 100000 then
			sparkleCount = sparkleCount + 2
		end
		sparkleCount = math.min(offlineIncomeState.maxSparkles, sparkleCount)

		for index = 1, sparkleCount do
			local sparkle = Instance.new("TextLabel")
			local isCoin = index % 3 ~= 0
			local startX = math.random(-175, 175)
			local startY = math.random(-96, 64)
			local driftX = math.random(-56, 56)
			local driftY = -math.random(54, 106)
			local textSize = isCoin and math.random(18, 24) or math.random(20, 28)

			sparkle.Name = "OfflineIncomeSparkle"
			sparkle.AnchorPoint = Vector2.new(0.5, 0.5)
			sparkle.Size = UDim2.fromOffset(34, 34)
			sparkle.Position = UDim2.new(0.5, startX, 0.5, startY)
			sparkle.BackgroundTransparency = 1
			sparkle.Text = isCoin and "🪙" or "✦"
			sparkle.TextColor3 = isCoin and Color3.fromRGB(255, 214, 70) or Color3.fromRGB(255, 245, 170)
			sparkle.TextSize = textSize
			sparkle.TextTransparency = 0
			sparkle.TextStrokeColor3 = Color3.fromRGB(88, 46, 0)
			sparkle.TextStrokeTransparency = 0.35
			sparkle.Font = Enum.Font.GothamBlack
			sparkle.Rotation = math.random(-16, 16)
			sparkle.ZIndex = 82
			sparkle.Parent = screenGui
			table.insert(offlineIncomeState.sparkles, sparkle)

			tweenOfflineIncome(sparkle, 0.64 + math.random() * 0.22, {
				Position = UDim2.new(0.5, startX + driftX, 0.5, startY + driftY),
				TextTransparency = 1,
				TextStrokeTransparency = 1,
				Rotation = sparkle.Rotation + math.random(-38, 38),
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out).Completed:Connect(function()
				if sequence ~= offlineIncomeState.sequence then
					return
				end
				if sparkle.Parent then
					sparkle:Destroy()
				end
			end)
		end

		local rewardPosition = offlineIncomeReward.AbsolutePosition
		local rewardSize = offlineIncomeReward.AbsoluteSize
		local coinPosition = coinsLabel.AbsolutePosition
		local coinSize = coinsLabel.AbsoluteSize
		local startCenter = rewardPosition + Vector2.new(rewardSize.X * 0.5, rewardSize.Y * 0.5)
		local endCenter = coinPosition + Vector2.new(math.min(34, coinSize.X * 0.22), coinSize.Y * 0.5)
		local coinCount = math.min(offlineIncomeState.maxCoinParticles, math.max(7, math.floor(sparkleCount * 0.8)))

		for index = 1, coinCount do
			local particle = Instance.new("TextLabel")
			local size = math.random(18, 25)
			local startOffset = Vector2.new(math.random(-118, 118), math.random(-18, 38))
			local midLift = math.random(34, 82)
			local endOffset = Vector2.new(math.random(-8, 18), math.random(-8, 8))
			local delayTime = 0.08 + (index - 1) * 0.026

			particle.Name = "OfflineIncomeCounterCoin"
			particle.AnchorPoint = Vector2.new(0.5, 0.5)
			particle.Size = UDim2.fromOffset(32, 32)
			particle.Position = UDim2.fromOffset(startCenter.X + startOffset.X, startCenter.Y + startOffset.Y)
			particle.BackgroundTransparency = 1
			particle.Text = "🪙"
			particle.TextColor3 = Color3.fromRGB(255, 222, 82)
			particle.TextSize = size
			particle.TextTransparency = 0
			particle.TextStrokeColor3 = Color3.fromRGB(80, 43, 0)
			particle.TextStrokeTransparency = 0.28
			particle.Font = Enum.Font.GothamBlack
			particle.Rotation = math.random(-18, 18)
			particle.ZIndex = 84
			particle.Parent = screenGui
			table.insert(offlineIncomeState.coinParticles, particle)

			task.delay(delayTime, function()
				if sequence ~= offlineIncomeState.sequence or not particle.Parent then
					return
				end

				local target = endCenter + endOffset
				local currentCenter = particle.AbsolutePosition + Vector2.new(particle.AbsoluteSize.X * 0.5, particle.AbsoluteSize.Y * 0.5)
				local drift = Vector2.new(
					(target.X - currentCenter.X) * 0.2,
					-math.abs(midLift)
				)

				tweenOfflineIncome(particle, 0.24, {
					Position = UDim2.fromOffset(currentCenter.X + drift.X, currentCenter.Y + drift.Y),
					Rotation = particle.Rotation + math.random(28, 64),
				}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out).Completed:Connect(function()
					if sequence ~= offlineIncomeState.sequence or not particle.Parent then
						return
					end

					tweenOfflineIncome(particle, 0.42 + math.random() * 0.12, {
						Position = UDim2.fromOffset(target.X, target.Y),
						TextTransparency = 1,
						TextStrokeTransparency = 1,
						Rotation = particle.Rotation + math.random(74, 132),
					}, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Connect(function()
						if sequence ~= offlineIncomeState.sequence then
							return
						end
						if particle.Parent then
							particle:Destroy()
						end
					end)
				end)
			end)
		end
	end

	local function hideOfflineIncomePopup()
		if not offlineIncomePanel.Visible then
			return
		end

		offlineIncomeState.sequence = offlineIncomeState.sequence + 1
		local sequence = offlineIncomeState.sequence
		clearOfflineIncomeSparkles()
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
		local totalDuration = summary.totalDuration or countedDuration
		local cappedAwayDuration = summary.cappedAwayDuration or "0m"
		local toolName = summary.toolName or "Your tool"
		local coinsPerMinute = math.floor(tonumber(summary.coinsPerMinute) or 0)
		local foremanPassId = tonumber(summary.foremanPassId) or Config.GAMEPASS_FOREMAN_ID
		local foremanPassOwned = summary.foremanPassOwned == true
		local foremanPassAvailable = summary.foremanPassAvailable == true
			and type(Config.isGamepassIdAvailable) == "function"
			and Config.isGamepassIdAvailable(foremanPassId)
		local showForemanUpsell = summary.hitCap == true and not foremanPassOwned and foremanPassAvailable
		local sourceLine = toolName .. " earned " .. tostring(coinsPerMinute) .. "/min while you were away"
		local popupKey = tostring(reward) .. "|" .. tostring(countedDuration) .. "|" .. tostring(capDuration) .. "|" .. tostring(totalDuration) .. "|" .. tostring(cappedAwayDuration) .. "|" .. tostring(toolName) .. "|" .. tostring(coinsPerMinute) .. "|" .. tostring(summary.hitCap == true) .. "|" .. tostring(foremanPassOwned) .. "|" .. tostring(foremanPassAvailable)
		if popupKey == offlineIncomeState.lastKey then
			return
		end

		offlineIncomeState.lastKey = popupKey
		offlineIncomeState.sequence = offlineIncomeState.sequence + 1
		local sequence = offlineIncomeState.sequence
		offlineIncomeState.foremanUpsellActive = showForemanUpsell
		offlineIncomeState.foremanUpsellAvailable = foremanPassAvailable
		offlineIncomeState.foremanPassId = foremanPassId
		clearOfflineIncomeSparkles()
		clearOfflineIncomeTweens()

		offlineIncomeReward.Text = "+" .. tostring(reward) .. " coins"
		offlineIncomeClaim.Text = "Collect"
		offlineIncomeClaim.Size = showForemanUpsell and UDim2.new(0, 132, 0, 34) or UDim2.new(0, 150, 0, 34)
		offlineIncomeClaim.Position = showForemanUpsell and UDim2.new(0.5, -140, 1, -44) or UDim2.new(0.5, -75, 1, -44)
		offlineIncomeClaim.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
		offlineIncomeClaim.TextColor3 = Color3.fromRGB(40, 20, 0)
		offlineIncomeState.foremanUpsell.Size = UDim2.new(0, 150, 0, 34)
		offlineIncomeState.foremanUpsell.Position = UDim2.new(0.5, -2, 1, -44)
		offlineIncomeState.foremanUpsell.Visible = showForemanUpsell
		offlineIncomeState.foremanUpsell.Active = showForemanUpsell
		offlineIncomeState.foremanUpsell.AutoButtonColor = showForemanUpsell
		offlineIncomeState.foremanUpsell.BackgroundColor3 = Color3.fromRGB(95, 205, 160)
		offlineIncomeState.foremanUpsell.TextColor3 = Color3.fromRGB(8, 35, 24)
		offlineIncomeState.foremanUpsell.Text = "Get 24h Pass"

		offlineIncomeBody.Text = sourceLine .. "."
		if summary.hitCap == true then
			offlineIncomeCap.Text = "Counted " .. countedDuration .. " of " .. totalDuration .. " away; " .. cappedAwayDuration .. " not counted by the " .. capDuration .. " cap."
		elseif foremanPassOwned then
			offlineIncomeCap.Text = "Foreman's Pass active: offline income can count up to " .. capDuration .. "."
		else
			offlineIncomeCap.Text = "Offline time counted: " .. countedDuration
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

		pulseCoinLabel("gain")
		playOfflineIncomeSparkleBurst(reward, sequence)

		if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
			LocalPlaySound:Fire("offline_income")
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

		local promptGamepass = Remotes:FindFirstChild("PromptGamepass")
		if promptGamepass and promptGamepass:IsA("RemoteEvent") then
			promptGamepass:FireServer(offlineIncomeState.foremanPassId or Config.GAMEPASS_FOREMAN_ID)
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

	local shouldShow = currentStreakReviveEligible
		and currentStreakRevivePending
		and currentStreakReviveProductAvailable
	streakRevivePanel.Visible = shouldShow

	if not shouldShow then
		return
	end

	local streak = math.max(currentStreakReviveBaseStreak, currentLoginStreak)
	local day = streak > 0 and ((streak - 1) % 7 + 1) or 1
	local cycle = streak > 0 and math.floor((streak - 1) / 7) + 1 or 1

	streakReviveTitle.Text = "🔥 Streak Revive"
	streakReviveBody.Text = "You missed one day. Revive your streak for " .. currentStreakRevivePrice .. " Robux to keep your momentum and today's reward."
	streakReviveDetail.Text = "Current streak: Day " .. day .. " (×" .. streak .. ", Cycle " .. cycle .. ")"
	streakReviveBuyButton.Visible = true
	streakReviveBuyButton.Active = true
	streakReviveBuyButton.AutoButtonColor = true
	streakReviveBuyButton.Selectable = true
	streakReviveBuyButton.Text = "Revive for " .. currentStreakRevivePrice .. " Robux"
	streakReviveBuyButton.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
	streakReviveBuyButton.TextColor3 = Color3.fromRGB(40, 20, 0)
	streakReviveDeclineButton.Size = UDim2.new(0, 140, 0, 40)
	streakReviveDeclineButton.Position = UDim2.new(1, -155, 1, -54)
end

streakReviveBuyButton.MouseButton1Click:Connect(function()
	if not currentStreakReviveEligible or not currentStreakRevivePending then
		return
	end
	if not currentStreakReviveProductAvailable then
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

	DeepDigClearFullBackpackPressure = function()
		sellPulseSequence = sellPulseSequence + 1
		if activeSellButtonTween then
			activeSellButtonTween:Cancel()
			activeSellButtonTween = nil
		end
		if activeSellGlowTween then
			activeSellGlowTween:Cancel()
			activeSellGlowTween = nil
		end

		sellButton.BackgroundColor3 = restColor
		sellButton.TextColor3 = restTextColor
		sellGlow.Transparency = 1

		if DeepDigClearBackpackFullBurst then
			DeepDigClearBackpackFullBurst()
		end
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
upgradeButton.TextSize = 13
upgradeButton.Font = Enum.Font.GothamBold
upgradeButton.TextWrapped = true
upgradeButton.Parent = screenGui

local upCorner = Instance.new("UICorner")
upCorner.CornerRadius = UDim.new(0, 8)
upCorner.Parent = upgradeButton

DeepDigToolUpgradeBurstUi = {}
DeepDigToolUpgradeBurstSequence = 0

DeepDigToolUpgradeBurstUi.frame = Instance.new("Frame")
DeepDigToolUpgradeBurstUi.frame.Name = "ToolUpgradeBurst"
DeepDigToolUpgradeBurstUi.frame.AnchorPoint = Vector2.new(0.5, 0.5)
DeepDigToolUpgradeBurstUi.frame.Size = UDim2.fromOffset(252, 54)
DeepDigToolUpgradeBurstUi.frame.Position = UDim2.fromScale(0.5, 0.82)
DeepDigToolUpgradeBurstUi.frame.BackgroundColor3 = Color3.fromRGB(25, 42, 58)
DeepDigToolUpgradeBurstUi.frame.BackgroundTransparency = 1
DeepDigToolUpgradeBurstUi.frame.BorderSizePixel = 0
DeepDigToolUpgradeBurstUi.frame.Visible = false
DeepDigToolUpgradeBurstUi.frame.ZIndex = 36
DeepDigToolUpgradeBurstUi.frame.Parent = screenGui

DeepDigToolUpgradeBurstUi.corner = Instance.new("UICorner")
DeepDigToolUpgradeBurstUi.corner.CornerRadius = UDim.new(0, 8)
DeepDigToolUpgradeBurstUi.corner.Parent = DeepDigToolUpgradeBurstUi.frame

DeepDigToolUpgradeBurstUi.stroke = Instance.new("UIStroke")
DeepDigToolUpgradeBurstUi.stroke.Color = Color3.fromRGB(255, 205, 80)
DeepDigToolUpgradeBurstUi.stroke.Thickness = 1
DeepDigToolUpgradeBurstUi.stroke.Transparency = 1
DeepDigToolUpgradeBurstUi.stroke.Parent = DeepDigToolUpgradeBurstUi.frame

DeepDigToolUpgradeBurstUi.scale = Instance.new("UIScale")
DeepDigToolUpgradeBurstUi.scale.Scale = 0.88
DeepDigToolUpgradeBurstUi.scale.Parent = DeepDigToolUpgradeBurstUi.frame

DeepDigToolUpgradeBurstUi.title = Instance.new("TextLabel")
DeepDigToolUpgradeBurstUi.title.Name = "Title"
DeepDigToolUpgradeBurstUi.title.Size = UDim2.new(1, -18, 0, 26)
DeepDigToolUpgradeBurstUi.title.Position = UDim2.fromOffset(9, 5)
DeepDigToolUpgradeBurstUi.title.BackgroundTransparency = 1
DeepDigToolUpgradeBurstUi.title.Text = ""
DeepDigToolUpgradeBurstUi.title.TextColor3 = Color3.fromRGB(255, 235, 160)
DeepDigToolUpgradeBurstUi.title.TextTransparency = 1
DeepDigToolUpgradeBurstUi.title.TextSize = 16
DeepDigToolUpgradeBurstUi.title.Font = Enum.Font.GothamBlack
DeepDigToolUpgradeBurstUi.title.TextXAlignment = Enum.TextXAlignment.Center
DeepDigToolUpgradeBurstUi.title.TextYAlignment = Enum.TextYAlignment.Center
DeepDigToolUpgradeBurstUi.title.TextTruncate = Enum.TextTruncate.AtEnd
DeepDigToolUpgradeBurstUi.title.ZIndex = 37
DeepDigToolUpgradeBurstUi.title.Parent = DeepDigToolUpgradeBurstUi.frame

DeepDigToolUpgradeBurstUi.damage = Instance.new("TextLabel")
DeepDigToolUpgradeBurstUi.damage.Name = "Damage"
DeepDigToolUpgradeBurstUi.damage.Size = UDim2.new(1, -18, 0, 20)
DeepDigToolUpgradeBurstUi.damage.Position = UDim2.fromOffset(9, 29)
DeepDigToolUpgradeBurstUi.damage.BackgroundTransparency = 1
DeepDigToolUpgradeBurstUi.damage.Text = ""
DeepDigToolUpgradeBurstUi.damage.TextColor3 = Color3.fromRGB(210, 235, 255)
DeepDigToolUpgradeBurstUi.damage.TextTransparency = 1
DeepDigToolUpgradeBurstUi.damage.TextSize = 13
DeepDigToolUpgradeBurstUi.damage.Font = Enum.Font.GothamBold
DeepDigToolUpgradeBurstUi.damage.TextXAlignment = Enum.TextXAlignment.Center
DeepDigToolUpgradeBurstUi.damage.TextYAlignment = Enum.TextYAlignment.Center
DeepDigToolUpgradeBurstUi.damage.TextTruncate = Enum.TextTruncate.AtEnd
DeepDigToolUpgradeBurstUi.damage.ZIndex = 37
DeepDigToolUpgradeBurstUi.damage.Parent = DeepDigToolUpgradeBurstUi.frame

local currentToolTier = 1
local updateUpgradeAffordance = function() end
DeepDigToolHud = {
	currentToolName = "Rusty Shovel",
	lastObservedToolTier = nil,
}

function DeepDigToolHud.getToolDamage(toolTier)
	local toolConfig = Config.TOOLS[tonumber(toolTier)]
	if not toolConfig then
		return nil
	end

	return toolConfig.damage
end

function DeepDigToolHud.updateToolReadout(toolName, toolTier)
	if toolName then
		DeepDigToolHud.currentToolName = toolName
	end
	if toolTier then
		currentToolTier = toolTier
	end

	local damage = DeepDigToolHud.getToolDamage(currentToolTier)
	if damage then
		toolLabel.Text = "🔧 " .. DeepDigToolHud.currentToolName .. " - DMG " .. tostring(damage)
	else
		toolLabel.Text = "🔧 " .. DeepDigToolHud.currentToolName
	end
end

function DeepDigToolHud.seedObservedToolTier(toolTier)
	local nextTier = tonumber(toolTier)
	if nextTier then
		DeepDigToolHud.lastObservedToolTier = nextTier
	end
end

function DeepDigPositionToolUpgradeBurst()
	local camera = workspace.CurrentCamera
	local viewportSize = camera and camera.ViewportSize or Vector2.new(800, 600)
	local burstWidth = DeepDigToolUpgradeBurstUi.frame.AbsoluteSize.X > 0 and DeepDigToolUpgradeBurstUi.frame.AbsoluteSize.X or 252
	local buttonCenter = upgradeButton.AbsolutePosition + (upgradeButton.AbsoluteSize / 2)
	local x = math.clamp(buttonCenter.X, (burstWidth / 2) + 12, math.max((burstWidth / 2) + 12, viewportSize.X - (burstWidth / 2) - 12))
	local y = math.clamp(upgradeButton.AbsolutePosition.Y - 82, 82, math.max(82, viewportSize.Y - 86))

	DeepDigToolUpgradeBurstUi.frame.Position = UDim2.fromOffset(x, y)
end

function DeepDigToolHud.playUpgradeBurst(toolName, previousTier, nextTier)
	previousTier = tonumber(previousTier)
	nextTier = tonumber(nextTier)
	if not previousTier or not nextTier then
		return
	end

	local nextToolConfig = Config.TOOLS[nextTier]
	local newToolName = toolName or (nextToolConfig and nextToolConfig.name) or "Tool Upgraded"
	local previousDamage = DeepDigToolHud.getToolDamage(previousTier)
	local nextDamage = DeepDigToolHud.getToolDamage(nextTier)
	local damageText = "Damage upgraded"
	if previousDamage and nextDamage then
		local damageDelta = nextDamage - previousDamage
		damageText = "DMG +" .. tostring(damageDelta) .. " (" .. tostring(previousDamage) .. "->" .. tostring(nextDamage) .. ")"
	end

	DeepDigToolUpgradeBurstSequence = DeepDigToolUpgradeBurstSequence + 1
	local sequence = DeepDigToolUpgradeBurstSequence

	DeepDigToolUpgradeBurstUi.title.Text = "⬆️ " .. newToolName
	DeepDigToolUpgradeBurstUi.damage.Text = damageText
	DeepDigPositionToolUpgradeBurst()

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("upgrade_whoosh")
	end

	DeepDigToolUpgradeBurstUi.frame.Visible = true
	DeepDigToolUpgradeBurstUi.frame.BackgroundTransparency = 1
	DeepDigToolUpgradeBurstUi.stroke.Transparency = 1
	DeepDigToolUpgradeBurstUi.title.TextTransparency = 1
	DeepDigToolUpgradeBurstUi.damage.TextTransparency = 1
	DeepDigToolUpgradeBurstUi.scale.Scale = 0.88

	TweenService:Create(DeepDigToolUpgradeBurstUi.frame, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.08,
	}):Play()
	TweenService:Create(DeepDigToolUpgradeBurstUi.stroke, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 0.12,
	}):Play()
	TweenService:Create(DeepDigToolUpgradeBurstUi.title, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
	TweenService:Create(DeepDigToolUpgradeBurstUi.damage, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
	TweenService:Create(DeepDigToolUpgradeBurstUi.scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	task.delay(1.25, function()
		if sequence ~= DeepDigToolUpgradeBurstSequence then
			return
		end

		local fadeFrame = TweenService:Create(DeepDigToolUpgradeBurstUi.frame, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		})
		TweenService:Create(DeepDigToolUpgradeBurstUi.stroke, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
		}):Play()
		TweenService:Create(DeepDigToolUpgradeBurstUi.title, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		}):Play()
		TweenService:Create(DeepDigToolUpgradeBurstUi.damage, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		}):Play()
		TweenService:Create(DeepDigToolUpgradeBurstUi.scale, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Scale = 0.95,
		}):Play()

		fadeFrame:Play()
		fadeFrame.Completed:Connect(function()
			if sequence ~= DeepDigToolUpgradeBurstSequence then
				return
			end
			DeepDigToolUpgradeBurstUi.frame.Visible = false
		end)
	end)
end

function DeepDigToolHud.observeToolTier(toolName, toolTier)
	local nextTier = tonumber(toolTier)
	if not nextTier then
		return
	end

	local previousTier = DeepDigToolHud.lastObservedToolTier
	if previousTier ~= nil and nextTier > previousTier then
		DeepDigToolHud.playUpgradeBurst(toolName, previousTier, nextTier)
	end

	DeepDigToolHud.lastObservedToolTier = nextTier
end

function DeepDigToolHud.setUpgradeButtonText(nextToolName, nextToolCost, atMaxLevel)
	local currentDamage = DeepDigToolHud.getToolDamage(currentToolTier)

	if atMaxLevel then
		if currentDamage then
			upgradeButton.Text = "⬆️ MAX LEVEL\nDMG " .. tostring(currentDamage)
		else
			upgradeButton.Text = "⬆️ MAX LEVEL"
		end
		return
	end

	local nextDamage = DeepDigToolHud.getToolDamage(currentToolTier + 1)
	local damageText = ""
	if currentDamage and nextDamage then
		damageText = "\nDMG " .. tostring(currentDamage) .. "->" .. tostring(nextDamage)
	end

	upgradeButton.Text = "⬆️ " .. nextToolName .. " ($" .. tostring(nextToolCost) .. ")" .. damageText
end

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

function DeepDigClearPassShopCards()
	for _, child in ipairs(cardsFrame:GetChildren()) do
		if child ~= cardsLayout then
			child:Destroy()
		end
	end
	passCards = {}
end

function DeepDigBuildPassComingSoonState()
	local emptyState = Instance.new("Frame")
	emptyState.Name = "PassesComingSoon"
	emptyState.Size = UDim2.new(1, 0, 0, 108)
	emptyState.BackgroundColor3 = Color3.fromRGB(32, 31, 38)
	emptyState.BorderSizePixel = 0
	emptyState.LayoutOrder = 1
	emptyState.ZIndex = 11
	emptyState.Parent = cardsFrame

	local emptyCorner = Instance.new("UICorner")
	emptyCorner.CornerRadius = UDim.new(0, 10)
	emptyCorner.Parent = emptyState

	local emptyStroke = Instance.new("UIStroke")
	emptyStroke.Color = Color3.fromRGB(92, 90, 104)
	emptyStroke.Thickness = 1
	emptyStroke.Transparency = 0.15
	emptyStroke.Parent = emptyState

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -28, 0, 30)
	titleLabel.Position = UDim2.new(0, 14, 0, 18)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = Config.UNAVAILABLE_GAMEPASS_LABEL or "Coming Soon"
	titleLabel.TextColor3 = Color3.fromRGB(225, 220, 240)
	titleLabel.TextSize = 18
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.ZIndex = 12
	titleLabel.Parent = emptyState

	local bodyLabel = Instance.new("TextLabel")
	bodyLabel.Name = "Body"
	bodyLabel.Size = UDim2.new(1, -36, 0, 40)
	bodyLabel.Position = UDim2.new(0, 18, 0, 52)
	bodyLabel.BackgroundTransparency = 1
	bodyLabel.Text = "Gamepasses are being prepared for launch. Check back soon."
	bodyLabel.TextColor3 = Color3.fromRGB(170, 166, 188)
	bodyLabel.TextSize = 13
	bodyLabel.Font = Enum.Font.GothamBold
	bodyLabel.TextWrapped = true
	bodyLabel.TextXAlignment = Enum.TextXAlignment.Center
	bodyLabel.ZIndex = 12
	bodyLabel.Parent = emptyState

	return emptyState
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
		local populateSequence = (cardsFrame:GetAttribute("PopulateSequence") or 0) + 1
		cardsFrame:SetAttribute("PopulateSequence", populateSequence)
		DeepDigClearPassShopCards()
		task.spawn(function()
			local GetPassInfo = Remotes:FindFirstChild("GetGamepassInfo")
			if not GetPassInfo then return end
			local info = GetPassInfo:InvokeServer()
			if not info then return end
			if cardsFrame:GetAttribute("PopulateSequence") ~= populateSequence then return end

			local availableCount = 0
			for _, passInfo in ipairs(info) do
				if isPassInfoAvailable(passInfo) then
					buildPassCard(passInfo)
					setCardOwned(passInfo.id, passInfo.owned)
					availableCount = availableCount + 1
				end
			end

			if availableCount == 0 then
				DeepDigBuildPassComingSoonState()
			end
		end)
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

DeepDigShowResurfaceCelebrationBurst = (function()
local state = {
	sequence = 0,
	frame = nil,
	tweens = {},
}

local function clearTweens()
	for _, tween in ipairs(state.tweens) do
		tween:Cancel()
	end
	state.tweens = {}
end

local function destroyActiveFrame()
	clearTweens()
	if state.frame and state.frame.Parent then
		state.frame:Destroy()
	end
	state.frame = nil
end

local function trackTween(instance, duration, goal, easingStyle, easingDirection)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
		goal
	)
	table.insert(state.tweens, tween)
	tween:Play()
	return tween
end

local function fitText(label, maxTextSize, minTextSize)
	label.TextScaled = true
	label.TextWrapped = true

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxTextSize
	constraint.MinTextSize = minTextSize or 10
	constraint.Parent = label
end

local function makeLabel(parent, name, text, y, height, color, maxTextSize, font)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(1, -42, 0, height)
	label.Position = UDim2.fromOffset(21, y)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 1
	label.TextStrokeColor3 = Color3.fromRGB(18, 13, 8)
	label.TextStrokeTransparency = 1
	label.Font = font or Enum.Font.GothamBlack
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = 93
	fitText(label, maxTextSize, 12)
	label.Parent = parent
	return label
end

local function fadeDescendants(frame, duration)
	for _, descendant in ipairs(frame:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			trackTween(descendant, duration, {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		elseif descendant:IsA("Frame") then
			trackTween(descendant, duration, {
				BackgroundTransparency = 1,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		elseif descendant:IsA("UIStroke") then
			trackTween(descendant, duration, {
				Transparency = 1,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end
end

local function formatMultiplier(value)
	local rounded = math.floor((tonumber(value) or 1) * 10 + 0.5) / 10
	return string.format("%.1fx", rounded)
end

return function(payload)
	if type(payload) ~= "table" then
		return
	end

	local resurfaceCount = math.floor(tonumber(payload.resurfaceCount) or 0)
	local permanentMultiplier = tonumber(payload.permanentMultiplier) or 1
	if resurfaceCount <= 0 then
		return
	end

	state.sequence = state.sequence + 1
	local sequence = state.sequence
	destroyActiveFrame()

	local layer = Instance.new("Frame")
	layer.Name = "ResurfaceCelebrationBurst"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundColor3 = Color3.fromRGB(18, 13, 8)
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.ZIndex = 88
	layer.Parent = screenGui
	state.frame = layer

	local panel = Instance.new("Frame")
	panel.Name = "Center"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromOffset(350, 150)
	panel.Position = UDim2.fromScale(0.5, 0.52)
	panel.BackgroundColor3 = Color3.fromRGB(45, 34, 18)
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.ZIndex = 91
	panel.Parent = layer

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 219, 88)
	stroke.Thickness = 3
	stroke.Transparency = 1
	stroke.Parent = panel

	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Size = UDim2.fromOffset(360, 150)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.BackgroundColor3 = Color3.fromRGB(255, 205, 64)
	glow.BackgroundTransparency = 1
	glow.BorderSizePixel = 0
	glow.ZIndex = 89
	glow.Parent = layer

	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(1, 0)
	glowCorner.Parent = glow

	for index = 1, 10 do
		local ray = Instance.new("Frame")
		ray.Name = "Ray"
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Size = UDim2.fromOffset(10, 88)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.BackgroundColor3 = Color3.fromRGB(255, 225, 110)
		ray.BackgroundTransparency = 1
		ray.BorderSizePixel = 0
		ray.Rotation = index * 18
		ray.ZIndex = 90
		ray.Parent = layer
	end

	makeLabel(panel, "Title", "RESURFACED", 16, 38, Color3.fromRGB(255, 231, 123), 32)
	makeLabel(panel, "Count", "Resurface #" .. tostring(resurfaceCount), 56, 48, Color3.fromRGB(255, 255, 255), 38)
	makeLabel(
		panel,
		"Multiplier",
		"Permanent Coin Multiplier " .. formatMultiplier(permanentMultiplier),
		110,
		30,
		Color3.fromRGB(255, 238, 160),
		20,
		Enum.Font.GothamBold
	)

	trackTween(layer, 0.16, { BackgroundTransparency = 0.18 })
	trackTween(glow, 0.22, {
		Size = UDim2.fromOffset(620, 260),
		BackgroundTransparency = 0.76,
	}, Enum.EasingStyle.Quad)
	trackTween(panel, 0.22, {
		Size = UDim2.fromOffset(490, 182),
		Position = UDim2.fromScale(0.5, 0.47),
		BackgroundTransparency = 0.04,
	}, Enum.EasingStyle.Back)
	trackTween(stroke, 0.16, { Transparency = 0, Thickness = 4 })

	for _, descendant in ipairs(panel:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			trackTween(descendant, 0.18, {
				TextTransparency = 0,
				TextStrokeTransparency = 0.42,
			})
		end
	end

	for _, ray in ipairs(layer:GetChildren()) do
		if ray.Name == "Ray" then
			trackTween(ray, 0.24, {
				Size = UDim2.fromOffset(7, 270),
				BackgroundTransparency = 0.55,
			}, Enum.EasingStyle.Quad)
			trackTween(ray, 0.62, {
				Rotation = ray.Rotation + 40,
				BackgroundTransparency = 1,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end

	task.delay(2.7, function()
		if sequence ~= state.sequence or not layer.Parent then
			return
		end

		trackTween(layer, 0.32, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		trackTween(glow, 0.28, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		trackTween(panel, 0.28, {
			Position = UDim2.fromScale(0.5, 0.40),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		fadeDescendants(panel, 0.24)

		task.delay(0.34, function()
			if sequence ~= state.sequence then
				return
			end
			destroyActiveFrame()
		end)
	end)
end
end)()

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
	if data.toolName or data.toolTier then
		if data.toolTier ~= nil then
			DeepDigToolHud.observeToolTier(data.toolName, data.toolTier)
		end
		DeepDigToolHud.updateToolReadout(data.toolName, data.toolTier)
	end
	if data.blocksDug then
		blocksLabel.Text = "Blocks: " .. tostring(data.blocksDug)
	end
	if data.inventoryCount ~= nil or data.inventoryCapacity ~= nil then
		setInventoryDisplay(data.inventoryCount, data.inventoryCapacity)
	end
	if data.infiniteBackpackUnlocked then
		DeepDigShowInfiniteBackpackUnlockBurst(data.infiniteBackpackUnlocked)
	end
	if data.fragments ~= nil then
		local newFragments = math.floor(data.fragments)
		fragLabel.Text = "Fragments: " .. tostring(newFragments)
		if previousFragmentValue ~= nil and newFragments > previousFragmentValue then
			pulseFragmentLabel()
		end
		previousFragmentValue = newFragments
	end
	if data.rarePity ~= nil or data.rarePityThreshold ~= nil or data.rarePityTriggered then
		DeepDigUpdateRareMeter(data.rarePity, data.rarePityThreshold, data.rarePityTriggered == true)
	end
	if data.questSummary ~= nil then
		DeepDigUpdateQuestSidePanel(data.questSummary)
	end
	DeepDigUpdateEnemyDefeatPanel(data)
	if data.nextToolCost ~= nil and data.nextToolName then
		DeepDigToolHud.setUpgradeButtonText(data.nextToolName, data.nextToolCost, false)
		affordanceNextToolCost = tonumber(data.nextToolCost)
		affordanceAtMaxLevel = false
		upgradeAffordanceChanged = true
	elseif data.nextToolCost == nil and data.toolTier then
		DeepDigToolHud.setUpgradeButtonText(nil, nil, true)
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
	local shouldPlaySellCoins = data.soldItem == true
		and math.floor(tonumber(data.soldCoinsEarned) or 0) > 0
	if type(data.sellAllSummary) == "table" then
		shouldPlaySellCoins = shouldPlaySellCoins
			or math.floor(tonumber(data.sellAllSummary.coinsEarned) or 0) > 0
	end
	if shouldPlaySellCoins and LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("sell_coins")
	end
	if data.sellAllSummary then
		showSellAllSummaryBurst(data.sellAllSummary)
	end
	if data.backpackFull then
		DeepDigShowBackpackFullBurst(data.backpackFull)
	end
	if data.enemyDangerUnlocked then
		showEnemyDangerUnlockedBurst(data.enemyDangerUnlocked)
	end
	if data.depthTierUnlocked and showDepthTierUnlockedBurst then
		local depthTierUnlockedPayload = data.depthTierUnlocked
		if data.badgeUnlock or data.enemyDangerUnlocked then
			task.delay(3.35, function()
				showDepthTierUnlockedBurst(depthTierUnlockedPayload)
			end)
		else
			showDepthTierUnlockedBurst(depthTierUnlockedPayload)
		end
	end
	if data.depthMilestone then
		local depthMilestonePayload = data.depthMilestone
		if data.depthTierUnlocked then
			task.delay(2.65, function()
				DeepDigShowDepthMilestoneBurst(depthMilestonePayload)
			end)
		else
			DeepDigShowDepthMilestoneBurst(depthMilestonePayload)
		end
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

do
	local museumUpdateEvent = Remotes:WaitForChild("MuseumUpdate", 5)
	if museumUpdateEvent then
		museumUpdateEvent.OnClientEvent:Connect(DeepDigShowMuseumTierCompleteBurst)
	end
end

do
	local resurfaceCelebrationEvent = Remotes:WaitForChild("ResurfaceCelebration", 5)
	if resurfaceCelebrationEvent then
		resurfaceCelebrationEvent.OnClientEvent:Connect(DeepDigShowResurfaceCelebrationBurst)
	end
end

Remotes.ItemFound.OnClientEvent:Connect(function(item)
	if not DeepDigIsValidItemFoundPayload(item) then
		return
	end

	local function playItemFoundFlow()
		local shouldPlayRareReveal = DeepDigShouldPlayRareRevealForRarity(item.rarity)

		if shouldPlayRareReveal then
			playLegendaryFindFlash(item.rarity, item)
			DeepDigPlayRareRevealSound()
			if LEGENDARY_FIND_FLASH_RARITIES[item.rarity] then
				LEGENDARY_FIND_FLASH_RARITIES._cameraBump.play(item.rarity)
			end
		else
			DeepDigPlayItemFoundSound(item)
		end

		if LIGHTING_PULSE_PROFILES[item.rarity] then
			playLightingPulse(item.rarity)
		end

		if item.seasonalExclusive == true or item.seasonId ~= nil then
			DeepDigPlaySeasonalExclusiveReveal(item)
		end

		showNotification("Found: " .. item.name .. " (+" .. tostring(item.sellValue or 0) .. " coins)", item.rarity)
	end

	if LEGENDARY_FIND_FLASH_RARITIES.PlayAnchoredGlint(item) then
		task.delay(0.12, playItemFoundFlow)
	else
		playItemFoundFlow()
	end
end)

Remotes.EventTriggered.OnClientEvent:Connect(function(eventName, message, duration, effectId)
	updateSeasonBadge(effectId)
	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("event_alarm")
		if isEarthquakeEvent(eventName, message, effectId) then
			LocalPlaySound:Fire("earthquake_rumble")
		end
	end
	DeepDigActiveEventHud.show(eventName, message, duration, effectId)
	DeepDigEventStartFlash.play(eventName, message, duration, effectId)
	if shouldPlayEventCameraShake(duration) then
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
		DeepDigToolHud.updateToolReadout(data.toolName, data.toolTier)
		DeepDigToolHud.seedObservedToolTier(data.toolTier)
		blocksLabel.Text = "Blocks: " .. tostring(data.totalBlocksDug)
		setInventoryDisplay(#data.inventory, data.inventoryCapacity)
		if data.fragments ~= nil then
			previousFragmentValue = math.floor(data.fragments)
			fragLabel.Text = "Fragments: " .. tostring(previousFragmentValue)
		end
		DeepDigUpdateRareMeter(data.rarePity, data.rarePityThreshold, false)
		if data.questSummary ~= nil then
			DeepDigUpdateQuestSidePanel(data.questSummary)
		end
		DeepDigUpdateEnemyDefeatPanel(data)
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
			DeepDigToolHud.setUpgradeButtonText(data.nextToolName, data.nextToolCost, false)
			updateUpgradeAffordance(previousCoinValue, tonumber(data.nextToolCost), false)
		elseif data.nextToolCost == nil and data.toolTier then
			DeepDigToolHud.setUpgradeButtonText(nil, nil, true)
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
