-- HudGui.client.lua — Heads-up display (coins, depth, tool, notifications)
-- Place in: StarterGui/HudGui (LocalScript)
--
-- Added in this version:
--   • Login streak display (top-left, below fragments counter)
--   • Gamepass status badges (row of small icons when passes are active)
--   • Shop button + gamepass shop panel

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

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

-- ─── Gamepass badge row ──────────────────────────────────────────────────────
-- Small pills shown when a gamepass is active.

local badgeRow = Instance.new("Frame")
badgeRow.Name = "PassBadges"
badgeRow.Size = UDim2.new(0, 300, 0, 24)
badgeRow.Position = UDim2.new(0, 20, 0, 142)
badgeRow.BackgroundTransparency = 1
badgeRow.Parent = screenGui

local badgeLayout = Instance.new("UIListLayout")
badgeLayout.FillDirection = Enum.FillDirection.Horizontal
badgeLayout.SortOrder = Enum.SortOrder.LayoutOrder
badgeLayout.Padding = UDim.new(0, 4)
badgeLayout.Parent = badgeRow

local PASS_BADGE_COLORS = {
	[1] = Color3.fromRGB(255, 80,  80),  -- DOUBLE_LOOT  — red
	[2] = Color3.fromRGB(255, 200, 0),   -- VIP          — gold
	[3] = Color3.fromRGB(80,  220, 80),  -- LUCKY        — green
}

local PASS_BADGE_LABELS = {
	[1] = "2× LOOT",
	[2] = "★ VIP",
	[3] = "🍀 LUCKY",
}

local badgeInstances = {} -- passId → TextLabel

local function updatePassBadges(ownedGamepasses)
	-- Clear old badges
	for _, child in ipairs(badgeRow:GetChildren()) do
		if child:IsA("TextLabel") then child:Destroy() end
	end
	badgeInstances = {}

	if not ownedGamepasses then return end

	for passId = 1, 3 do
		if ownedGamepasses[passId] then
			local badge = Instance.new("TextLabel")
			badge.Size = UDim2.new(0, 72, 0, 20)
			badge.BackgroundColor3 = PASS_BADGE_COLORS[passId]
			badge.BackgroundTransparency = 0.2
			badge.BorderSizePixel = 0
			badge.Text = PASS_BADGE_LABELS[passId]
			badge.TextColor3 = Color3.fromRGB(20, 15, 0)
			badge.TextSize = 11
			badge.Font = Enum.Font.GothamBlack
			badge.TextXAlignment = Enum.TextXAlignment.Center
			badge.LayoutOrder = passId
			badge.Parent = badgeRow

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 4)
			corner.Parent = badge

			badgeInstances[passId] = badge
		end
	end
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

upgradeButton.MouseButton1Click:Connect(function()
	Remotes.BuyTool:FireServer(currentToolTier + 1)
end)

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
local cardsFrame = Instance.new("Frame")
cardsFrame.Name = "Cards"
cardsFrame.Size = UDim2.new(1, -20, 1, -60)
cardsFrame.Position = UDim2.new(0, 10, 0, 54)
cardsFrame.BackgroundTransparency = 1
cardsFrame.ZIndex = 11
cardsFrame.Parent = shopPanel

local cardsLayout = Instance.new("UIListLayout")
cardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardsLayout.Padding = UDim.new(0, 8)
cardsLayout.Parent = cardsFrame

-- Gamepass card colours (matching badge row)
local CARD_COLORS = {
	[1] = Color3.fromRGB(180, 40, 40),
	[2] = Color3.fromRGB(160, 130, 0),
	[3] = Color3.fromRGB(30, 130, 30),
}

local passCards = {} -- passId → { frame, buyBtn, statusLabel }

local function buildPassCard(passInfo)
	local card = Instance.new("Frame")
	card.Name = "Card_" .. passInfo.id
	card.Size = UDim2.new(1, 0, 0, 70)
	card.BackgroundColor3 = Color3.fromRGB(28, 24, 40)
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
	strip.BackgroundColor3 = CARD_COLORS[passInfo.id] or Color3.fromRGB(100, 100, 100)
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
	nameLabel.TextColor3 = Color3.fromRGB(240, 230, 255)
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
	descLabel.TextColor3 = Color3.fromRGB(170, 160, 190)
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
	buyBtn.BackgroundColor3 = CARD_COLORS[passInfo.id] or Color3.fromRGB(80, 80, 80)
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

	buyBtn.MouseButton1Click:Connect(function()
		if Remotes:FindFirstChild("PromptGamepass") then
			Remotes.PromptGamepass:FireServer(passInfo.id)
		end
	end)

	passCards[passInfo.id] = { frame = card, buyBtn = buyBtn }
	return card
end

local function setCardOwned(passId, owned)
	local card = passCards[passId]
	if not card then return end

	if owned then
		card.buyBtn.Text = "✓ Owned"
		card.buyBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 40)
		card.buyBtn.Active = false
	else
		card.buyBtn.Active = true
	end
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

Remotes.UpdateHUD.OnClientEvent:Connect(function(data)
	if data.coins then
		coinsLabel.Text = "🪙 " .. tostring(math.floor(data.coins))
	end
	if data.depth then
		local tierText = data.tierName or "Surface"
		depthLabel.Text = "⛏️ " .. tierText .. " (Depth: " .. data.depth .. ")"
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
	if data.inventoryCount then
		invLabel.Text = "Items: " .. tostring(data.inventoryCount)
	end
	if data.fragments then
		fragLabel.Text = "Fragments: " .. tostring(data.fragments)
	end
	if data.loginStreak then
		local day = (data.loginStreak - 1) % 7 + 1
		local emoji = day == 7 and "🏆" or "🔥"
		streakLabel.Text = emoji .. " Streak: Day " .. day .. " (×" .. data.loginStreak .. ")"
	end
	if data.nextToolCost and data.nextToolName then
		upgradeButton.Text = "⬆️ " .. data.nextToolName .. " ($" .. data.nextToolCost .. ")"
	elseif data.nextToolCost == nil and data.toolTier then
		upgradeButton.Text = "⬆️ MAX LEVEL"
		upgradeButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
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
end)

Remotes.ItemFound.OnClientEvent:Connect(function(item)
	showNotification("Found: " .. item.name .. " (+" .. item.sellValue .. " coins)", item.rarity)
end)

Remotes.EventTriggered.OnClientEvent:Connect(function(eventName, message, duration)
	showNotification("⚡ " .. message, "Legendary")
end)

Remotes.Notify.OnClientEvent:Connect(function(message, rarity)
	showNotification(message, rarity)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Initial load
-- ═══════════════════════════════════════════════════════════════════

task.spawn(function()
	local data = Remotes.GetPlayerData:InvokeServer()
	if data then
		coinsLabel.Text = "🪙 " .. tostring(math.floor(data.coins))
		toolLabel.Text = "🔧 " .. data.toolName
		blocksLabel.Text = "Blocks: " .. tostring(data.totalBlocksDug)
		invLabel.Text = "Items: " .. tostring(#data.inventory)
		currentToolTier = data.toolTier

		if data.nextToolCost and data.nextToolName then
			upgradeButton.Text = "⬆️ " .. data.nextToolName .. " ($" .. data.nextToolCost .. ")"
		end

		if data.loginStreak and data.loginStreak > 0 then
			local day = (data.loginStreak - 1) % 7 + 1
			local emoji = day == 7 and "🏆" or "🔥"
			streakLabel.Text = emoji .. " Streak: Day " .. day .. " (×" .. data.loginStreak .. ")"
		end

		if data.ownedGamepasses then
			updatePassBadges(data.ownedGamepasses)
		end
	end
end)

print("[DeepDig] HUD loaded")
