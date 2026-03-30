-- Leaderboard.server.lua — Global depth leaderboard + server-local top 5
-- Place in: ServerScriptService/Leaderboard (Script)
--
-- Global:  OrderedDataStore, updated on PlayerRemoving with deepestBlock.
--          In-world Part (SurfaceGui) shows top 10, refreshes every 60 s.
-- Local:   In-memory scan of current players, shown as a secondary column
--          on the same board.  No DataStore needed.
-- Personal best: fires "New Personal Best!" Notify when a player sets a
--          new deepest record during their session.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local DepthStore = DataStoreService:GetOrderedDataStore("DeepDig_DepthLeaderboard_v1")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyEvent = Remotes:WaitForChild("Notify")
local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD")

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function getSharedData(player)
	local cache = _G.DeepDig_playerData
	if cache then
		return cache[player.UserId]
	end
	return nil
end

-- ─── Personal best tracking ──────────────────────────────────────────────────
-- We track the session-start deepestBlock per player so we can fire a
-- notification only when a new all-time record is actually broken.

local sessionDeepest = {} -- { [userId] = number } — value at join time

Players.PlayerAdded:Connect(function(player)
	task.wait(3) -- let GameManager load data first
	local data = getSharedData(player)
	if data then
		sessionDeepest[player.UserId] = data.deepestBlock or 0
	end
end)

Players.PlayerRemoving:Connect(function(player)
	sessionDeepest[player.UserId] = nil
end)

-- Called from DigBlockEvent path in GameManager — but since GameManager is a
-- separate script we poll instead.  Poll every 5 seconds for new personal bests.
task.spawn(function()
	while true do
		task.wait(5)
		for _, player in ipairs(Players:GetPlayers()) do
			local data = getSharedData(player)
			if data then
				local prev = sessionDeepest[player.UserId] or 0
				local current = data.deepestBlock or 0
				if current > prev then
					sessionDeepest[player.UserId] = current
					-- Only notify if prev > 0 (skip the very first few blocks)
					if prev > 5 then
						NotifyEvent:FireClient(
							player,
							"New Personal Best! Depth " .. current .. " blocks",
							"Rare"
						)
						UpdateHUDEvent:FireClient(player, {
							personalBest = current,
						})
					end
				end
			end
		end
	end
end)

-- ─── Global leaderboard — save on leave ──────────────────────────────────────

local function saveDepthToLeaderboard(player)
	local data = getSharedData(player)
	if not data then return end

	local depth = data.deepestBlock or 0
	if depth <= 0 then return end

	pcall(function()
		DepthStore:SetAsync("player_" .. player.UserId, depth)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	saveDepthToLeaderboard(player)
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveDepthToLeaderboard(player)
	end
end)

-- ─── Top-10 fetching ─────────────────────────────────────────────────────────

-- Returns a list of { rank, name, depth } for the global top 10.
local function fetchGlobalTop10()
	local results = {}
	local success, pages = pcall(function()
		return DepthStore:GetSortedAsync(false, 10) -- descending, 10 entries
	end)
	if not success or not pages then return results end

	local ok, entries = pcall(function() return pages:GetCurrentPage() end)
	if not ok or not entries then return results end

	for rank, entry in ipairs(entries) do
		-- entry.key is "player_<UserId>", entry.value is the depth
		local userId = tonumber(entry.key:match("player_(%d+)"))
		local name = "[unknown]"
		if userId then
			local ok2, displayName = pcall(function()
				return Players:GetNameFromUserIdAsync(userId)
			end)
			if ok2 then name = displayName end
		end
		table.insert(results, { rank = rank, name = name, depth = entry.value })
	end

	return results
end

-- Returns a list of { rank, name, depth } for players currently on the server.
local function getLocalTop5()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local data = getSharedData(player)
		if data then
			table.insert(list, { name = player.Name, depth = data.deepestBlock or 0 })
		end
	end

	table.sort(list, function(a, b) return a.depth > b.depth end)

	local top5 = {}
	for i = 1, math.min(5, #list) do
		top5[i] = { rank = i, name = list[i].name, depth = list[i].depth }
	end
	return top5
end

-- ─── In-world leaderboard Part ───────────────────────────────────────────────
-- Position: near the spawn platform, beside the dig site entrance.

local function buildLeaderboardPart()
	local part = Instance.new("Part")
	part.Name = "DepthLeaderboard"
	part.Size = Vector3.new(12, 8, 1)
	part.Position = Vector3.new(30, 6, 0) -- adjust in Studio as needed
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(20, 20, 30)
	part.Parent = workspace

	-- Decorative border
	local border = Instance.new("SelectionBox")
	border.Adornee = part
	border.Color3 = Color3.fromRGB(80, 160, 255)
	border.LineThickness = 0.05
	border.Parent = part

	-- SurfaceGui on front face
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(600, 400)
	gui.LightInfluence = 0
	gui.Parent = part

	-- Background
	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(12, 12, 20)
	bg.BackgroundTransparency = 0.1
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = bg

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 50)
	title.BackgroundTransparency = 1
	title.Text = "DEEPEST DIGGERS"
	title.TextColor3 = Color3.fromRGB(80, 200, 255)
	title.TextSize = 28
	title.Font = Enum.Font.GothamBlack
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Parent = bg

	-- Divider
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(0.9, 0, 0, 2)
	divider.Position = UDim2.new(0.05, 0, 0, 50)
	divider.BackgroundColor3 = Color3.fromRGB(80, 160, 255)
	divider.BorderSizePixel = 0
	divider.Parent = bg

	-- Two columns: global top 10 (left 60%) | server top 5 (right 40%)
	local globalCol = Instance.new("Frame")
	globalCol.Name = "GlobalColumn"
	globalCol.Size = UDim2.new(0.58, 0, 1, -55)
	globalCol.Position = UDim2.new(0.01, 0, 0, 55)
	globalCol.BackgroundTransparency = 1
	globalCol.Parent = bg

	local globalHeader = Instance.new("TextLabel")
	globalHeader.Size = UDim2.new(1, 0, 0, 28)
	globalHeader.BackgroundTransparency = 1
	globalHeader.Text = "GLOBAL TOP 10"
	globalHeader.TextColor3 = Color3.fromRGB(255, 200, 50)
	globalHeader.TextSize = 18
	globalHeader.Font = Enum.Font.GothamBold
	globalHeader.TextXAlignment = Enum.TextXAlignment.Center
	globalHeader.Parent = globalCol

	local globalList = Instance.new("Frame")
	globalList.Name = "List"
	globalList.Size = UDim2.new(1, 0, 1, -30)
	globalList.Position = UDim2.new(0, 0, 0, 30)
	globalList.BackgroundTransparency = 1
	globalList.Parent = globalCol

	local globalLayout = Instance.new("UIListLayout")
	globalLayout.SortOrder = Enum.SortOrder.LayoutOrder
	globalLayout.Padding = UDim.new(0, 3)
	globalLayout.Parent = globalList

	local serverCol = Instance.new("Frame")
	serverCol.Name = "ServerColumn"
	serverCol.Size = UDim2.new(0.38, 0, 1, -55)
	serverCol.Position = UDim2.new(0.61, 0, 0, 55)
	serverCol.BackgroundTransparency = 1
	serverCol.Parent = bg

	local serverHeader = Instance.new("TextLabel")
	serverHeader.Size = UDim2.new(1, 0, 0, 28)
	serverHeader.BackgroundTransparency = 1
	serverHeader.Text = "THIS SERVER"
	serverHeader.TextColor3 = Color3.fromRGB(100, 255, 100)
	serverHeader.TextSize = 18
	serverHeader.Font = Enum.Font.GothamBold
	serverHeader.TextXAlignment = Enum.TextXAlignment.Center
	serverHeader.Parent = serverCol

	local serverList = Instance.new("Frame")
	serverList.Name = "List"
	serverList.Size = UDim2.new(1, 0, 1, -30)
	serverList.Position = UDim2.new(0, 0, 0, 30)
	serverList.BackgroundTransparency = 1
	serverList.Parent = serverCol

	local serverLayout = Instance.new("UIListLayout")
	serverLayout.SortOrder = Enum.SortOrder.LayoutOrder
	serverLayout.Padding = UDim.new(0, 3)
	serverLayout.Parent = serverList

	-- Last updated label
	local updated = Instance.new("TextLabel")
	updated.Name = "LastUpdated"
	updated.Size = UDim2.new(1, 0, 0, 20)
	updated.Position = UDim2.new(0, 0, 1, -22)
	updated.BackgroundTransparency = 1
	updated.Text = "Updating..."
	updated.TextColor3 = Color3.fromRGB(80, 80, 100)
	updated.TextSize = 12
	updated.Font = Enum.Font.Gotham
	updated.TextXAlignment = Enum.TextXAlignment.Center
	updated.Parent = bg

	return part, gui
end

-- Create a single row label for a leaderboard entry
local function makeRow(parent, rank, name, depth, highlight)
	local row = Instance.new("TextLabel")
	row.Name = "Row_" .. rank
	row.Size = UDim2.new(1, 0, 0, 26)
	row.BackgroundTransparency = rank % 2 == 0 and 0.85 or 1
	row.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
	row.BorderSizePixel = 0

	local rankEmoji = rank == 1 and "🥇" or (rank == 2 and "🥈" or (rank == 3 and "🥉" or ("#" .. rank)))
	row.Text = rankEmoji .. "  " .. name .. "   " .. depth .. " blocks"
	row.TextColor3 = highlight and Color3.fromRGB(255, 220, 80) or Color3.fromRGB(200, 200, 220)
	row.TextSize = 14
	row.Font = rank <= 3 and Enum.Font.GothamBold or Enum.Font.Gotham
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.LayoutOrder = rank
	row.Parent = parent

	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0, 4)
	rc.Parent = row

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.Parent = row
end

-- ─── Refresh loop ────────────────────────────────────────────────────────────

local function refreshBoard(gui)
	local globalList = gui.Frame.GlobalColumn.List
	local serverList = gui.Frame.ServerColumn.List
	local updatedLabel = gui.Frame.LastUpdated

	-- Clear old rows
	for _, child in ipairs(globalList:GetChildren()) do
		if child:IsA("TextLabel") then child:Destroy() end
	end
	for _, child in ipairs(serverList:GetChildren()) do
		if child:IsA("TextLabel") then child:Destroy() end
	end

	-- Global top 10
	local globalEntries = fetchGlobalTop10()
	if #globalEntries == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 26)
		empty.BackgroundTransparency = 1
		empty.Text = "No records yet!"
		empty.TextColor3 = Color3.fromRGB(120, 120, 140)
		empty.TextSize = 14
		empty.Font = Enum.Font.Gotham
		empty.Parent = globalList
	else
		for _, entry in ipairs(globalEntries) do
			makeRow(globalList, entry.rank, entry.name, entry.depth, false)
		end
	end

	-- Server-local top 5
	local serverEntries = getLocalTop5()
	if #serverEntries == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 26)
		empty.BackgroundTransparency = 1
		empty.Text = "No players yet"
		empty.TextColor3 = Color3.fromRGB(120, 120, 140)
		empty.TextSize = 14
		empty.Font = Enum.Font.Gotham
		empty.Parent = serverList
	else
		for _, entry in ipairs(serverEntries) do
			makeRow(serverList, entry.rank, entry.name, entry.depth, entry.rank == 1)
		end
	end

	updatedLabel.Text = "Updated: " .. os.date("%H:%M:%S")
end

-- ─── Initialize ──────────────────────────────────────────────────────────────

task.spawn(function()
	-- Wait for workspace and GameManager to be ready
	task.wait(5)

	local part, gui = buildLeaderboardPart()

	-- Initial refresh
	refreshBoard(gui)

	-- Refresh every 60 seconds
	while true do
		task.wait(60)
		refreshBoard(gui)
	end
end)

print("[DeepDig] Leaderboard loaded")
