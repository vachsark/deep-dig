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

local DigBlockEvent = createRemote("DigBlock")
local SellItemEvent = createRemote("SellItem")
local BuyToolEvent = createRemote("BuyTool")
local SellAllEvent = createRemote("SellAll")
local UpdateHUDEvent = createRemote("UpdateHUD")
local ItemFoundEvent = createRemote("ItemFound")
local EventTriggeredEvent = createRemote("EventTriggered")
local NotifyEvent = createRemote("Notify")
local GetPlayerDataFunc = createRemote("GetPlayerData", "RemoteFunction")

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
	lastLoginDate = "",   -- "YYYY-MM-DD" for streak tracking
	loginStreak = 0,      -- Consecutive daily login count
	ownedGamepasses = {}, -- { [passId] = true }
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
	if not data then return end

	pcall(function()
		PlayerDataStore:SetAsync("player_" .. player.UserId, data)
	end)
end

local function getPlayerData(player)
	return playerData[player.UserId]
end

-- ═══════════════════════════════════════════════════════════════════
-- Dig System
-- ═══════════════════════════════════════════════════════════════════

local activeEvents = {} -- { [eventName] = endTick }

local function isEventActive(effectName)
	local endTick = activeEvents[effectName]
	return endTick and tick() < endTick
end

local function triggerRandomEvent(player)
	if math.random() > Config.EVENT_CHANCE then return end

	local event = Config.EVENTS[math.random(#Config.EVENTS)]
	activeEvents[event.effect] = tick() + event.duration

	-- SOUND HOOK: alarm horn when a world event triggers (handled client-side via EventTriggeredEvent)
	-- Remotes.PlaySound:FireAllClients("event_alarm")

	-- Notify all players
	EventTriggeredEvent:FireAllClients(event.name, event.message, event.duration)
end

DigBlockEvent.OnServerEvent:Connect(function(player, blockPosition)
	local data = getPlayerData(player)
	if not data then return end

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
	end

	-- SOUND HOOK: short crunch on every block break
	-- Remotes.PlaySound:FireClient(player, "block_break")

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

	-- Apply LUCKY gamepass bonus (+25% drop chance)
	if data.ownedGamepasses and data.ownedGamepasses[3] then
		dropChance = dropChance * 1.25
	end

	-- Guarantee a drop for the first 10 blocks (FTUE)
	if isNewPlayer then dropChance = 1.0 end

	if math.random() < dropChance then
		-- FTUE: First-ever find is always Common or Uncommon.
		-- Save the big dopamine spike for after the loop is understood.
		local item
		if isFirstEverFind then
			item = ItemDatabase.rollItemWithMaxRarity(tierName, "Uncommon")
		else
			item = ItemDatabase.rollItem(tierName)
		end

		if item then
			-- Apply event multipliers
			if isEventActive("gold_rush") then
				item.sellValue = item.sellValue * 3
			end

			-- Apply DOUBLE_LOOT gamepass (2x sell value)
			if data.ownedGamepasses and data.ownedGamepasses[1] then
				item.sellValue = item.sellValue * 2
			end

			-- Add to inventory
			table.insert(data.inventory, {
				name = item.name,
				rarity = item.rarity,
				sellValue = item.sellValue,
			})

			-- Track collection
			data.collections[item.name] = true

			-- Notify player
			ItemFoundEvent:FireClient(player, item)
			-- SOUND HOOK: sparkle chime for any item find
			-- Remotes.PlaySound:FireClient(player, "item_found")
			-- SOUND HOOK: dramatic reveal for Rare+
			-- if item.rarity == "Rare" or item.rarity == "Epic"
			--    or item.rarity == "Legendary" or item.rarity == "Mythic" then
			--     Remotes.PlaySound:FireClient(player, "rare_reveal")
			-- end

			-- Notify all players for rare+ finds
			if item.rarity == "Epic" or item.rarity == "Legendary" or item.rarity == "Mythic" then
				NotifyEvent:FireAllClients(
					player.Name .. " found a " .. item.rarity .. " " .. item.name .. "!",
					item.rarity
				)
			end
		end
	end

	-- Random events
	triggerRandomEvent(player)

	-- Update client HUD
	UpdateHUDEvent:FireClient(player, {
		coins = data.coins,
		depth = depth,
		tierName = tierName,
		blocksDug = data.totalBlocksDug,
		inventoryCount = #data.inventory,
	})
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

	UpdateHUDEvent:FireClient(player, {
		coins = data.coins,
		inventoryCount = #data.inventory,
	})
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

	-- SOUND HOOK: coin clink/jingle on sell
	-- Remotes.PlaySound:FireClient(player, "sell_coins")

	NotifyEvent:FireClient(player, "Sold all items for " .. total .. " coins!", "Common")
	UpdateHUDEvent:FireClient(player, {
		coins = data.coins,
		inventoryCount = 0,
	})

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
	UpdateHUDEvent:FireClient(player, {
		coins = data.coins,
		inventoryCount = #data.inventory,
		fragments = data.fragments,
	})
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

	UpdateHUDEvent:FireClient(player, {
		coins = data.coins,
		inventoryCount = #data.inventory,
		fragments = data.fragments,
	})
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

	-- Deduct fragments and give item
	data.fragments = data.fragments - cost
	local chosen = candidates[math.random(#candidates)]
	local rarityData = ItemDatabase.RARITY[chosen.rarity]

	local newItem = {
		name = chosen.name,
		rarity = chosen.rarity,
		sellValue = chosen.baseValue * rarityData.multiplier,
	}
	table.insert(data.inventory, newItem)
	data.collections[chosen.name] = true

	NotifyEvent:FireClient(player, "Crafted: " .. chosen.name .. " (" .. chosen.rarity .. ")!", targetRarity)
	ItemFoundEvent:FireClient(player, {
		name = chosen.name,
		rarity = chosen.rarity,
		sellValue = newItem.sellValue,
		color = rarityData.color,
	})

	UpdateHUDEvent:FireClient(player, {
		coins = data.coins,
		inventoryCount = #data.inventory,
		fragments = data.fragments,
	})
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
	-- Remotes.PlaySound:FireClient(player, "upgrade_whoosh")
	NotifyEvent:FireClient(player, "Upgraded to " .. tool.name .. "!", "Rare")
	UpdateHUDEvent:FireClient(player, {
		coins = data.coins,
		toolName = tool.name,
		toolTier = toolTier,
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
		collections = data.collections,
		rebirths = data.rebirths,
		loginStreak = data.loginStreak,
		ownedGamepasses = data.ownedGamepasses,
		nextToolCost = Config.TOOLS[data.toolTier + 1] and Config.TOOLS[data.toolTier + 1].cost or nil,
		nextToolName = Config.TOOLS[data.toolTier + 1] and Config.TOOLS[data.toolTier + 1].name or nil,
	}
end

-- ═══════════════════════════════════════════════════════════════════
-- Player Join / Leave
-- ═══════════════════════════════════════════════════════════════════

Players.PlayerAdded:Connect(function(player)
	local data = loadPlayerData(player)
	print("[DeepDig] " .. player.Name .. " joined (coins: " .. data.coins .. ", tool: " .. Config.TOOLS[data.toolTier].name .. ")")
end)

Players.PlayerRemoving:Connect(function(player)
	savePlayerData(player)
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
		savePlayerData(player)
	end
end)

print("[DeepDig] GameManager loaded")
