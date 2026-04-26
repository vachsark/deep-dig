-- GameManager.server.lua — Core game loop, player data, saving
-- Place in: ServerScriptService/GameManager (Script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local ItemDatabase = require(ReplicatedStorage:WaitForChild("ItemDatabase"))

-- DataStore for persistence
local PlayerDataStore = DataStoreService:GetDataStore("DeepDig_PlayerData_v1")

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
local PlaySound = Remotes:WaitForChild("PlaySound", 5)

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

-- ═══════════════════════════════════════════════════════════════════
-- Player Data Management
-- ═══════════════════════════════════════════════════════════════════

local playerData = {} -- In-memory cache
_G.DeepDig_playerData = playerData -- Shared with DailyStreak, Leaderboard, Gamepasses

local DEFAULT_DATA = {
	coins = Config.STARTING_COINS,
	toolTier = 1,
	totalBlocksDug = 0,
	deepestBlock = 0,
	inventory = {},       -- { {name, rarity, sellValue}, ... }
	collections = {},     -- { ["T-Rex Tooth"] = true, ... }
	fragments = 0,        -- Duplicate recycling currency
	rebirths = 0,
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
	firstSellAffordabilityGrantUsed = false, -- FTUE: one-time first-sell catch-up
}

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

	return playerData[player.UserId]
end

local function savePlayerData(player)
	local data = playerData[player.UserId]
	if not data then return true end

	data.lastSeenAt = os.time()

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

local function isEventActive(effectName)
	local endTick = activeEvents[effectName]
	return endTick and tick() < endTick
end

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

local function triggerRandomEvent(player)
	local chance = Config.EVENT_CHANCE
	-- summer_loot: doubles random world event trigger frequency.
	-- We bump the per-tick probability instead of halving the wait,
	-- because the random event check runs inline in BlockBrokenEvent
	-- (no fixed-cadence loop to halve).
	if getActiveSeasonId() == "summer" then
		chance = chance * 2
	end
	if math.random() > chance then return end

	local event = Config.EVENTS[math.random(#Config.EVENTS)]
	activeEvents[event.effect] = tick() + event.duration

	-- SOUND HOOK: alarm horn when a world event triggers (handled client-side via EventTriggeredEvent)
	if PlaySound then
		PlaySound:FireAllClients("event_alarm")
	end

	-- Notify all players
	EventTriggeredEvent:FireAllClients(event.name, event.message, event.duration)
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

	-- ── Equipped-pet multipliers ───────────────────────────────────
	-- Look up the equipped pet once per dig. PetSystem stores either
	-- the petId (number) in data.equippedPet, or false/nil for none.
	-- The pet record on the player only holds `name` (canonical key
	-- into PetDatabase), so we resolve owned-pet → name → pet def.
	-- dig_speed multiplier is consumed by DigSystem.server.lua via data.equippedPet (TODO: wire reads on the dig side)
	local petLuck = 1
	local petLoot = 1
	if data.equippedPet and data.pets then
		local equippedName
		for _, record in ipairs(data.pets) do
			if record.id == data.equippedPet then
				equippedName = record.name
				break
			end
		end
		if equippedName then
			local PetDatabase = require(ReplicatedStorage:WaitForChild("PetDatabase"))
			local equippedPet = PetDatabase.getPet(equippedName)
			if equippedPet and equippedPet.multipliers then
				petLuck = equippedPet.multipliers.luck or 1
				petLoot = equippedPet.multipliers.loot_value or 1
			end
		end
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

	-- Update stats
	data.totalBlocksDug = data.totalBlocksDug + 1
	if depth > data.deepestBlock then
		data.deepestBlock = depth
		-- Fire depth_reached on each new max so QuestSystem can take max
		fireQuestProgress(player, "depth_reached", { depth = data.deepestBlock })
	end

	-- SOUND HOOK: short crunch on every block break
	if PlaySound then
		PlaySound:FireClient(player, "block_break")
	end

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
					NotifyEvent:FireClient(player, "Artifact Detector pinged: " .. item.name .. "!", item.rarity)
				end
			end

			local wasAlreadyCollected = data.collections[item.name] == true

			-- winter_loot: 25% chance to promote the rolled rarity one tier
			-- (Common → Uncommon, …, Legendary → Mythic; Mythic doesn't
			-- promote). FTUE rolls cap at Uncommon — we still allow the
			-- promotion there, since first-find-as-Rare is still well below
			-- the "save the dopamine" Epic+ floor. Promotion cascade is
			-- single-step by construction (one helper call).
			--
			-- TODO: re-roll item from ItemDatabase to match the promoted
			-- rarity. For first-pass we bump only the rarity LABEL on the
			-- existing item; sellValue therefore reflects the original
			-- rarity's multiplier. This is gameplay-acceptable (still a
			-- visible win) and avoids tangling with the FTUE / echo_blocks
			-- roll paths.
			if activeSeason == "winter" and item.rarity ~= "Mythic" then
				if math.random() < 0.25 then
					item.rarity = promoteRarity(item.rarity)
				end
			end

			-- Apply event multipliers
			if isEventActive("gold_rush") then
				item.sellValue = item.sellValue * 3
			end

			-- Apply DOUBLE_LOOT gamepass (2x sell value)
			if data.ownedGamepasses and data.ownedGamepasses[1] then
				item.sellValue = item.sellValue * 2
			end

			-- Apply equipped pet loot_value multiplier (capped at 5x above).
			-- Mutating `item.sellValue` here propagates to both the inventory
			-- record below AND the ItemFoundEvent:FireClient payload, so the
			-- client toast shows the bumped value.
			item.sellValue = math.floor(item.sellValue * petLoot)

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

				local earned = item.sellValue
				data.coins = data.coins + earned
				data.totalEarned = (data.totalEarned or 0) + earned
				fireQuestProgress(player, "coins_earned", { amount = earned })
				applyFirstSellAffordabilityGrant(player, data)

				NotifyEvent:FireClient(player, "Auto Collector sold duplicate " .. item.name .. " for " .. earned .. " coins.", item.rarity)
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

					-- Quest progress: items_found (always +1) and rarity_found (+1 with rarity tag).
					-- QuestSystem listener filters by quest.rarityFilter == eventData.rarity.
					fireQuestProgress(player, "items_found", { amount = 1 })
					fireQuestProgress(player, "rarity_found", { amount = 1, rarity = item.rarity })

					-- Notify player
					ItemFoundEvent:FireClient(player, item)
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
						NotifyEvent:FireAllClients(
							player.Name .. " found a " .. item.rarity .. " " .. item.name .. "!",
							item.rarity
						)
					end
				end
			end
		end
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
	triggerRandomEvent(player)

	-- Update client HUD
	UpdateHUDEvent:FireClient(player, addInventoryHudFields({
		coins = data.coins,
		depth = depth,
		tierName = tierName,
		blocksDug = data.totalBlocksDug,
		totalEarned = data.totalEarned,
		rebirths = data.rebirths or 0,
		-- spring_loot bumps fragments per-block; keep the HUD coherent.
		fragments = data.fragments,
	}, data))
end)

-- ═══════════════════════════════════════════════════════════════════
-- Economy
-- ═══════════════════════════════════════════════════════════════════

SellItemEvent.OnServerEvent:Connect(function(player, inventoryIndex)
	local data = getPlayerData(player)
	if not data then return end

	local item = data.inventory[inventoryIndex]
	if not item then return end

	data.coins = data.coins + item.sellValue
	data.totalEarned = data.totalEarned + item.sellValue
	table.remove(data.inventory, inventoryIndex)

	applyFirstSellAffordabilityGrant(player, data)

	UpdateHUDEvent:FireClient(player, addInventoryHudFields({
		coins = data.coins,
		totalEarned = data.totalEarned,
		rebirths = data.rebirths or 0,
	}, data))
end)

SellAllEvent.OnServerEvent:Connect(function(player)
	local data = getPlayerData(player)
	if not data then return end

	local total = 0
	for _, item in ipairs(data.inventory) do
		total = total + item.sellValue
	end

	data.coins = data.coins + total
	data.totalEarned = data.totalEarned + total
	data.inventory = {}

	-- Quest progress: coins_earned with the per-sale total (not cumulative)
	if total > 0 then
		fireQuestProgress(player, "coins_earned", { amount = total })
	end

	applyFirstSellAffordabilityGrant(player, data)

	-- SOUND HOOK: coin clink/jingle on sell
	if PlaySound then
		PlaySound:FireClient(player, "sell_coins")
	end

	NotifyEvent:FireClient(player, "Sold all items for " .. total .. " coins!", "Common")
	UpdateHUDEvent:FireClient(player, addInventoryHudFields({
		coins = data.coins,
		totalEarned = data.totalEarned,
		rebirths = data.rebirths or 0,
	}, data))

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

	NotifyEvent:FireClient(player, "Recycled " .. item.name .. " → +" .. fragValue .. " fragments (" .. data.fragments .. " total)", "Uncommon")
	UpdateHUDEvent:FireClient(player, addInventoryHudFields({
		coins = data.coins,
		fragments = data.fragments,
		totalEarned = data.totalEarned,
		rebirths = data.rebirths or 0,
	}, data))
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
		NotifyEvent:FireClient(player, "Recycled " .. recycled .. " duplicates → +" .. totalFrags .. " fragments!", "Rare")
	else
		NotifyEvent:FireClient(player, "No duplicates to recycle", "Common")
	end

	UpdateHUDEvent:FireClient(player, addInventoryHudFields({
		coins = data.coins,
		fragments = data.fragments,
		totalEarned = data.totalEarned,
		rebirths = data.rebirths or 0,
	}, data))
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

	UpdateHUDEvent:FireClient(player, addInventoryHudFields({
		coins = data.coins,
		fragments = data.fragments,
		totalEarned = data.totalEarned,
		rebirths = data.rebirths or 0,
	}, data))
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

	-- SOUND HOOK: power-up whoosh on tool upgrade
	if PlaySound then
		PlaySound:FireClient(player, "upgrade_whoosh")
	end
	NotifyEvent:FireClient(player, "Upgraded to " .. tool.name .. "!", "Rare")
	UpdateHUDEvent:FireClient(player, {
		coins = data.coins,
		toolName = tool.name,
		toolTier = toolTier,
		totalEarned = data.totalEarned,
		rebirths = data.rebirths or 0,
	})
end)

-- ═══════════════════════════════════════════════════════════════════
-- Data Requests
-- ═══════════════════════════════════════════════════════════════════

GetPlayerDataFunc.OnServerInvoke = function(player)
	local data = getPlayerData(player)
	if not data then return nil end

	local tool = Config.TOOLS[data.toolTier]
	return {
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
		totalEarned = data.totalEarned or 0,
		loginStreak = data.loginStreak,
		streakReviveEligible = data.streakReviveEligible,
		streakRevivePending = data.streakRevivePending,
		streakReviveBaseStreak = data.streakReviveBaseStreak,
		streakReviveOfferDate = data.streakReviveOfferDate,
		streakRevivePrice = 50,
		ownedGamepasses = data.ownedGamepasses,
		nextToolCost = Config.TOOLS[data.toolTier + 1] and Config.TOOLS[data.toolTier + 1].cost or nil,
		nextToolName = Config.TOOLS[data.toolTier + 1] and Config.TOOLS[data.toolTier + 1].name or nil,
	}
end

-- ═══════════════════════════════════════════════════════════════════
-- Player Join / Leave
-- ═══════════════════════════════════════════════════════════════════

local function onPlayerAdded(player)
	local data = loadPlayerData(player)
	-- Signal readiness AFTER playerData[UserId] is populated. Consumers
	-- (DailyStreak, Gamepasses, Leaderboard, Rebirth) wait on this event
	-- via awaitPlayerData() instead of guessing with task.wait(N).
	PlayerDataReady:Fire(player)
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
