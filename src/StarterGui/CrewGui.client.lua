-- CrewGui.client.lua - compact digging crew panel
-- Place in: StarterGui/CrewGui (LocalScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function waitForChildTimeout(parent, childName, timeoutSeconds)
	if not parent then
		return nil
	end
	return parent:WaitForChild(childName, timeoutSeconds or 5)
end

local Remotes = waitForChildTimeout(ReplicatedStorage, "Remotes", 5)
if not Remotes then
	warn("[CrewGui] Remotes folder missing - crew UI disabled.")
	return
end

local CrewCreateEvent = waitForChildTimeout(Remotes, "CrewCreate", 5)
local CrewInviteEvent = waitForChildTimeout(Remotes, "CrewInvite", 5)
local CrewRespondInviteEvent = waitForChildTimeout(Remotes, "CrewRespondInvite", 5)
local CrewLeaveEvent = waitForChildTimeout(Remotes, "CrewLeave", 5)
local CrewUpdateEvent = waitForChildTimeout(Remotes, "CrewUpdate", 5)
local GetCrewStateFunc = waitForChildTimeout(Remotes, "GetCrewState", 5)

if not (CrewCreateEvent and CrewInviteEvent and CrewRespondInviteEvent and CrewLeaveEvent and CrewUpdateEvent and GetCrewStateFunc) then
	warn("[CrewGui] Required crew remotes missing - crew UI disabled.")
	return
end

local PANEL_BG = Color3.fromRGB(20, 22, 25)
local SECTION_BG = Color3.fromRGB(29, 32, 36)
local CARD_BG = Color3.fromRGB(36, 40, 45)
local TEXT_PRIMARY = Color3.fromRGB(235, 238, 240)
local TEXT_MUTED = Color3.fromRGB(158, 168, 176)
local ACCENT_GREEN = Color3.fromRGB(80, 220, 140)
local ACCENT_BLUE = Color3.fromRGB(80, 160, 255)
local ACCENT_RED = Color3.fromRGB(235, 95, 95)
local ACCENT_GOLD = Color3.fromRGB(255, 200, 70)

local state = {
	inCrew = false,
	members = {},
	nearbyPlayers = {},
	topCrews = {},
}

local function setCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

local function setStroke(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Color3.fromRGB(70, 76, 84)
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
	return stroke
end

local function clearRenderedChildren(container)
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UIListLayout")
			and not child:IsA("UIPadding")
			and not child:IsA("UICorner")
			and not child:IsA("UIStroke")
		then
			child:Destroy()
		end
	end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeepDigCrewGui"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 58
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "CrewButton"
toggleButton.Size = UDim2.new(0, 140, 0, 40)
toggleButton.AnchorPoint = Vector2.new(1, 1)
toggleButton.Position = UDim2.new(1, -20, 1, -112)
toggleButton.BackgroundColor3 = PANEL_BG
toggleButton.BackgroundTransparency = 0.12
toggleButton.BorderSizePixel = 0
toggleButton.Text = "Crew"
toggleButton.TextColor3 = TEXT_PRIMARY
toggleButton.TextSize = 18
toggleButton.Font = Enum.Font.GothamBold
toggleButton.AutoButtonColor = true
toggleButton.Parent = screenGui
setCorner(toggleButton, 8)
setStroke(toggleButton, Color3.fromRGB(80, 86, 96), 1, 0)

local pendingDot = Instance.new("Frame")
pendingDot.Name = "PendingDot"
pendingDot.Size = UDim2.new(0, 12, 0, 12)
pendingDot.AnchorPoint = Vector2.new(1, 0)
pendingDot.Position = UDim2.new(1, -8, 0, 8)
pendingDot.BackgroundColor3 = ACCENT_GOLD
pendingDot.BorderSizePixel = 0
pendingDot.Visible = false
pendingDot.Parent = toggleButton
setCorner(pendingDot, 12)

local panel = Instance.new("Frame")
panel.Name = "CrewPanel"
panel.Size = UDim2.new(0, 330, 0, 466)
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -20, 1, -160)
panel.BackgroundColor3 = PANEL_BG
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui
setCorner(panel, 10)
setStroke(panel, Color3.fromRGB(62, 68, 76), 1, 0)

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -54, 0, 38)
title.Position = UDim2.new(0, 14, 0, 8)
title.BackgroundTransparency = 1
title.Text = "Digging Crew"
title.TextColor3 = TEXT_PRIMARY
title.TextSize = 18
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.Size = UDim2.new(0, 30, 0, 30)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -10, 0, 10)
closeButton.BackgroundColor3 = Color3.fromRGB(54, 30, 34)
closeButton.BackgroundTransparency = 0.12
closeButton.BorderSizePixel = 0
closeButton.Text = "x"
closeButton.TextColor3 = TEXT_PRIMARY
closeButton.TextSize = 18
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = panel
setCorner(closeButton, 6)

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.Size = UDim2.new(1, -28, 0, 20)
statusLabel.Position = UDim2.new(0, 14, 0, 44)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = ""
statusLabel.TextColor3 = TEXT_MUTED
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.GothamMedium
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
statusLabel.Parent = panel

local invitePrompt = Instance.new("Frame")
invitePrompt.Name = "InvitePrompt"
invitePrompt.Size = UDim2.new(1, -28, 0, 58)
invitePrompt.Position = UDim2.new(0, 14, 0, 72)
invitePrompt.BackgroundColor3 = Color3.fromRGB(45, 39, 24)
invitePrompt.BackgroundTransparency = 0.04
invitePrompt.BorderSizePixel = 0
invitePrompt.Visible = false
invitePrompt.Parent = panel
setCorner(invitePrompt, 8)
setStroke(invitePrompt, Color3.fromRGB(128, 100, 45), 1, 0.1)

local inviteText = Instance.new("TextLabel")
inviteText.Name = "InviteText"
inviteText.Size = UDim2.new(1, -112, 1, 0)
inviteText.Position = UDim2.new(0, 10, 0, 0)
inviteText.BackgroundTransparency = 1
inviteText.Text = ""
inviteText.TextColor3 = TEXT_PRIMARY
inviteText.TextSize = 12
inviteText.Font = Enum.Font.GothamMedium
inviteText.TextXAlignment = Enum.TextXAlignment.Left
inviteText.TextWrapped = true
inviteText.Parent = invitePrompt

local acceptButton = Instance.new("TextButton")
acceptButton.Name = "Accept"
acceptButton.Size = UDim2.new(0, 48, 0, 28)
acceptButton.AnchorPoint = Vector2.new(1, 0.5)
acceptButton.Position = UDim2.new(1, -58, 0.5, 0)
acceptButton.BackgroundColor3 = ACCENT_GREEN
acceptButton.BorderSizePixel = 0
acceptButton.Text = "Join"
acceptButton.TextColor3 = Color3.fromRGB(14, 22, 18)
acceptButton.TextSize = 12
acceptButton.Font = Enum.Font.GothamBold
acceptButton.Parent = invitePrompt
setCorner(acceptButton, 6)

local declineButton = Instance.new("TextButton")
declineButton.Name = "Decline"
declineButton.Size = UDim2.new(0, 42, 0, 28)
declineButton.AnchorPoint = Vector2.new(1, 0.5)
declineButton.Position = UDim2.new(1, -10, 0.5, 0)
declineButton.BackgroundColor3 = ACCENT_RED
declineButton.BorderSizePixel = 0
declineButton.Text = "No"
declineButton.TextColor3 = Color3.fromRGB(28, 12, 12)
declineButton.TextSize = 12
declineButton.Font = Enum.Font.GothamBold
declineButton.Parent = invitePrompt
setCorner(declineButton, 6)

local actionButton = Instance.new("TextButton")
actionButton.Name = "Action"
actionButton.Size = UDim2.new(1, -28, 0, 36)
actionButton.Position = UDim2.new(0, 14, 0, 140)
actionButton.BackgroundColor3 = ACCENT_BLUE
actionButton.BorderSizePixel = 0
actionButton.Text = "Create Crew"
actionButton.TextColor3 = Color3.fromRGB(12, 20, 34)
actionButton.TextSize = 14
actionButton.Font = Enum.Font.GothamBold
actionButton.AutoButtonColor = true
actionButton.Parent = panel
setCorner(actionButton, 8)

local progressFrame = Instance.new("Frame")
progressFrame.Name = "CrewProgress"
progressFrame.Size = UDim2.new(1, -28, 0, 52)
progressFrame.Position = UDim2.new(0, 14, 0, 136)
progressFrame.BackgroundColor3 = SECTION_BG
progressFrame.BackgroundTransparency = 0.08
progressFrame.BorderSizePixel = 0
progressFrame.Visible = false
progressFrame.Parent = panel
setCorner(progressFrame, 8)

local levelLabel = Instance.new("TextLabel")
levelLabel.Name = "Level"
levelLabel.Size = UDim2.new(0.5, -10, 0, 20)
levelLabel.Position = UDim2.new(0, 10, 0, 6)
levelLabel.BackgroundTransparency = 1
levelLabel.Text = "Level 1"
levelLabel.TextColor3 = TEXT_PRIMARY
levelLabel.TextSize = 13
levelLabel.Font = Enum.Font.GothamBold
levelLabel.TextXAlignment = Enum.TextXAlignment.Left
levelLabel.Parent = progressFrame

local bonusLabel = Instance.new("TextLabel")
bonusLabel.Name = "Bonus"
bonusLabel.Size = UDim2.new(0.5, -10, 0, 20)
bonusLabel.Position = UDim2.new(0.5, 0, 0, 6)
bonusLabel.BackgroundTransparency = 1
bonusLabel.Text = "+1 fragments"
bonusLabel.TextColor3 = ACCENT_GREEN
bonusLabel.TextSize = 12
bonusLabel.Font = Enum.Font.GothamBold
bonusLabel.TextXAlignment = Enum.TextXAlignment.Right
bonusLabel.Parent = progressFrame

local progressTrack = Instance.new("Frame")
progressTrack.Name = "Track"
progressTrack.Size = UDim2.new(1, -20, 0, 10)
progressTrack.Position = UDim2.new(0, 10, 0, 29)
progressTrack.BackgroundColor3 = Color3.fromRGB(16, 18, 20)
progressTrack.BorderSizePixel = 0
progressTrack.Parent = progressFrame
setCorner(progressTrack, 5)

local progressFill = Instance.new("Frame")
progressFill.Name = "Fill"
progressFill.Size = UDim2.new(0, 0, 1, 0)
progressFill.BackgroundColor3 = ACCENT_GOLD
progressFill.BorderSizePixel = 0
progressFill.Parent = progressTrack
setCorner(progressFill, 5)

local progressText = Instance.new("TextLabel")
progressText.Name = "ProgressText"
progressText.Size = UDim2.new(1, -20, 0, 12)
progressText.Position = UDim2.new(0, 10, 0, 39)
progressText.BackgroundTransparency = 1
progressText.Text = "0/25 XP"
progressText.TextColor3 = TEXT_MUTED
progressText.TextSize = 10
progressText.Font = Enum.Font.GothamMedium
progressText.TextXAlignment = Enum.TextXAlignment.Left
progressText.Parent = progressFrame

local memberHeader = Instance.new("TextLabel")
memberHeader.Name = "MemberHeader"
memberHeader.Size = UDim2.new(1, -28, 0, 20)
memberHeader.Position = UDim2.new(0, 14, 0, 186)
memberHeader.BackgroundTransparency = 1
memberHeader.Text = "Members"
memberHeader.TextColor3 = TEXT_PRIMARY
memberHeader.TextSize = 13
memberHeader.Font = Enum.Font.GothamBold
memberHeader.TextXAlignment = Enum.TextXAlignment.Left
memberHeader.Parent = panel

local memberList = Instance.new("ScrollingFrame")
memberList.Name = "Members"
memberList.Size = UDim2.new(1, -28, 0, 82)
memberList.Position = UDim2.new(0, 14, 0, 208)
memberList.BackgroundColor3 = SECTION_BG
memberList.BackgroundTransparency = 0.08
memberList.BorderSizePixel = 0
memberList.ScrollBarThickness = 4
memberList.CanvasSize = UDim2.new(0, 0, 0, 0)
memberList.Parent = panel
setCorner(memberList, 8)

local memberLayout = Instance.new("UIListLayout")
memberLayout.Padding = UDim.new(0, 4)
memberLayout.SortOrder = Enum.SortOrder.LayoutOrder
memberLayout.Parent = memberList

local memberPadding = Instance.new("UIPadding")
memberPadding.PaddingTop = UDim.new(0, 6)
memberPadding.PaddingBottom = UDim.new(0, 6)
memberPadding.PaddingLeft = UDim.new(0, 6)
memberPadding.PaddingRight = UDim.new(0, 6)
memberPadding.Parent = memberList

local nearbyHeader = Instance.new("TextLabel")
nearbyHeader.Name = "NearbyHeader"
nearbyHeader.Size = UDim2.new(1, -28, 0, 20)
nearbyHeader.Position = UDim2.new(0, 14, 0, 300)
nearbyHeader.BackgroundTransparency = 1
nearbyHeader.Text = "Nearby"
nearbyHeader.TextColor3 = TEXT_PRIMARY
nearbyHeader.TextSize = 13
nearbyHeader.Font = Enum.Font.GothamBold
nearbyHeader.TextXAlignment = Enum.TextXAlignment.Left
nearbyHeader.Parent = panel

local nearbyList = Instance.new("ScrollingFrame")
nearbyList.Name = "Nearby"
nearbyList.Size = UDim2.new(1, -28, 0, 76)
nearbyList.Position = UDim2.new(0, 14, 0, 322)
nearbyList.BackgroundColor3 = SECTION_BG
nearbyList.BackgroundTransparency = 0.08
nearbyList.BorderSizePixel = 0
nearbyList.ScrollBarThickness = 4
nearbyList.CanvasSize = UDim2.new(0, 0, 0, 0)
nearbyList.Parent = panel
setCorner(nearbyList, 8)

local nearbyLayout = Instance.new("UIListLayout")
nearbyLayout.Padding = UDim.new(0, 4)
nearbyLayout.SortOrder = Enum.SortOrder.LayoutOrder
nearbyLayout.Parent = nearbyList

local nearbyPadding = Instance.new("UIPadding")
nearbyPadding.PaddingTop = UDim.new(0, 6)
nearbyPadding.PaddingBottom = UDim.new(0, 6)
nearbyPadding.PaddingLeft = UDim.new(0, 6)
nearbyPadding.PaddingRight = UDim.new(0, 6)
nearbyPadding.Parent = nearbyList

local leaderboardHeader = Instance.new("TextLabel")
leaderboardHeader.Name = "LeaderboardHeader"
leaderboardHeader.Size = UDim2.new(1, -28, 0, 20)
leaderboardHeader.Position = UDim2.new(0, 14, 0, 186)
leaderboardHeader.BackgroundTransparency = 1
leaderboardHeader.Text = "Top Crews"
leaderboardHeader.TextColor3 = TEXT_PRIMARY
leaderboardHeader.TextSize = 13
leaderboardHeader.Font = Enum.Font.GothamBold
leaderboardHeader.TextXAlignment = Enum.TextXAlignment.Left
leaderboardHeader.Parent = panel

local leaderboardList = Instance.new("ScrollingFrame")
leaderboardList.Name = "TopCrews"
leaderboardList.Size = UDim2.new(1, -28, 0, 64)
leaderboardList.Position = UDim2.new(0, 14, 0, 208)
leaderboardList.BackgroundColor3 = SECTION_BG
leaderboardList.BackgroundTransparency = 0.08
leaderboardList.BorderSizePixel = 0
leaderboardList.ScrollBarThickness = 4
leaderboardList.CanvasSize = UDim2.new(0, 0, 0, 0)
leaderboardList.Parent = panel
setCorner(leaderboardList, 8)

local leaderboardLayout = Instance.new("UIListLayout")
leaderboardLayout.Padding = UDim.new(0, 4)
leaderboardLayout.SortOrder = Enum.SortOrder.LayoutOrder
leaderboardLayout.Parent = leaderboardList

local leaderboardPadding = Instance.new("UIPadding")
leaderboardPadding.PaddingTop = UDim.new(0, 6)
leaderboardPadding.PaddingBottom = UDim.new(0, 6)
leaderboardPadding.PaddingLeft = UDim.new(0, 6)
leaderboardPadding.PaddingRight = UDim.new(0, 6)
leaderboardPadding.Parent = leaderboardList

local function makeRow(parent, text, rightText, buttonText, buttonColor, onClick)
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.Size = UDim2.new(1, -4, 0, 30)
	row.BackgroundColor3 = CARD_BG
	row.BackgroundTransparency = 0.05
	row.BorderSizePixel = 0
	row.Parent = parent
	setCorner(row, 6)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, buttonText and -118 or -8, 1, 0)
	label.Position = UDim2.new(0, 8, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = TEXT_PRIMARY
	label.TextSize = 12
	label.Font = Enum.Font.GothamMedium
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = row

	if rightText and rightText ~= "" then
		local detail = Instance.new("TextLabel")
		detail.Size = UDim2.new(0, 52, 1, 0)
		detail.AnchorPoint = Vector2.new(1, 0)
		detail.Position = UDim2.new(1, buttonText and -60 or -8, 0, 0)
		detail.BackgroundTransparency = 1
		detail.Text = rightText
		detail.TextColor3 = TEXT_MUTED
		detail.TextSize = 11
		detail.Font = Enum.Font.GothamMedium
		detail.TextXAlignment = Enum.TextXAlignment.Right
		detail.Parent = row
	end

	if buttonText then
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0, 52, 0, 22)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -6, 0.5, 0)
		button.BackgroundColor3 = buttonColor
		button.BorderSizePixel = 0
		button.Text = buttonText
		button.TextColor3 = Color3.fromRGB(12, 18, 24)
		button.TextSize = 11
		button.Font = Enum.Font.GothamBold
		button.AutoButtonColor = true
		button.Parent = row
		setCorner(button, 5)
		button.MouseButton1Click:Connect(onClick)
	end

	return row
end

local function makeEmptyRow(parent, text)
	makeRow(parent, text, "", nil, nil, nil)
end

local function makeLeaderboardRow(parent, crew)
	local row = Instance.new("Frame")
	row.Name = "CrewRank"
	row.Size = UDim2.new(1, -4, 0, 30)
	row.BackgroundColor3 = crew.isPlayerCrew and Color3.fromRGB(56, 49, 31) or CARD_BG
	row.BackgroundTransparency = crew.isPlayerCrew and 0 or 0.05
	row.BorderSizePixel = 0
	row.Parent = parent
	setCorner(row, 6)
	if crew.isPlayerCrew then
		setStroke(row, ACCENT_GOLD, 1, 0.05)
	end

	local leaderText = "#" .. tostring(crew.rank or 0) .. " " .. tostring(crew.leaderDisplayName or crew.leaderName or "Crew")
	if crew.isPlayerCrew then
		leaderText = leaderText .. " (Your Crew)"
	end

	local leaderLabel = Instance.new("TextLabel")
	leaderLabel.Size = UDim2.new(1, -128, 1, 0)
	leaderLabel.Position = UDim2.new(0, 8, 0, 0)
	leaderLabel.BackgroundTransparency = 1
	leaderLabel.Text = leaderText
	leaderLabel.TextColor3 = TEXT_PRIMARY
	leaderLabel.TextSize = 11
	leaderLabel.Font = crew.isPlayerCrew and Enum.Font.GothamBold or Enum.Font.GothamMedium
	leaderLabel.TextXAlignment = Enum.TextXAlignment.Left
	leaderLabel.TextTruncate = Enum.TextTruncate.AtEnd
	leaderLabel.Parent = row

	local memberText = tostring(crew.memberCount or 0) .. "/" .. tostring(crew.maxSize or 0)
	local detailText = "Lv " .. tostring(crew.level or 1) .. " | " .. tostring(crew.xp or 0) .. " XP | " .. memberText

	local detailLabel = Instance.new("TextLabel")
	detailLabel.Size = UDim2.new(0, 118, 1, 0)
	detailLabel.AnchorPoint = Vector2.new(1, 0)
	detailLabel.Position = UDim2.new(1, -8, 0, 0)
	detailLabel.BackgroundTransparency = 1
	detailLabel.Text = detailText
	detailLabel.TextColor3 = crew.isPlayerCrew and ACCENT_GOLD or TEXT_MUTED
	detailLabel.TextSize = 10
	detailLabel.Font = Enum.Font.GothamBold
	detailLabel.TextXAlignment = Enum.TextXAlignment.Right
	detailLabel.TextTruncate = Enum.TextTruncate.AtEnd
	detailLabel.Parent = row
end

local function updateCanvas(frame, layout)
	frame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 12)
end

local function clampUnit(value)
	if value < 0 then
		return 0
	end
	if value > 1 then
		return 1
	end

	return value
end

local render

local function requestState()
	local ok, result = pcall(function()
		return GetCrewStateFunc:InvokeServer()
	end)
	if ok and type(result) == "table" then
		state = result
		render()
	end
end

render = function()
	local members = state.members or {}
	local nearbyPlayers = state.nearbyPlayers or {}
	local topCrews = state.topCrews or {}
	local maxSize = state.maxSize or 10
	local bonus = state.fragmentBonus or 0
	local radius = state.coopRadius or 0
	local pendingInvite = state.pendingInvite
	local level = state.crewLevel or 1
	local xpInLevel = state.crewXPInLevel or 0
	local xpForNextLevel = state.crewXPForNextLevel or 0

	pendingDot.Visible = pendingInvite ~= nil
	toggleButton.Text = state.inCrew and ("Crew " .. tostring(#members) .. "/" .. tostring(maxSize)) or "Crew"

	if state.inCrew then
		statusLabel.Text = "Level " .. tostring(level) .. " crew - +" .. tostring(bonus) .. " fragments within " .. tostring(radius) .. " studs"
		actionButton.Text = "Leave Crew"
		actionButton.BackgroundColor3 = ACCENT_RED
	else
		statusLabel.Text = "Create a crew, then invite nearby players."
		actionButton.Text = "Create Crew"
		actionButton.BackgroundColor3 = ACCENT_BLUE
	end

	if pendingInvite then
		invitePrompt.Visible = true
		inviteText.Text = pendingInvite.fromDisplayName .. " invited you to a crew."
		actionButton.Position = UDim2.new(0, 14, 0, 140)
	else
		invitePrompt.Visible = false
		actionButton.Position = UDim2.new(0, 14, 0, 92)
	end

	local actionY = pendingInvite and 140 or 92
	local progressY = actionY + 46
	local progressHeight = state.inCrew and 52 or 0
	local progressGap = state.inCrew and 10 or 0
	local topOffset = progressY + progressHeight + progressGap
	local compactLayout = topOffset >= 240
	local leaderboardHeight = compactLayout and 54 or 64
	local memberHeight = compactLayout and 34 or (state.inCrew and 48 or 54)
	local nearbyHeight = compactLayout and 42 or (state.inCrew and 58 or 70)
	progressFrame.Position = UDim2.new(0, 14, 0, progressY)
	progressFrame.Visible = state.inCrew
	levelLabel.Text = "Level " .. tostring(level)
	bonusLabel.Text = "+" .. tostring(bonus) .. " fragments"
	if xpForNextLevel > 0 then
		progressFill.Size = UDim2.new(clampUnit(xpInLevel / xpForNextLevel), 0, 1, 0)
		progressText.Text = tostring(xpInLevel) .. "/" .. tostring(xpForNextLevel) .. " XP"
	else
		progressFill.Size = UDim2.new(1, 0, 1, 0)
		progressText.Text = tostring(state.crewXP or 0) .. " XP - Max level"
	end

	leaderboardHeader.Position = UDim2.new(0, 14, 0, topOffset)
	leaderboardList.Position = UDim2.new(0, 14, 0, topOffset + 22)
	leaderboardList.Size = UDim2.new(1, -28, 0, leaderboardHeight)
	memberHeader.Position = UDim2.new(0, 14, 0, topOffset + leaderboardHeight + 30)
	memberList.Position = UDim2.new(0, 14, 0, topOffset + leaderboardHeight + 52)
	memberList.Size = UDim2.new(1, -28, 0, memberHeight)
	nearbyHeader.Position = UDim2.new(0, 14, 0, topOffset + leaderboardHeight + memberHeight + 60)
	nearbyList.Position = UDim2.new(0, 14, 0, topOffset + leaderboardHeight + memberHeight + 82)
	nearbyList.Size = UDim2.new(1, -28, 0, nearbyHeight)

	clearRenderedChildren(leaderboardList)
	if #topCrews == 0 then
		makeEmptyRow(leaderboardList, "No active crews yet.")
	else
		for _, crew in ipairs(topCrews) do
			makeLeaderboardRow(leaderboardList, crew)
		end
	end
	updateCanvas(leaderboardList, leaderboardLayout)

	clearRenderedChildren(memberList)
	if #members == 0 then
		makeEmptyRow(memberList, "No crew yet.")
	else
		for _, member in ipairs(members) do
			local suffix = member.isOwner and "Leader" or ""
			makeRow(memberList, member.displayName, suffix, nil, nil, nil)
		end
	end
	updateCanvas(memberList, memberLayout)

	clearRenderedChildren(nearbyList)
	if not state.inCrew then
		makeEmptyRow(nearbyList, "Create a crew to send invites.")
	elseif #nearbyPlayers == 0 then
		makeEmptyRow(nearbyList, "No invite-ready players nearby.")
	else
		for _, nearby in ipairs(nearbyPlayers) do
			makeRow(nearbyList, nearby.displayName, tostring(nearby.distance) .. " st", "Invite", ACCENT_GREEN, function()
				CrewInviteEvent:FireServer(nearby.userId)
				task.delay(0.2, requestState)
			end)
		end
	end
	updateCanvas(nearbyList, nearbyLayout)
end

toggleButton.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		requestState()
	end
end)

closeButton.MouseButton1Click:Connect(function()
	panel.Visible = false
end)

actionButton.MouseButton1Click:Connect(function()
	if state.inCrew then
		CrewLeaveEvent:FireServer()
	else
		CrewCreateEvent:FireServer()
	end
	task.delay(0.2, requestState)
end)

acceptButton.MouseButton1Click:Connect(function()
	CrewRespondInviteEvent:FireServer(true)
	task.delay(0.2, requestState)
end)

declineButton.MouseButton1Click:Connect(function()
	CrewRespondInviteEvent:FireServer(false)
	task.delay(0.2, requestState)
end)

CrewUpdateEvent.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" then
		state = payload
		if state.pendingInvite then
			panel.Visible = true
		end
		render()
	end
end)

Players.PlayerAdded:Connect(function()
	if panel.Visible then
		task.delay(0.4, requestState)
	end
end)

Players.PlayerRemoving:Connect(function()
	task.delay(0.2, requestState)
end)

task.spawn(function()
	while true do
		task.wait(3)
		if panel.Visible then
			requestState()
		end
	end
end)

requestState()
