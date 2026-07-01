-- OfflineIncome.server.lua — grant passive coins when players return
-- Place in: ServerScriptService/OfflineIncome (Script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
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

local function hasOwnedGamepass(data, passId, passKey)
	local ownedGamepasses = data and data.ownedGamepasses
	if not ownedGamepasses then
		return false
	end

	return ownedGamepasses[passId] == true or (passKey and ownedGamepasses[passKey] == true)
end

local function getOfflineSecondsCap(data)
	-- Foreman's Pass is intentionally not wired yet; keep v1 capped at 8h.
	return Config.OFFLINE_INCOME_DEFAULT_CAP_SECONDS
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

	local processedAt = os.time()
	local previousLastSeenAt = math.floor(tonumber(data.lastSeenAt) or 0)
	data.lastLoginAt = processedAt

	if previousLastSeenAt <= 0 then
		data.lastSeenAt = processedAt
		return
	end

	if previousLastSeenAt > processedAt then
		data.lastSeenAt = processedAt
		return
	end

	local offlineSecondsCap = getOfflineSecondsCap(data)
	local offlineSeconds = processedAt - previousLastSeenAt
	local elapsed = math.min(offlineSeconds, offlineSecondsCap)
	local tool = Config.TOOLS[data.toolTier] or Config.TOOLS[1]
	local toolDamage = tool and tool.damage or 1
	local coinsPerMinute = toolDamage * Config.OFFLINE_INCOME_COINS_PER_DAMAGE_PER_MINUTE
	local reward = math.floor((elapsed / 60) * coinsPerMinute)

	if reward < 1 then
		data.lastSeenAt = processedAt
		return
	end

	data.coins = (data.coins or 0) + reward
	data.totalEarned = (data.totalEarned or 0) + reward
	data.lastSeenAt = processedAt

	if not player.Parent then
		return
	end

	local countedDuration = formatOfflineDuration(elapsed)
	local capDuration = formatOfflineDuration(offlineSecondsCap)
	local totalDuration = formatOfflineDuration(offlineSeconds)
	local cappedAwayDuration = formatOfflineDuration(math.max(0, offlineSeconds - elapsed))
	local rewardSummary = {
		reward = reward,
		countedDuration = countedDuration,
		capDuration = capDuration,
		totalDuration = totalDuration,
		cappedAwayDuration = cappedAwayDuration,
		toolName = tool and tool.name or "Tool",
		coinsPerMinute = coinsPerMinute,
		hitCap = offlineSeconds >= offlineSecondsCap,
	}

	NotifyEvent:FireClient(
		player,
		"Welcome back! " .. rewardSummary.toolName .. " earned " .. reward .. " coins at " .. coinsPerMinute .. "/min while you were away.",
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
