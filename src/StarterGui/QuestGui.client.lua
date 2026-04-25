local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local REMOTE_WAIT_SECONDS = 5
local REFRESH_INTERVAL_SECONDS = 5

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
local refreshInFlight = false

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

local function destroyQuestCards()
	for _, card in ipairs(activeCards) do
		if card and card.Parent then
			card:Destroy()
		end
	end
	activeCards = {}
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
toggleButton.Size = UDim2.fromOffset(120, 40)
toggleButton.Position = UDim2.new(1, -136, 1, -56)
toggleButton.BackgroundColor3 = Color3.fromRGB(44, 42, 58)
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
toggleStroke.Color = Color3.fromRGB(68, 65, 82)
toggleStroke.Thickness = 1
toggleStroke.Transparency = 0.2
toggleStroke.Parent = toggleButton

local function updateToggleAppearance()
	if panelOpen then
		toggleButton.Text = "Quests"
		toggleButton.BackgroundColor3 = Color3.fromRGB(60, 54, 76)
	else
		toggleButton.Text = "Quests"
		toggleButton.BackgroundColor3 = Color3.fromRGB(44, 42, 58)
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

setPanelOpen(panelOpen, false)
if panelOpen then
	task.spawn(refreshQuestStatus)
end

task.spawn(function()
	while screenGui.Parent do
		if panelOpen then
			refreshQuestStatus()
		end
		task.wait(REFRESH_INTERVAL_SECONDS)
	end
end)
