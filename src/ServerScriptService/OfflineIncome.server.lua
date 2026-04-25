-- OfflineIncome.server.lua — grant passive coins when players return
-- Place in: ServerScriptService/OfflineIncome (Script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyEvent = Remotes:WaitForChild("Notify")
local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD")

local OFFLINE_SECONDS_CAP = 8 * 3600
local OFFLINE_RATES = {
	[1] = 30,   -- Rusty Shovel
	[2] = 80,   -- Iron Pickaxe
	[3] = 200,  -- Steel Drill
	[4] = 500,  -- Dynamite Kit
	[5] = 1200, -- Laser Cutter
	[6] = 3000, -- Quantum Excavator
}

local processedPlayers = {}

local function getData(player)
	local cache = _G.DeepDig_playerData
	if not cache then return nil end
	return cache[player.UserId]
end

local function loadDataWithRetry(player)
	task.wait(2)

	local data = getData(player)
	if data then
		return data
	end

	task.wait(2)
	return getData(player)
end

local function grantOfflineIncome(player)
	if processedPlayers[player.UserId] then return end
	processedPlayers[player.UserId] = true

	local data = loadDataWithRetry(player)
	if not data then
		return
	end

	local previousLastSeenAt = data.lastSeenAt or 0
	if previousLastSeenAt <= 0 then
		return
	end

	local elapsed = math.clamp(os.time() - previousLastSeenAt, 0, OFFLINE_SECONDS_CAP)
	local coinsPerHour = OFFLINE_RATES[data.toolTier] or 0
	local reward = math.floor(coinsPerHour * elapsed / 3600)
	local processedAt = os.time()

	if reward < 1 then
		data.lastSeenAt = processedAt
		return
	end

	data.coins = data.coins + reward
	data.totalEarned = data.totalEarned + reward
	data.lastSeenAt = processedAt

	if not player.Parent then
		return
	end

	local minutes = math.floor(elapsed / 60)
	NotifyEvent:FireClient(
		player,
		"Welcome back! You earned " .. reward .. " coins while offline (" .. minutes .. " min).",
		"Rare"
	)
	UpdateHUDEvent:FireClient(player, {
		coins = data.coins,
	})
end

local function onPlayerAdded(player)
	task.spawn(grantOfflineIncome, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	processedPlayers[player.UserId] = nil
end)
