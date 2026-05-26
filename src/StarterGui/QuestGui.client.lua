local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local REMOTE_WAIT_SECONDS = 5
local REFRESH_INTERVAL_SECONDS = 5
local CLOSED_SUMMARY_INTERVAL_SECONDS = 25
local LOCAL_PLAY_SOUND_NAME = "DeepDigLocalPlaySound"

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT_SECONDS)
if not remotesFolder then
	warn("[QuestGui] Remotes folder not found; quest UI disabled.")
	return
end

local getQuestStatus = remotesFolder:WaitForChild("GetQuestStatus", REMOTE_WAIT_SECONDS)
if not getQuestStatus or not getQuestStatus:IsA("RemoteFunction") then
	warn("[QuestGui] GetQuestStatus remote not found; quest UI disabled.")
	return
end

local claimQuest = remotesFolder:WaitForChild("ClaimQuest", REMOTE_WAIT_SECONDS)
if not claimQuest or not claimQuest:IsA("RemoteEvent") then
	warn("[QuestGui] ClaimQuest remote not found; quest UI disabled.")
	return
end

local questClaimResult = remotesFolder:WaitForChild("QuestClaimResult", REMOTE_WAIT_SECONDS)
if not questClaimResult or not questClaimResult:IsA("RemoteEvent") then
	warn("[QuestGui] QuestClaimResult remote not found; quest reward FX disabled.")
	questClaimResult = nil
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QuestGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 60
screenGui.Parent = playerGui

local panelOpen = player:GetAttribute("QuestPanelOpen") == true
local currentQuestDay = ""
local currentQuestWeekKey = ""
local claimedQuestIds = {}
local weeklyQuestClaimed = false
local activeCards = {}
local activeCardByQuestId = {}
local activeWeeklyCard = nil
local refreshInFlight = false
local currentReadyCount = 0
local lastClosedSummaryRefresh = -CLOSED_SUMMARY_INTERVAL_SECONDS

local COLOR_PANEL = Color3.fromRGB(19, 18, 28)
local COLOR_PANEL_EDGE = Color3.fromRGB(42, 38, 60)
local COLOR_HEADER = Color3.fromRGB(76, 52, 110)
local COLOR_TEXT_MAIN = Color3.fromRGB(245, 242, 255)
local COLOR_TEXT_MUTED = Color3.fromRGB(171, 164, 190)
local COLOR_TEXT_DIM = Color3.fromRGB(120, 115, 135)
local COLOR_ACCENT = Color3.fromRGB(255, 210, 85)
local COLOR_READY = Color3.fromRGB(85, 190, 95)
local COLOR_DISABLED = Color3.fromRGB(74, 72, 82)
local COLOR_BAR_BG = Color3.fromRGB(38, 36, 48)
local COLOR_BAR_FILL = Color3.fromRGB(255, 196, 72)
local COLOR_WEEKLY = Color3.fromRGB(92, 145, 255)
local COLOR_TOGGLE_OPEN = Color3.fromRGB(60, 54, 76)
local COLOR_TOGGLE_CLOSED = Color3.fromRGB(44, 42, 58)
local COLOR_TOGGLE_READY = Color3.fromRGB(38, 74, 48)
local COLOR_TOGGLE_STROKE = Color3.fromRGB(68, 65, 82)

local function destroyQuestCards()
	for _, card in ipairs(activeCards) do
		if card and card.Parent then
			card:Destroy()
		end
	end
	activeCards = {}
	activeCardByQuestId = {}
	activeWeeklyCard = nil
end

local function safeNumber(value)
	if type(value) == "number" then
		return value
	end
	return 0
end

local function normalizeStatus(status)
	if type(status) ~= "table" then
		return nil
	end

	local quests = {}
	if type(status.quests) == "table" then
		for _, quest in ipairs(status.quests) do
			if type(quest) == "table" then
				quests[#quests + 1] = quest
			end
		end
	end

	return {
		day = type(status.day) == "string" and status.day or "",
		quests = quests,
		weekly = type(status.weekly) == "table" and {
			id = type(status.weekly.id) == "string" and status.weekly.id or "",
			description = type(status.weekly.description) == "string" and status.weekly.description or "Weekly quest",
			progress = safeNumber(status.weekly.progress),
			target = math.max(1, safeNumber(status.weekly.target)),
			complete = status.weekly.complete == true,
			claimed = status.weekly.claimed == true,
			weekKey = type(status.weekly.weekKey) == "string" and status.weekly.weekKey or "",
		} or nil,
	}
end

local function isQuestClaimed(questId)
	return claimedQuestIds[questId] == true
end

local function markQuestClaimed(questId)
	claimedQuestIds[questId] = true
end

local function isWeeklyQuestClaimed()
	return weeklyQuestClaimed == true
end

local function markWeeklyQuestClaimed(claimed)
	weeklyQuestClaimed = claimed == true
end

local function syncQuestClaimState(normalized)
	if type(normalized) ~= "table" then
		return
	end

	if normalized.day ~= "" and normalized.day ~= currentQuestDay then
		claimedQuestIds = {}
	end

	if normalized.day ~= "" then
		currentQuestDay = normalized.day
	end

	if normalized.weekly then
		if normalized.weekly.weekKey ~= "" and normalized.weekly.weekKey ~= currentQuestWeekKey then
			weeklyQuestClaimed = false
		end

		if normalized.weekly.weekKey ~= "" then
			currentQuestWeekKey = normalized.weekly.weekKey
		end

		markWeeklyQuestClaimed(normalized.weekly.claimed)
	end
end

local function countReadyQuests(normalized)
	if type(normalized) ~= "table" then
		return 0
	end

	local readyCount = 0
	for _, quest in ipairs(normalized.quests) do
		local questId = type(quest.id) == "string" and quest.id or ""
		if questId ~= "" and quest.complete == true and not isQuestClaimed(questId) then
			readyCount = readyCount + 1
		end
	end

	if normalized.weekly and normalized.weekly.id ~= "" and normalized.weekly.complete == true and not isWeeklyQuestClaimed() then
		readyCount = readyCount + 1
	end

	return readyCount
end

local panel = Instance.new("Frame")
panel.Name = "QuestPanel"
panel.Size = UDim2.fromOffset(360, 398)
panel.Position = UDim2.new(1, -376, 1, -454)
panel.BackgroundColor3 = COLOR_PANEL
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = panelOpen
panel.ZIndex = 10
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLOR_PANEL_EDGE
panelStroke.Thickness = 1
panelStroke.Transparency = 0.15
panelStroke.Parent = panel

local headerBar = Instance.new("Frame")
headerBar.Name = "Header"
headerBar.Size = UDim2.new(1, 0, 0, 44)
headerBar.BackgroundColor3 = COLOR_HEADER
headerBar.BorderSizePixel = 0
headerBar.ZIndex = 11
headerBar.Parent = panel

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 14)
headerCorner.Parent = headerBar

local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 14)
headerFix.Position = UDim2.new(0, 0, 1, -14)
headerFix.BackgroundColor3 = COLOR_HEADER
headerFix.BorderSizePixel = 0
headerFix.ZIndex = 11
headerFix.Parent = headerBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, -20, 1, 0)
titleLabel.Position = UDim2.fromOffset(12, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Daily Quests"
titleLabel.TextColor3 = COLOR_TEXT_MAIN
titleLabel.TextSize = 19
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 12
titleLabel.Parent = headerBar

local dayLabel = Instance.new("TextLabel")
dayLabel.Name = "Day"
dayLabel.Size = UDim2.new(1, -18, 0, 18)
dayLabel.Position = UDim2.fromOffset(10, 52)
dayLabel.BackgroundTransparency = 1
dayLabel.Text = "Daily Quests · Loading..."
dayLabel.TextColor3 = COLOR_TEXT_MUTED
dayLabel.TextSize = 13
dayLabel.Font = Enum.Font.Gotham
dayLabel.TextXAlignment = Enum.TextXAlignment.Left
dayLabel.ZIndex = 11
dayLabel.Parent = panel

local cardsFrame = Instance.new("Frame")
cardsFrame.Name = "Cards"
cardsFrame.Size = UDim2.new(1, -20, 0, 320)
cardsFrame.Position = UDim2.fromOffset(10, 76)
cardsFrame.BackgroundTransparency = 1
cardsFrame.ZIndex = 11
cardsFrame.Parent = panel

local cardsLayout = Instance.new("UIListLayout")
cardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardsLayout.Padding = UDim.new(0, 8)
cardsLayout.Parent = cardsFrame

local loadingLabel = Instance.new("TextLabel")
loadingLabel.Name = "Loading"
loadingLabel.Size = UDim2.new(1, 0, 0, 24)
loadingLabel.Position = UDim2.fromOffset(0, 88)
loadingLabel.BackgroundTransparency = 1
loadingLabel.Text = "Loading..."
loadingLabel.TextColor3 = COLOR_TEXT_DIM
loadingLabel.TextSize = 14
loadingLabel.Font = Enum.Font.Gotham
loadingLabel.TextXAlignment = Enum.TextXAlignment.Center
loadingLabel.ZIndex = 11
loadingLabel.Visible = false
loadingLabel.Parent = panel

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "QuestToggle"
toggleButton.Size = UDim2.fromOffset(154, 40)
toggleButton.Position = UDim2.new(1, -170, 1, -56)
toggleButton.BackgroundColor3 = COLOR_TOGGLE_CLOSED
toggleButton.BorderSizePixel = 0
toggleButton.Text = "Quests"
toggleButton.TextColor3 = COLOR_TEXT_MAIN
toggleButton.TextSize = 15
toggleButton.Font = Enum.Font.GothamBold
toggleButton.AutoButtonColor = false
toggleButton.ZIndex = 20
toggleButton.Parent = screenGui

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

local toggleStroke = Instance.new("UIStroke")
toggleStroke.Color = COLOR_TOGGLE_STROKE
toggleStroke.Thickness = 1
toggleStroke.Transparency = 0.2
toggleStroke.Parent = toggleButton

local localPlaySound = SoundService:FindFirstChild(LOCAL_PLAY_SOUND_NAME)
if not localPlaySound then
	localPlaySound = Instance.new("BindableEvent")
	localPlaySound.Name = LOCAL_PLAY_SOUND_NAME
	localPlaySound.Parent = SoundService
end

local rewardBurst = Instance.new("Frame")
rewardBurst.Name = "QuestRewardBurst"
rewardBurst.AnchorPoint = Vector2.new(0.5, 0.5)
rewardBurst.Size = UDim2.fromOffset(320, 126)
rewardBurst.Position = UDim2.fromScale(0.5, 0.38)
rewardBurst.BackgroundColor3 = Color3.fromRGB(26, 24, 36)
rewardBurst.BackgroundTransparency = 0.1
rewardBurst.BorderSizePixel = 0
rewardBurst.Visible = false
rewardBurst.ZIndex = 80
rewardBurst.Parent = screenGui

local rewardBurstCorner = Instance.new("UICorner")
rewardBurstCorner.CornerRadius = UDim.new(0, 12)
rewardBurstCorner.Parent = rewardBurst

local rewardBurstStroke = Instance.new("UIStroke")
rewardBurstStroke.Color = COLOR_ACCENT
rewardBurstStroke.Thickness = 2
rewardBurstStroke.Transparency = 0.1
rewardBurstStroke.Parent = rewardBurst

local rewardBurstTitle = Instance.new("TextLabel")
rewardBurstTitle.Name = "Title"
rewardBurstTitle.Size = UDim2.new(1, -28, 0, 24)
rewardBurstTitle.Position = UDim2.fromOffset(14, 14)
rewardBurstTitle.BackgroundTransparency = 1
rewardBurstTitle.Text = "Quest Claimed"
rewardBurstTitle.TextColor3 = COLOR_ACCENT
rewardBurstTitle.TextTransparency = 1
rewardBurstTitle.TextSize = 19
rewardBurstTitle.Font = Enum.Font.GothamBlack
rewardBurstTitle.TextXAlignment = Enum.TextXAlignment.Center
rewardBurstTitle.ZIndex = 81
rewardBurstTitle.Parent = rewardBurst

local rewardBurstDescription = Instance.new("TextLabel")
rewardBurstDescription.Name = "Description"
rewardBurstDescription.Size = UDim2.new(1, -32, 0, 38)
rewardBurstDescription.Position = UDim2.fromOffset(16, 42)
rewardBurstDescription.BackgroundTransparency = 1
rewardBurstDescription.Text = "Completed quest"
rewardBurstDescription.TextColor3 = COLOR_TEXT_MAIN
rewardBurstDescription.TextTransparency = 1
rewardBurstDescription.TextSize = 14
rewardBurstDescription.Font = Enum.Font.GothamBold
rewardBurstDescription.TextWrapped = true
rewardBurstDescription.TextXAlignment = Enum.TextXAlignment.Center
rewardBurstDescription.TextYAlignment = Enum.TextYAlignment.Center
rewardBurstDescription.ZIndex = 81
rewardBurstDescription.Parent = rewardBurst

local rewardBurstAmount = Instance.new("TextLabel")
rewardBurstAmount.Name = "Reward"
rewardBurstAmount.Size = UDim2.new(1, -32, 0, 26)
rewardBurstAmount.Position = UDim2.fromOffset(16, 86)
rewardBurstAmount.BackgroundTransparency = 1
rewardBurstAmount.Text = "+0 coins"
rewardBurstAmount.TextColor3 = Color3.fromRGB(255, 235, 130)
rewardBurstAmount.TextTransparency = 1
rewardBurstAmount.TextSize = 18
rewardBurstAmount.Font = Enum.Font.GothamBlack
rewardBurstAmount.TextWrapped = true
rewardBurstAmount.TextXAlignment = Enum.TextXAlignment.Center
rewardBurstAmount.ZIndex = 81
rewardBurstAmount.Parent = rewardBurst

local rewardBurstTweens = {}
local rewardBurstSequence = 0

local function updateToggleAppearance()
	if panelOpen then
		toggleButton.Text = "Quests"
		toggleButton.BackgroundColor3 = COLOR_TOGGLE_OPEN
		toggleStroke.Color = COLOR_TOGGLE_STROKE
		toggleStroke.Thickness = 1
		toggleStroke.Transparency = 0.2
	elseif currentReadyCount > 0 then
		toggleButton.Text = "Quests · " .. currentReadyCount .. " Ready"
		toggleButton.BackgroundColor3 = COLOR_TOGGLE_READY
		toggleStroke.Color = COLOR_ACCENT
		toggleStroke.Thickness = 2
		toggleStroke.Transparency = 0.08
	else
		toggleButton.Text = "Quests"
		toggleButton.BackgroundColor3 = COLOR_TOGGLE_CLOSED
		toggleStroke.Color = COLOR_TOGGLE_STROKE
		toggleStroke.Thickness = 1
		toggleStroke.Transparency = 0.2
	end
end

local function setPanelOpen(open, syncAttribute)
	open = open == true
	panelOpen = open
	panel.Visible = open
	updateToggleAppearance()

	if syncAttribute then
		player:SetAttribute("QuestPanelOpen", open)
	end
end

local function setLoadingVisible(isLoading, dayText)
	loadingLabel.Visible = isLoading == true
	if type(dayText) == "string" and dayText ~= "" then
		dayLabel.Text = "Daily Quests · " .. dayText
	elseif isLoading then
		dayLabel.Text = "Daily Quests · Loading..."
	else
		local fallbackDay = currentQuestDay ~= "" and currentQuestDay or "Loading..."
		dayLabel.Text = "Daily Quests · " .. fallbackDay
	end
end

local function clearRewardBurstTweens()
	for _, tween in ipairs(rewardBurstTweens) do
		tween:Cancel()
	end
	rewardBurstTweens = {}
end

local function tweenRewardBurst(instance, duration, goal, easingStyle, easingDirection)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
		goal
	)
	table.insert(rewardBurstTweens, tween)
	tween:Play()
	return tween
end

local function playQuestClaimSound()
	if localPlaySound and localPlaySound:IsA("BindableEvent") then
		localPlaySound:Fire("quest_claim")
	end
end

local function formatReward(reward)
	if type(reward) ~= "table" then
		return "Quest reward"
	end

	local parts = {}
	local coins = safeNumber(reward.coins)
	local fragments = safeNumber(reward.fragments)

	if coins > 0 then
		parts[#parts + 1] = "+" .. math.floor(coins) .. " coins"
	end
	if fragments > 0 then
		parts[#parts + 1] = "+" .. math.floor(fragments) .. " fragments"
	end

	if #parts == 0 then
		return "Quest reward"
	end

	return table.concat(parts, "  ")
end

local function pulseToggle()
	toggleStroke.Color = COLOR_ACCENT
	toggleStroke.Thickness = 3
	toggleStroke.Transparency = 0
	toggleButton.BackgroundColor3 = Color3.fromRGB(58, 102, 56)

	tweenRewardBurst(toggleStroke, 0.42, {
		Color = currentReadyCount > 0 and COLOR_ACCENT or COLOR_TOGGLE_STROKE,
		Thickness = currentReadyCount > 0 and 2 or 1,
		Transparency = currentReadyCount > 0 and 0.08 or 0.2,
	})
	tweenRewardBurst(toggleButton, 0.42, {
		BackgroundColor3 = panelOpen and COLOR_TOGGLE_OPEN or currentReadyCount > 0 and COLOR_TOGGLE_READY or COLOR_TOGGLE_CLOSED,
	})
end

local function updateQuestToggleSummary(status)
	local normalized = normalizeStatus(status)
	if not normalized then
		currentReadyCount = 0
		updateToggleAppearance()
		return nil
	end

	syncQuestClaimState(normalized)

	local previousReadyCount = currentReadyCount
	currentReadyCount = countReadyQuests(normalized)
	updateToggleAppearance()

	if currentReadyCount > previousReadyCount and not panelOpen then
		pulseToggle()
	end

	return normalized
end

local function pulseClaimedCard(entry)
	if type(entry) ~= "table" or not entry.card or not entry.card.Parent then
		pulseToggle()
		return
	end

	if type(entry.applyButtonState) == "function" then
		entry.applyButtonState()
	end

	entry.card.BackgroundColor3 = Color3.fromRGB(43, 37, 47)
	if entry.stroke and entry.stroke.Parent then
		entry.stroke.Color = COLOR_ACCENT
		entry.stroke.Thickness = 3
		entry.stroke.Transparency = 0
	end
	if entry.accent and entry.accent.Parent then
		entry.accent.BackgroundColor3 = COLOR_ACCENT
	end

	tweenRewardBurst(entry.card, 0.46, {
		BackgroundColor3 = Color3.fromRGB(28, 25, 39),
	})
	if entry.stroke and entry.stroke.Parent then
		tweenRewardBurst(entry.stroke, 0.46, {
			Color = COLOR_READY,
			Thickness = 1,
			Transparency = 0.1,
		})
	end
	if entry.accent and entry.accent.Parent then
		tweenRewardBurst(entry.accent, 0.46, {
			BackgroundColor3 = COLOR_READY,
		})
	end
end

local function showQuestClaimReward(payload)
	if type(payload) ~= "table" then
		return
	end

	local questId = type(payload.questId) == "string" and payload.questId or ""
	local isWeekly = payload.weekly == true
	local description = type(payload.description) == "string" and payload.description or "Completed quest"
	local rewardText = formatReward(payload.reward)

	if isWeekly then
		markWeeklyQuestClaimed(true)
	elseif questId ~= "" then
		markQuestClaimed(questId)
	end
	currentReadyCount = math.max(0, currentReadyCount - 1)
	updateToggleAppearance()

	local entry = isWeekly and activeWeeklyCard or activeCardByQuestId[questId]

	rewardBurstSequence = rewardBurstSequence + 1
	local sequence = rewardBurstSequence
	clearRewardBurstTweens()
	playQuestClaimSound()
	pulseClaimedCard(entry)

	rewardBurst.Visible = true
	rewardBurst.Size = UDim2.fromOffset(292, 112)
	rewardBurst.Position = UDim2.fromScale(0.5, 0.40)
	rewardBurst.BackgroundTransparency = 0.22
	rewardBurstStroke.Transparency = 0
	rewardBurstTitle.Text = isWeekly and "Weekly Claimed" or "Quest Claimed"
	rewardBurstTitle.TextTransparency = 1
	rewardBurstDescription.Text = description
	rewardBurstDescription.TextTransparency = 1
	rewardBurstAmount.Text = rewardText
	rewardBurstAmount.TextTransparency = 1

	tweenRewardBurst(rewardBurst, 0.18, {
		Size = UDim2.fromOffset(320, 126),
		Position = UDim2.fromScale(0.5, 0.38),
		BackgroundTransparency = 0.08,
	}, Enum.EasingStyle.Back)
	tweenRewardBurst(rewardBurstTitle, 0.16, { TextTransparency = 0 })
	tweenRewardBurst(rewardBurstDescription, 0.2, { TextTransparency = 0.02 })
	tweenRewardBurst(rewardBurstAmount, 0.22, { TextTransparency = 0 })

	task.delay(1.55, function()
		if sequence ~= rewardBurstSequence or not rewardBurst.Parent then
			return
		end

		tweenRewardBurst(rewardBurst, 0.26, {
			Position = UDim2.fromScale(0.5, 0.35),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenRewardBurst(rewardBurstStroke, 0.22, { Transparency = 1 })
		tweenRewardBurst(rewardBurstTitle, 0.18, { TextTransparency = 1 })
		tweenRewardBurst(rewardBurstDescription, 0.18, { TextTransparency = 1 })
		local amountTween = tweenRewardBurst(rewardBurstAmount, 0.18, { TextTransparency = 1 })
		amountTween.Completed:Once(function()
			if sequence == rewardBurstSequence then
				rewardBurst.Visible = false
			end
		end)
	end)
end

local function makeCard(quest, cardConfig)
	cardConfig = cardConfig or {}

	local questId = type(quest.id) == "string" and quest.id or ""
	local description = type(quest.description) == "string" and quest.description or "Unknown quest"
	local progress = safeNumber(quest.progress)
	local target = math.max(1, safeNumber(quest.target))
	local complete = cardConfig.isComplete == true or quest.complete == true
	local claimed = cardConfig.isClaimed
	if claimed == nil then
		claimed = questId ~= "" and isQuestClaimed(questId)
	end
	local isWeekly = cardConfig.isWeekly == true
	local onClaim = cardConfig.onClaim
	local fillRatio = math.clamp(progress / target, 0, 1)

	local card = Instance.new("Frame")
	card.Name = "QuestCard"
	card.Size = UDim2.new(1, 0, 0, 74)
	card.BackgroundColor3 = Color3.fromRGB(28, 25, 39)
	card.BackgroundTransparency = 0
	card.BorderSizePixel = 0
	card.ZIndex = 12
	card.LayoutOrder = cardConfig.layoutOrder or 0
	card.Parent = cardsFrame

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 10)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Thickness = 1
	cardStroke.Transparency = claimed and 0.1 or complete and 0.18 or 0.55
	cardStroke.Color = claimed and COLOR_READY or complete and COLOR_ACCENT or (isWeekly and COLOR_WEEKLY or COLOR_PANEL_EDGE)
	cardStroke.Parent = card

	local accent = Instance.new("Frame")
	accent.Size = UDim2.new(0, 6, 1, 0)
	accent.BackgroundColor3 = claimed and COLOR_READY or complete and COLOR_ACCENT or (isWeekly and COLOR_WEEKLY or Color3.fromRGB(88, 84, 104))
	accent.BorderSizePixel = 0
	accent.ZIndex = 13
	accent.Parent = card

	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 10)
	accentCorner.Parent = accent

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.fromOffset(208, 28)
	descLabel.Position = UDim2.fromOffset(14, 8)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = description
	descLabel.TextColor3 = COLOR_TEXT_MAIN
	descLabel.TextSize = 14
	descLabel.Font = Enum.Font.GothamBold
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.TextWrapped = true
	descLabel.ZIndex = 13
	descLabel.Parent = card

	local progressLabel = Instance.new("TextLabel")
	progressLabel.Size = UDim2.fromOffset(208, 16)
	progressLabel.Position = UDim2.fromOffset(14, 38)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Text = string.format("%d / %d", math.floor(progress), math.floor(target))
	progressLabel.TextColor3 = COLOR_TEXT_MUTED
	progressLabel.TextSize = 12
	progressLabel.Font = Enum.Font.Gotham
	progressLabel.TextXAlignment = Enum.TextXAlignment.Left
	progressLabel.ZIndex = 13
	progressLabel.Parent = card

	local progressBack = Instance.new("Frame")
	progressBack.Size = UDim2.fromOffset(208, 8)
	progressBack.Position = UDim2.fromOffset(14, 56)
	progressBack.BackgroundColor3 = COLOR_BAR_BG
	progressBack.BorderSizePixel = 0
	progressBack.ZIndex = 13
	progressBack.Parent = card

	local progressBackCorner = Instance.new("UICorner")
	progressBackCorner.CornerRadius = UDim.new(1, 0)
	progressBackCorner.Parent = progressBack

	local progressFill = Instance.new("Frame")
	progressFill.Size = UDim2.fromScale(fillRatio, 1)
	progressFill.BackgroundColor3 = complete and COLOR_READY or COLOR_BAR_FILL
	progressFill.BorderSizePixel = 0
	progressFill.ZIndex = 14
	progressFill.Parent = progressBack

	local progressFillCorner = Instance.new("UICorner")
	progressFillCorner.CornerRadius = UDim.new(1, 0)
	progressFillCorner.Parent = progressFill

	local stateBadge = Instance.new("TextLabel")
	stateBadge.Size = UDim2.fromOffset(72, 22)
	stateBadge.Position = UDim2.new(1, -86, 0, 10)
	stateBadge.BackgroundTransparency = 0
	stateBadge.BorderSizePixel = 0
	stateBadge.TextSize = 11
	stateBadge.Font = Enum.Font.GothamBold
	stateBadge.TextXAlignment = Enum.TextXAlignment.Center
	stateBadge.ZIndex = 13
	stateBadge.Parent = card

	local stateBadgeCorner = Instance.new("UICorner")
	stateBadgeCorner.CornerRadius = UDim.new(0, 6)
	stateBadgeCorner.Parent = stateBadge

	local claimButton = Instance.new("TextButton")
	claimButton.Name = "Claim"
	claimButton.Size = UDim2.fromOffset(86, 32)
	claimButton.Position = UDim2.new(1, -98, 0.5, -16)
	claimButton.BorderSizePixel = 0
	claimButton.TextSize = 14
	claimButton.Font = Enum.Font.GothamBold
	claimButton.AutoButtonColor = false
	claimButton.ZIndex = 14
	claimButton.Parent = card

	local claimCorner = Instance.new("UICorner")
	claimCorner.CornerRadius = UDim.new(0, 8)
	claimCorner.Parent = claimButton

	local function applyButtonState()
		local questClaimed = claimed
		if isWeekly then
			questClaimed = isWeeklyQuestClaimed() or claimed
		elseif questId ~= "" then
			questClaimed = isQuestClaimed(questId) or claimed
		end
		local questComplete = complete and not questClaimed

		if questClaimed then
			claimButton.Text = "Claimed"
			claimButton.BackgroundColor3 = COLOR_DISABLED
			claimButton.TextColor3 = Color3.fromRGB(210, 210, 210)
			claimButton.Active = false
			claimButton.AutoButtonColor = false
			stateBadge.Text = "CLAIMED"
			stateBadge.TextColor3 = Color3.fromRGB(230, 255, 230)
			stateBadge.BackgroundColor3 = COLOR_READY
		elseif questComplete then
			claimButton.Text = "Claim"
			claimButton.BackgroundColor3 = COLOR_READY
			claimButton.TextColor3 = Color3.fromRGB(255, 255, 255)
			claimButton.Active = true
			claimButton.AutoButtonColor = true
			stateBadge.Text = "READY"
			stateBadge.TextColor3 = Color3.fromRGB(40, 28, 0)
			stateBadge.BackgroundColor3 = COLOR_ACCENT
		else
			claimButton.Text = "Claim"
			claimButton.BackgroundColor3 = COLOR_DISABLED
			claimButton.TextColor3 = Color3.fromRGB(185, 185, 185)
			claimButton.Active = false
			claimButton.AutoButtonColor = false
			stateBadge.Text = isWeekly and "WEEKLY" or "LOCKED"
			stateBadge.TextColor3 = isWeekly and Color3.fromRGB(235, 242, 255) or Color3.fromRGB(195, 192, 204)
			stateBadge.BackgroundColor3 = isWeekly and COLOR_WEEKLY or Color3.fromRGB(58, 56, 68)
		end
	end

	claimButton.MouseButton1Click:Connect(function()
		if not complete then
			return
		end

		if isWeekly then
			if isWeeklyQuestClaimed() then
				return
			end
		elseif questId == "" or isQuestClaimed(questId) then
			return
		end

		local ok = pcall(function()
			if onClaim then
				onClaim()
			else
				claimQuest:FireServer(questId)
			end
		end)
		if not ok then
			return
		end

		if isWeekly then
			markWeeklyQuestClaimed(true)
		else
			markQuestClaimed(questId)
		end
		applyButtonState()
	end)

	applyButtonState()
	local cardEntry = {
		card = card,
		stroke = cardStroke,
		accent = accent,
		applyButtonState = applyButtonState,
	}
	if isWeekly then
		activeWeeklyCard = cardEntry
	elseif questId ~= "" then
		activeCardByQuestId[questId] = cardEntry
	end
	activeCards[#activeCards + 1] = card
end

local function renderQuestStatus(status)
	destroyQuestCards()

	if type(status) ~= "table" then
		setLoadingVisible(true, "")
		return
	end

	local normalized = normalizeStatus(status)
	if not normalized or (#normalized.quests == 0 and not normalized.weekly) then
		setLoadingVisible(true, normalized and normalized.day or "")
		return
	end

	syncQuestClaimState(normalized)

	setLoadingVisible(false, normalized.day)

	for index, quest in ipairs(normalized.quests) do
		if index > 3 then
			break
		end
		makeCard(quest, {
			layoutOrder = index,
		})
	end

	if normalized.weekly then
		makeCard(normalized.weekly, {
			isWeekly = true,
			isComplete = normalized.weekly.complete,
			isClaimed = normalized.weekly.claimed,
			layoutOrder = 4,
			onClaim = function()
				claimQuest:FireServer(normalized.weekly.id)
			end,
		})
	end
end

local function refreshQuestStatus()
	if refreshInFlight then
		return
	end

	refreshInFlight = true
	if panelOpen then
		setLoadingVisible(true, currentQuestDay)
	end

	local ok, result = pcall(function()
		return getQuestStatus:InvokeServer()
	end)

	if ok then
		updateQuestToggleSummary(result)
	end

	if panelOpen then
		if ok then
			renderQuestStatus(result)
		else
			warn("[QuestGui] GetQuestStatus failed: " .. tostring(result))
			setLoadingVisible(true, currentQuestDay)
		end
	end

	refreshInFlight = false
end

toggleButton.MouseButton1Click:Connect(function()
	setPanelOpen(not panelOpen, true)
	if panelOpen then
		task.spawn(refreshQuestStatus)
	end
end)

player:GetAttributeChangedSignal("QuestPanelOpen"):Connect(function()
	local attrOpen = player:GetAttribute("QuestPanelOpen") == true
	if attrOpen ~= panelOpen then
		setPanelOpen(attrOpen, false)
		if panelOpen then
			task.spawn(refreshQuestStatus)
		end
	end
end)

if questClaimResult then
	questClaimResult.OnClientEvent:Connect(showQuestClaimReward)
end

setPanelOpen(panelOpen, false)
if panelOpen then
	task.spawn(refreshQuestStatus)
end

task.spawn(function()
	while screenGui.Parent do
		if panelOpen then
			refreshQuestStatus()
		else
			local now = os.clock()
			if now - lastClosedSummaryRefresh >= CLOSED_SUMMARY_INTERVAL_SECONDS then
				lastClosedSummaryRefresh = now
				refreshQuestStatus()
			end
		end
		task.wait(REFRESH_INTERVAL_SECONDS)
	end
end)
