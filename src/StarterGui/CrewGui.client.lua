-- CrewGui.client.lua - compact digging crew panel
-- Place in: StarterGui/CrewGui (LocalScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local LOCAL_PLAY_SOUND_NAME = "DeepDigLocalPlaySound"

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
local CrewMailboxSendEvent = waitForChildTimeout(Remotes, "CrewMailboxSend", 5)
local CrewMailboxClaimEvent = waitForChildTimeout(Remotes, "CrewMailboxClaim", 5)
local GetCrewStateFunc = waitForChildTimeout(Remotes, "GetCrewState", 5)
local GetPlayerDataFunc = waitForChildTimeout(Remotes, "GetPlayerData", 5)

if not (CrewCreateEvent and CrewInviteEvent and CrewRespondInviteEvent and CrewLeaveEvent and CrewUpdateEvent and CrewMailboxSendEvent and CrewMailboxClaimEvent and GetCrewStateFunc and GetPlayerDataFunc) then
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
local CREW_MARKER_GUI_NAME = "DeepDigCrewMarker"
local CREW_MARKER_HIGHLIGHT_NAME = "DeepDigCrewHighlight"
local COOP_RADIUS_MARKER_NAME = "DeepDigLocalCoopRadius"
local COOP_RADIUS_MARKER_HEIGHT = 0.08
local COOP_RADIUS_MARKER_Y_OFFSET = 0.04
local COOP_RADIUS_INACTIVE_COLOR = Color3.fromRGB(90, 108, 118)
local COOP_LINK_STYLE = {
	prefix = "DeepDigCrewCoop",
	localAttachmentName = "DeepDigCrewCoopLocalAttachment",
	crewmateAttachmentName = "DeepDigCrewCoopMateAttachment",
	beamName = "DeepDigCrewCoopBeam",
}

local RARITY_COLORS = {
	Common = Color3.fromRGB(180, 180, 180),
	Uncommon = Color3.fromRGB(30, 200, 30),
	Rare = Color3.fromRGB(30, 100, 255),
	Epic = Color3.fromRGB(160, 50, 255),
	Legendary = Color3.fromRGB(255, 170, 0),
	Mythic = Color3.fromRGB(255, 50, 50),
}

local state = {
	inCrew = false,
	members = {},
	nearbyPlayers = {},
	topCrews = {},
	mailboxItems = {},
}
local coopBonusState = {
	active = false,
	partnerName = nil,
}
local currentInventory = {}
local selectedMailboxRecipientUserId = nil
local levelUpBurstSequence = 0
local activeLevelUpBurst = nil
local lastLevelUpKey = nil
local mailboxClaimBurstSequence = 0
local activeMailboxClaimBurst = nil
local lastMailboxClaimKey = nil
local mailboxSentBurstSequence = 0
local activeMailboxSentBurst = nil
local lastMailboxSentKey = nil
local mailboxReceivedBurstSequence = 0
local activeMailboxReceivedBurst = nil
local lastMailboxReceivedKey = nil
local activeCrewMembersByUserId = {}
local crewMarkerConnections = {}
local coopRadiusMarker = nil
local crewCoopLinkState = {
	links = {},
}
local refreshCoopBonusState

local LocalPlaySound = SoundService:FindFirstChild(LOCAL_PLAY_SOUND_NAME)
if not LocalPlaySound then
	LocalPlaySound = Instance.new("BindableEvent")
	LocalPlaySound.Name = LOCAL_PLAY_SOUND_NAME
	LocalPlaySound.Parent = SoundService
end

local function getRarityColor(rarity)
	return RARITY_COLORS[rarity] or TEXT_MUTED
end

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

local function clearLevelUpBurst(sequence)
	if sequence and sequence ~= levelUpBurstSequence then
		return
	end

	if activeLevelUpBurst then
		activeLevelUpBurst:Destroy()
		activeLevelUpBurst = nil
	end
end

local function clearMailboxClaimBurst(sequence)
	if sequence and sequence ~= mailboxClaimBurstSequence then
		return
	end

	if activeMailboxClaimBurst then
		activeMailboxClaimBurst:Destroy()
		activeMailboxClaimBurst = nil
	end
end

local function clearMailboxSentBurst(sequence)
	if sequence and sequence ~= mailboxSentBurstSequence then
		return
	end

	if activeMailboxSentBurst then
		activeMailboxSentBurst:Destroy()
		activeMailboxSentBurst = nil
	end
end

local function clearMailboxReceivedBurst(sequence)
	if sequence and sequence ~= mailboxReceivedBurstSequence then
		return
	end

	if activeMailboxReceivedBurst then
		activeMailboxReceivedBurst:Destroy()
		activeMailboxReceivedBurst = nil
	end
end

local function destroyCrewMarkerInstances(character)
	if not character then
		return
	end

	local highlight = character:FindFirstChild(CREW_MARKER_HIGHLIGHT_NAME)
	if highlight then
		highlight:Destroy()
	end

	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	local markerParent = head or root
	if markerParent then
		local marker = markerParent:FindFirstChild(CREW_MARKER_GUI_NAME)
		if marker then
			marker:Destroy()
		end
	end

	if head and root then
		local rootMarker = root:FindFirstChild(CREW_MARKER_GUI_NAME)
		if rootMarker then
			rootMarker:Destroy()
		end
	end
end

local function clearCrewMarker(userId, shouldDisconnect)
	local crewmate = Players:GetPlayerByUserId(userId)
	if crewmate then
		destroyCrewMarkerInstances(crewmate.Character)
	end

	if shouldDisconnect and crewMarkerConnections[userId] then
		crewMarkerConnections[userId]:Disconnect()
		crewMarkerConnections[userId] = nil
	end

	activeCrewMembersByUserId[userId] = nil
end

local function getCrewMarkerText(member)
	local displayName = tostring(member.displayName or member.name or "Crewmate")
	local level = tonumber(state.crewLevel) or 1
	return displayName, "Crew Lv " .. tostring(math.floor(level))
end

local function applyCrewMarker(crewmate, member)
	if not crewmate or crewmate == player then
		return
	end

	local character = crewmate.Character
	if not character then
		return
	end

	local adornPart = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not adornPart then
		return
	end

	destroyCrewMarkerInstances(character)

	local highlight = Instance.new("Highlight")
	highlight.Name = CREW_MARKER_HIGHLIGHT_NAME
	highlight.Adornee = character
	highlight.FillColor = ACCENT_GREEN
	highlight.FillTransparency = 0.9
	highlight.OutlineColor = ACCENT_GREEN
	highlight.OutlineTransparency = 0.42
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character

	local markerGui = Instance.new("BillboardGui")
	markerGui.Name = CREW_MARKER_GUI_NAME
	markerGui.Adornee = adornPart
	markerGui.AlwaysOnTop = false
	markerGui.LightInfluence = 0.2
	markerGui.MaxDistance = 125
	markerGui.Size = UDim2.fromOffset(98, 34)
	markerGui.StudsOffsetWorldSpace = Vector3.new(0, 2.9, 0)
	markerGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	markerGui.Parent = adornPart

	local frame = Instance.new("Frame")
	frame.Name = "Tag"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(16, 24, 20)
	frame.BackgroundTransparency = 0.18
	frame.BorderSizePixel = 0
	frame.Parent = markerGui
	setCorner(frame, 6)
	setStroke(frame, ACCENT_GREEN, 1, 0.38)

	local displayName, levelText = getCrewMarkerText(member)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, -10, 0, 17)
	nameLabel.Position = UDim2.fromOffset(5, 2)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = displayName
	nameLabel.TextColor3 = TEXT_PRIMARY
	nameLabel.TextSize = 10
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = frame

	local tagLabel = Instance.new("TextLabel")
	tagLabel.Name = "CrewTag"
	tagLabel.Size = UDim2.new(1, -10, 0, 13)
	tagLabel.Position = UDim2.fromOffset(5, 18)
	tagLabel.BackgroundTransparency = 1
	tagLabel.Text = levelText
	tagLabel.TextColor3 = Color3.fromRGB(178, 255, 206)
	tagLabel.TextSize = 9
	tagLabel.Font = Enum.Font.GothamMedium
	tagLabel.TextXAlignment = Enum.TextXAlignment.Center
	tagLabel.TextTruncate = Enum.TextTruncate.AtEnd
	tagLabel.Parent = frame
end

local function ensureCrewMarkerConnection(crewmate)
	if crewMarkerConnections[crewmate.UserId] then
		return
	end

	crewMarkerConnections[crewmate.UserId] = crewmate.CharacterAdded:Connect(function()
		task.wait(0.25)
		local member = activeCrewMembersByUserId[crewmate.UserId]
		if member then
			applyCrewMarker(crewmate, member)
		end
		refreshCoopBonusState(true)
	end)
end

local function refreshCrewMarkers(members)
	local wanted = {}
	local staleUserIds = {}

	if state.inCrew then
		for _, member in ipairs(members) do
			local userId = tonumber(member.userId)
			if userId and userId ~= player.UserId then
				local crewmate = Players:GetPlayerByUserId(userId)
				if crewmate then
					wanted[userId] = member
					activeCrewMembersByUserId[userId] = member
					ensureCrewMarkerConnection(crewmate)
					applyCrewMarker(crewmate, member)
				end
			end
		end
	end

	for userId in pairs(activeCrewMembersByUserId) do
		if not wanted[userId] then
			table.insert(staleUserIds, userId)
		end
	end

	for userId in pairs(crewMarkerConnections) do
		if not wanted[userId] then
			table.insert(staleUserIds, userId)
		end
	end

	for _, userId in ipairs(staleUserIds) do
		clearCrewMarker(userId, true)
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
toggleButton.TextSize = 16
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextYAlignment = Enum.TextYAlignment.Top
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

local coopBadge = Instance.new("Frame")
coopBadge.Name = "CoopBadge"
coopBadge.Size = UDim2.fromOffset(58, 14)
coopBadge.AnchorPoint = Vector2.new(1, 1)
coopBadge.Position = UDim2.new(1, -8, 1, -5)
coopBadge.BackgroundColor3 = SECTION_BG
coopBadge.BackgroundTransparency = 0.18
coopBadge.BorderSizePixel = 0
coopBadge.Visible = false
coopBadge.Parent = toggleButton
setCorner(coopBadge, 5)

local coopBadgeStroke = setStroke(coopBadge, Color3.fromRGB(80, 86, 96), 1, 0.25)

local coopBadgeLabel = Instance.new("TextLabel")
coopBadgeLabel.Name = "Label"
coopBadgeLabel.Size = UDim2.fromScale(1, 1)
coopBadgeLabel.BackgroundTransparency = 1
coopBadgeLabel.Text = "+Frag"
coopBadgeLabel.TextColor3 = TEXT_MUTED
coopBadgeLabel.TextSize = 9
coopBadgeLabel.Font = Enum.Font.GothamBlack
coopBadgeLabel.TextXAlignment = Enum.TextXAlignment.Center
coopBadgeLabel.TextYAlignment = Enum.TextYAlignment.Center
coopBadgeLabel.Parent = coopBadge

local function showLevelUpBurst(level, fragmentBonus)
	levelUpBurstSequence = levelUpBurstSequence + 1
	local sequence = levelUpBurstSequence
	clearLevelUpBurst()

	local burst = Instance.new("Frame")
	burst.Name = "CrewLevelUpBurst"
	burst.AnchorPoint = Vector2.new(1, 1)
	burst.Position = UDim2.new(1, -20, 1, -158)
	burst.Size = UDim2.fromOffset(214, 58)
	burst.BackgroundColor3 = Color3.fromRGB(42, 34, 22)
	burst.BackgroundTransparency = 1
	burst.BorderSizePixel = 0
	burst.ZIndex = 80
	burst.Parent = screenGui
	activeLevelUpBurst = burst
	setCorner(burst, 8)

	local stroke = setStroke(burst, ACCENT_GOLD, 1, 1)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -18, 0, 24)
	titleLabel.Position = UDim2.fromOffset(9, 7)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Crew Level Up"
	titleLabel.TextColor3 = Color3.fromRGB(255, 234, 168)
	titleLabel.TextTransparency = 1
	titleLabel.TextSize = 15
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.ZIndex = 81
	titleLabel.Parent = burst

	local detailLabel = Instance.new("TextLabel")
	detailLabel.Name = "Detail"
	detailLabel.Size = UDim2.new(1, -18, 0, 20)
	detailLabel.Position = UDim2.fromOffset(9, 30)
	detailLabel.BackgroundTransparency = 1
	detailLabel.Text = "Level " .. tostring(level) .. " - +" .. tostring(fragmentBonus) .. " fragments"
	detailLabel.TextColor3 = Color3.fromRGB(212, 255, 224)
	detailLabel.TextTransparency = 1
	detailLabel.TextSize = 12
	detailLabel.Font = Enum.Font.GothamBold
	detailLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailLabel.TextTruncate = Enum.TextTruncate.AtEnd
	detailLabel.ZIndex = 81
	detailLabel.Parent = burst

	local scale = Instance.new("UIScale")
	scale.Scale = 0.9
	scale.Parent = burst

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("crew_level_up")
	end

	TweenService:Create(burst, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.08,
		Position = UDim2.new(1, -20, 1, -166),
	}):Play()
	TweenService:Create(stroke, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 0.08,
	}):Play()
	TweenService:Create(titleLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
	TweenService:Create(detailLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	task.delay(1.15, function()
		if sequence ~= levelUpBurstSequence or activeLevelUpBurst ~= burst then
			return
		end

		TweenService:Create(burst, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -20, 1, -174),
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
		}):Play()
		TweenService:Create(titleLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		}):Play()
		TweenService:Create(detailLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		}):Play()
	end)

	task.delay(1.5, function()
		clearLevelUpBurst(sequence)
	end)
end

local function showMailboxClaimBurst(itemName, senderName, rarity)
	mailboxClaimBurstSequence = mailboxClaimBurstSequence + 1
	local sequence = mailboxClaimBurstSequence
	clearMailboxClaimBurst()

	local rarityColor = getRarityColor(rarity)
	local burst = Instance.new("Frame")
	burst.Name = "CrewMailboxClaimBurst"
	burst.AnchorPoint = Vector2.new(1, 1)
	burst.Position = UDim2.new(1, -20, 1, -224)
	burst.Size = UDim2.fromOffset(236, 64)
	burst.BackgroundColor3 = Color3.fromRGB(24, 34, 32)
	burst.BackgroundTransparency = 1
	burst.BorderSizePixel = 0
	burst.ZIndex = 80
	burst.Parent = screenGui
	activeMailboxClaimBurst = burst
	setCorner(burst, 8)

	local stroke = setStroke(burst, rarityColor, 1, 1)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -18, 0, 22)
	titleLabel.Position = UDim2.fromOffset(9, 7)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Crew Mail Claimed"
	titleLabel.TextColor3 = rarityColor
	titleLabel.TextTransparency = 1
	titleLabel.TextSize = 14
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.ZIndex = 81
	titleLabel.Parent = burst

	local detailLabel = Instance.new("TextLabel")
	detailLabel.Name = "Detail"
	detailLabel.Size = UDim2.new(1, -18, 0, 26)
	detailLabel.Position = UDim2.fromOffset(9, 29)
	detailLabel.BackgroundTransparency = 1
	detailLabel.Text = tostring(itemName) .. " from " .. tostring(senderName)
	detailLabel.TextColor3 = TEXT_PRIMARY
	detailLabel.TextTransparency = 1
	detailLabel.TextSize = 12
	detailLabel.Font = Enum.Font.GothamBold
	detailLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailLabel.TextTruncate = Enum.TextTruncate.AtEnd
	detailLabel.ZIndex = 81
	detailLabel.Parent = burst

	local scale = Instance.new("UIScale")
	scale.Scale = 0.9
	scale.Parent = burst

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("crew_mail_claim")
	end

	TweenService:Create(burst, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.06,
		Position = UDim2.new(1, -20, 1, -232),
	}):Play()
	TweenService:Create(stroke, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 0.08,
	}):Play()
	TweenService:Create(titleLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
	TweenService:Create(detailLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	task.delay(1.2, function()
		if sequence ~= mailboxClaimBurstSequence or activeMailboxClaimBurst ~= burst then
			return
		end

		TweenService:Create(burst, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -20, 1, -240),
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
		}):Play()
		TweenService:Create(titleLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		}):Play()
		TweenService:Create(detailLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		}):Play()
	end)

	task.delay(1.55, function()
		clearMailboxClaimBurst(sequence)
	end)
end

local function showMailboxSentBurst(itemName, recipientName, rarity)
	mailboxSentBurstSequence = mailboxSentBurstSequence + 1
	local sequence = mailboxSentBurstSequence
	clearMailboxSentBurst()

	local rarityColor = getRarityColor(rarity)
	local burst = Instance.new("Frame")
	burst.Name = "CrewMailboxSentBurst"
	burst.AnchorPoint = Vector2.new(1, 1)
	burst.Position = UDim2.new(1, -20, 1, -294)
	burst.Size = UDim2.fromOffset(236, 64)
	burst.BackgroundColor3 = Color3.fromRGB(31, 31, 42)
	burst.BackgroundTransparency = 1
	burst.BorderSizePixel = 0
	burst.ZIndex = 80
	burst.Parent = screenGui
	activeMailboxSentBurst = burst
	setCorner(burst, 8)

	local stroke = setStroke(burst, rarityColor, 1, 1)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -18, 0, 22)
	titleLabel.Position = UDim2.fromOffset(9, 7)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Crew Mail Sent"
	titleLabel.TextColor3 = rarityColor
	titleLabel.TextTransparency = 1
	titleLabel.TextSize = 14
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.ZIndex = 81
	titleLabel.Parent = burst

	local detailLabel = Instance.new("TextLabel")
	detailLabel.Name = "Detail"
	detailLabel.Size = UDim2.new(1, -18, 0, 26)
	detailLabel.Position = UDim2.fromOffset(9, 29)
	detailLabel.BackgroundTransparency = 1
	detailLabel.Text = tostring(itemName) .. " to " .. tostring(recipientName)
	detailLabel.TextColor3 = TEXT_PRIMARY
	detailLabel.TextTransparency = 1
	detailLabel.TextSize = 12
	detailLabel.Font = Enum.Font.GothamBold
	detailLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailLabel.TextTruncate = Enum.TextTruncate.AtEnd
	detailLabel.ZIndex = 81
	detailLabel.Parent = burst

	local scale = Instance.new("UIScale")
	scale.Scale = 0.9
	scale.Parent = burst

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("crew_mail_send")
	end

	TweenService:Create(burst, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.06,
		Position = UDim2.new(1, -20, 1, -302),
	}):Play()
	TweenService:Create(stroke, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 0.08,
	}):Play()
	TweenService:Create(titleLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
	TweenService:Create(detailLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	task.delay(1.2, function()
		if sequence ~= mailboxSentBurstSequence or activeMailboxSentBurst ~= burst then
			return
		end

		TweenService:Create(burst, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -20, 1, -310),
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
		}):Play()
		TweenService:Create(titleLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		}):Play()
		TweenService:Create(detailLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		}):Play()
	end)

	task.delay(1.55, function()
		clearMailboxSentBurst(sequence)
	end)
end

local function showMailboxReceivedBurst(itemName, senderName, rarity)
	mailboxReceivedBurstSequence = mailboxReceivedBurstSequence + 1
	local sequence = mailboxReceivedBurstSequence
	clearMailboxReceivedBurst()

	local rarityColor = getRarityColor(rarity)
	local burst = Instance.new("Frame")
	burst.Name = "CrewMailboxReceivedBurst"
	burst.AnchorPoint = Vector2.new(1, 1)
	burst.Position = UDim2.new(1, -20, 1, -364)
	burst.Size = UDim2.fromOffset(236, 64)
	burst.BackgroundColor3 = Color3.fromRGB(27, 38, 35)
	burst.BackgroundTransparency = 1
	burst.BorderSizePixel = 0
	burst.ZIndex = 80
	burst.Parent = screenGui
	activeMailboxReceivedBurst = burst
	setCorner(burst, 8)

	local stroke = setStroke(burst, rarityColor, 1, 1)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -18, 0, 22)
	titleLabel.Position = UDim2.fromOffset(9, 7)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Crew Mail Received"
	titleLabel.TextColor3 = rarityColor
	titleLabel.TextTransparency = 1
	titleLabel.TextSize = 14
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.ZIndex = 81
	titleLabel.Parent = burst

	local detailLabel = Instance.new("TextLabel")
	detailLabel.Name = "Detail"
	detailLabel.Size = UDim2.new(1, -18, 0, 26)
	detailLabel.Position = UDim2.fromOffset(9, 29)
	detailLabel.BackgroundTransparency = 1
	detailLabel.Text = tostring(itemName) .. " from " .. tostring(senderName)
	detailLabel.TextColor3 = TEXT_PRIMARY
	detailLabel.TextTransparency = 1
	detailLabel.TextSize = 12
	detailLabel.Font = Enum.Font.GothamBold
	detailLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailLabel.TextTruncate = Enum.TextTruncate.AtEnd
	detailLabel.ZIndex = 81
	detailLabel.Parent = burst

	local scale = Instance.new("UIScale")
	scale.Scale = 0.9
	scale.Parent = burst

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("crew_mail_receive")
	end

	TweenService:Create(burst, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.06,
		Position = UDim2.new(1, -20, 1, -372),
	}):Play()
	TweenService:Create(stroke, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 0.08,
	}):Play()
	TweenService:Create(titleLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
	TweenService:Create(detailLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	task.delay(1.2, function()
		if sequence ~= mailboxReceivedBurstSequence or activeMailboxReceivedBurst ~= burst then
			return
		end

		TweenService:Create(burst, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -20, 1, -380),
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
		}):Play()
		TweenService:Create(titleLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		}):Play()
		TweenService:Create(detailLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		}):Play()
	end)

	task.delay(1.55, function()
		clearMailboxReceivedBurst(sequence)
	end)
end

local panel = Instance.new("Frame")
panel.Name = "CrewPanel"
panel.Size = UDim2.new(0, 330, 0, 580)
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -20, 1, -142)
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

local mailboxHeader = Instance.new("TextLabel")
mailboxHeader.Name = "MailboxHeader"
mailboxHeader.Size = UDim2.new(1, -28, 0, 20)
mailboxHeader.Position = UDim2.new(0, 14, 0, 430)
mailboxHeader.BackgroundTransparency = 1
mailboxHeader.Text = "Mailbox"
mailboxHeader.TextColor3 = TEXT_PRIMARY
mailboxHeader.TextSize = 13
mailboxHeader.Font = Enum.Font.GothamBold
mailboxHeader.TextXAlignment = Enum.TextXAlignment.Left
mailboxHeader.Parent = panel

local mailboxTargetLabel = Instance.new("TextLabel")
mailboxTargetLabel.Name = "MailboxTarget"
mailboxTargetLabel.Size = UDim2.new(1, -28, 0, 16)
mailboxTargetLabel.Position = UDim2.new(0, 14, 0, 450)
mailboxTargetLabel.BackgroundTransparency = 1
mailboxTargetLabel.Text = "Pick a crewmate above to send an item."
mailboxTargetLabel.TextColor3 = TEXT_MUTED
mailboxTargetLabel.TextSize = 11
mailboxTargetLabel.Font = Enum.Font.GothamMedium
mailboxTargetLabel.TextXAlignment = Enum.TextXAlignment.Left
mailboxTargetLabel.TextTruncate = Enum.TextTruncate.AtEnd
mailboxTargetLabel.Parent = panel

local mailboxList = Instance.new("ScrollingFrame")
mailboxList.Name = "Mailbox"
mailboxList.Size = UDim2.new(1, -28, 0, 80)
mailboxList.Position = UDim2.new(0, 14, 0, 470)
mailboxList.BackgroundColor3 = SECTION_BG
mailboxList.BackgroundTransparency = 0.08
mailboxList.BorderSizePixel = 0
mailboxList.ScrollBarThickness = 4
mailboxList.CanvasSize = UDim2.new(0, 0, 0, 0)
mailboxList.Parent = panel
setCorner(mailboxList, 8)

local mailboxLayout = Instance.new("UIListLayout")
mailboxLayout.Padding = UDim.new(0, 4)
mailboxLayout.SortOrder = Enum.SortOrder.LayoutOrder
mailboxLayout.Parent = mailboxList

local mailboxPadding = Instance.new("UIPadding")
mailboxPadding.PaddingTop = UDim.new(0, 6)
mailboxPadding.PaddingBottom = UDim.new(0, 6)
mailboxPadding.PaddingLeft = UDim.new(0, 6)
mailboxPadding.PaddingRight = UDim.new(0, 6)
mailboxPadding.Parent = mailboxList

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

local function getRootPart(targetPlayer)
	local character = targetPlayer and targetPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function clearCoopRadiusMarker()
	if coopRadiusMarker then
		coopRadiusMarker:Destroy()
		coopRadiusMarker = nil
	end
end

local function destroyNamedCoopLinkInstances(root)
	if not root then
		return
	end

	for _, child in ipairs(root:GetChildren()) do
		if string.sub(child.Name, 1, #COOP_LINK_STYLE.prefix) == COOP_LINK_STYLE.prefix then
			child:Destroy()
		end
	end
end

local function cleanupCrewCoopLink(userId)
	local link = crewCoopLinkState.links[userId]
	if not link then
		return
	end

	if link.beam then
		link.beam:Destroy()
	end
	if link.localAttachment then
		link.localAttachment:Destroy()
	end
	if link.crewmateAttachment then
		link.crewmateAttachment:Destroy()
	end

	crewCoopLinkState.links[userId] = nil
end

local function cleanupAllCrewCoopLinks()
	for userId in pairs(crewCoopLinkState.links) do
		cleanupCrewCoopLink(userId)
	end
end

local function createCrewCoopLink(crewmate, localRoot, crewmateRoot)
	cleanupCrewCoopLink(crewmate.UserId)
	destroyNamedCoopLinkInstances(crewmateRoot)

	local localAttachment = Instance.new("Attachment")
	localAttachment.Name = COOP_LINK_STYLE.localAttachmentName .. tostring(crewmate.UserId)
	localAttachment.Position = Vector3.new(0, 0.35, 0)
	localAttachment.Parent = localRoot

	local crewmateAttachment = Instance.new("Attachment")
	crewmateAttachment.Name = COOP_LINK_STYLE.crewmateAttachmentName .. tostring(player.UserId)
	crewmateAttachment.Position = Vector3.new(0, 0.35, 0)
	crewmateAttachment.Parent = crewmateRoot

	local beam = Instance.new("Beam")
	beam.Name = COOP_LINK_STYLE.beamName .. tostring(crewmate.UserId)
	beam.Attachment0 = localAttachment
	beam.Attachment1 = crewmateAttachment
	beam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(62, 222, 210)),
		ColorSequenceKeypoint.new(0.5, ACCENT_GOLD),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(62, 222, 210)),
	})
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.72),
		NumberSequenceKeypoint.new(0.5, 0.22),
		NumberSequenceKeypoint.new(1, 0.72),
	})
	beam.Width0 = 0.12
	beam.Width1 = 0.12
	beam.FaceCamera = true
	beam.LightEmission = 0.45
	beam.LightInfluence = 0
	beam.Segments = 8
	beam.Parent = localRoot

	crewCoopLinkState.links[crewmate.UserId] = {
		beam = beam,
		localAttachment = localAttachment,
		crewmateAttachment = crewmateAttachment,
		localRoot = localRoot,
		crewmateRoot = crewmateRoot,
		phase = os.clock() % 1,
	}
end

local function updateCrewCoopLinks()
	if not state.inCrew or not coopBonusState.active then
		cleanupAllCrewCoopLinks()
		return
	end

	local radius = tonumber(state.coopRadius) or 0
	local localRoot = getRootPart(player)
	if radius <= 0 or not localRoot then
		cleanupAllCrewCoopLinks()
		return
	end

	local wanted = {}
	for _, member in ipairs(state.members or {}) do
		local userId = tonumber(member.userId)
		if userId and userId ~= player.UserId then
			local crewmate = Players:GetPlayerByUserId(userId)
			local crewmateRoot = getRootPart(crewmate)
			if crewmateRoot and (crewmateRoot.Position - localRoot.Position).Magnitude <= radius then
				wanted[userId] = true
				local link = crewCoopLinkState.links[userId]
				if not link or link.localRoot ~= localRoot or link.crewmateRoot ~= crewmateRoot then
					createCrewCoopLink(crewmate, localRoot, crewmateRoot)
				end
			end
		end
	end

	for userId in pairs(crewCoopLinkState.links) do
		if not wanted[userId] then
			cleanupCrewCoopLink(userId)
		end
	end
end

local function pulseCrewCoopLinks()
	local now = os.clock()
	for userId, link in pairs(crewCoopLinkState.links) do
		local beam = link.beam
		if not beam or not beam.Parent or not link.localAttachment.Parent or not link.crewmateAttachment.Parent then
			cleanupCrewCoopLink(userId)
		else
			local alpha = (math.sin((now + link.phase) * 3.8) + 1) * 0.5
			local width = 0.09 + (alpha * 0.07)
			local centerTransparency = 0.18 + ((1 - alpha) * 0.16)

			beam.Width0 = width
			beam.Width1 = width
			beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.76),
				NumberSequenceKeypoint.new(0.5, centerTransparency),
				NumberSequenceKeypoint.new(1, 0.76),
			})
		end
	end
end

local function ensureCoopRadiusMarker()
	if coopRadiusMarker and coopRadiusMarker.Parent then
		return coopRadiusMarker
	end

	coopRadiusMarker = Instance.new("Part")
	coopRadiusMarker.Name = COOP_RADIUS_MARKER_NAME
	coopRadiusMarker.Shape = Enum.PartType.Cylinder
	coopRadiusMarker.Anchored = true
	coopRadiusMarker.CanCollide = false
	coopRadiusMarker.CanQuery = false
	coopRadiusMarker.CanTouch = false
	coopRadiusMarker.CastShadow = false
	coopRadiusMarker.Material = Enum.Material.Neon
	coopRadiusMarker.TopSurface = Enum.SurfaceType.Smooth
	coopRadiusMarker.BottomSurface = Enum.SurfaceType.Smooth
	coopRadiusMarker.Parent = workspace

	return coopRadiusMarker
end

local function getLocalGroundY(root)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootHalfHeight = root.Size.Y * 0.5
	local hipHeight = humanoid and humanoid.HipHeight or 2

	return root.Position.Y - rootHalfHeight - hipHeight + COOP_RADIUS_MARKER_Y_OFFSET
end

local function updateCoopRadiusMarker()
	if not state.inCrew then
		clearCoopRadiusMarker()
		return
	end

	local radius = tonumber(state.coopRadius) or 0
	local root = getRootPart(player)
	if radius <= 0 or not root then
		clearCoopRadiusMarker()
		return
	end

	local marker = ensureCoopRadiusMarker()
	local diameter = math.max(radius * 2, 1)

	marker.Size = Vector3.new(diameter, COOP_RADIUS_MARKER_HEIGHT, diameter)
	marker.CFrame = CFrame.new(root.Position.X, getLocalGroundY(root), root.Position.Z)

	if coopBonusState.active then
		marker.Color = ACCENT_GREEN
		marker.Transparency = 0.74
	else
		marker.Color = COOP_RADIUS_INACTIVE_COLOR
		marker.Transparency = 0.88
	end
end

local function getCoopBonusPartner()
	if not state.inCrew then
		return nil
	end

	local radius = tonumber(state.coopRadius) or 0
	if radius <= 0 then
		return nil
	end

	local localRoot = getRootPart(player)
	if not localRoot then
		return nil
	end

	for _, member in ipairs(state.members or {}) do
		local userId = tonumber(member.userId)
		if userId and userId ~= player.UserId then
			local crewmate = Players:GetPlayerByUserId(userId)
			local crewmateRoot = getRootPart(crewmate)
			if crewmateRoot and (crewmateRoot.Position - localRoot.Position).Magnitude <= radius then
				return tostring(member.displayName or member.name or crewmate.DisplayName or crewmate.Name or "Crewmate")
			end
		end
	end

	return nil
end

refreshCoopBonusState = function(shouldRender)
	local partnerName = getCoopBonusPartner()
	local isActive = partnerName ~= nil
	local changed = coopBonusState.active ~= isActive or coopBonusState.partnerName ~= partnerName

	coopBonusState.active = isActive
	coopBonusState.partnerName = partnerName
	updateCoopRadiusMarker()
	updateCrewCoopLinks()

	if changed and shouldRender and render then
		render()
	end

	return changed
end

local function refreshCoopBonusStateSoon(delaySeconds)
	task.delay(delaySeconds or 0.2, function()
		refreshCoopBonusState(true)
	end)
end

local function requestInventoryRefresh()
	local ok, result = pcall(function()
		return GetPlayerDataFunc:InvokeServer()
	end)
	if ok and type(result) == "table" and type(result.inventory) == "table" then
		currentInventory = result.inventory
	else
		currentInventory = {}
	end
end

local function requestState()
	requestInventoryRefresh()
	local ok, result = pcall(function()
		return GetCrewStateFunc:InvokeServer()
	end)
	if ok and type(result) == "table" then
		state = result
		refreshCoopBonusState(false)
		render()
	end
end

local function getSelectedRecipient(members)
	for _, member in ipairs(members) do
		if member.userId == selectedMailboxRecipientUserId and member.userId ~= player.UserId then
			return member
		end
	end

	selectedMailboxRecipientUserId = nil
	return nil
end

local function makeMailboxEntry(parent, text, detailText, buttonText, buttonColor, onClick, rarity)
	local row = makeRow(parent, text, detailText, buttonText, buttonColor, onClick)
	if rarity then
		setStroke(row, getRarityColor(rarity), 1, 0.15)
	end
	return row
end

local function renderMailbox(members)
	clearRenderedChildren(mailboxList)

	local selectedRecipient = getSelectedRecipient(members)
	local mailboxItems = state.mailboxItems or {}

	if not state.inCrew then
		mailboxHeader.Visible = false
		mailboxTargetLabel.Visible = false
		mailboxList.Visible = false
		return
	end

	mailboxHeader.Visible = true
	mailboxTargetLabel.Visible = true
	mailboxList.Visible = true
	mailboxTargetLabel.Text = selectedRecipient and ("Sending to " .. selectedRecipient.displayName) or "Pick a crewmate above to send an item."

	for _, mailboxItem in ipairs(mailboxItems) do
		local item = mailboxItem.item or {}
		local mailboxId = mailboxItem.id
		makeMailboxEntry(mailboxList, item.name or "Unknown item", "From " .. tostring(mailboxItem.fromDisplayName or mailboxItem.fromName or "Crew"), "Claim", ACCENT_GOLD, function()
			CrewMailboxClaimEvent:FireServer(mailboxId)
			task.delay(0.2, requestState)
		end, item.rarity)
	end

	if selectedRecipient then
		for index, item in ipairs(currentInventory) do
			item = type(item) == "table" and item or {}
			local sendIndex = index
			local detail = tostring(item.rarity or "Common") .. " | " .. tostring(item.sellValue or 0)
			makeMailboxEntry(mailboxList, item.name or "Unknown item", detail, "Send", ACCENT_GREEN, function()
				CrewMailboxSendEvent:FireServer(selectedRecipient.userId, sendIndex)
				task.delay(0.2, requestState)
			end, item.rarity)
		end
	elseif #mailboxItems == 0 then
		makeEmptyRow(mailboxList, "No mailbox items yet.")
	end

	if selectedRecipient and #currentInventory == 0 and #mailboxItems == 0 then
		makeEmptyRow(mailboxList, "No owned items to send.")
	end

	updateCanvas(mailboxList, mailboxLayout)
end

render = function()
	local members = state.members or {}
	local nearbyPlayers = state.nearbyPlayers or {}
	local topCrews = state.topCrews or {}
	local mailboxCount = state.mailboxCount or 0
	local maxSize = state.maxSize or 10
	local bonus = state.fragmentBonus or 0
	local radius = state.coopRadius or 0
	local pendingInvite = state.pendingInvite
	local level = state.crewLevel or 1
	local xpInLevel = state.crewXPInLevel or 0
	local xpForNextLevel = state.crewXPForNextLevel or 0

	refreshCoopBonusState(false)
	refreshCrewMarkers(members)
	updateCoopRadiusMarker()

	pendingDot.Visible = pendingInvite ~= nil or mailboxCount > 0
	coopBadge.Visible = state.inCrew
	if coopBonusState.active then
		coopBadge.BackgroundColor3 = ACCENT_GREEN
		coopBadge.BackgroundTransparency = 0.04
		coopBadgeStroke.Color = ACCENT_GREEN
		coopBadgeStroke.Transparency = 0
		coopBadgeLabel.Text = "ACTIVE"
		coopBadgeLabel.TextColor3 = Color3.fromRGB(12, 24, 18)
	else
		coopBadge.BackgroundColor3 = SECTION_BG
		coopBadge.BackgroundTransparency = 0.18
		coopBadgeStroke.Color = Color3.fromRGB(80, 86, 96)
		coopBadgeStroke.Transparency = 0.25
		coopBadgeLabel.Text = "+Frag"
		coopBadgeLabel.TextColor3 = TEXT_MUTED
	end

	if state.inCrew then
		toggleButton.Text = mailboxCount > 0 and ("Crew " .. tostring(#members) .. "/" .. tostring(maxSize) .. " Mail " .. tostring(mailboxCount)) or ("Crew " .. tostring(#members) .. "/" .. tostring(maxSize))
	else
		toggleButton.Text = "Crew"
	end

	if state.inCrew then
		if coopBonusState.active then
			statusLabel.Text = "Co-op bonus active with " .. tostring(coopBonusState.partnerName) .. " - +" .. tostring(bonus) .. " fragments"
			statusLabel.TextColor3 = ACCENT_GREEN
		else
			statusLabel.Text = "Level " .. tostring(level) .. " crew - +" .. tostring(bonus) .. " fragments within " .. tostring(radius) .. " studs"
			statusLabel.TextColor3 = TEXT_MUTED
		end
		actionButton.Text = "Leave Crew"
		actionButton.BackgroundColor3 = ACCENT_RED
	else
		statusLabel.Text = "Create a crew, then invite nearby players."
		statusLabel.TextColor3 = TEXT_MUTED
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
	local leaderboardHeight = compactLayout and 46 or 54
	local memberHeight = compactLayout and 38 or (state.inCrew and 44 or 54)
	local nearbyHeight = compactLayout and 34 or (state.inCrew and 42 or 70)
	local mailboxY = topOffset + leaderboardHeight + memberHeight + nearbyHeight + (compactLayout and 78 or 90)
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
	mailboxHeader.Position = UDim2.new(0, 14, 0, mailboxY)
	mailboxTargetLabel.Position = UDim2.new(0, 14, 0, mailboxY + 20)
	mailboxList.Position = UDim2.new(0, 14, 0, mailboxY + 40)
	mailboxList.Size = UDim2.new(1, -28, 0, compactLayout and 72 or 82)

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
			if member.userId == player.UserId then
				suffix = suffix ~= "" and (suffix .. " | You") or "You"
			end
			local buttonText = nil
			local buttonColor = nil
			local onClick = nil
			if state.inCrew and member.userId ~= player.UserId then
				buttonText = selectedMailboxRecipientUserId == member.userId and "Picked" or "To"
				buttonColor = selectedMailboxRecipientUserId == member.userId and ACCENT_GOLD or ACCENT_BLUE
				onClick = function()
					selectedMailboxRecipientUserId = member.userId
					render()
				end
			end
			makeRow(memberList, member.displayName, suffix, buttonText, buttonColor, onClick)
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
	renderMailbox(members)
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
		if panel.Visible then
			requestInventoryRefresh()
		end
		local levelUp = payload.levelUp
		if type(levelUp) == "table" then
			local level = tonumber(levelUp.level)
			local fragmentBonus = tonumber(levelUp.fragmentBonus)
			local levelUpKey = tostring(payload.crewId or "crew") .. ":" .. tostring(level) .. ":" .. tostring(payload.crewXP or 0)
			if level and fragmentBonus and levelUpKey ~= lastLevelUpKey then
				lastLevelUpKey = levelUpKey
				showLevelUpBurst(math.floor(level), math.floor(fragmentBonus))
			end
		end
		local mailboxClaimed = payload.mailboxClaimed
		if type(mailboxClaimed) == "table" then
			local itemName = tostring(mailboxClaimed.itemName or "Crew item")
			local senderName = tostring(mailboxClaimed.fromDisplayName or mailboxClaimed.fromName or "Crew")
			local rarity = tostring(mailboxClaimed.rarity or "Common")
			local claimKey = tostring(mailboxClaimed.id or "mail") .. ":" .. itemName .. ":" .. senderName
			if claimKey ~= lastMailboxClaimKey then
				lastMailboxClaimKey = claimKey
				showMailboxClaimBurst(itemName, senderName, rarity)
			end
		end
		local mailboxSent = payload.mailboxSent
		if type(mailboxSent) == "table" then
			local itemName = tostring(mailboxSent.itemName or "Crew item")
			local recipientName = tostring(mailboxSent.toDisplayName or mailboxSent.toName or "Crew")
			local rarity = tostring(mailboxSent.rarity or "Common")
			local sentKey = tostring(mailboxSent.id or "mail") .. ":" .. itemName .. ":" .. recipientName
			if sentKey ~= lastMailboxSentKey then
				lastMailboxSentKey = sentKey
				showMailboxSentBurst(itemName, recipientName, rarity)
			end
		end
		local mailboxReceived = payload.mailboxReceived
		if type(mailboxReceived) == "table" then
			local itemName = tostring(mailboxReceived.itemName or "Crew item")
			local senderName = tostring(mailboxReceived.fromDisplayName or mailboxReceived.fromName or "Crew")
			local rarity = tostring(mailboxReceived.rarity or "Common")
			local receivedKey = tostring(mailboxReceived.id or "mail") .. ":" .. itemName .. ":" .. senderName
			if receivedKey ~= lastMailboxReceivedKey then
				lastMailboxReceivedKey = receivedKey
				showMailboxReceivedBurst(itemName, senderName, rarity)
			end
		end
		state = payload
		if state.pendingInvite then
			panel.Visible = true
		end
		render()
	end
end)

Players.PlayerAdded:Connect(function()
	refreshCoopBonusStateSoon(0.5)
	if panel.Visible then
		task.delay(0.4, requestState)
	end
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	clearCrewMarker(leavingPlayer.UserId, true)
	cleanupCrewCoopLink(leavingPlayer.UserId)
	refreshCoopBonusStateSoon(0.2)
	task.delay(0.2, requestState)
end)

player.CharacterAdded:Connect(function()
	cleanupAllCrewCoopLinks()
	refreshCoopBonusStateSoon(0.35)
	task.delay(0.35, updateCoopRadiusMarker)
end)

RunService.RenderStepped:Connect(function()
	updateCoopRadiusMarker()
	pulseCrewCoopLinks()
end)

task.spawn(function()
	while true do
		task.wait(0.5)
		refreshCoopBonusState(true)
	end
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
