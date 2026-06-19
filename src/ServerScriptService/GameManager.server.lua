-- GameManager.server.lua — Core game loop, player data, saving
-- Place in: ServerScriptService/GameManager (Script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local ItemDatabase = require(ReplicatedStorage:WaitForChild("ItemDatabase"))
local PetDatabase = require(ReplicatedStorage:WaitForChild("PetDatabase"))

-- DataStore for persistence. In unpublished Studio places GetDataStore can
-- throw "You must publish this place to the web" — wrap so GameManager keeps
-- loading and creates the Remotes/ServerEvents folders the rest of the game
-- depends on. Read/write call sites are already pcall-wrapped.
local PlayerDataStore
do
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore("DeepDig_PlayerData_v1")
	end)
	if ok then
		PlayerDataStore = store
	else
		warn("[DeepDig] DataStore unavailable (unpublished Studio?) — running with in-memory data only")
		PlayerDataStore = {
			GetAsync = function() return nil end,
			SetAsync = function() end,
			UpdateAsync = function() end,
		}
	end
end

-- RemoteEvents for client-server communication
local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

local function createRemote(name, className)
	local remote = Instance.new(className or "RemoteEvent")
	remote.Name = name
	remote.Parent = Remotes
	return remote
end

-- Server-to-server communication (BindableEvents)
local ServerEvents = Instance.new("Folder")
ServerEvents.Name = "ServerEvents"
ServerEvents.Parent = ReplicatedStorage

local BlockBrokenEvent = Instance.new("BindableEvent")
BlockBrokenEvent.Name = "BlockBroken"
BlockBrokenEvent.Parent = ServerEvents

local TriggerWorldEvent = Instance.new("BindableEvent")
TriggerWorldEvent.Name = "TriggerWorldEvent"
TriggerWorldEvent.Parent = ServerEvents

-- Fired per player after their persisted data finishes loading.
-- Consumers (DailyStreak, Gamepasses, Leaderboard, Rebirth) wait on this
-- instead of sleeping a fixed `task.wait(N)` and hoping GameManager beat
-- them to populate `_G.DeepDig_playerData`. See awaitPlayerData() helper
-- in each consumer.
local PlayerDataReady = Instance.new("BindableEvent")
PlayerDataReady.Name = "PlayerDataReady"
PlayerDataReady.Parent = ServerEvents

-- Fires (player, item) every time an item is added to data.inventory.
-- Race-free signal for systems that need to react to a new find — e.g.
-- BadgeSystem awarding first_rare_find / first_legendary. Subscribers
-- should expect the same record shape that goes into inventory:
--   { name, rarity, sellValue, ... }
-- Idempotent find-or-create: if another script created it first, reuse it.
local ItemFoundBindable = ServerEvents:FindFirstChild("ItemFoundBindable")
if not ItemFoundBindable then
	ItemFoundBindable = Instance.new("BindableEvent")
	ItemFoundBindable.Name = "ItemFoundBindable"
	ItemFoundBindable.Parent = ServerEvents
end
local SellItemEvent = createRemote("SellItem")
local BuyToolEvent = createRemote("BuyTool")
local SellAllEvent = createRemote("SellAll")
local UpdateHUDEvent = createRemote("UpdateHUD")
local ItemFoundEvent = createRemote("ItemFound")
local EventTriggeredEvent = createRemote("EventTriggered")
local NotifyEvent = createRemote("Notify")
local GetPlayerDataFunc = createRemote("GetPlayerData", "RemoteFunction")
local MarkFTUEHintsSeenEvent = createRemote("MarkFTUEHintsSeen")
local PlaySound = Remotes:WaitForChild("PlaySound", 5)
local REFRESH_EXCAVATOR_VISUAL_EVENT_NAME = "RefreshExcavatorVisual"

-- ── Quest progress feeder ────────────────────────────────────────
-- QuestSystem creates ReplicatedStorage.QuestProgressBindable on load
-- and listens for (player, eventType, eventData). Other server systems
-- fire it to notify of progress. The helper short-circuits gracefully
-- when QuestSystem hasn't loaded yet (BindableEvent absent).
local QuestProgressBindable = ReplicatedStorage:FindFirstChild("QuestProgressBindable")
local function fireQuestProgress(player, eventType, eventData)
	if not QuestProgressBindable then
		QuestProgressBindable = ReplicatedStorage:FindFirstChild("QuestProgressBindable")
	end
	if QuestProgressBindable then
		QuestProgressBindable:Fire(player, eventType, eventData)
	end
end

local function isRareRevealRarity(rarity)
	return rarity == "Rare" or rarity == "Epic" or rarity == "Legendary" or rarity == "Mythic"
end

local function getDepthTierRecord(depth)
	for index, tier in ipairs(Config.TIERS or {}) do
		if depth >= tier.minDepth and depth <= tier.maxDepth then
			return tier, index
		end
	end

	return nil, nil
end

local function buildDepthTierUnlockedPayload(previousDepth, newDepth)
	local previousTier, previousIndex = getDepthTierRecord(previousDepth)
	local newTier, newIndex = getDepthTierRecord(newDepth)
	if not previousTier or not newTier or not previousIndex or not newIndex then
		return nil
	end
	if previousTier.name == newTier.name or newIndex <= previousIndex then
		return nil
	end

	return {
		tierName = newTier.name,
		minDepth = newTier.minDepth,
		maxDepth = newTier.maxDepth,
		color = newTier.color,
		depth = newDepth,
	}
end

local function buildDepthMilestonePayload(previousDepth, newDepth)
	local previousMilestone = math.floor((previousDepth or 0) / 25)
	local newMilestone = math.floor((newDepth or 0) / 25)
	if newMilestone <= previousMilestone then
		return nil
	end

	local milestoneDepth = newMilestone * 25
	local tier = getDepthTierRecord(milestoneDepth)

	return {
		depth = milestoneDepth,
		tierName = tier and tier.name or ItemDatabase.getTierForDepth(milestoneDepth),
		color = tier and tier.color or nil,
	}
end

local function fireItemFindSounds(player, rarity)
	if not PlaySound then
		return
	end

	PlaySound:FireClient(player, "item_found")
	if isRareRevealRarity(rarity) then
		PlaySound:FireClient(player, "rare_reveal")
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Player Data Management
-- ═══════════════════════════════════════════════════════════════════

local playerData = {} -- In-memory cache
_G.DeepDig_playerData = playerData -- Shared with DailyStreak, Leaderboard, Gamepasses
local offlineIncomeHandled = {}
_G.DeepDig_offlineIncomeHandled = offlineIncomeHandled
local ENEMY_DANGER_UNLOCK_DEPTH = 11 -- Keep aligned with EnemySystem.server.lua FIRST_ENEMY_DEPTH.

local DEFAULT_DATA = {
	coins = Config.STARTING_COINS,
	toolTier = 1,
	totalBlocksDug = 0,
	deepestBlock = 0,
	inventory = {},       -- { {name, rarity, sellValue}, ... }
	collections = {},     -- { ["T-Rex Tooth"] = true, ... }
	fragments = 0,        -- Duplicate recycling currency
	rebirths = 0,
	enemyKills = 0,
	totalEarned = 0,
	lastSeenAt = 0,      -- Unix timestamp of the last successful save
	lastLoginDate = "",   -- "YYYY-MM-DD" for streak tracking
	loginStreak = 0,      -- Consecutive daily login count
	streakReviveEligible = false,
	streakRevivePending = false,
	streakReviveBaseStreak = 0,
	streakReviveOfferDate = "",
	streakReviveProcessedReceiptId = "",
	ownedGamepasses = {}, -- { [passId] = true }
	friendReferralRewards = {}, -- { [friendUserIdString] = true }
	crewMailbox = {}, -- { {id, fromUserId, fromName, fromDisplayName, sentAt, item}, ... }
	firstSellAffordabilityGrantUsed = false, -- FTUE: one-time first-sell catch-up
	ftueHintsSeen = false,
	enemyDangerUnlockedSeen = false,
	rarePity = 0,
}

local function getRarePityThreshold()
	return math.max(1, math.floor(tonumber(Config.RARE_PITY_THRESHOLD) or 8))
end

local function clampRarePity(value)
	local threshold = getRarePityThreshold()
	local pity = math.floor(tonumber(value) or 0)
	return math.max(0, math.min(threshold, pity))
end

local function normalizeRarePity(data)
	data.rarePity = clampRarePity(data.rarePity)
end

local function addRarePityHudFields(payload, data)
	payload.rarePityThreshold = getRarePityThreshold()
	payload.rarePity = data and clampRarePity(data.rarePity) or 0
	return payload
end

local function shouldForceRarePity(data, isNewPlayer, isFirstEverFind)
	if isNewPlayer or isFirstEverFind then
		return false
	end

	return clampRarePity(data and data.rarePity) >= getRarePityThreshold()
end

local function recordRarePityAward(data, rarity)
	if not data then
		return
	end

	if isRareRevealRarity(rarity) then
		data.rarePity = 0
	elseif rarity == "Common" or rarity == "Uncommon" then
		data.rarePity = math.min(getRarePityThreshold(), clampRarePity(data.rarePity) + 1)
	else
		data.rarePity = clampRarePity(data.rarePity)
	end
end

local function normalizeBooleanMap(value)
	local normalized = {}
	if type(value) ~= "table" then
		return normalized
	end

	for key, claimed in pairs(value) do
		if claimed == true then
			normalized[tostring(key)] = true
		end
	end

	return normalized
end

local function cloneMailboxItem(item)
	if type(item) ~= "table" or type(item.name) ~= "string" or item.name == "" then
		return nil
	end

	return {
		name = item.name,
		rarity = type(item.rarity) == "string" and item.rarity or "Common",
		sellValue = tonumber(item.sellValue) or 0,
	}
end

local function normalizeCrewMailbox(value)
	local normalized = {}
	if type(value) ~= "table" then
		return normalized
	end

	for _, entry in ipairs(value) do
		if type(entry) == "table" then
			local id = math.floor(tonumber(entry.id) or 0)
			local item = cloneMailboxItem(entry.item)
			if id > 0 and item then
				table.insert(normalized, {
					id = id,
					fromUserId = math.floor(tonumber(entry.fromUserId) or 0),
					fromName = type(entry.fromName) == "string" and entry.fromName or "Crewmate",
					fromDisplayName = type(entry.fromDisplayName) == "string" and entry.fromDisplayName or "Crewmate",
					sentAt = math.floor(tonumber(entry.sentAt) or 0),
					item = item,
				})
			end
		end
	end

	return normalized
end

local function loadPlayerData(player)
	local success, data = pcall(function()
		return PlayerDataStore:GetAsync("player_" .. player.UserId)
	end)

	if success and data then
		-- Merge with defaults (handles new fields)
		for key, default in pairs(DEFAULT_DATA) do
			if data[key] == nil then
				data[key] = default
			end
		end
		playerData[player.UserId] = data
	else
		playerData[player.UserId] = table.clone(DEFAULT_DATA)
	end

	playerData[player.UserId].friendReferralRewards = normalizeBooleanMap(playerData[player.UserId].friendReferralRewards)
	playerData[player.UserId].crewMailbox = normalizeCrewMailbox(playerData[player.UserId].crewMailbox)
	normalizeRarePity(playerData[player.UserId])
	if (playerData[player.UserId].deepestBlock or 0) >= ENEMY_DANGER_UNLOCK_DEPTH then
		playerData[player.UserId].enemyDangerUnlockedSeen = true
	end

	return playerData[player.UserId]
end

local function savePlayerData(player)
	local data = playerData[player.UserId]
	if not data then return true end

	data.lastSeenAt = os.time()
	normalizeRarePity(data)
	data.crewMailbox = normalizeCrewMailbox(data.crewMailbox)

	local success, err = pcall(function()
		PlayerDataStore:SetAsync("player_" .. player.UserId, data)
	end)

	if success then
		return true
	end

	warn(string.format("[DeepDig] save FAILED for %s (UserId %d): %s", player.Name, player.UserId, tostring(err)))
	task.wait(1)

	success, err = pcall(function()
		PlayerDataStore:SetAsync("player_" .. player.UserId, data)
	end)

	return success
end

local function getPlayerData(player)
	return playerData[player.UserId]
end

local function hasOwnedGamepass(data, passId, passKey)
	local ownedGamepasses = data and data.ownedGamepasses
	if not ownedGamepasses then
		return false
	end

	return ownedGamepasses[passId] == true or (passKey and ownedGamepasses[passKey] == true)
end

local addStandardHudFields
local getEquippedPetRecord
local getEquippedPetMultipliers

local function getOfflineIncomeCapSeconds(data)
	if hasOwnedGamepass(data, Config.GAMEPASS_FOREMAN_ID, Config.GAMEPASS_FOREMAN) then
		return Config.OFFLINE_INCOME_FOREMAN_CAP_SECONDS
	end

	return Config.OFFLINE_INCOME_DEFAULT_CAP_SECONDS
end

local function formatOfflineDuration(seconds)
	seconds = math.max(0, math.floor(seconds or 0))

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

local function grantOfflineIncome(player, data)
	offlineIncomeHandled[player.UserId] = true

	local previousLastSeenAt = data.lastSeenAt or 0
	if previousLastSeenAt <= 0 then
		return nil
	end

	local now = os.time()
	local offlineSeconds = math.max(0, now - previousLastSeenAt)
	data.lastSeenAt = now

	if offlineSeconds < Config.OFFLINE_INCOME_MIN_SECONDS then
		return nil
	end

	local capSeconds = getOfflineIncomeCapSeconds(data)
	local countedSeconds = math.min(offlineSeconds, capSeconds)
	local tool = Config.TOOLS[data.toolTier] or Config.TOOLS[1]
	local toolDamage = tool and tool.damage or 1
	local coinsPerMinute = toolDamage * Config.OFFLINE_INCOME_COINS_PER_DAMAGE_PER_MINUTE
	local reward = math.floor((countedSeconds / 60) * coinsPerMinute)
	if reward <= 0 then
		return nil
	end

	data.coins = (data.coins or 0) + reward
	data.totalEarned = (data.totalEarned or 0) + reward
	fireQuestProgress(player, "coins_earned", { amount = reward })

	return {
		reward = reward,
		countedSeconds = countedSeconds,
		capSeconds = capSeconds,
		offlineSeconds = offlineSeconds,
		cappedAwaySeconds = math.max(0, offlineSeconds - countedSeconds),
		toolName = tool and tool.name or "Tool",
		coinsPerMinute = coinsPerMinute,
		hitCap = offlineSeconds >= capSeconds,
	}
end

local function notifyOfflineIncome(player, data, result)
	if not result then
		return
	end

	task.delay(1, function()
		if player.Parent ~= Players then
			return
		end

		UpdateHUDEvent:FireClient(player, addStandardHudFields({
			coins = data.coins,
			totalEarned = data.totalEarned,
			rebirths = data.rebirths or 0,
			offlineIncome = {
				reward = result.reward,
				countedDuration = formatOfflineDuration(result.countedSeconds),
				capDuration = formatOfflineDuration(result.capSeconds),
				totalDuration = formatOfflineDuration(result.offlineSeconds),
				cappedAwayDuration = formatOfflineDuration(result.cappedAwaySeconds),
				toolName = result.toolName,
				coinsPerMinute = result.coinsPerMinute,
				hitCap = result.hitCap == true,
			},
		}, data, player))
	end)
end

local backpackFullNotifiedAt = {}

local function hasInfiniteBackpack(data)
	return hasOwnedGamepass(
		data,
		Config.GAMEPASS_INFINITE_BACKPACK_ID,
		Config.GAMEPASS_INFINITE_BACKPACK
	)
end

local function getBackpackCapacity(data)
	if hasInfiniteBackpack(data) then
		return nil
	end

	return Config.DEFAULT_BACKPACK_CAPACITY
end

local function hasInventorySpace(data, itemCount)
	if not data or not data.inventory then
		return false
	end

	local capacity = getBackpackCapacity(data)
	if not capacity then
		return true
	end

	return #data.inventory + (itemCount or 1) <= capacity
end

local function getInventoryCapacityLabel(data)
	local capacity = getBackpackCapacity(data)
	return capacity or "unlimited"
end

local function addInventoryHudFields(payload, data)
	payload.inventoryCount = data.inventory and #data.inventory or 0
	payload.inventoryCapacity = getInventoryCapacityLabel(data)
	return payload
end

local function notifyBackpackFull(player)
	local now = tick()
	local last = backpackFullNotifiedAt[player]
	if last and now - last < 2 then
		return
	end

	backpackFullNotifiedAt[player] = now
	NotifyEvent:FireClient(player, "Backpack full - sell items before collecting more.", "Common")
end

local function tryAddInventoryItem(player, item)
	local data = getPlayerData(player)
	if not data then
		return false
	end

	if not hasInventorySpace(data, 1) then
		notifyBackpackFull(player)
		return false
	end

	table.insert(data.inventory, item)
	return true
end

_G.DeepDig_tryAddInventoryItem = tryAddInventoryItem
_G.DeepDig_hasInventorySpace = hasInventorySpace
_G.DeepDig_getBackpackCapacity = getBackpackCapacity
_G.DeepDig_getInventoryCapacityLabel = getInventoryCapacityLabel

local function applyFirstSellAffordabilityGrant(player, data)
	if data.toolTier ~= 1 then return end
	if data.firstSellAffordabilityGrantUsed then return end

	local nextTool = Config.TOOLS[data.toolTier + 1]
	if not nextTool then return end

	data.firstSellAffordabilityGrantUsed = true

	if data.coins >= nextTool.cost then return end

	local grantAmount = nextTool.cost - data.coins
	data.coins = data.coins + grantAmount

	NotifyEvent:FireClient(
		player,
		"FTUE boost: you can now afford the " .. nextTool.name .. ". Upgrade to dig faster.",
		"Uncommon"
	)
end

-- ═══════════════════════════════════════════════════════════════════
-- Dig System
-- ═══════════════════════════════════════════════════════════════════

local activeEvents = {} -- { [eventName] = endTick }
local ARTIFACT_DETECTOR_CHANCE = 0.10
local ARTIFACT_DETECTOR_MIN_RANK = 3
local RESURFACE_LOOT_BONUS_PER_REBIRTH = 0.5
local REBIRTH_BOOST_LOOT_BONUS_PER_REBIRTH = 1.0
local FRIEND_DIG_SPEED_MULTIPLIER = 1.05
local friendBoostActiveByUserId = {}
local groupBenefitActiveByUserId = {}
local resolvedGroupBenefitGroupId = nil

local function resolveGroupBenefitGroupId()
	local configuredGroupId = Config.GROUP_BENEFIT_GROUP_ID or 0
	if configuredGroupId ~= 0 then
		return configuredGroupId
	end

	if game.CreatorType == Enum.CreatorType.Group then
		return game.CreatorId
	end

	return 0
end

local function getGroupBenefitGroupId()
	if resolvedGroupBenefitGroupId == nil then
		resolvedGroupBenefitGroupId = resolveGroupBenefitGroupId()
	end

	return resolvedGroupBenefitGroupId
end

local function refreshGroupBenefitMembership(player)
	local groupId = getGroupBenefitGroupId()
	if groupId == 0 then
		groupBenefitActiveByUserId[player.UserId] = false
		return false
	end

	local success, isMember = pcall(function()
		return player:IsInGroup(groupId)
	end)

	local active = success and isMember == true
	groupBenefitActiveByUserId[player.UserId] = active
	return active
end

local function hasGroupBenefit(player)
	return player and groupBenefitActiveByUserId[player.UserId] == true
end

local function addGroupBenefitHudFields(payload, player)
	local active = hasGroupBenefit(player)
	payload.groupBenefitActive = active
	payload.groupBenefitMultiplier = active and Config.GROUP_BENEFIT_COIN_MULTIPLIER or 1
	payload.groupBenefitLabel = Config.GROUP_BENEFIT_DISPLAY_LABEL
	payload.groupBenefitColor = Config.GROUP_BENEFIT_DISPLAY_COLOR
	return payload
end

local function getGroupSellPayout(player, baseCoins)
	if hasGroupBenefit(player) then
		return math.floor((baseCoins or 0) * Config.GROUP_BENEFIT_COIN_MULTIPLIER)
	end

	return baseCoins or 0
end

local function awardSellPayout(player, data, baseCoins, shouldFireQuestProgress)
	local earned = getGroupSellPayout(player, baseCoins)
	data.coins = data.coins + earned
	data.totalEarned = (data.totalEarned or 0) + earned

	if shouldFireQuestProgress and earned > 0 then
		fireQuestProgress(player, "coins_earned", { amount = earned })
	end

	return earned
end

local function applyGroupBenefitNameTreatment(player, character)
	if not hasGroupBenefit(player) then
		return
	end

	local head = character:FindFirstChild("Head") or character:WaitForChild("Head", 10)
	if not head then return end

	local existing = head:FindFirstChild("GroupSupporterTag")
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GroupSupporterTag"
	billboard.Size = UDim2.new(0, 220, 0, 28)
	billboard.StudsOffset = Vector3.new(0, 2.65, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = "★ " .. player.DisplayName .. " • " .. Config.GROUP_BENEFIT_DISPLAY_LABEL
	label.TextColor3 = Config.GROUP_BENEFIT_DISPLAY_COLOR
	label.TextStrokeTransparency = 0.45
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Parent = billboard
end

local function hasFriendInServer(player, excludedPlayer)
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer ~= excludedPlayer then
			local success, isFriend = pcall(function()
				return player:IsFriendsWith(otherPlayer.UserId)
			end)
			if success and isFriend then
				return true
			end
		end
	end

	return false
end

local function getFriendsInServer(player, excludedPlayer)
	local friends = {}
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer ~= excludedPlayer then
			local success, isFriend = pcall(function()
				return player:IsFriendsWith(otherPlayer.UserId)
			end)
			if success and isFriend then
				table.insert(friends, otherPlayer)
			end
		end
	end

	return friends
end

local function ensureFriendReferralRewards(data)
	if not data then
		return nil
	end

	if type(data.friendReferralRewards) ~= "table" then
		data.friendReferralRewards = {}
	end

	return data.friendReferralRewards
end

local function formatFriendReferralEggLabel(eggType)
	eggType = tostring(eggType or Config.FRIEND_REFERRAL_REWARD_EGG or "Stone")
	if eggType == "" then
		eggType = tostring(Config.FRIEND_REFERRAL_REWARD_EGG or "Stone")
	end

	if string.find(string.lower(eggType), "egg", 1, true) then
		return eggType
	end

	return eggType .. " Egg"
end

local function grantFriendReferralReward(player, friendPlayer)
	if not Config.FRIEND_REFERRAL_REWARD_ENABLED then
		return
	end

	local data = getPlayerData(player)
	local friendData = getPlayerData(friendPlayer)
	if not data or not friendData then
		return
	end

	local rewards = ensureFriendReferralRewards(data)
	local friendRewards = ensureFriendReferralRewards(friendData)
	local friendKey = tostring(friendPlayer.UserId)
	local playerKey = tostring(player.UserId)
	if rewards[friendKey] == true or friendRewards[playerKey] == true then
		return
	end

	rewards[friendKey] = true
	friendRewards[playerKey] = true

	local coins = Config.FRIEND_REFERRAL_REWARD_COINS or 0
	local eggType = Config.FRIEND_REFERRAL_REWARD_EGG or "Stone"
	local eggLabel = formatFriendReferralEggLabel(eggType)

	local function awardOne(recipient, recipientData, otherPlayer)
		local friendName = otherPlayer.DisplayName
		if friendName == nil or friendName == "" then
			friendName = otherPlayer.Name
		end

		recipientData.coins = (recipientData.coins or 0) + coins
		recipientData.totalEarned = (recipientData.totalEarned or 0) + coins
		if coins > 0 then
			fireQuestProgress(recipient, "coins_earned", { amount = coins })
		end

		NotifyEvent:FireClient(
			recipient,
			"Friend referral bonus with " .. friendName .. ": +" .. coins .. " coins and a free " .. eggLabel .. "!",
			"Rare"
		)

		local grantFreeEgg = _G.DeepDig_grantFreeEggPet
		local petAwarded = false
		if grantFreeEgg then
			petAwarded = grantFreeEgg(
				recipient,
				eggType,
				"Referral " .. eggLabel .. " hatched from playing with " .. friendName .. "!"
			)
		end

		if not petAwarded then
			NotifyEvent:FireClient(
				recipient,
				"Free referral egg is unavailable this join, but your coin reward was saved.",
				"Common"
			)
		end

		UpdateHUDEvent:FireClient(recipient, addStandardHudFields({
			coins = recipientData.coins,
			totalEarned = recipientData.totalEarned,
			rebirths = recipientData.rebirths or 0,
			petCount = recipientData.pets and #recipientData.pets or 0,
			friendReferralReward = {
				friendName = friendName,
				coins = coins,
				eggType = eggType,
				eggGranted = petAwarded == true,
			},
		}, recipientData, recipient))
	end

	awardOne(player, data, friendPlayer)
	awardOne(friendPlayer, friendData, player)
end

local function getFriendBoostPayload(player)
	local active = friendBoostActiveByUserId[player.UserId] == true
	return {
		friendBoostActive = active,
		friendBoostMultiplier = active and FRIEND_DIG_SPEED_MULTIPLIER or 1,
	}
end

local function addFriendBoostHudFields(payload, player)
	if not player then
		return payload
	end

	local boostPayload = getFriendBoostPayload(player)
	payload.friendBoostActive = boostPayload.friendBoostActive
	payload.friendBoostMultiplier = boostPayload.friendBoostMultiplier
	return payload
end

function addStandardHudFields(payload, data, player)
	addInventoryHudFields(payload, data)
	addRarePityHudFields(payload, data)
	addFriendBoostHudFields(payload, player)
	addGroupBenefitHudFields(payload, player)
	if data then
		payload.petCount = type(data.pets) == "table" and #data.pets or 0
		local equippedRecord = getEquippedPetRecord(data)
		if equippedRecord then
			local petMultipliers = getEquippedPetMultipliers(data) or {}
			payload.equippedPet = equippedRecord.id
			payload.petName = equippedRecord.name
			payload.petRarity = equippedRecord.rarity
			payload.petLevel = tonumber(equippedRecord.level) or 1
			payload.petMultipliers = {
				dig_speed = petMultipliers.dig_speed or 1,
				loot_value = petMultipliers.loot_value or 1,
				luck = petMultipliers.luck or 1,
			}
		else
			payload.equippedPet = false
		end
	end
	return payload
end

_G.DeepDig_getFriendDigSpeedMultiplier = function(player)
	if not player then
		return 1
	end

	return friendBoostActiveByUserId[player.UserId] == true and FRIEND_DIG_SPEED_MULTIPLIER or 1
end

local function refreshFriendBoostStates(shouldNotifyClients, excludedPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= excludedPlayer then
			local wasActive = friendBoostActiveByUserId[player.UserId] == true
			local friendsInServer = getFriendsInServer(player, excludedPlayer)
			local isActive = hasFriendInServer(player, excludedPlayer)
			friendBoostActiveByUserId[player.UserId] = isActive

			for _, friendPlayer in ipairs(friendsInServer) do
				if player.UserId < friendPlayer.UserId then
					grantFriendReferralReward(player, friendPlayer)
				end
			end

			if shouldNotifyClients and wasActive ~= isActive then
				UpdateHUDEvent:FireClient(player, addFriendBoostHudFields({}, player))
			end
		end
	end
end

local function getResurfaceLootMultiplier(data)
	local rebirths = data and (data.rebirths or 0) or 0
	if rebirths <= 0 then
		return 1
	end

	local bonusPerRebirth = RESURFACE_LOOT_BONUS_PER_REBIRTH
	if hasOwnedGamepass(
		data,
		Config.GAMEPASS_REBIRTH_BOOST_ID,
		Config.GAMEPASS_REBIRTH_BOOST
	) then
		bonusPerRebirth = REBIRTH_BOOST_LOOT_BONUS_PER_REBIRTH
	end

	return 1 + (rebirths * bonusPerRebirth)
end

local function getMuseumLootMultiplier(player, tierName)
	local fn = _G.DeepDig_getMuseumLootMultiplier
	if type(fn) ~= "function" then
		return 1
	end

	local ok, result = pcall(fn, player, tierName)
	if not ok then
		return 1
	end

	local multiplier = tonumber(result) or 1
	if multiplier <= 0 then
		return 1
	end

	return multiplier
end

function getEquippedPetRecord(data)
	if not data or not data.equippedPet or type(data.pets) ~= "table" then
		return nil
	end

	for _, record in ipairs(data.pets) do
		if type(record) == "table" and record.id == data.equippedPet then
			return record
		end
	end

	return nil
end

function getEquippedPetMultipliers(data)
	local record = getEquippedPetRecord(data)
	if not record then
		return nil
	end

	if type(record.multipliers) == "table" then
		return record.multipliers
	end

	local petDef = PetDatabase.getPet(record.name)
	return petDef and petDef.multipliers
end

local function isEventActive(effectName)
	local endTick = activeEvents[effectName]
	return endTick and tick() < endTick
end

_G.DeepDig_isWorldEventEffectActive = function(effectName)
	if type(effectName) ~= "string" then
		return false
	end

	return isEventActive(effectName) == true
end

local function activateWorldEvent(event)
	activeEvents[event.effect] = tick() + event.duration

	EventTriggeredEvent:FireAllClients(event.name, event.message, event.duration, event.effect)
end

TriggerWorldEvent.Event:Connect(function(event)
	if type(event) ~= "table" or not event.effect then
		return
	end

	activateWorldEvent(event)
end)

-- echo_blocks world event: re-implements ItemDatabase.rollItem locally so we can
-- double the rarity weight on Legendary / Mythic for this single roll, without
-- mutating the shared RARITY table. Mirrors ItemDatabase.rollItem() semantics
-- (weighted pool, cumulative roll, returns same shape) — keep in sync if the
-- source roll ever changes. Falls back to nil if the tier is unknown.
local function rollItemEchoBoosted(tierName)
	local tierItems = ItemDatabase.ITEMS[tierName]
	if not tierItems then return nil end

	local pool = {}
	local totalWeight = 0
	for _, item in ipairs(tierItems) do
		local rarityData = ItemDatabase.RARITY[item.rarity]
		if rarityData then
			local w = rarityData.weight
			if item.rarity == "Legendary" or item.rarity == "Mythic" then
				w = w * 2
			end
			totalWeight = totalWeight + w
			table.insert(pool, { item = item, cumWeight = totalWeight })
		end
	end

	if totalWeight == 0 then return nil end

	local roll = math.random() * totalWeight
	for _, entry in ipairs(pool) do
		if roll <= entry.cumWeight then
			local item = entry.item
			local rarityData = ItemDatabase.RARITY[item.rarity]
			return {
				name = item.name,
				rarity = item.rarity,
				baseValue = item.baseValue,
				sellValue = item.baseValue * rarityData.multiplier,
				color = rarityData.color,
			}
		end
	end

	return nil
end

local RARITY_RANK = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
}

local function rollRarePlusItem(tierName)
	local tierItems = ItemDatabase.ITEMS[tierName]
	if not tierItems then return nil end

	local pool = {}
	local totalWeight = 0
	for _, item in ipairs(tierItems) do
		local rarityData = ItemDatabase.RARITY[item.rarity]
		local rank = RARITY_RANK[item.rarity] or 0
		if rarityData and rank >= ARTIFACT_DETECTOR_MIN_RANK then
			totalWeight = totalWeight + rarityData.weight
			table.insert(pool, { item = item, cumWeight = totalWeight })
		end
	end

	if totalWeight == 0 then return nil end

	local roll = math.random() * totalWeight
	for _, entry in ipairs(pool) do
		if roll <= entry.cumWeight then
			local item = entry.item
			local rarityData = ItemDatabase.RARITY[item.rarity]
			return {
				name = item.name,
				rarity = item.rarity,
				baseValue = item.baseValue,
				sellValue = item.baseValue * rarityData.multiplier,
				color = rarityData.color,
			}
		end
	end

	return nil
end

-- ── Seasonal event accessors (Phase 3 wiring) ─────────────────────
-- SeasonalEvents.server.lua publishes _G.DeepDig_getActiveSeason; we
-- query per-dig. No-ops cleanly if SeasonalEvents hasn't loaded yet.
local function getActiveSeasonId()
	local fn = _G.DeepDig_getActiveSeason
	if not fn then return nil end
	local season = fn()
	return season and season.id or nil
end

local function getSeasonalExclusiveDropChance(activeSeason)
	local chance = Config.SEASONAL_EXCLUSIVE_DROP_CHANCE or 0.025
	if activeSeason == "summer" and isEventActive("volcano_vent") then
		chance = math.max(chance, Config.VOLCANO_VENT_OBSIDIAN_DROP_CHANCE or chance)
	end

	return chance
end

local crewBonusNotifiedAt = {}

local function hasNearbyCrewmate(player)
	local fn = _G.DeepDig_hasNearbyCrewmate
	if type(fn) ~= "function" then
		return false, nil
	end

	local success, hasCrewmate, crewmate, nearbyCount = pcall(fn, player, Config.CREW_COOP_RADIUS)
	if success and hasCrewmate == true then
		return true, crewmate, nearbyCount
	end

	return false, nil, 0
end

local function awardCrewCoopDigXP(player)
	local fn = _G.DeepDig_awardCrewCoopDigXP
	if type(fn) ~= "function" then
		return Config.CREW_FRAGMENT_BONUS or 0
	end

	local success, fragmentBonus = pcall(fn, player, Config.CREW_XP_PER_COOP_DIG or 1)
	if success and type(fragmentBonus) == "number" then
		return fragmentBonus
	end

	return Config.CREW_FRAGMENT_BONUS or 0
end

local function notifyCrewDigBonus(player, bonus)
	local now = tick()
	local last = crewBonusNotifiedAt[player.UserId] or 0
	if now - last < 8 then
		return
	end

	crewBonusNotifiedAt[player.UserId] = now
	NotifyEvent:FireClient(player, "Crew dig bonus: +" .. tostring(bonus) .. " fragments", "Uncommon")
end

-- Rarity ladder used by winter_loot's 25% promotion. Mythic is the cap.
local RARITY_LADDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
local function promoteRarity(r)
	for i = 1, #RARITY_LADDER - 1 do
		if RARITY_LADDER[i] == r then
			return RARITY_LADDER[i + 1]
		end
	end
	return r -- Mythic (or unknown) doesn't promote
end

local function promoteWinterLootItem(tierName, item, isFirstEverFind)
	if not item or item.rarity == "Mythic" then
		return item
	end

	if math.random() >= 0.25 then
		return item
	end

	local promotedRarity = promoteRarity(item.rarity)
	if promotedRarity == item.rarity then
		return item
	end

	-- The first-ever FTUE find may reach Rare through winter_loot, but not
	-- the Epic+ reveal tiers the onboarding guard intentionally avoids.
	if isFirstEverFind and (RARITY_RANK[promotedRarity] or 999) > RARITY_RANK.Rare then
		return item
	end

	return ItemDatabase.rollItemOfRarity(tierName, promotedRarity) or item
end

local function triggerRandomEvent(activeSeason)
	local chance = Config.EVENT_CHANCE
	-- summer_loot: doubles random world event trigger frequency.
	-- We bump the per-tick probability instead of halving the wait,
	-- because the random event check runs inline in BlockBrokenEvent
	-- (no fixed-cadence loop to halve).
	if activeSeason == "summer" then
		chance = chance * 2
	end
	if math.random() > chance then return end

	local eligibleEvents = {}
	for _, configuredEvent in ipairs(Config.EVENTS) do
		if configuredEvent.seasonId == nil or configuredEvent.seasonId == activeSeason then
			table.insert(eligibleEvents, configuredEvent)
		end
	end
	if #eligibleEvents == 0 then
		return
	end

	local event = eligibleEvents[math.random(#eligibleEvents)]
	activateWorldEvent(event)
end

BlockBrokenEvent.Event:Connect(function(player, blockPosition)
	local data = getPlayerData(player)
	if not data then return end

	-- ── Active seasonal event (Phase 3) ────────────────────────────
	-- Cached once per block so the four seasonal branches below all
	-- read the same value (and can't race a calendar rollover mid-dig).
	local activeSeason = getActiveSeasonId()

	-- spring_loot: +1 fragment per block break, regardless of drop.
	-- Fired once per BlockBrokenEvent (not per chunk). No toast — the
	-- HUD push below carries the new fragment count.
	if activeSeason == "spring" then
		data.fragments = (data.fragments or 0) + 1
	end

	local crewDigBonus = 0
	local crewDigPartnerName = nil
	local crewDigPartnerCount = 0
	local nearCrewmate, crewDigPartner, nearbyCrewmateCount = hasNearbyCrewmate(player)
	if nearCrewmate then
		local crewFragmentBonus = awardCrewCoopDigXP(player)
		data.fragments = (data.fragments or 0) + crewFragmentBonus
		if crewFragmentBonus > 0 then
			crewDigBonus = crewFragmentBonus
			crewDigPartnerCount = math.max(math.floor(tonumber(nearbyCrewmateCount) or 1), 1)
			if typeof(crewDigPartner) == "Instance" and crewDigPartner:IsA("Player") then
				crewDigPartnerName = crewDigPartner.DisplayName
				if type(crewDigPartnerName) ~= "string" or crewDigPartnerName == "" then
					crewDigPartnerName = crewDigPartner.Name
				end
			end
			notifyCrewDigBonus(player, crewFragmentBonus)
		end
	end

	local petLuck = 1
	local petLoot = 1
	local petMultipliers = getEquippedPetMultipliers(data)
	if petMultipliers then
		petLuck = petMultipliers.luck or 1
		petLoot = petMultipliers.loot_value or 1
	end
	-- Defensive caps so a future config typo can't break the economy.
	petLuck = math.min(petLuck, 5)
	petLoot = math.min(petLoot, 5)

	-- Get tool info
	local tool = Config.TOOLS[data.toolTier]
	if not tool then return end

	-- Calculate depth (in blocks)
	local depth = math.floor(math.abs(blockPosition.Y) / Config.BLOCK_SIZE)
	local tierName = ItemDatabase.getTierForDepth(depth)
	local previousDeepestBlock = data.deepestBlock or 0
	local enemyDangerUnlockedPayload = nil
	local depthTierUnlockedPayload = nil
	local depthMilestonePayload = nil

	-- Update stats
	data.totalBlocksDug = data.totalBlocksDug + 1

	-- Tick the chain combo on every dig (regardless of loot drop).
	-- ChainCombo.server.lua publishes _G.DeepDig_recordDigForCombo and
	-- pushes a ChainComboUpdate RemoteEvent for the HUD widget.
	local recordCombo = _G.DeepDig_recordDigForCombo
	if type(recordCombo) == "function" then
		recordCombo(player)
		-- Feed the new streak to QuestSystem so chain_streak quests can
		-- progress. QuestSystem treats this like depth_reached (max value).
		local getStreak = _G.DeepDig_getChainComboStreak
		if type(getStreak) == "function" then
			fireQuestProgress(player, "chain_streak", { value = getStreak(player) })
		end
	end

	if depth > data.deepestBlock then
		data.deepestBlock = depth
		depthTierUnlockedPayload = buildDepthTierUnlockedPayload(previousDeepestBlock, data.deepestBlock)
		depthMilestonePayload = buildDepthMilestonePayload(previousDeepestBlock, data.deepestBlock)
		-- Fire depth_reached on each new max so QuestSystem can take max
		fireQuestProgress(player, "depth_reached", { depth = data.deepestBlock })
	end
	if not data.enemyDangerUnlockedSeen
		and previousDeepestBlock < ENEMY_DANGER_UNLOCK_DEPTH
		and data.deepestBlock >= ENEMY_DANGER_UNLOCK_DEPTH then
		data.enemyDangerUnlockedSeen = true
		enemyDangerUnlockedPayload = {
			depth = ENEMY_DANGER_UNLOCK_DEPTH,
			tierName = ItemDatabase.getTierForDepth(ENEMY_DANGER_UNLOCK_DEPTH),
		}
	end

	-- (block_break sound fires from DigSystem.server.lua at the actual
	-- break point, paired with the VFX. Don't duplicate it here.)

	-- ── FTUE: First 10 blocks guarantee a drop ──────────────────────
	-- New players get an item every block for the first 10 digs so the
	-- core loop (dig → find → sell) is felt before the 35% RNG starts.
	-- isFirstEverFind guards: if inventory is empty AND collections is
	-- empty, this is literally the player's first find ever.
	local isNewPlayer = data.totalBlocksDug <= 10
	local isFirstEverFind = #data.inventory == 0 and next(data.collections) == nil

	-- Loot roll
	local dropChance = Config.LOOT_DROP_CHANCE
	if isEventActive("2x_rare") then dropChance = dropChance * 1.5 end
	if isEventActive("bonus_loot") then dropChance = dropChance * 2 end
	-- lucky_hour world event: 1.5x drop chance multiplier
	if isEventActive("lucky_hour") then dropChance = dropChance * 1.5 end

	-- Apply LUCKY gamepass bonus (+25% drop chance)
	if data.ownedGamepasses and data.ownedGamepasses[3] then
		dropChance = dropChance * 1.25
	end

	-- Apply equipped pet luck multiplier (capped at 5x above)
	dropChance = dropChance * petLuck

	-- halloween_loot: +50% drop chance multiplier. Stacks with everything
	-- above; the cap at 1.0 below keeps the stacked total sane.
	if activeSeason == "halloween" then
		dropChance = dropChance * 1.5
	end

	-- Cap drop chance at 1.0 to prevent overflow when multiple multipliers stack
	-- (FTUE override below intentionally also sets to 1.0).
	if dropChance > 1.0 then dropChance = 1.0 end

	-- Guarantee a drop for the first 10 blocks (FTUE)
	if isNewPlayer then dropChance = 1.0 end

	local autoCollectedPayload = nil
	local artifactDetectedPayload = nil
	local rarePityTriggeredPayload = false

	if math.random() < dropChance then
		-- FTUE: First-ever find is always Common or Uncommon.
		-- Save the big dopamine spike for after the loop is understood.
		local item
		if isFirstEverFind then
			-- FTUE caps at Uncommon so echo_blocks (Legendary/Mythic boost) is a no-op here.
			item = ItemDatabase.rollItemWithMaxRarity(tierName, "Uncommon")
		elseif isEventActive("echo_blocks") then
			-- echo_blocks: Legendary/Mythic weights doubled for this roll only.
			item = rollItemEchoBoosted(tierName)
		else
			item = ItemDatabase.rollItem(tierName)
		end

		if item then
			if not isFirstEverFind
				and (item.rarity == "Common" or item.rarity == "Uncommon")
				and hasOwnedGamepass(
					data,
					Config.GAMEPASS_ARTIFACT_DETECTOR_ID,
					Config.GAMEPASS_ARTIFACT_DETECTOR
				)
				and math.random() < ARTIFACT_DETECTOR_CHANCE then
				local detectorItem = rollRarePlusItem(tierName)
				if detectorItem then
					item = detectorItem
					artifactDetectedPayload = {
						name = item.name,
						rarity = item.rarity,
					}
					NotifyEvent:FireClient(player, "Artifact Detector pinged: " .. item.name .. "!", item.rarity)
				end
			end

			-- winter_loot: 25% chance to promote the rolled rarity one tier.
			-- Promotion swaps in a real same-tier item at the promoted rarity,
			-- so name, rarity, color, and base sell value stay consistent.
			if activeSeason == "winter" then
				item = promoteWinterLootItem(tierName, item, isFirstEverFind)
			end

			if activeSeason
				and not isNewPlayer
				and not isFirstEverFind
				and math.random() < getSeasonalExclusiveDropChance(activeSeason) then
				local seasonalItem
				if activeSeason == "spring" then
					seasonalItem = ItemDatabase.buildSpringDinoEgg(tierName)
				elseif activeSeason == "summer" then
					seasonalItem = ItemDatabase.buildSummerObsidianTool(tierName)
				elseif activeSeason == "halloween" then
					seasonalItem = ItemDatabase.buildHalloweenGhostFossil(tierName)
				elseif activeSeason == "winter" then
					seasonalItem = ItemDatabase.buildWinterFrozenArtifact(tierName)
				else
					seasonalItem = ItemDatabase.buildSeasonalItem(activeSeason)
				end
				if seasonalItem then
					item = seasonalItem
				end
			end

			local rarePityTriggered = false
			if shouldForceRarePity(data, isNewPlayer, isFirstEverFind)
				and not isRareRevealRarity(item.rarity) then
				local pityItem = rollRarePlusItem(tierName)
				if pityItem then
					item = pityItem
					rarePityTriggered = true
				end
			end

			local wasAlreadyCollected = data.collections[item.name] == true

			local function buildDigItemFoundPayload()
				local payload = table.clone(item)
				if item.rarity == "Legendary" or item.rarity == "Mythic" then
					payload.worldPosition = blockPosition
				end
				return payload
			end

			-- Apply event multipliers
			if isEventActive("gold_rush") then
				item.sellValue = item.sellValue * 3
			end

			-- Apply DOUBLE_LOOT gamepass (2x sell value)
			if data.ownedGamepasses and data.ownedGamepasses[1] then
				item.sellValue = item.sellValue * 2
			end

			-- Apply resurface, museum, equipped pet loot_value, and chain-combo
			-- multipliers. Mutating `item.sellValue` here propagates to
			-- both the inventory record below AND the ItemFoundEvent
			-- :FireClient payload, so the client toast shows the bumped
			-- value.
			local getCombo = _G.DeepDig_getChainComboMultiplier
			local comboMult = (type(getCombo) == "function" and getCombo(player)) or 1.0
			local museumMult = getMuseumLootMultiplier(player, tierName)
			item.sellValue = math.floor(item.sellValue * getResurfaceLootMultiplier(data) * museumMult * petLoot * comboMult)

			local autoCollectDuplicate = wasAlreadyCollected and hasOwnedGamepass(
				data,
				Config.GAMEPASS_AUTO_COLLECTOR_ID,
				Config.GAMEPASS_AUTO_COLLECTOR
			)

			if autoCollectDuplicate then
				data.collections[item.name] = true
				-- Quest progress: items_found (always +1) and rarity_found (+1 with rarity tag).
				-- QuestSystem listener filters by quest.rarityFilter == eventData.rarity.
				fireQuestProgress(player, "items_found", { amount = 1 })
				fireQuestProgress(player, "rarity_found", { amount = 1, rarity = item.rarity })

				local earned = awardSellPayout(player, data, item.sellValue, true)
				applyFirstSellAffordabilityGrant(player, data)
				recordRarePityAward(data, item.rarity)
				if rarePityTriggered then
					rarePityTriggeredPayload = true
				end
				autoCollectedPayload = {
					name = item.name,
					earned = earned,
					rarity = item.rarity,
				}

				NotifyEvent:FireClient(player, "Auto Collector sold duplicate " .. item.name .. " for " .. earned .. " coins.", item.rarity)
				if isRareRevealRarity(item.rarity) then
					ItemFoundEvent:FireClient(player, buildDigItemFoundPayload())
					fireItemFindSounds(player, item.rarity)
				end
				if PlaySound then
					PlaySound:FireClient(player, "sell_coins")
				end
			else
				local inventoryItem = {
					name = item.name,
					rarity = item.rarity,
					sellValue = item.sellValue,
				}

				if tryAddInventoryItem(player, inventoryItem) then
					-- Track collection
					data.collections[item.name] = true
					recordRarePityAward(data, item.rarity)
					if rarePityTriggered then
						rarePityTriggeredPayload = true
					end

					-- Quest progress: items_found (always +1) and rarity_found (+1 with rarity tag).
					-- QuestSystem listener filters by quest.rarityFilter == eventData.rarity.
					fireQuestProgress(player, "items_found", { amount = 1 })
					fireQuestProgress(player, "rarity_found", { amount = 1, rarity = item.rarity })

					-- Notify player
					ItemFoundEvent:FireClient(player, buildDigItemFoundPayload())
					-- Race-free server-side signal for BadgeSystem etc. The client
					-- toast (ItemFoundEvent above) wins the visual race; this fires
					-- just after for server consumers that need the find record.
					ItemFoundBindable:Fire(player, item)
					-- SOUND HOOK: sparkle chime for any item find
					if PlaySound then
						PlaySound:FireClient(player, "item_found")
					end
					-- SOUND HOOK: dramatic reveal for Rare+
					if item.rarity == "Rare" or item.rarity == "Epic"
						or item.rarity == "Legendary" or item.rarity == "Mythic" then
						if PlaySound then
							PlaySound:FireClient(player, "rare_reveal")
						end
					end

					-- Notify all players for rare+ finds
					if item.rarity == "Epic" or item.rarity == "Legendary" or item.rarity == "Mythic" then
						for _, otherPlayer in ipairs(Players:GetPlayers()) do
							if otherPlayer ~= player then
								NotifyEvent:FireClient(
									otherPlayer,
									player.Name .. " found a " .. item.rarity .. " " .. item.name .. "!",
									item.rarity
								)
							end
						end
					end
				end
			end
		end
	end

	-- Per-dig payout: every block pays a small amount of coins directly
	-- (scaling slowly with depth) so progress is felt block-by-block even
	-- on no-drop rolls. No toast — the HUD coin counter carries it.
	local digPayout = (Config.DIG_COINS_BASE or 0)
		+ math.floor(depth / (Config.DIG_COINS_DEPTH_DIVISOR or 20))
	if digPayout > 0 then
		data.coins = data.coins + digPayout
		data.totalEarned = data.totalEarned + digPayout
		fireQuestProgress(player, "coins_earned", { amount = digPayout })
	end

	-- earthquake world event: 5-15 bonus "rumble" coins on EVERY block break,
	-- regardless of whether the loot roll yielded an item. No toast (event fires
	-- often) — the HUD coin counter animates via the UpdateHUDEvent below.
	-- Counts toward the coins_earned quest objective.
	if isEventActive("earthquake") then
		local rumble = math.random(5, 15)
		data.coins = data.coins + rumble
		data.totalEarned = data.totalEarned + rumble
		fireQuestProgress(player, "coins_earned", { amount = rumble })
	end

	-- Random events
	triggerRandomEvent(activeSeason)

	-- Update client HUD
	local hudPayload = {
		coins = data.coins,
		depth = depth,
		tierName = tierName,
		blocksDug = data.totalBlocksDug,
		totalEarned = data.totalEarned,
		rebirths = data.rebirths or 0,
		autoCollected = autoCollectedPayload,
		artifactDetected = artifactDetectedPayload,
		enemyDangerUnlocked = enemyDangerUnlockedPayload,
		depthTierUnlocked = depthTierUnlockedPayload,
		depthMilestone = depthMilestonePayload,
		rarePityTriggered = rarePityTriggeredPayload or nil,
		-- spring_loot bumps fragments per-block; keep the HUD coherent.
		fragments = data.fragments,
	}
	if crewDigBonus > 0 then
		hudPayload.crewDigBonus = crewDigBonus
		hudPayload.crewDigPartnerCount = crewDigPartnerCount
		if crewDigPartnerName then
			hudPayload.crewDigPartnerName = crewDigPartnerName
		end
	end
	UpdateHUDEvent:FireClient(player, addStandardHudFields(hudPayload, data, player))
end)

-- ═══════════════════════════════════════════════════════════════════
-- Economy
-- ═══════════════════════════════════════════════════════════════════

SellItemEvent.OnServerEvent:Connect(function(player, inventoryIndex)
	local data = getPlayerData(player)
	if not data then return end

	local item = data.inventory[inventoryIndex]
	if not item then return end

	awardSellPayout(player, data, item.sellValue, false)
	if PlaySound then
		PlaySound:FireClient(player, "sell_coins")
	end

	table.remove(data.inventory, inventoryIndex)

	applyFirstSellAffordabilityGrant(player, data)

	UpdateHUDEvent:FireClient(player, addStandardHudFields({
		coins = data.coins,
		totalEarned = data.totalEarned,
		rebirths = data.rebirths or 0,
		-- Marker so the FTUE objective tracker can detect any sale
		-- (SellAll has sellAllSummary; this covers single-item sells).
		soldItem = true,
	}, data, player))
end)

SellAllEvent.OnServerEvent:Connect(function(player)
	local data = getPlayerData(player)
	if not data then return end

	local itemsSold = #data.inventory
	local capacity = getBackpackCapacity(data)
	local wasBackpackFull = capacity ~= nil and itemsSold >= capacity
	local total = 0
	for _, item in ipairs(data.inventory) do
		total = total + item.sellValue
	end

	local earned = awardSellPayout(player, data, total, true)
	data.inventory = {}

	applyFirstSellAffordabilityGrant(player, data)

	-- SOUND HOOK: coin clink/jingle on sell
	if itemsSold > 0 and PlaySound then
		PlaySound:FireClient(player, "sell_coins")
	end

	NotifyEvent:FireClient(player, "Sold all items for " .. earned .. " coins!", "Common")
	UpdateHUDEvent:FireClient(player, addStandardHudFields({
		coins = data.coins,
		totalEarned = data.totalEarned,
		rebirths = data.rebirths or 0,
		sellAllSummary = itemsSold > 0 and {
			itemsSold = itemsSold,
			coinsEarned = earned,
			wasBackpackFull = wasBackpackFull,
		} or nil,
	}, data, player))

	-- ── FTUE: Post-sell upgrade nudge ───────────────────────────────
	-- After selling, check if the player can now afford the next tool.
	-- Only fires once (guarded by _upgradeNudgeSent flag) so it's not
	-- spammy. Tier 1 only — higher tiers have their own shop UI hints.
	local nextTool = Config.TOOLS[data.toolTier + 1]
	if data.toolTier == 1 and nextTool and data.coins >= nextTool.cost then
		if not data._upgradeNudgeSent then
			data._upgradeNudgeSent = true
			NotifyEvent:FireClient(
				player,
				"You can afford the " .. nextTool.name .. "! Upgrade to dig faster.",
				"Uncommon"
			)
		end
	end
end)

-- ═══════════════════════════════════════════════════════════════════
-- Duplicate Recycling (Fragment System)
-- ═══════════════════════════════════════════════════════════════════

local FRAGMENT_VALUES = {
	Common = 1, Uncommon = 3, Rare = 10, Epic = 30, Legendary = 100, Mythic = 500,
}

local CRAFT_COSTS = {
	Uncommon = 5, Rare = 15, Epic = 50, Legendary = 200, Mythic = 1000,
}

-- Recycle a single item (must be a duplicate — already in collections)
local RecycleItemEvent = createRemote("RecycleItem")
RecycleItemEvent.OnServerEvent:Connect(function(player, inventoryIndex)
	local data = getPlayerData(player)
	if not data then return end

	local item = data.inventory[inventoryIndex]
	if not item then return end

	-- Must be a duplicate (already collected)
	if not data.collections[item.name] then
		NotifyEvent:FireClient(player, "Not a duplicate — display it in your museum first!", "Common")
		return
	end

	local fragValue = FRAGMENT_VALUES[item.rarity] or 1
	data.fragments = (data.fragments or 0) + fragValue
	table.remove(data.inventory, inventoryIndex)

	if PlaySound then
		PlaySound:FireClient(player, "fragment_recycle")
	end
	NotifyEvent:FireClient(player, "Recycled " .. item.name .. " → +" .. fragValue .. " fragments (" .. data.fragments .. " total)", "Uncommon")
	UpdateHUDEvent:FireClient(player, addStandardHudFields({
		coins = data.coins,
		fragments = data.fragments,
		totalEarned = data.totalEarned,
		rebirths = data.rebirths or 0,
	}, data, player))
end)

-- Recycle ALL duplicates at once
local RecycleAllDupesEvent = createRemote("RecycleAllDupes")
RecycleAllDupesEvent.OnServerEvent:Connect(function(player)
	local data = getPlayerData(player)
	if not data then return end

	local totalFrags = 0
	local recycled = 0
	local kept = {}

	for _, item in ipairs(data.inventory) do
		if data.collections[item.name] then
			-- It's a duplicate — recycle it
			local fragValue = FRAGMENT_VALUES[item.rarity] or 1
			totalFrags = totalFrags + fragValue
			recycled = recycled + 1
		else
			-- First find — keep it
			table.insert(kept, item)
		end
	end

	data.inventory = kept
	data.fragments = (data.fragments or 0) + totalFrags

	if recycled > 0 then
		if PlaySound then
			PlaySound:FireClient(player, "fragment_recycle")
		end
		NotifyEvent:FireClient(player, "Recycled " .. recycled .. " duplicates → +" .. totalFrags .. " fragments!", "Rare")
	else
		NotifyEvent:FireClient(player, "No duplicates to recycle", "Common")
	end

	UpdateHUDEvent:FireClient(player, addStandardHudFields({
		coins = data.coins,
		fragments = data.fragments,
		totalEarned = data.totalEarned,
		rebirths = data.rebirths or 0,
	}, data, player))
end)

-- Craft a guaranteed rarity item from fragments
local CraftFromFragsEvent = createRemote("CraftFromFrags")
CraftFromFragsEvent.OnServerEvent:Connect(function(player, targetRarity, tierName)
	local data = getPlayerData(player)
	if not data then return end

	local cost = CRAFT_COSTS[targetRarity]
	if not cost then
		NotifyEvent:FireClient(player, "Can't craft that rarity", "Common")
		return
	end

	if (data.fragments or 0) < cost then
		NotifyEvent:FireClient(player, "Need " .. cost .. " fragments (have " .. (data.fragments or 0) .. ")", "Common")
		return
	end

	-- Default to deepest unlocked tier if not specified
	if not tierName then
		tierName = ItemDatabase.getTierForDepth(data.deepestBlock)
	end

	-- Roll an item of the target rarity from that tier
	local tierItems = ItemDatabase.ITEMS[tierName]
	if not tierItems then return end

	local candidates = {}
	for _, item in ipairs(tierItems) do
		if item.rarity == targetRarity then
			table.insert(candidates, item)
		end
	end

	if #candidates == 0 then
		NotifyEvent:FireClient(player, "No " .. targetRarity .. " items in " .. tierName .. " tier", "Common")
		return
	end

	local chosen = candidates[math.random(#candidates)]
	local rarityData = ItemDatabase.RARITY[chosen.rarity]

	local newItem = {
		name = chosen.name,
		rarity = chosen.rarity,
		sellValue = chosen.baseValue * rarityData.multiplier,
	}

	if not tryAddInventoryItem(player, newItem) then
		return
	end

	-- Deduct fragments and give item
	data.fragments = data.fragments - cost
	data.collections[chosen.name] = true

	if PlaySound then
		PlaySound:FireClient(player, "fragment_craft")
	end
	NotifyEvent:FireClient(player, "Crafted: " .. chosen.name .. " (" .. chosen.rarity .. ")!", targetRarity)
	ItemFoundEvent:FireClient(player, {
		name = chosen.name,
		rarity = chosen.rarity,
		sellValue = newItem.sellValue,
		color = rarityData.color,
	})
	-- Race-free server-side signal for BadgeSystem (mirrors normal drop path).
	-- Crafted items count as a "find" for first_rare_find / first_legendary.
	ItemFoundBindable:Fire(player, newItem)
	fireItemFindSounds(player, newItem.rarity)

	UpdateHUDEvent:FireClient(player, addStandardHudFields({
		coins = data.coins,
		fragments = data.fragments,
		totalEarned = data.totalEarned,
		rebirths = data.rebirths or 0,
	}, data, player))
end)

BuyToolEvent.OnServerEvent:Connect(function(player, toolTier)
	local data = getPlayerData(player)
	if not data then return end

	local tool = Config.TOOLS[toolTier]
	if not tool then return end

	-- Must be next tier
	if toolTier ~= data.toolTier + 1 then return end

	if data.coins < tool.cost then
		NotifyEvent:FireClient(player, "Not enough coins! Need " .. tool.cost, "Common")
		return
	end

	data.coins = data.coins - tool.cost
	data.toolTier = toolTier

	local refreshExcavatorVisual = ServerEvents:FindFirstChild(REFRESH_EXCAVATOR_VISUAL_EVENT_NAME)
	if refreshExcavatorVisual then
		refreshExcavatorVisual:Fire(player)
	end

	-- SOUND HOOK: power-up whoosh on tool upgrade
	if PlaySound then
		PlaySound:FireClient(player, "upgrade_whoosh")
	end
	NotifyEvent:FireClient(player, "Upgraded to " .. tool.name .. "!", "Rare")
	UpdateHUDEvent:FireClient(player, addFriendBoostHudFields({
		coins = data.coins,
		toolName = tool.name,
		toolTier = toolTier,
		totalEarned = data.totalEarned,
		rebirths = data.rebirths or 0,
	}, player))
end)

MarkFTUEHintsSeenEvent.OnServerEvent:Connect(function(player)
	local data = getPlayerData(player)
	if not data then
		return
	end

	if data.ftueHintsSeen == true then
		return
	end

	data.ftueHintsSeen = true
	task.spawn(function()
		if not savePlayerData(player) then
			warn(string.format("[DeepDig] FTUE hints save FAILED for %s (UserId %d)", player.Name, player.UserId))
		end
	end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Data Requests
-- ═══════════════════════════════════════════════════════════════════

GetPlayerDataFunc.OnServerInvoke = function(player)
	local data = getPlayerData(player)
	if not data then return nil end

	local tool = Config.TOOLS[data.toolTier]
	local payload = {
		coins = data.coins,
		toolTier = data.toolTier,
		toolName = tool and tool.name or "Rusty Shovel",
		toolPower = tool and tool.power or 1,
		toolSpeed = tool and tool.speed or 1,
		totalBlocksDug = data.totalBlocksDug,
		deepestBlock = data.deepestBlock,
		inventory = data.inventory,
		inventoryCapacity = getInventoryCapacityLabel(data),
		collections = data.collections,
		rebirths = data.rebirths,
		enemyKills = data.enemyKills or 0,
		totalEarned = data.totalEarned or 0,
		loginStreak = data.loginStreak,
		streakReviveEligible = data.streakReviveEligible,
		streakRevivePending = data.streakRevivePending,
		streakReviveBaseStreak = data.streakReviveBaseStreak,
		streakReviveOfferDate = data.streakReviveOfferDate,
		streakRevivePrice = 50,
		streakReviveProductAvailable = Config.isStreakReviveProductIdValid(Config.STREAK_REVIVE_PRODUCT_ID),
		ownedGamepasses = data.ownedGamepasses,
		ftueHintsSeen = data.ftueHintsSeen == true,
		nextToolCost = Config.TOOLS[data.toolTier + 1] and Config.TOOLS[data.toolTier + 1].cost or nil,
		nextToolName = Config.TOOLS[data.toolTier + 1] and Config.TOOLS[data.toolTier + 1].name or nil,
	}

	return addStandardHudFields(payload, data, player)
end

-- ═══════════════════════════════════════════════════════════════════
-- Player Join / Leave
-- ═══════════════════════════════════════════════════════════════════

local function onPlayerAdded(player)
	local data = loadPlayerData(player)
	local offlineIncomeResult = grantOfflineIncome(player, data)
	refreshGroupBenefitMembership(player)
	player.CharacterAdded:Connect(function(character)
		applyGroupBenefitNameTreatment(player, character)
	end)
	if player.Character then
		task.spawn(function()
			applyGroupBenefitNameTreatment(player, player.Character)
		end)
	end
	refreshFriendBoostStates(true)
	-- Signal readiness AFTER playerData[UserId] is populated. Consumers
	-- (DailyStreak, Gamepasses, Leaderboard, Rebirth) wait on this event
	-- via awaitPlayerData() instead of guessing with task.wait(N).
	PlayerDataReady:Fire(player)
	notifyOfflineIncome(player, data, offlineIncomeResult)
	print("[DeepDig] " .. player.Name .. " joined (coins: " .. data.coins .. ", tool: " .. Config.TOOLS[data.toolTier].name .. ")")
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- Handle players already in the game when the script loads (Studio playtest)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		onPlayerAdded(player)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	if not savePlayerData(player) then
		warn(string.format("[DeepDig] final save FAILED on PlayerRemoving for %s (UserId %d)", player.Name, player.UserId))
	end
	backpackFullNotifiedAt[player] = nil
	playerData[player.UserId] = nil
	offlineIncomeHandled[player.UserId] = nil
	friendBoostActiveByUserId[player.UserId] = nil
	groupBenefitActiveByUserId[player.UserId] = nil
	crewBonusNotifiedAt[player.UserId] = nil
	refreshFriendBoostStates(true, player)
end)

-- Auto-save every 2 minutes
task.spawn(function()
	while true do
		task.wait(120)
		for _, player in ipairs(Players:GetPlayers()) do
			savePlayerData(player)
		end
	end
end)

-- Save all on shutdown
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		if not savePlayerData(player) then
			warn(string.format("[DeepDig] final save FAILED on BindToClose for %s (UserId %d)", player.Name, player.UserId))
		end
	end
end)

print("[DeepDig] GameManager loaded")
