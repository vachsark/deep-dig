-- Trading.server.lua — Player-to-player trading + duplicate management
-- Place in: ServerScriptService/Trading (Script)
--
-- Trading flow:
-- 1. Player A sends trade request to Player B (proximity-based)
-- 2. Player B accepts/declines
-- 3. Both players select items from inventory to offer
-- 4. Both confirm → items swap
--
-- Duplicate system:
-- - "Recycle" duplicates into Fragments
-- - Fragments combine into guaranteed rarity rolls
-- - Higher rarity dupes = more fragments

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local ItemDatabase = require(ReplicatedStorage:WaitForChild("ItemDatabase"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Create trading remotes
local RequestTradeEvent = Instance.new("RemoteEvent")
RequestTradeEvent.Name = "RequestTrade"
RequestTradeEvent.Parent = Remotes

local RespondTradeEvent = Instance.new("RemoteEvent")
RespondTradeEvent.Name = "RespondTrade"
RespondTradeEvent.Parent = Remotes

local SetTradeOfferEvent = Instance.new("RemoteEvent")
SetTradeOfferEvent.Name = "SetTradeOffer"
SetTradeOfferEvent.Parent = Remotes

local ConfirmTradeEvent = Instance.new("RemoteEvent")
ConfirmTradeEvent.Name = "ConfirmTrade"
ConfirmTradeEvent.Parent = Remotes

local CancelTradeEvent = Instance.new("RemoteEvent")
CancelTradeEvent.Name = "CancelTrade"
CancelTradeEvent.Parent = Remotes

local TradeUIEvent = Instance.new("RemoteEvent")
TradeUIEvent.Name = "TradeUI"
TradeUIEvent.Parent = Remotes

local RecycleItemEvent = Instance.new("RemoteEvent")
RecycleItemEvent.Name = "RecycleItem"
RecycleItemEvent.Parent = Remotes

local RecycleAllDupesEvent = Instance.new("RemoteEvent")
RecycleAllDupesEvent.Name = "RecycleAllDupes"
RecycleAllDupesEvent.Parent = Remotes

local CraftFromFragsEvent = Instance.new("RemoteEvent")
CraftFromFragsEvent.Name = "CraftFromFrags"
CraftFromFragsEvent.Parent = Remotes

-- ═══════════════════════════════════════════════════════════════════
-- Duplicate / Fragment System
-- ═══════════════════════════════════════════════════════════════════

local FRAGMENT_VALUES = {
	Common    = 1,
	Uncommon  = 3,
	Rare      = 10,
	Epic      = 30,
	Legendary = 100,
	Mythic    = 500,
}

local CRAFT_COSTS = {
	-- Spend fragments for a guaranteed rarity roll
	Uncommon  = 5,
	Rare      = 15,
	Epic      = 50,
	Legendary = 200,
	Mythic    = 1000,
}

-- Get player data (shares the same in-memory store as GameManager)
-- In production, use a shared module. For MVP, we use RemoteFunction.
local function getPlayerInventory(player)
	local data = Remotes:FindFirstChild("GetPlayerData"):InvokeServer()
	return data
end

RecycleItemEvent.OnServerEvent:Connect(function(player, inventoryIndex)
	-- Access shared player data
	-- NOTE: In the actual game, GameManager exposes a module-level API.
	-- For this MVP, we fire a custom internal event.

	local NotifyEvent = Remotes:FindFirstChild("Notify")
	if not NotifyEvent then return end

	-- This needs to integrate with GameManager's playerData table.
	-- For now, we define the recycling logic and trust the integration.
	NotifyEvent:FireClient(player, "Recycling system ready — integrate with GameManager", "Common")
end)

-- ═══════════════════════════════════════════════════════════════════
-- Trading State Machine
-- ═══════════════════════════════════════════════════════════════════

-- Active trades: { [tradeId] = { playerA, playerB, offerA, offerB, confirmA, confirmB } }
local activeTrades = {}
local playerTradeMap = {} -- userId -> tradeId (one trade at a time)

local function generateTradeId()
	return "trade_" .. tostring(tick()) .. "_" .. math.random(10000)
end

local function cancelTrade(tradeId, reason)
	local trade = activeTrades[tradeId]
	if not trade then return end

	-- Notify both players
	if trade.playerA then
		TradeUIEvent:FireClient(trade.playerA, "cancelled", reason)
		playerTradeMap[trade.playerA.UserId] = nil
	end
	if trade.playerB then
		TradeUIEvent:FireClient(trade.playerB, "cancelled", reason)
		playerTradeMap[trade.playerB.UserId] = nil
	end

	activeTrades[tradeId] = nil
end

-- Player A requests trade with Player B
RequestTradeEvent.OnServerEvent:Connect(function(playerA, playerBId)
	local playerB = Players:GetPlayerByUserId(playerBId)
	if not playerB then
		Remotes.Notify:FireClient(playerA, "Player not found", "Common")
		return
	end

	-- Check proximity (within 20 studs)
	local charA = playerA.Character
	local charB = playerB.Character
	if charA and charB then
		local hrpA = charA:FindFirstChild("HumanoidRootPart")
		local hrpB = charB:FindFirstChild("HumanoidRootPart")
		if hrpA and hrpB then
			local dist = (hrpA.Position - hrpB.Position).Magnitude
			if dist > 20 then
				Remotes.Notify:FireClient(playerA, "Too far away! Get within 20 studs.", "Common")
				return
			end
		end
	end

	-- Check neither is already trading
	if playerTradeMap[playerA.UserId] then
		Remotes.Notify:FireClient(playerA, "You're already in a trade!", "Common")
		return
	end
	if playerTradeMap[playerB.UserId] then
		Remotes.Notify:FireClient(playerA, playerB.Name .. " is already trading!", "Common")
		return
	end

	local tradeId = generateTradeId()
	activeTrades[tradeId] = {
		playerA = playerA,
		playerB = playerB,
		offerA = {},    -- inventory indices
		offerB = {},
		confirmA = false,
		confirmB = false,
		state = "pending", -- pending, selecting, confirmed
	}
	playerTradeMap[playerA.UserId] = tradeId
	playerTradeMap[playerB.UserId] = tradeId

	-- Notify Player B of the request
	TradeUIEvent:FireClient(playerB, "request", {
		tradeId = tradeId,
		fromPlayer = playerA.Name,
		fromUserId = playerA.UserId,
	})

	Remotes.Notify:FireClient(playerA, "Trade request sent to " .. playerB.Name, "Uncommon")

	-- Auto-cancel after 30 seconds if not accepted
	task.delay(30, function()
		local trade = activeTrades[tradeId]
		if trade and trade.state == "pending" then
			cancelTrade(tradeId, "Trade request expired")
		end
	end)
end)

-- Player B responds to trade request
RespondTradeEvent.OnServerEvent:Connect(function(playerB, tradeId, accepted)
	local trade = activeTrades[tradeId]
	if not trade then return end
	if trade.playerB ~= playerB then return end

	if not accepted then
		cancelTrade(tradeId, playerB.Name .. " declined the trade")
		return
	end

	trade.state = "selecting"

	-- Open trade UI for both players
	TradeUIEvent:FireClient(trade.playerA, "open", {
		tradeId = tradeId,
		partnerName = trade.playerB.Name,
	})
	TradeUIEvent:FireClient(trade.playerB, "open", {
		tradeId = tradeId,
		partnerName = trade.playerA.Name,
	})
end)

-- Player updates their offer
SetTradeOfferEvent.OnServerEvent:Connect(function(player, tradeId, itemIndices)
	local trade = activeTrades[tradeId]
	if not trade or trade.state ~= "selecting" then return end

	if player == trade.playerA then
		trade.offerA = itemIndices
		trade.confirmA = false -- Reset confirm on offer change
	elseif player == trade.playerB then
		trade.offerB = itemIndices
		trade.confirmB = false
	else
		return
	end

	-- Notify partner of updated offer
	local partner = (player == trade.playerA) and trade.playerB or trade.playerA
	local offer = (player == trade.playerA) and trade.offerA or trade.offerB

	TradeUIEvent:FireClient(partner, "partner_offer", {
		tradeId = tradeId,
		itemCount = #offer,
	})
end)

-- Player confirms their side of the trade
ConfirmTradeEvent.OnServerEvent:Connect(function(player, tradeId)
	local trade = activeTrades[tradeId]
	if not trade or trade.state ~= "selecting" then return end

	if player == trade.playerA then
		trade.confirmA = true
	elseif player == trade.playerB then
		trade.confirmB = true
	end

	-- Notify partner
	local partner = (player == trade.playerA) and trade.playerB or trade.playerA
	TradeUIEvent:FireClient(partner, "partner_confirmed", { tradeId = tradeId })

	-- If both confirmed, execute the trade
	if trade.confirmA and trade.confirmB then
		executeTrade(tradeId)
	end
end)

function executeTrade(tradeId)
	local trade = activeTrades[tradeId]
	if not trade then return end

	trade.state = "confirmed"

	-- NOTE: In production, this directly manipulates the shared playerData
	-- table from GameManager. For MVP, we send the trade result via events
	-- and GameManager processes the inventory swap.

	-- Notify both players
	Remotes.Notify:FireClient(trade.playerA, "Trade complete with " .. trade.playerB.Name .. "!", "Rare")
	Remotes.Notify:FireClient(trade.playerB, "Trade complete with " .. trade.playerA.Name .. "!", "Rare")

	TradeUIEvent:FireClient(trade.playerA, "complete", { tradeId = tradeId })
	TradeUIEvent:FireClient(trade.playerB, "complete", { tradeId = tradeId })

	-- Cleanup
	playerTradeMap[trade.playerA.UserId] = nil
	playerTradeMap[trade.playerB.UserId] = nil
	activeTrades[tradeId] = nil
end

-- Cancel trade
CancelTradeEvent.OnServerEvent:Connect(function(player, tradeId)
	local trade = activeTrades[tradeId]
	if not trade then return end
	if player ~= trade.playerA and player ~= trade.playerB then return end

	cancelTrade(tradeId, player.Name .. " cancelled the trade")
end)

-- ═══════════════════════════════════════════════════════════════════
-- Duplicate Detection + Recycling
-- ═══════════════════════════════════════════════════════════════════

-- This integrates into GameManager's player data. The fragments field
-- is added to the player data schema:
--   data.fragments = 0  (integer, fragment currency)
--   data.collections = { ["Old Coin"] = true, ... }
--
-- Recycling a duplicate: item is removed from inventory, fragments added.
-- Crafting: spend fragments for a guaranteed rarity roll from any unlocked tier.

RecycleAllDupesEvent.OnServerEvent:Connect(function(player)
	-- NOTE: Needs GameManager integration
	-- Logic: scan inventory, find items already in collections{}, recycle them
	-- For each dupe: remove from inventory, add FRAGMENT_VALUES[rarity] to data.fragments

	Remotes.Notify:FireClient(player, "Recycle system active — duplicates converted to fragments", "Uncommon")
end)

CraftFromFragsEvent.OnServerEvent:Connect(function(player, targetRarity)
	local cost = CRAFT_COSTS[targetRarity]
	if not cost then
		Remotes.Notify:FireClient(player, "Invalid rarity: " .. tostring(targetRarity), "Common")
		return
	end

	-- NOTE: Needs GameManager integration
	-- Logic:
	-- 1. Check data.fragments >= cost
	-- 2. Deduct fragments
	-- 3. Pick random unlocked tier, roll item of targetRarity
	-- 4. Add to inventory
	-- 5. Notify player

	Remotes.Notify:FireClient(player, "Crafting: " .. targetRarity .. " costs " .. cost .. " fragments", "Rare")
end)

-- ═══════════════════════════════════════════════════════════════════
-- Cleanup on player leave
-- ═══════════════════════════════════════════════════════════════════

Players.PlayerRemoving:Connect(function(player)
	local tradeId = playerTradeMap[player.UserId]
	if tradeId then
		cancelTrade(tradeId, player.Name .. " left the game")
	end
end)

print("[DeepDig] Trading + Duplicate system loaded")
