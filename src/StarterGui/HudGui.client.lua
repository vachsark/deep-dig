-- HudGui.client.lua — Heads-up display (coins, depth, tool, notifications)
-- Place in: StarterGui/HudGui (LocalScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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

-- Fragments display
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
	if data.nextToolCost and data.nextToolName then
		upgradeButton.Text = "⬆️ " .. data.nextToolName .. " ($" .. data.nextToolCost .. ")"
	elseif not data.nextToolCost then
		upgradeButton.Text = "⬆️ MAX LEVEL"
		upgradeButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
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
	end
end)

print("[DeepDig] HUD loaded")
