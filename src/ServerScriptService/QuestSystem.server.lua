-- QuestSystem.server.lua
-- Client/server progress contract for other systems:
--   local QuestProgressBindable = ReplicatedStorage:WaitForChild("QuestProgressBindable")
--   QuestProgressBindable:Fire(player, "items_found", {
--     amount = 1,
--     rarity = item.rarity,
--     itemName = item.name,
--   })
-- Supported event types:
--   blocks_dug, items_found, rarity_found, coins_earned, kill_enemies, depth_reached
-- Block breaks still come through ServerEvents.BlockBroken.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestDatabase = require(ReplicatedStorage:WaitForChild("QuestDatabase"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ServerEvents = ReplicatedStorage:WaitForChild("ServerEvents")

local function getOrCreate(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end

	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

local GetQuestStatusFunc = getOrCreate(Remotes, "RemoteFunction", "GetQuestStatus")
local ClaimQuestEvent = getOrCreate(Remotes, "RemoteEvent", "ClaimQuest")
local NotifyEvent = Remotes:WaitForChild("Notify")
local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD")
local BlockBrokenEvent = ServerEvents:WaitForChild("BlockBroken")
local QuestProgressBindable = getOrCreate(ReplicatedStorage, "BindableEvent", "QuestProgressBindable")

local questById = {}
for _, quest in ipairs(QuestDatabase) do
	questById[quest.id] = quest
end

local weeklyQuestById = {}
local function indexWeeklyQuest(quest)
	if type(quest) == "table" and type(quest.id) == "string" then
		weeklyQuestById[quest.id] = quest
	end
end

indexWeeklyQuest(QuestDatabase.weeklyQuest)
if type(QuestDatabase.weeklyQuests) == "table" then
	for _, quest in ipairs(QuestDatabase.weeklyQuests) do
		indexWeeklyQuest(quest)
	end
end

local function currentDay()
	return os.date("!%Y-%m-%d")
end

local function currentWeekKey()
	-- %V (ISO 8601 week) isn't supported by Luau's os.date — using it
	-- throws "invalid conversion specifier" on every quest progress
	-- call. %W (Monday-based week of year) works and is just as stable
	-- as a DataStore key for "the same week".
	return os.date("!%Y-W%W")
end

local function selectedWeeklyQuestId(weekKey)
	if type(QuestDatabase.weeklyRoll) == "function" then
		local ok, questId = pcall(QuestDatabase.weeklyRoll, weekKey)
		if ok and type(questId) == "string" and weeklyQuestById[questId] then
			return questId
		end
	end

	if type(QuestDatabase.weeklyQuest) == "table" then
		return QuestDatabase.weeklyQuest.id
	end

	return nil
end

local function resolveWeeklyQuest(data)
	if data and type(data.weeklyQuestId) == "string" and weeklyQuestById[data.weeklyQuestId] then
		return weeklyQuestById[data.weeklyQuestId]
	end

	local questId = selectedWeeklyQuestId(currentWeekKey())
	if questId then
		return weeklyQuestById[questId]
	end

	if type(QuestDatabase.weeklyQuest) == "table" then
		return QuestDatabase.weeklyQuest
	end

	return nil
end

local function dailySeed()
	return math.floor(os.time() / 86400)
end

local function getData(player)
	local cache = _G.DeepDig_playerData
	if not cache then
		return nil
	end
	return cache[player.UserId]
end

local function ensureQuestFields(data)
	if type(data.questProgress) ~= "table" then
		data.questProgress = {}
	end
	if type(data.questClaimed) ~= "table" then
		data.questClaimed = {}
	end
	if type(data.questAssignedIds) ~= "table" then
		data.questAssignedIds = {}
	end
	if type(data.questDay) ~= "string" then
		data.questDay = ""
	end
	if type(data.weeklyQuestProgress) ~= "number" then
		data.weeklyQuestProgress = 0
	end
	if type(data.weeklyQuestClaimed) ~= "boolean" then
		data.weeklyQuestClaimed = false
	end
	if type(data.weeklyQuestWeekKey) ~= "string" then
		data.weeklyQuestWeekKey = ""
	end
	if type(data.weeklyQuestId) ~= "string" then
		data.weeklyQuestId = ""
	end
end

local function ensureWeeklyQuestState(data)
	local weekKey = currentWeekKey()
	local questId = selectedWeeklyQuestId(weekKey)
	if not questId then
		return
	end

	if data.weeklyQuestWeekKey ~= weekKey then
		data.weeklyQuestWeekKey = weekKey
		data.weeklyQuestId = questId
		data.weeklyQuestProgress = 0
		data.weeklyQuestClaimed = false
		return
	end

	if not weeklyQuestById[data.weeklyQuestId] then
		data.weeklyQuestId = questId
		local weeklyQuest = resolveWeeklyQuest(data)
		if weeklyQuest and weeklyQuest.type ~= "daily_claims" then
			data.weeklyQuestProgress = 0
			data.weeklyQuestClaimed = false
		end
	end
end

local function isAssignedQuest(data, questId)
	for _, assignedId in ipairs(data.questAssignedIds) do
		if assignedId == questId then
			return true
		end
	end
	return false
end

local function assignDailyQuests(data)
	local day = currentDay()
	local roll = QuestDatabase.dailyRoll(dailySeed())

	data.questDay = day
	data.questAssignedIds = {
		roll[1],
		roll[2],
		roll[3],
	}
	data.questProgress = {}
	data.questClaimed = {}

	for _, questId in ipairs(data.questAssignedIds) do
		data.questProgress[questId] = 0
	end

	return day
end

local function ensureTodayQuests(player)
	local data = getData(player)
	if not data then
		return nil
	end

	ensureQuestFields(data)
	ensureWeeklyQuestState(data)

	local day = currentDay()
	if data.questDay ~= day or #data.questAssignedIds == 0 then
		assignDailyQuests(data)
	else
		for _, questId in ipairs(data.questAssignedIds) do
			if data.questProgress[questId] == nil then
				data.questProgress[questId] = 0
			end
		end
	end

	return data
end

local function getNumber(value, fallback)
	if type(value) == "number" then
		return value
	end
	return fallback or 0
end

local function getEventAmount(eventData, fallback)
	if type(eventData) == "number" then
		return eventData
	end
	if type(eventData) == "table" then
		local amount = eventData.amount
			or eventData.count
			or eventData.value
			or eventData.coins
			or eventData.blocks
			or eventData.depth
		if type(amount) == "number" then
			return amount
		end
	end
	return fallback or 1
end

local function getEventDepth(eventData)
	if type(eventData) == "number" then
		return eventData
	end
	if type(eventData) == "table" then
		local depth = eventData.depth or eventData.value
		if type(depth) == "number" then
			return depth
		end
	end
	return nil
end

local function getEventRarity(eventData)
	if type(eventData) == "table" then
		return eventData.rarity or eventData.itemRarity
	end
	return nil
end

local function normalizeEventType(eventType)
	if type(eventType) ~= "string" then
		return nil
	end

	local lower = string.lower(eventType)
	local aliases = {
		block_broken = "blocks_dug",
		blockbroken = "blocks_dug",
		blocks_dug = "blocks_dug",
		item_found = "items_found",
		items_found = "items_found",
		coins = "coins_earned",
		coins_earned = "coins_earned",
		enemy_killed = "kill_enemies",
		enemies_killed = "kill_enemies",
		kill_enemy = "kill_enemies",
		kill_enemies = "kill_enemies",
		depth = "depth_reached",
		depth_reached = "depth_reached",
		rarity_found = "rarity_found",
		streak = "chain_streak",
		chain = "chain_streak",
		chain_streak = "chain_streak",
	}

	return aliases[lower] or lower
end

local function setProgress(data, questId, value)
	local quest = questById[questId]
	if not quest then
		return
	end

	local capped = math.min(quest.target, math.max(0, value))
	data.questProgress[questId] = capped
end

local function addProgress(data, questId, amount)
	local quest = questById[questId]
	if not quest then
		return
	end

	local current = getNumber(data.questProgress[questId], 0)
	setProgress(data, questId, current + amount)
end

local function incrementWeeklyQuestProgress(data)
	ensureWeeklyQuestState(data)
	local weeklyQuest = resolveWeeklyQuest(data)
	if type(weeklyQuest) ~= "table" or weeklyQuest.type ~= "daily_claims" then
		return
	end
	if data.weeklyQuestClaimed then
		return
	end

	local current = getNumber(data.weeklyQuestProgress, 0)
	data.weeklyQuestProgress = math.min(weeklyQuest.target, current + 1)
end

local function applyProgress(player, eventType, eventData)
	local data = ensureTodayQuests(player)
	if not data then
		return
	end

	local normalizedType = normalizeEventType(eventType)
	if not normalizedType then
		return
	end

	if normalizedType == "blocks_dug" then
		local amount = getEventAmount(eventData, 1)
		for _, questId in ipairs(data.questAssignedIds) do
			local quest = questById[questId]
			if quest and quest.type == "blocks_dug" then
				addProgress(data, questId, amount)
			end
		end
		return
	end

	if normalizedType == "items_found" then
		local amount = getEventAmount(eventData, 1)
		for _, questId in ipairs(data.questAssignedIds) do
			local quest = questById[questId]
			if quest and quest.type == "items_found" then
				addProgress(data, questId, amount)
			end
		end
		return
	end

	if normalizedType == "rarity_found" then
		local rarity = getEventRarity(eventData)
		if not rarity then
			return
		end

		local amount = getEventAmount(eventData, 1)
		for _, questId in ipairs(data.questAssignedIds) do
			local quest = questById[questId]
			if quest and quest.type == "rarity_found" and quest.rarityFilter == rarity then
				addProgress(data, questId, amount)
			end
		end
		return
	end

	if normalizedType == "coins_earned" then
		local amount = getEventAmount(eventData, 0)
		for _, questId in ipairs(data.questAssignedIds) do
			local quest = questById[questId]
			if quest and quest.type == "coins_earned" then
				addProgress(data, questId, amount)
			end
		end
		return
	end

	if normalizedType == "kill_enemies" then
		local amount = getEventAmount(eventData, 1)
		for _, questId in ipairs(data.questAssignedIds) do
			local quest = questById[questId]
			if quest and quest.type == "kill_enemies" then
				addProgress(data, questId, amount)
			end
		end
		return
	end

	if normalizedType == "depth_reached" then
		local depth = getEventDepth(eventData)
		if not depth then
			return
		end

		for _, questId in ipairs(data.questAssignedIds) do
			local quest = questById[questId]
			if quest and quest.type == "depth_reached" then
				local current = getNumber(data.questProgress[questId], 0)
				setProgress(data, questId, math.max(current, depth))
			end
		end

		local weeklyQuest = resolveWeeklyQuest(data)
		if type(weeklyQuest) == "table" and weeklyQuest.type == "depth_reached" and not data.weeklyQuestClaimed then
			local current = getNumber(data.weeklyQuestProgress, 0)
			data.weeklyQuestProgress = math.min(weeklyQuest.target, math.max(current, depth))
		end
		return
	end

	if normalizedType == "chain_streak" then
		-- Same shape as depth_reached: track the max streak seen this day.
		local streak = getEventAmount(eventData, 0)
		for _, questId in ipairs(data.questAssignedIds) do
			local quest = questById[questId]
			if quest and quest.type == "chain_streak" then
				local current = getNumber(data.questProgress[questId], 0)
				setProgress(data, questId, math.max(current, streak))
			end
		end
	end
end

local function buildQuestStatus(player)
	local data = ensureTodayQuests(player)
	local day = currentDay()
	local quests = {}
	local weeklyStatus = nil
	local weeklyQuest = resolveWeeklyQuest(data)

	if not data then
		if type(weeklyQuest) == "table" then
			weeklyStatus = {
				id = weeklyQuest.id,
				description = weeklyQuest.description,
				progress = 0,
				target = weeklyQuest.target,
				complete = false,
				claimed = false,
				reward = weeklyQuest.reward,
				weekKey = currentWeekKey(),
			}
		end

		return {
			quests = quests,
			day = day,
			weekly = weeklyStatus,
		}
	end

	for _, questId in ipairs(data.questAssignedIds) do
		local quest = questById[questId]
		if quest then
			local progress = getNumber(data.questProgress[questId], 0)
			quests[#quests + 1] = {
				id = quest.id,
				description = quest.description,
				progress = progress,
				target = quest.target,
				complete = progress >= quest.target,
			}
		end
	end

	weeklyQuest = resolveWeeklyQuest(data)
	if type(weeklyQuest) == "table" then
		local progress = math.min(weeklyQuest.target, getNumber(data.weeklyQuestProgress, 0))
		weeklyStatus = {
			id = weeklyQuest.id,
			description = weeklyQuest.description,
			progress = progress,
			target = weeklyQuest.target,
			complete = progress >= weeklyQuest.target,
			claimed = data.weeklyQuestClaimed == true,
			reward = weeklyQuest.reward,
			weekKey = data.weeklyQuestWeekKey ~= "" and data.weeklyQuestWeekKey or currentWeekKey(),
		}
	end

	return {
		quests = quests,
		day = data.questDay ~= "" and data.questDay or day,
		weekly = weeklyStatus,
	}
end

GetQuestStatusFunc.OnServerInvoke = function(player)
	return buildQuestStatus(player)
end

local function grantQuestReward(player, data, quest)
	local reward = quest.reward or {}
	data.coins = (data.coins or 0) + (reward.coins or 0)
	data.fragments = (data.fragments or 0) + (reward.fragments or 0)

	UpdateHUDEvent:FireClient(player, {
		coins = data.coins,
		fragments = data.fragments,
	})

	NotifyEvent:FireClient(
		player,
		"Quest claimed: " .. quest.description .. "!",
		"Rare"
	)
end

local function claimQuest(player, questId)
	if type(questId) ~= "string" then
		return
	end

	local data = ensureTodayQuests(player)
	if not data then
		return
	end
	ensureWeeklyQuestState(data)

	local weeklyQuest = resolveWeeklyQuest(data)
	if type(weeklyQuest) == "table" and questId == weeklyQuest.id then
		local progress = getNumber(data.weeklyQuestProgress, 0)
		if data.weeklyQuestClaimed then
			NotifyEvent:FireClient(player, "Weekly quest already claimed.", "Common")
			return
		end
		if progress < weeklyQuest.target then
			NotifyEvent:FireClient(player, "Weekly quest is not complete yet.", "Common")
			return
		end

		data.weeklyQuestClaimed = true
		data.weeklyQuestProgress = weeklyQuest.target
		grantQuestReward(player, data, weeklyQuest)
		return
	end

	local quest = questById[questId]
	if not quest then
		NotifyEvent:FireClient(player, "Unknown quest.", "Common")
		return
	end

	if not isAssignedQuest(data, questId) then
		NotifyEvent:FireClient(player, "That quest is not in today's rotation.", "Common")
		return
	end

	if data.questClaimed[questId] then
		NotifyEvent:FireClient(player, "Quest already claimed.", "Common")
		return
	end

	local progress = getNumber(data.questProgress[questId], 0)
	if progress < quest.target then
		NotifyEvent:FireClient(player, "Quest is not complete yet.", "Common")
		return
	end

	data.questClaimed[questId] = true
	incrementWeeklyQuestProgress(data)
	grantQuestReward(player, data, quest)
end

ClaimQuestEvent.OnServerEvent:Connect(function(player, questId)
	claimQuest(player, questId)
end)

BlockBrokenEvent.Event:Connect(function(player)
	applyProgress(player, "blocks_dug", { amount = 1 })
end)

QuestProgressBindable.Event:Connect(function(player, eventType, eventData)
	if not player or not player:IsA("Player") then
		return
	end

	applyProgress(player, eventType, eventData)
end)

local function onPlayerAdded(player)
	task.spawn(function()
		while player.Parent do
			if ensureTodayQuests(player) then
				return
			end
			task.wait(0.2)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

print("[DeepDig] QuestSystem loaded")
