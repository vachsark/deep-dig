-- TradeGui.client.lua — player-to-player trade UI for Deep Dig
-- Place in: StarterGui/TradeGui (LocalScript)
--
-- Three modes:
--   1. Browser button + player list for sending trade requests
--   2. Incoming trade banner with accept / decline
--   3. Active trade window with offer selection + confirm flow

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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
	warn("[TradeGui] Remotes folder missing — trading UI disabled.")
	return
end

local RequestTradeEvent = waitForChildTimeout(Remotes, "RequestTrade", 5)
local RespondTradeEvent = waitForChildTimeout(Remotes, "RespondTrade", 5)
local SetTradeOfferEvent = waitForChildTimeout(Remotes, "SetTradeOffer", 5)
local ConfirmTradeEvent = waitForChildTimeout(Remotes, "ConfirmTrade", 5)
local CancelTradeEvent = waitForChildTimeout(Remotes, "CancelTrade", 5)
local TradeUIEvent = waitForChildTimeout(Remotes, "TradeUI", 5)
local GetPlayerDataFunction = waitForChildTimeout(Remotes, "GetPlayerData", 5)
local UpdateHUDEvent = waitForChildTimeout(Remotes, "UpdateHUD", 5)

if not (RequestTradeEvent and RespondTradeEvent and SetTradeOfferEvent and ConfirmTradeEvent and CancelTradeEvent and TradeUIEvent and GetPlayerDataFunction) then
	warn("[TradeGui] Required trade remotes missing — trading UI disabled.")
	return
end

local RarityColors = {
	Common = Color3.fromRGB(180, 180, 180),
	Uncommon = Color3.fromRGB(30, 200, 30),
	Rare = Color3.fromRGB(30, 100, 255),
	Epic = Color3.fromRGB(160, 50, 255),
	Legendary = Color3.fromRGB(255, 170, 0),
	Mythic = Color3.fromRGB(255, 50, 50),
}

local PANEL_BG = Color3.fromRGB(20, 20, 25)
local SECTION_BG = Color3.fromRGB(28, 28, 34)
local CARD_BG = Color3.fromRGB(34, 34, 40)
local CARD_BG_ALT = Color3.fromRGB(40, 40, 48)
local TEXT_PRIMARY = Color3.fromRGB(235, 235, 235)
local TEXT_MUTED = Color3.fromRGB(160, 160, 160)
local TEXT_SOFT = Color3.fromRGB(200, 200, 200)
local ACCENT_GOLD = Color3.fromRGB(255, 200, 50)
local ACCENT_GREEN = Color3.fromRGB(80, 220, 140)
local ACCENT_RED = Color3.fromRGB(240, 90, 90)
local ACCENT_BLUE = Color3.fromRGB(80, 160, 255)

local MAX_OFFER_ITEMS = 20

local function setCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

local function setStroke(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Color3.fromRGB(70, 70, 80)
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
	return stroke
end

local function clearRenderedChildren(container)
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UIListLayout")
			and not child:IsA("UIGridLayout")
			and not child:IsA("UIPadding")
			and not child:IsA("UICorner")
			and not child:IsA("UIStroke")
		then
			child:Destroy()
		end
	end
end

local function getRarityColor(rarity)
	return RarityColors[rarity] or TEXT_MUTED
end

local function cloneArray(value)
	local result = {}
	if type(value) ~= "table" then
		return result
	end
	for index, entry in ipairs(value) do
		result[index] = entry
	end
	return result
end

local function countSelected(selectedSet)
	local count = 0
	for _ in pairs(selectedSet) do
		count = count + 1
	end
	return count
end

local function sortedSelectedIndices(selectedSet)
	local indices = {}
	for index in pairs(selectedSet) do
		table.insert(indices, index)
	end
	table.sort(indices)
	return indices
end

local function safeInvokePlayerData()
	local ok, result = pcall(function()
		return GetPlayerDataFunction:InvokeServer()
	end)
	if ok and type(result) == "table" then
		return result
	end
	return nil
end

local function isArrayLike(value)
	return type(value) == "table"
end

local function normalizePartnerOffer(payload)
	if type(payload) ~= "table" then
		return {}
	end

	local candidates = payload.items or payload.offer or payload.snapshot or payload.selection or payload.offeredItems
	if type(candidates) == "table" then
		return candidates
	end

	local count = tonumber(payload.itemCount) or tonumber(payload.count) or 0
	local items = {}
	for index = 1, count do
		items[index] = {
			name = "Hidden item " .. index,
			rarity = "Common",
			sellValue = nil,
			hidden = true,
		}
	end
	return items
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeepDigTradeGui"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 60
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local tradeHint = Instance.new("TextLabel")
tradeHint.Name = "TradeHint"
tradeHint.Size = UDim2.new(0, 140, 0, 18)
tradeHint.AnchorPoint = Vector2.new(1, 1)
tradeHint.Position = UDim2.new(1, -20, 1, -64)
tradeHint.BackgroundTransparency = 1
tradeHint.Text = "20 studs required"
tradeHint.TextColor3 = TEXT_MUTED
tradeHint.TextSize = 12
tradeHint.Font = Enum.Font.GothamMedium
tradeHint.TextXAlignment = Enum.TextXAlignment.Right
tradeHint.Parent = screenGui

local tradeButton = Instance.new("TextButton")
tradeButton.Name = "TradeButton"
tradeButton.Size = UDim2.new(0, 140, 0, 40)
tradeButton.AnchorPoint = Vector2.new(1, 1)
tradeButton.Position = UDim2.new(1, -20, 1, -20)
tradeButton.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
tradeButton.BackgroundTransparency = 0.12
tradeButton.BorderSizePixel = 0
tradeButton.Text = "🤝 Trade"
tradeButton.TextColor3 = TEXT_PRIMARY
tradeButton.TextSize = 18
tradeButton.Font = Enum.Font.GothamBold
tradeButton.AutoButtonColor = true
tradeButton.Parent = screenGui
setCorner(tradeButton, 8)
setStroke(tradeButton, Color3.fromRGB(80, 80, 92), 1, 0)

local browserPanel = Instance.new("Frame")
browserPanel.Name = "BrowserPanel"
browserPanel.Size = UDim2.new(0, 300, 0, 300)
browserPanel.AnchorPoint = Vector2.new(1, 1)
browserPanel.Position = UDim2.new(1, -20, 1, -76)
browserPanel.BackgroundColor3 = PANEL_BG
browserPanel.BackgroundTransparency = 0.08
browserPanel.BorderSizePixel = 0
browserPanel.Visible = false
browserPanel.Parent = screenGui
setCorner(browserPanel, 12)
setStroke(browserPanel, Color3.fromRGB(60, 60, 75), 1, 0)

local browserTitle = Instance.new("TextLabel")
browserTitle.Size = UDim2.new(1, -48, 0, 34)
browserTitle.Position = UDim2.new(0, 12, 0, 8)
browserTitle.BackgroundTransparency = 1
browserTitle.Text = "Players in Server"
browserTitle.TextColor3 = TEXT_PRIMARY
browserTitle.TextSize = 16
browserTitle.Font = Enum.Font.GothamBold
browserTitle.TextXAlignment = Enum.TextXAlignment.Left
browserTitle.Parent = browserPanel

local browserSubtitle = Instance.new("TextLabel")
browserSubtitle.Size = UDim2.new(1, -24, 0, 18)
browserSubtitle.Position = UDim2.new(0, 12, 0, 34)
browserSubtitle.BackgroundTransparency = 1
browserSubtitle.Text = "Click a nearby player to invite them"
browserSubtitle.TextColor3 = TEXT_MUTED
browserSubtitle.TextSize = 12
browserSubtitle.Font = Enum.Font.Gotham
browserSubtitle.TextXAlignment = Enum.TextXAlignment.Left
browserSubtitle.Parent = browserPanel

local browserClose = Instance.new("TextButton")
browserClose.Size = UDim2.new(0, 28, 0, 28)
browserClose.AnchorPoint = Vector2.new(1, 0)
browserClose.Position = UDim2.new(1, -10, 0, 10)
browserClose.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
browserClose.BackgroundTransparency = 0.15
browserClose.BorderSizePixel = 0
browserClose.Text = "×"
browserClose.TextColor3 = TEXT_PRIMARY
browserClose.TextSize = 20
browserClose.Font = Enum.Font.GothamBold
browserClose.Parent = browserPanel
setCorner(browserClose, 6)

local browserScroll = Instance.new("ScrollingFrame")
browserScroll.Name = "PlayerList"
browserScroll.Size = UDim2.new(1, -16, 1, -66)
browserScroll.Position = UDim2.new(0, 8, 0, 58)
browserScroll.BackgroundTransparency = 1
browserScroll.BorderSizePixel = 0
browserScroll.ScrollBarThickness = 6
browserScroll.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 140)
browserScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
browserScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
browserScroll.Parent = browserPanel

local browserPadding = Instance.new("UIPadding")
browserPadding.PaddingTop = UDim.new(0, 2)
browserPadding.PaddingLeft = UDim.new(0, 2)
browserPadding.PaddingRight = UDim.new(0, 2)
browserPadding.PaddingBottom = UDim.new(0, 2)
browserPadding.Parent = browserScroll

local browserLayout = Instance.new("UIListLayout")
browserLayout.Padding = UDim.new(0, 6)
browserLayout.SortOrder = Enum.SortOrder.LayoutOrder
browserLayout.Parent = browserScroll

local incomingBanner = Instance.new("Frame")
incomingBanner.Name = "IncomingTradeBanner"
incomingBanner.Size = UDim2.new(0, 460, 0, 90)
incomingBanner.AnchorPoint = Vector2.new(0.5, 0)
incomingBanner.Position = UDim2.new(0.5, 0, 0, 72)
incomingBanner.BackgroundColor3 = PANEL_BG
incomingBanner.BackgroundTransparency = 0.05
incomingBanner.BorderSizePixel = 0
incomingBanner.Visible = false
incomingBanner.Parent = screenGui
setCorner(incomingBanner, 12)
setStroke(incomingBanner, Color3.fromRGB(120, 95, 45), 1, 0)

local incomingText = Instance.new("TextLabel")
incomingText.Size = UDim2.new(1, -20, 0, 24)
incomingText.Position = UDim2.new(0, 10, 0, 10)
incomingText.BackgroundTransparency = 1
incomingText.Text = "Someone wants to trade with you"
incomingText.TextColor3 = TEXT_PRIMARY
incomingText.TextSize = 16
incomingText.Font = Enum.Font.GothamBold
incomingText.TextXAlignment = Enum.TextXAlignment.Left
incomingText.Parent = incomingBanner

local incomingSubtext = Instance.new("TextLabel")
incomingSubtext.Size = UDim2.new(1, -20, 0, 18)
incomingSubtext.Position = UDim2.new(0, 10, 0, 34)
incomingSubtext.BackgroundTransparency = 1
incomingSubtext.Text = "Accept to open the trade window"
incomingSubtext.TextColor3 = TEXT_MUTED
incomingSubtext.TextSize = 12
incomingSubtext.Font = Enum.Font.Gotham
incomingSubtext.TextXAlignment = Enum.TextXAlignment.Left
incomingSubtext.Parent = incomingBanner

local incomingAccept = Instance.new("TextButton")
incomingAccept.Size = UDim2.new(0, 90, 0, 28)
incomingAccept.Position = UDim2.new(1, -194, 1, -36)
incomingAccept.BackgroundColor3 = ACCENT_GREEN
incomingAccept.BackgroundTransparency = 0.1
incomingAccept.BorderSizePixel = 0
incomingAccept.Text = "Accept"
incomingAccept.TextColor3 = Color3.fromRGB(20, 25, 20)
incomingAccept.TextSize = 13
incomingAccept.Font = Enum.Font.GothamBold
incomingAccept.AutoButtonColor = true
incomingAccept.Parent = incomingBanner
setCorner(incomingAccept, 6)

local incomingDecline = Instance.new("TextButton")
incomingDecline.Size = UDim2.new(0, 90, 0, 28)
incomingDecline.Position = UDim2.new(1, -98, 1, -36)
incomingDecline.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
incomingDecline.BackgroundTransparency = 0.1
incomingDecline.BorderSizePixel = 0
incomingDecline.Text = "Decline"
incomingDecline.TextColor3 = TEXT_PRIMARY
incomingDecline.TextSize = 13
incomingDecline.Font = Enum.Font.GothamBold
incomingDecline.AutoButtonColor = true
incomingDecline.Parent = incomingBanner
setCorner(incomingDecline, 6)

local tradeWindow = Instance.new("Frame")
tradeWindow.Name = "TradeWindow"
tradeWindow.Size = UDim2.new(0, 900, 0, 540)
tradeWindow.AnchorPoint = Vector2.new(0.5, 0.5)
tradeWindow.Position = UDim2.new(0.5, 0, 0.52, 0)
tradeWindow.BackgroundColor3 = PANEL_BG
tradeWindow.BackgroundTransparency = 0.06
tradeWindow.BorderSizePixel = 0
tradeWindow.Visible = false
tradeWindow.Parent = screenGui
setCorner(tradeWindow, 14)
setStroke(tradeWindow, Color3.fromRGB(65, 65, 82), 1, 0)

local tradeTitle = Instance.new("TextLabel")
tradeTitle.Size = UDim2.new(1, -90, 0, 34)
tradeTitle.Position = UDim2.new(0, 14, 0, 12)
tradeTitle.BackgroundTransparency = 1
tradeTitle.Text = "🤝 Trade"
tradeTitle.TextColor3 = TEXT_PRIMARY
tradeTitle.TextSize = 19
tradeTitle.Font = Enum.Font.GothamBold
tradeTitle.TextXAlignment = Enum.TextXAlignment.Left
tradeTitle.Parent = tradeWindow

local tradeState = Instance.new("TextLabel")
tradeState.Size = UDim2.new(1, -28, 0, 20)
tradeState.Position = UDim2.new(0, 14, 0, 44)
tradeState.BackgroundTransparency = 1
tradeState.Text = "Waiting for offers"
tradeState.TextColor3 = TEXT_MUTED
tradeState.TextSize = 12
tradeState.Font = Enum.Font.Gotham
tradeState.TextXAlignment = Enum.TextXAlignment.Left
tradeState.Parent = tradeWindow

local tradeClose = Instance.new("TextButton")
tradeClose.Size = UDim2.new(0, 28, 0, 28)
tradeClose.AnchorPoint = Vector2.new(1, 0)
tradeClose.Position = UDim2.new(1, -12, 0, 12)
tradeClose.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
tradeClose.BackgroundTransparency = 0.15
tradeClose.BorderSizePixel = 0
tradeClose.Text = "×"
tradeClose.TextColor3 = TEXT_PRIMARY
tradeClose.TextSize = 20
tradeClose.Font = Enum.Font.GothamBold
tradeClose.Parent = tradeWindow
setCorner(tradeClose, 6)

local leftColumn = Instance.new("Frame")
leftColumn.Name = "YourOffer"
leftColumn.Size = UDim2.new(0.5, -14, 1, -132)
leftColumn.Position = UDim2.new(0, 12, 0, 72)
leftColumn.BackgroundColor3 = SECTION_BG
leftColumn.BackgroundTransparency = 0.15
leftColumn.BorderSizePixel = 0
leftColumn.Parent = tradeWindow
setCorner(leftColumn, 10)

local rightColumn = Instance.new("Frame")
rightColumn.Name = "TheirOffer"
rightColumn.Size = UDim2.new(0.5, -14, 1, -132)
rightColumn.Position = UDim2.new(0.5, 2, 0, 72)
rightColumn.BackgroundColor3 = SECTION_BG
rightColumn.BackgroundTransparency = 0.15
rightColumn.BorderSizePixel = 0
rightColumn.Parent = tradeWindow
setCorner(rightColumn, 10)

local yourHeader = Instance.new("TextLabel")
yourHeader.Size = UDim2.new(1, -20, 0, 22)
yourHeader.Position = UDim2.new(0, 10, 0, 8)
yourHeader.BackgroundTransparency = 1
yourHeader.Text = "Your Offer"
yourHeader.TextColor3 = TEXT_PRIMARY
yourHeader.TextSize = 15
yourHeader.Font = Enum.Font.GothamBold
yourHeader.TextXAlignment = Enum.TextXAlignment.Left
yourHeader.Parent = leftColumn

local yourSubheader = Instance.new("TextLabel")
yourSubheader.Size = UDim2.new(1, -20, 0, 18)
yourSubheader.Position = UDim2.new(0, 10, 0, 28)
yourSubheader.BackgroundTransparency = 1
yourSubheader.Text = "Click items to add or remove"
yourSubheader.TextColor3 = TEXT_MUTED
yourSubheader.TextSize = 12
yourSubheader.Font = Enum.Font.Gotham
yourSubheader.TextXAlignment = Enum.TextXAlignment.Left
yourSubheader.Parent = leftColumn

local yourScroll = Instance.new("ScrollingFrame")
yourScroll.Name = "Inventory"
yourScroll.Size = UDim2.new(1, -16, 1, -48)
yourScroll.Position = UDim2.new(0, 8, 0, 44)
yourScroll.BackgroundTransparency = 1
yourScroll.BorderSizePixel = 0
yourScroll.ScrollBarThickness = 6
yourScroll.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 140)
yourScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
yourScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
yourScroll.Parent = leftColumn

local yourPadding = Instance.new("UIPadding")
yourPadding.PaddingTop = UDim.new(0, 4)
yourPadding.PaddingLeft = UDim.new(0, 2)
yourPadding.PaddingRight = UDim.new(0, 2)
yourPadding.PaddingBottom = UDim.new(0, 6)
yourPadding.Parent = yourScroll

local yourGrid = Instance.new("UIGridLayout")
yourGrid.CellSize = UDim2.new(0, 170, 0, 62)
yourGrid.CellPadding = UDim2.new(0, 8, 0, 8)
yourGrid.SortOrder = Enum.SortOrder.LayoutOrder
yourGrid.Parent = yourScroll

local theirHeader = Instance.new("TextLabel")
theirHeader.Size = UDim2.new(1, -20, 0, 22)
theirHeader.Position = UDim2.new(0, 10, 0, 8)
theirHeader.BackgroundTransparency = 1
theirHeader.Text = "Their Offer"
theirHeader.TextColor3 = TEXT_PRIMARY
theirHeader.TextSize = 15
theirHeader.Font = Enum.Font.GothamBold
theirHeader.TextXAlignment = Enum.TextXAlignment.Left
theirHeader.Parent = rightColumn

local theirSubheader = Instance.new("TextLabel")
theirSubheader.Size = UDim2.new(1, -20, 0, 18)
theirSubheader.Position = UDim2.new(0, 10, 0, 28)
theirSubheader.BackgroundTransparency = 1
theirSubheader.Text = "Read-only partner selection"
theirSubheader.TextColor3 = TEXT_MUTED
theirSubheader.TextSize = 12
theirSubheader.Font = Enum.Font.Gotham
theirSubheader.TextXAlignment = Enum.TextXAlignment.Left
theirSubheader.Parent = rightColumn

local theirScroll = Instance.new("ScrollingFrame")
theirScroll.Name = "PartnerOffer"
theirScroll.Size = UDim2.new(1, -16, 1, -48)
theirScroll.Position = UDim2.new(0, 8, 0, 44)
theirScroll.BackgroundTransparency = 1
theirScroll.BorderSizePixel = 0
theirScroll.ScrollBarThickness = 6
theirScroll.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 140)
theirScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
theirScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
theirScroll.Parent = rightColumn

local theirPadding = Instance.new("UIPadding")
theirPadding.PaddingTop = UDim.new(0, 4)
theirPadding.PaddingLeft = UDim.new(0, 2)
theirPadding.PaddingRight = UDim.new(0, 2)
theirPadding.PaddingBottom = UDim.new(0, 6)
theirPadding.Parent = theirScroll

local theirList = Instance.new("UIListLayout")
theirList.Padding = UDim.new(0, 8)
theirList.SortOrder = Enum.SortOrder.LayoutOrder
theirList.Parent = theirScroll

local footerStatus = Instance.new("TextLabel")
footerStatus.Name = "Status"
footerStatus.Size = UDim2.new(0.52, -20, 0, 24)
footerStatus.Position = UDim2.new(0, 14, 1, -74)
footerStatus.BackgroundTransparency = 1
footerStatus.Text = "Select items, then press Set Offer"
footerStatus.TextColor3 = TEXT_MUTED
footerStatus.TextSize = 13
footerStatus.Font = Enum.Font.Gotham
footerStatus.TextXAlignment = Enum.TextXAlignment.Left
footerStatus.Parent = tradeWindow

local selectionStatus = Instance.new("TextLabel")
selectionStatus.Name = "SelectionStatus"
selectionStatus.Size = UDim2.new(0.52, -20, 0, 24)
selectionStatus.Position = UDim2.new(0, 14, 1, -98)
selectionStatus.BackgroundTransparency = 1
selectionStatus.Text = "Selected 0/20"
selectionStatus.TextColor3 = TEXT_SOFT
selectionStatus.TextSize = 13
selectionStatus.Font = Enum.Font.GothamBold
selectionStatus.TextXAlignment = Enum.TextXAlignment.Left
selectionStatus.Parent = tradeWindow

local setOfferButton = Instance.new("TextButton")
setOfferButton.Size = UDim2.new(0, 128, 0, 34)
setOfferButton.Position = UDim2.new(1, -408, 1, -48)
setOfferButton.BackgroundColor3 = ACCENT_BLUE
setOfferButton.BackgroundTransparency = 0.08
setOfferButton.BorderSizePixel = 0
setOfferButton.Text = "Set Offer"
setOfferButton.TextColor3 = Color3.fromRGB(20, 25, 35)
setOfferButton.TextSize = 14
setOfferButton.Font = Enum.Font.GothamBold
setOfferButton.AutoButtonColor = true
setOfferButton.Parent = tradeWindow
setCorner(setOfferButton, 6)

local confirmButton = Instance.new("TextButton")
confirmButton.Size = UDim2.new(0, 128, 0, 34)
confirmButton.Position = UDim2.new(1, -272, 1, -48)
confirmButton.BackgroundColor3 = Color3.fromRGB(80, 80, 88)
confirmButton.BackgroundTransparency = 0.12
confirmButton.BorderSizePixel = 0
confirmButton.Text = "Confirm"
confirmButton.TextColor3 = TEXT_MUTED
confirmButton.TextSize = 14
confirmButton.Font = Enum.Font.GothamBold
confirmButton.AutoButtonColor = false
confirmButton.Parent = tradeWindow
setCorner(confirmButton, 6)

local cancelButton = Instance.new("TextButton")
cancelButton.Size = UDim2.new(0, 128, 0, 34)
cancelButton.Position = UDim2.new(1, -136, 1, -48)
cancelButton.BackgroundColor3 = ACCENT_RED
cancelButton.BackgroundTransparency = 0.1
cancelButton.BorderSizePixel = 0
cancelButton.Text = "Cancel"
cancelButton.TextColor3 = Color3.fromRGB(35, 20, 20)
cancelButton.TextSize = 14
cancelButton.Font = Enum.Font.GothamBold
cancelButton.AutoButtonColor = true
cancelButton.Parent = tradeWindow
setCorner(cancelButton, 6)

local noticeFrame = Instance.new("Frame")
noticeFrame.Name = "TradeNotices"
noticeFrame.Size = UDim2.new(0, 440, 0, 70)
noticeFrame.AnchorPoint = Vector2.new(0.5, 0)
noticeFrame.Position = UDim2.new(0.5, 0, 0, 168)
noticeFrame.BackgroundTransparency = 1
noticeFrame.Parent = screenGui

local noticeLayout = Instance.new("UIListLayout")
noticeLayout.Padding = UDim.new(0, 6)
noticeLayout.SortOrder = Enum.SortOrder.LayoutOrder
noticeLayout.Parent = noticeFrame

local function showNotice(text, rarity)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 28)
	label.BackgroundColor3 = PANEL_BG
	label.BackgroundTransparency = 0.22
	label.BorderSizePixel = 0
	label.Text = tostring(text)
	label.TextColor3 = getRarityColor(rarity)
	label.TextSize = 15
	label.Font = Enum.Font.GothamBold
	label.TextWrapped = true
	label.LayoutOrder = math.floor(os.clock() * 1000)
	label.Parent = noticeFrame
	setCorner(label, 6)

	task.delay(3, function()
		if not label.Parent then
			return
		end
		local tween = TweenService:Create(label, TweenInfo.new(0.35), {
			BackgroundTransparency = 1,
			TextTransparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function()
			if label.Parent then
				label:Destroy()
			end
		end)
	end)
end

local currentData = nil
local activeTradeId = nil
local activePartnerName = nil
local incomingRequest = nil
local incomingSequence = 0
local tradeRefreshSequence = 0
local tradeRefreshInFlight = false
local tradeRefreshQueued = false
local tradeRefreshEnabled = false

local selectedIndices = {}
local myOfferCommitted = false
local partnerOfferCommitted = false
local myConfirmed = false
local partnerConfirmed = false
local partnerOfferPayload = nil

local function updateTradeButton()
	if activeTradeId then
		tradeButton.Text = "🤝 Trading..."
		tradeHint.Text = "Active trade open"
		tradeButton.BackgroundColor3 = Color3.fromRGB(54, 40, 20)
		tradeButton.TextColor3 = Color3.fromRGB(255, 230, 180)
	else
		tradeButton.Text = "🤝 Trade"
		tradeHint.Text = "20 studs required"
		tradeButton.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
		tradeButton.TextColor3 = TEXT_PRIMARY
	end
end

local function setConfirmButtonState()
	local canConfirm = activeTradeId and myOfferCommitted and partnerOfferCommitted and not myConfirmed
	if canConfirm then
		confirmButton.AutoButtonColor = true
		confirmButton.BackgroundColor3 = ACCENT_GOLD
		confirmButton.TextColor3 = Color3.fromRGB(40, 30, 10)
		confirmButton.Text = "Confirm"
	else
		confirmButton.AutoButtonColor = false
		confirmButton.BackgroundColor3 = Color3.fromRGB(80, 80, 88)
		confirmButton.TextColor3 = TEXT_MUTED
		if myConfirmed then
			confirmButton.Text = "Confirmed"
		else
			confirmButton.Text = "Confirm"
		end
	end
end

local function updateStatusLabel()
	if not activeTradeId then
		footerStatus.Text = "Select items, then press Set Offer"
		return
	end

	if partnerConfirmed and not myConfirmed then
		footerStatus.Text = "Partner confirmed — your turn"
	elseif myConfirmed and partnerConfirmed then
		footerStatus.Text = "Both confirmed — waiting for the server"
	elseif myConfirmed then
		footerStatus.Text = "You confirmed — waiting on partner"
	elseif partnerOfferCommitted then
		footerStatus.Text = "Partner made an offer"
	elseif myOfferCommitted then
		footerStatus.Text = "Offer sent — waiting on partner"
	else
		footerStatus.Text = "Select items, then press Set Offer"
	end
end

local function updateSelectionStatus()
	selectionStatus.Text = string.format("Selected %d/%d", countSelected(selectedIndices), MAX_OFFER_ITEMS)
end

local function renderPlayerBrowser()
	clearRenderedChildren(browserScroll)

	local visiblePlayers = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			table.insert(visiblePlayers, other)
		end
	end
	table.sort(visiblePlayers, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)

	if #visiblePlayers == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -8, 0, 38)
		empty.BackgroundTransparency = 1
		empty.Text = "No other players in the server."
		empty.TextColor3 = TEXT_MUTED
		empty.TextSize = 13
		empty.Font = Enum.Font.GothamMedium
		empty.TextWrapped = true
		empty.Parent = browserScroll
		return
	end

	for _, target in ipairs(visiblePlayers) do
		local targetPlayer = target
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, -8, 0, 44)
		button.BackgroundColor3 = activeTradeId and Color3.fromRGB(45, 45, 52) or CARD_BG
		button.BackgroundTransparency = activeTradeId and 0.45 or 0.1
		button.BorderSizePixel = 0
		button.AutoButtonColor = not activeTradeId
		button.Text = ""
		button.Parent = browserScroll
		setCorner(button, 8)
		setStroke(button, Color3.fromRGB(78, 78, 90), 1, activeTradeId and 0.4 or 0)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -16, 0, 18)
		nameLabel.Position = UDim2.new(0, 10, 0, 6)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = target.Name
		nameLabel.TextColor3 = activeTradeId and TEXT_MUTED or TEXT_PRIMARY
		nameLabel.TextSize = 15
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = button

		local idLabel = Instance.new("TextLabel")
		idLabel.Size = UDim2.new(1, -16, 0, 16)
		idLabel.Position = UDim2.new(0, 10, 0, 22)
		idLabel.BackgroundTransparency = 1
		idLabel.Text = "UserId " .. tostring(target.UserId)
		idLabel.TextColor3 = TEXT_MUTED
		idLabel.TextSize = 12
		idLabel.Font = Enum.Font.Gotham
		idLabel.TextXAlignment = Enum.TextXAlignment.Left
		idLabel.Parent = button

		button.Activated:Connect(function()
			if activeTradeId then
				showNotice("Finish or cancel your current trade first.", "Common")
				return
			end
			RequestTradeEvent:FireServer(targetPlayer.UserId)
		end)
	end
end

local function pruneSelectedIndices(inventory)
	local size = type(inventory) == "table" and #inventory or 0
	for index in pairs(selectedIndices) do
		if type(index) ~= "number" or index < 1 or index > size then
			selectedIndices[index] = nil
		end
	end
end

local function createOfferCard(parent, item, index, interactive)
	local card = Instance.new(interactive and "TextButton" or "Frame")
	card.Size = UDim2.new(1, -6, 0, 58)
	card.BackgroundColor3 = CARD_BG
	card.BackgroundTransparency = 0.08
	card.BorderSizePixel = 0
	card.LayoutOrder = index or 1
	if interactive then
		card.Text = ""
		card.AutoButtonColor = true
	else
		card.Active = false
	end
	card.Parent = parent
	setCorner(card, 8)
	setStroke(card, getRarityColor(type(item) == "table" and item.rarity or "Common"), 2, 0)

	local name = type(item) == "table" and item.name or "Unknown item"
	local rarity = type(item) == "table" and item.rarity or "Common"
	local sellValue = type(item) == "table" and item.sellValue or nil

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 18)
	title.Position = UDim2.new(0, 10, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = name
	title.TextColor3 = TEXT_PRIMARY
	title.TextSize = 14
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = card

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Size = UDim2.new(1, -20, 0, 14)
	rarityLabel.Position = UDim2.new(0, 10, 0, 28)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Text = rarity .. (sellValue and ("  •  " .. tostring(sellValue) .. " coins") or "")
	rarityLabel.TextColor3 = getRarityColor(rarity)
	rarityLabel.TextSize = 11
	rarityLabel.Font = Enum.Font.GothamBold
	rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
	rarityLabel.TextTruncate = Enum.TextTruncate.AtEnd
	rarityLabel.Parent = card

	if interactive then
		local selectedTag = Instance.new("TextLabel")
		selectedTag.Name = "Selected"
		selectedTag.Size = UDim2.new(0, 52, 0, 18)
		selectedTag.AnchorPoint = Vector2.new(1, 0)
		selectedTag.Position = UDim2.new(1, -8, 0, 8)
		selectedTag.BackgroundColor3 = ACCENT_GOLD
		selectedTag.BackgroundTransparency = 0.05
		selectedTag.BorderSizePixel = 0
		selectedTag.Text = "Selected"
		selectedTag.TextColor3 = Color3.fromRGB(30, 25, 5)
		selectedTag.TextSize = 10
		selectedTag.Font = Enum.Font.GothamBold
		selectedTag.Visible = false
		selectedTag.Parent = card
		setCorner(selectedTag, 6)

		local function refreshSelectedTag()
			selectedTag.Visible = selectedIndices[index] and true or false
			setStroke(card, selectedIndices[index] and ACCENT_GOLD or getRarityColor(rarity), selectedIndices[index] and 3 or 2, 0)
			card.BackgroundColor3 = selectedIndices[index] and CARD_BG_ALT or CARD_BG
		end

		refreshSelectedTag()

		card.Activated:Connect(function()
			if not activeTradeId then
				return
			end

			if selectedIndices[index] then
				selectedIndices[index] = nil
			else
				if countSelected(selectedIndices) >= MAX_OFFER_ITEMS then
					showNotice("You can only offer up to 20 items.", "Common")
					return
				end
				selectedIndices[index] = true
			end

			refreshSelectedTag()
			updateSelectionStatus()
		end)
	end

	return card
end

local function renderYourInventory()
	clearRenderedChildren(yourScroll)
	pruneSelectedIndices(currentData and currentData.inventory or nil)
	updateSelectionStatus()

	local inventory = currentData and currentData.inventory
	if not isArrayLike(inventory) or #inventory == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -12, 0, 48)
		empty.BackgroundTransparency = 1
		empty.Text = currentData and "No tradable items right now." or "Loading inventory..."
		empty.TextColor3 = TEXT_MUTED
		empty.TextSize = 13
		empty.Font = Enum.Font.GothamMedium
		empty.TextWrapped = true
		empty.Parent = yourScroll
		return
	end

	for index, item in ipairs(cloneArray(inventory)) do
		createOfferCard(yourScroll, item, index, true)
	end
end

local function renderTheirOffer()
	clearRenderedChildren(theirScroll)

	local offerItems = {}
	if partnerOfferPayload then
		offerItems = normalizePartnerOffer(partnerOfferPayload)
	end

	if not partnerOfferCommitted then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -12, 0, 48)
		empty.BackgroundTransparency = 1
		empty.Text = "Waiting for partner offer..."
		empty.TextColor3 = TEXT_MUTED
		empty.TextSize = 13
		empty.Font = Enum.Font.GothamMedium
		empty.TextWrapped = true
		empty.Parent = theirScroll
		return
	end

	if #offerItems == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -12, 0, 48)
		empty.BackgroundTransparency = 1
		empty.Text = "Partner sent an empty offer."
		empty.TextColor3 = TEXT_MUTED
		empty.TextSize = 13
		empty.Font = Enum.Font.GothamMedium
		empty.TextWrapped = true
		empty.Parent = theirScroll
		return
	end

	for index, item in ipairs(offerItems) do
		createOfferCard(theirScroll, item, index, false)
	end
end

local function renderTradeWindow()
	if not activeTradeId then
		return
	end

	updateTradeButton()

	tradeTitle.Text = "🤝 Trade with " .. tostring(activePartnerName or "Player")
	updateSelectionStatus()
	updateStatusLabel()
	setConfirmButtonState()
	renderYourInventory()
	renderTheirOffer()
end

local function requestInventoryRefresh()
	if not activeTradeId then
		return
	end

	if tradeRefreshInFlight then
		tradeRefreshQueued = true
		return
	end

	tradeRefreshInFlight = true
	local snapshot = safeInvokePlayerData()
	tradeRefreshInFlight = false

	if snapshot then
		currentData = snapshot
	end

	if activeTradeId then
		renderTradeWindow()
	end

	if tradeRefreshQueued and activeTradeId then
		tradeRefreshQueued = false
		requestInventoryRefresh()
	end
end

local function startTradeRefreshLoop()
	tradeRefreshSequence = tradeRefreshSequence + 1
	local sequence = tradeRefreshSequence
	tradeRefreshEnabled = true

	task.spawn(function()
		requestInventoryRefresh()
		while tradeRefreshEnabled and activeTradeId and sequence == tradeRefreshSequence do
			task.wait(5)
			if not (tradeRefreshEnabled and activeTradeId and sequence == tradeRefreshSequence) then
				break
			end
			requestInventoryRefresh()
		end
	end)
end

local function stopTradeRefreshLoop()
	tradeRefreshEnabled = false
	tradeRefreshSequence = tradeRefreshSequence + 1
	tradeRefreshInFlight = false
	tradeRefreshQueued = false
end

local function hideIncomingRequest()
	incomingBanner.Visible = false
	incomingRequest = nil
	incomingSequence = incomingSequence + 1
end

local function resetTradeWindow()
	activeTradeId = nil
	activePartnerName = nil
	table.clear(selectedIndices)
	myOfferCommitted = false
	partnerOfferCommitted = false
	myConfirmed = false
	partnerConfirmed = false
	partnerOfferPayload = nil
	tradeWindow.Visible = false
	browserPanel.Visible = false
	stopTradeRefreshLoop()
	updateTradeButton()
	updateSelectionStatus()
	updateStatusLabel()
	setConfirmButtonState()
end

local function openTradeWindow(tradeId, partnerName)
	activeTradeId = tradeId
	activePartnerName = partnerName or "Player"
	table.clear(selectedIndices)
	myOfferCommitted = false
	partnerOfferCommitted = false
	myConfirmed = false
	partnerConfirmed = false
	partnerOfferPayload = nil

	hideIncomingRequest()
	browserPanel.Visible = false
	tradeWindow.Visible = true
	updateTradeButton()
	updateSelectionStatus()
	updateStatusLabel()
	setConfirmButtonState()
	startTradeRefreshLoop()
	requestInventoryRefresh()
	renderTradeWindow()
end

local function closeTradeAndMaybeNotify(reasonText)
	if reasonText and reasonText ~= "" then
		showNotice(tostring(reasonText), "Common")
	end
	resetTradeWindow()
end

local function showIncomingRequest(payload)
	if type(payload) ~= "table" then
		return
	end

	incomingSequence = incomingSequence + 1
	local sequence = incomingSequence
	incomingRequest = payload

	incomingText.Text = string.format("%s wants to trade with you", tostring(payload.fromPlayer or "Someone"))
	incomingSubtext.Text = "Accept to open the trade window"
	incomingBanner.Visible = true

	task.delay(30, function()
		if sequence ~= incomingSequence then
			return
		end
		if incomingBanner.Visible and incomingRequest and incomingRequest.tradeId == payload.tradeId then
			closeTradeAndMaybeNotify("Trade request expired")
			hideIncomingRequest()
		end
	end)
end

local function handleTradeUI(action, payload)
	if action == "request" then
		if activeTradeId then
			return
		end
		showIncomingRequest(payload)
		return
	end

	if action == "open" then
		if type(payload) ~= "table" then
			return
		end
		openTradeWindow(payload.tradeId, payload.partnerName)
		return
	end

	if action == "partner_offer" then
		if type(payload) ~= "table" or payload.tradeId ~= activeTradeId then
			return
		end
		partnerOfferCommitted = true
		myConfirmed = false
		partnerConfirmed = false
		partnerOfferPayload = payload
		updateTradeButton()
		renderTradeWindow()
		return
	end

	if action == "partner_confirmed" then
		if type(payload) ~= "table" or payload.tradeId ~= activeTradeId then
			return
		end
		partnerConfirmed = true
		updateStatusLabel()
		setConfirmButtonState()
		return
	end

	if action == "complete" then
		if type(payload) ~= "table" or payload.tradeId ~= activeTradeId then
			return
		end
		resetTradeWindow()
		return
	end

	if action == "cancelled" then
		if activeTradeId or incomingBanner.Visible then
			closeTradeAndMaybeNotify(type(payload) == "string" and payload or "Trade cancelled")
		end
		hideIncomingRequest()
		return
	end
end

tradeButton.Activated:Connect(function()
	if activeTradeId then
		tradeWindow.Visible = true
		browserPanel.Visible = false
		return
	end

	browserPanel.Visible = not browserPanel.Visible
	if browserPanel.Visible then
		renderPlayerBrowser()
	end
end)

browserClose.Activated:Connect(function()
	browserPanel.Visible = false
end)

tradeClose.Activated:Connect(function()
	if activeTradeId then
		tradeWindow.Visible = false
		return
	end
	tradeWindow.Visible = false
end)

incomingAccept.Activated:Connect(function()
	if not incomingRequest then
		return
	end

	local tradeId = incomingRequest.tradeId
	hideIncomingRequest()
	RespondTradeEvent:FireServer(tradeId, true)
end)

incomingDecline.Activated:Connect(function()
	if not incomingRequest then
		return
	end

	local tradeId = incomingRequest.tradeId
	hideIncomingRequest()
	CancelTradeEvent:FireServer(tradeId)
end)

setOfferButton.Activated:Connect(function()
	if not activeTradeId then
		return
	end

	local indices = sortedSelectedIndices(selectedIndices)
	SetTradeOfferEvent:FireServer(activeTradeId, indices)
	myOfferCommitted = true
	myConfirmed = false
	partnerConfirmed = false
	updateStatusLabel()
	setConfirmButtonState()
end)

confirmButton.Activated:Connect(function()
	if not activeTradeId then
		return
	end

	if not (myOfferCommitted and partnerOfferCommitted) then
		showNotice("Both sides need to set an offer first.", "Common")
		return
	end

	if myConfirmed then
		return
	end

	ConfirmTradeEvent:FireServer(activeTradeId)
	myConfirmed = true
	updateStatusLabel()
	setConfirmButtonState()
end)

cancelButton.Activated:Connect(function()
	if not activeTradeId then
		return
	end

	CancelTradeEvent:FireServer(activeTradeId)
end)

Players.PlayerAdded:Connect(function()
	if browserPanel.Visible and not activeTradeId then
		renderPlayerBrowser()
	end
end)

Players.PlayerRemoving:Connect(function()
	if browserPanel.Visible and not activeTradeId then
		renderPlayerBrowser()
	end
end)

if UpdateHUDEvent then
	UpdateHUDEvent.OnClientEvent:Connect(function(_payload)
		if activeTradeId then
			requestInventoryRefresh()
		end
	end)
end

TradeUIEvent.OnClientEvent:Connect(function(action, payload)
	handleTradeUI(action, payload)
end)

updateTradeButton()
updateSelectionStatus()
updateStatusLabel()
setConfirmButtonState()
