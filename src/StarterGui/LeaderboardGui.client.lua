-- LeaderboardGui.client.lua — Global depth leaderboard panel (top 10 + your rank)
-- Place in: StarterGui/LeaderboardGui (LocalScript)
--
-- Top-right "🏆 Leaderboard" toggle stacks below the Stats button.
-- Click opens a panel querying `GetTopDepths` RemoteFunction (cached server-side).
-- Auto-refreshes every 30s while open. Hides if Remotes/GetTopDepths is missing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════════════
-- Visual tokens (match StatsGui / HudGui language)
-- ═══════════════════════════════════════════════════════════════════
local PANEL_BG = Color3.fromRGB(20, 20, 25)
local CARD_BG = Color3.fromRGB(28, 28, 34)
local ROW_BG = Color3.fromRGB(34, 34, 42)
local ROW_BG_ALT = Color3.fromRGB(28, 28, 36)
local TEXT_PRIMARY = Color3.fromRGB(235, 235, 235)
local TEXT_MUTED = Color3.fromRGB(160, 160, 160)
local TEXT_SOFT = Color3.fromRGB(200, 200, 200)
local ACCENT_GOLD = Color3.fromRGB(255, 200, 50)
local ACCENT_BLUE = Color3.fromRGB(80, 160, 255)
local STROKE_DIM = Color3.fromRGB(60, 60, 75)
local STROKE_GOLD = Color3.fromRGB(255, 200, 50)

local REFRESH_INTERVAL = 30  -- seconds, while open
local WAIT_FOR_REMOTE_TIMEOUT = 5

-- ═══════════════════════════════════════════════════════════════════
-- Resolve RemoteFunction (gracefully bail if missing)
-- ═══════════════════════════════════════════════════════════════════
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
if not Remotes then
	warn("[LeaderboardGui] ReplicatedStorage.Remotes missing; aborting")
	return
end

local GetTopDepthsFunc = Remotes:WaitForChild("GetTopDepths", WAIT_FOR_REMOTE_TIMEOUT)
if not GetTopDepthsFunc then
	warn("[LeaderboardGui] GetTopDepths RemoteFunction missing; UI hidden")
	return
end

-- ═══════════════════════════════════════════════════════════════════
-- ScreenGui + toggle button
-- ═══════════════════════════════════════════════════════════════════
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeepDigLeaderboardGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 21
screenGui.Parent = playerGui

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "LeaderboardToggle"
toggleButton.Size = UDim2.fromOffset(150, 40)
toggleButton.AnchorPoint = Vector2.new(1, 0)
-- StatsGui toggle is at (1,-20, 0,20) size 120x40; stack ours below it.
toggleButton.Position = UDim2.new(1, -20, 0, 70)
toggleButton.BackgroundColor3 = PANEL_BG
toggleButton.BackgroundTransparency = 0.1
toggleButton.BorderSizePixel = 0
toggleButton.Text = "🏆 Leaderboard"
toggleButton.TextColor3 = TEXT_PRIMARY
toggleButton.TextSize = 16
toggleButton.Font = Enum.Font.GothamBold
toggleButton.AutoButtonColor = true
toggleButton.Parent = screenGui

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

local toggleStroke = Instance.new("UIStroke")
toggleStroke.Color = STROKE_DIM
toggleStroke.Thickness = 1
toggleStroke.Parent = toggleButton

-- ═══════════════════════════════════════════════════════════════════
-- Main panel
-- ═══════════════════════════════════════════════════════════════════
local panel = Instance.new("Frame")
panel.Name = "LeaderboardPanel"
panel.Size = UDim2.fromOffset(420, 520)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = PANEL_BG
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Visible = false
panel.ClipsDescendants = true
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = STROKE_DIM
panelStroke.Thickness = 1
panelStroke.Parent = panel

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundTransparency = 1
titleBar.Parent = panel

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, -64, 1, 0)
titleLabel.Position = UDim2.fromOffset(15, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "🏆 Deepest Diggers"
titleLabel.TextColor3 = ACCENT_GOLD
titleLabel.TextSize = 18
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.Size = UDim2.fromOffset(32, 32)
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

-- Subtitle / disclaimer
local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Size = UDim2.new(1, -30, 0, 16)
subtitle.Position = UDim2.fromOffset(15, 44)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Records update on session end"
subtitle.TextColor3 = TEXT_MUTED
subtitle.TextSize = 12
subtitle.Font = Enum.Font.Gotham
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = panel

-- Status line (errors, refreshing…)
local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.Size = UDim2.new(1, -30, 0, 18)
statusLabel.Position = UDim2.fromOffset(15, 62)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Loading..."
statusLabel.TextColor3 = TEXT_MUTED
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = panel

-- Scrolling list of rows
local listFrame = Instance.new("ScrollingFrame")
listFrame.Name = "List"
listFrame.Size = UDim2.new(1, -20, 1, -130)
listFrame.Position = UDim2.fromOffset(10, 84)
listFrame.BackgroundColor3 = CARD_BG
listFrame.BackgroundTransparency = 0.4
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 5
listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.Parent = panel

local listCorner = Instance.new("UICorner")
listCorner.CornerRadius = UDim.new(0, 8)
listCorner.Parent = listFrame

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 4)
listLayout.Parent = listFrame

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 6)
listPadding.PaddingBottom = UDim.new(0, 6)
listPadding.PaddingLeft = UDim.new(0, 6)
listPadding.PaddingRight = UDim.new(0, 6)
listPadding.Parent = listFrame

-- Footer: your rank line
local footer = Instance.new("Frame")
footer.Name = "Footer"
footer.Size = UDim2.new(1, -20, 0, 36)
footer.Position = UDim2.new(0, 10, 1, -42)
footer.BackgroundColor3 = CARD_BG
footer.BackgroundTransparency = 0.25
footer.BorderSizePixel = 0
footer.Parent = panel

local footerCorner = Instance.new("UICorner")
footerCorner.CornerRadius = UDim.new(0, 8)
footerCorner.Parent = footer

local footerStroke = Instance.new("UIStroke")
footerStroke.Color = STROKE_DIM
footerStroke.Thickness = 1
footerStroke.Parent = footer

local footerLabel = Instance.new("TextLabel")
footerLabel.Name = "YourRank"
footerLabel.Size = UDim2.new(1, -16, 1, 0)
footerLabel.Position = UDim2.fromOffset(8, 0)
footerLabel.BackgroundTransparency = 1
footerLabel.Text = ""
footerLabel.TextColor3 = TEXT_SOFT
footerLabel.TextSize = 14
footerLabel.Font = Enum.Font.GothamMedium
footerLabel.TextXAlignment = Enum.TextXAlignment.Left
footerLabel.Parent = footer

-- ═══════════════════════════════════════════════════════════════════
-- Row builder
-- ═══════════════════════════════════════════════════════════════════
local function clearList()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function rankPrefix(rank)
	if rank == 1 then return "🥇" end
	if rank == 2 then return "🥈" end
	if rank == 3 then return "🥉" end
	return "#" .. rank
end

local function makeRow(rank, displayName, depth, isYou)
	local row = Instance.new("Frame")
	row.Name = "Row_" .. rank
	row.Size = UDim2.new(1, 0, 0, 32)
	row.BackgroundColor3 = (rank % 2 == 0) and ROW_BG_ALT or ROW_BG
	row.BackgroundTransparency = 0.25
	row.BorderSizePixel = 0
	row.LayoutOrder = rank
	row.Parent = listFrame

	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0, 6)
	rc.Parent = row

	if isYou then
		local stroke = Instance.new("UIStroke")
		stroke.Color = STROKE_GOLD
		stroke.Thickness = 2
		stroke.Parent = row
	end

	local rankLbl = Instance.new("TextLabel")
	rankLbl.Name = "Rank"
	rankLbl.Size = UDim2.new(0, 50, 1, 0)
	rankLbl.Position = UDim2.fromOffset(8, 0)
	rankLbl.BackgroundTransparency = 1
	rankLbl.Text = rankPrefix(rank)
	rankLbl.TextColor3 = (rank <= 3) and ACCENT_GOLD or TEXT_MUTED
	rankLbl.TextSize = (rank <= 3) and 18 or 14
	rankLbl.Font = (rank <= 3) and Enum.Font.GothamBlack or Enum.Font.GothamBold
	rankLbl.TextXAlignment = Enum.TextXAlignment.Left
	rankLbl.Parent = row

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Name = "PlayerName"
	nameLbl.Size = UDim2.new(1, -180, 1, 0)
	nameLbl.Position = UDim2.fromOffset(60, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = displayName
	nameLbl.TextColor3 = isYou and ACCENT_GOLD or TEXT_PRIMARY
	nameLbl.TextSize = 14
	nameLbl.Font = isYou and Enum.Font.GothamBold or Enum.Font.GothamMedium
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Parent = row

	local depthLbl = Instance.new("TextLabel")
	depthLbl.Name = "Depth"
	depthLbl.Size = UDim2.new(0, 110, 1, 0)
	depthLbl.AnchorPoint = Vector2.new(1, 0)
	depthLbl.Position = UDim2.new(1, -8, 0, 0)
	depthLbl.BackgroundTransparency = 1
	depthLbl.Text = tostring(depth) .. " blocks"
	depthLbl.TextColor3 = ACCENT_BLUE
	depthLbl.TextSize = 14
	depthLbl.Font = Enum.Font.GothamBold
	depthLbl.TextXAlignment = Enum.TextXAlignment.Right
	depthLbl.Parent = row
end

local function makeMessageRow(text, color)
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Message"
	lbl.Size = UDim2.new(1, 0, 0, 80)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = color or TEXT_MUTED
	lbl.TextSize = 14
	lbl.Font = Enum.Font.Gotham
	lbl.TextWrapped = true
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.LayoutOrder = 1
	lbl.Parent = listFrame
end

-- ═══════════════════════════════════════════════════════════════════
-- Refresh logic
-- ═══════════════════════════════════════════════════════════════════
local refreshing = false
local lastRefreshAt = 0

local function refresh()
	if refreshing then return end
	refreshing = true
	statusLabel.Text = "Refreshing..."
	statusLabel.TextColor3 = TEXT_MUTED

	local ok, response = pcall(function()
		return GetTopDepthsFunc:InvokeServer()
	end)

	refreshing = false

	if not ok or type(response) ~= "table" then
		clearList()
		makeMessageRow("Leaderboard unavailable — try again later.", Color3.fromRGB(240, 120, 120))
		statusLabel.Text = "Connection error"
		statusLabel.TextColor3 = Color3.fromRGB(240, 120, 120)
		footerLabel.Text = ""
		lastRefreshAt = os.clock()
		return
	end

	clearList()

	local entries = response.entries or {}
	local yourDepth = response.yourDepth or 0
	local yourRank = response.yourRank
	local errMsg = response.error

	if errMsg or #entries == 0 then
		if errMsg then
			makeMessageRow("Leaderboard unavailable — try again later.", Color3.fromRGB(240, 120, 120))
			statusLabel.Text = "Service error"
			statusLabel.TextColor3 = Color3.fromRGB(240, 120, 120)
		else
			makeMessageRow("Be the first to set a record!", ACCENT_GOLD)
			statusLabel.Text = "Updated " .. os.date("%H:%M:%S")
			statusLabel.TextColor3 = TEXT_MUTED
		end
	else
		for i, entry in ipairs(entries) do
			local isYou = (entry.userId == player.UserId)
			local name = entry.name or "Unknown"
			local depth = tonumber(entry.depth) or 0
			makeRow(i, name, depth, isYou)
		end
		statusLabel.Text = "Updated " .. os.date("%H:%M:%S")
		statusLabel.TextColor3 = TEXT_MUTED
	end

	-- Footer: your rank line
	if yourDepth and yourDepth > 0 then
		if yourRank then
			footerLabel.Text = string.format("Your rank: #%d  (depth: %d)", yourRank, yourDepth)
			footerLabel.TextColor3 = ACCENT_GOLD
		else
			footerLabel.Text = string.format("Your depth: %d  (not in top 100)", yourDepth)
			footerLabel.TextColor3 = TEXT_SOFT
		end
	else
		footerLabel.Text = ""
	end

	lastRefreshAt = os.clock()
end

-- ═══════════════════════════════════════════════════════════════════
-- Open / close + auto-refresh
-- ═══════════════════════════════════════════════════════════════════
local function setOpen(open)
	panel.Visible = open
	player:SetAttribute("LeaderboardPanelOpen", open)
	if open then
		task.spawn(refresh)
	end
end

toggleButton.Activated:Connect(function()
	setOpen(not panel.Visible)
end)

closeButton.Activated:Connect(function()
	setOpen(false)
end)

-- Restore prior open state if attribute was set previously this session
if player:GetAttribute("LeaderboardPanelOpen") then
	setOpen(true)
end

-- Auto-refresh loop (only while panel is open)
task.spawn(function()
	while true do
		task.wait(1)
		if panel.Visible and (os.clock() - lastRefreshAt) >= REFRESH_INTERVAL and not refreshing then
			refresh()
		end
	end
end)

print("[DeepDig] LeaderboardGui loaded")
