-- OfflineIncome.server.lua — grant passive coins when players return
-- Place in: ServerScriptService/OfflineIncome (Script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyEvent = Remotes:WaitForChild("Notify")
local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD")
local ServerEvents = ReplicatedStorage:WaitForChild("ServerEvents")
local PlayerDataReady = ServerEvents:WaitForChild("PlayerDataReady")
local OfflineIncomeRewardEvent = Remotes:FindFirstChild("OfflineIncomeReward")
if not OfflineIncomeRewardEvent then
	OfflineIncomeRewardEvent = Instance.new("RemoteEvent")
	OfflineIncomeRewardEvent.Name = "OfflineIncomeReward"
	OfflineIncomeRewardEvent.Parent = Remotes
end

local FOREMAN_PASS_ID = 4
local DEFAULT_OFFLINE_SECONDS_CAP = 8 * 3600
local FOREMAN_OFFLINE_SECONDS_CAP = 24 * 3600

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

local function awaitPlayerData(player, timeoutSeconds)
	local data = getData(player)
	if data then
		return data
	end

	local readyForThisPlayer = false
	local connection
	connection = PlayerDataReady.Event:Connect(function(p)
		if p == player then
			readyForThisPlayer = true
		end
	end)

	local elapsed = 0
	local step = 0.1
	local cap = timeoutSeconds or 30
	while not readyForThisPlayer and elapsed < cap and player.Parent do
		task.wait(step)
		elapsed = elapsed + step
	end

	connection:Disconnect()
	return getData(player)
end

local function getOfflineSecondsCap(data)
	if data and data.ownedGamepasses and data.ownedGamepasses[FOREMAN_PASS_ID] then
		return FOREMAN_OFFLINE_SECONDS_CAP
	end

	return DEFAULT_OFFLINE_SECONDS_CAP
end

local function formatOfflineDuration(seconds)
	seconds = math.max(0, math.floor(seconds))

	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	if hours > 0 and minutes > 0 then
		return hours .. "h " .. minutes .. "m"
	end

	if hours > 0 then
		return hours .. "h"
	end

	return minutes .. "m"
end

local function grantOfflineIncome(player)
	if processedPlayers[player.UserId] then return end
	processedPlayers[player.UserId] = true

	local data = awaitPlayerData(player, 30)
	if not data then
		processedPlayers[player.UserId] = nil
		return
	end

	local handledByGameManager = _G.DeepDig_offlineIncomeHandled
	if handledByGameManager and handledByGameManager[player.UserId] then
		return
	end

	local previousLastSeenAt = data.lastSeenAt or 0
	if previousLastSeenAt <= 0 then
		return
	end

	local offlineSecondsCap = getOfflineSecondsCap(data)
	local elapsed = math.clamp(os.time() - previousLastSeenAt, 0, offlineSecondsCap)
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

	local countedDuration = formatOfflineDuration(elapsed)
	local capDuration = formatOfflineDuration(offlineSecondsCap)
	local rewardSummary = {
		reward = reward,
		countedDuration = countedDuration,
		capDuration = capDuration,
		hitCap = elapsed >= offlineSecondsCap,
	}

	NotifyEvent:FireClient(
		player,
		"Welcome back! You earned " .. reward .. " coins while offline (" .. countedDuration .. " counted, capped at " .. capDuration .. ").",
		"Rare"
	)
	UpdateHUDEvent:FireClient(player, {
		coins = data.coins,
	})
	OfflineIncomeRewardEvent:FireClient(player, rewardSummary)
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
