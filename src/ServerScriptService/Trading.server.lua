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

-- NOTE: RecycleItem, RecycleAllDupes, CraftFromFrags are created and handled
-- by GameManager.server.lua (which owns playerData mutations). Earlier versions
-- of this file created duplicate RemoteEvents with the same names + stub
-- handlers, which silently shadowed the real handlers. Keep them out of here.

-- Shared player-data accessor: same pattern as Rebirth/AdminCommands.
local function getData(player)
	local cache = _G.DeepDig_playerData
	if not cache then return nil end
	return cache[player.UserId]
end

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

local function executeTrade(tradeId)
	local trade = activeTrades[tradeId]
	if not trade then return end

	local dataA = getData(trade.playerA)
	local dataB = getData(trade.playerB)
	if not dataA or not dataB then
		cancelTrade(tradeId, "trade aborted — player data not available")
		return
	end

	-- Validate that the offered indices are still in each player's inventory.
	-- Sort offer indices descending so removal doesn't shift later positions.
	local offerA = {}
	for _, idx in ipairs(trade.offerA) do
		local item = dataA.inventory[idx]
		if item then table.insert(offerA, { idx = idx, item = item }) end
	end
	local offerB = {}
	for _, idx in ipairs(trade.offerB) do
		local item = dataB.inventory[idx]
		if item then table.insert(offerB, { idx = idx, item = item }) end
	end

	table.sort(offerA, function(a, b) return a.idx > b.idx end)
	table.sort(offerB, function(a, b) return a.idx > b.idx end)

	-- Remove from each player's inventory.
	for _, entry in ipairs(offerA) do
		table.remove(dataA.inventory, entry.idx)
	end
	for _, entry in ipairs(offerB) do
		table.remove(dataB.inventory, entry.idx)
	end

	-- Add to opposite inventories. Update collections for new finds.
	for _, entry in ipairs(offerA) do
		local clone = { name = entry.item.name, rarity = entry.item.rarity, sellValue = entry.item.sellValue }
		table.insert(dataB.inventory, clone)
		dataB.collections[clone.name] = true
	end
	for _, entry in ipairs(offerB) do
		local clone = { name = entry.item.name, rarity = entry.item.rarity, sellValue = entry.item.sellValue }
		table.insert(dataA.inventory, clone)
		dataA.collections[clone.name] = true
	end

	trade.state = "confirmed"

	Remotes.Notify:FireClient(trade.playerA, "Trade complete with " .. trade.playerB.Name .. "!", "Rare")
	Remotes.Notify:FireClient(trade.playerB, "Trade complete with " .. trade.playerA.Name .. "!", "Rare")

	TradeUIEvent:FireClient(trade.playerA, "complete", { tradeId = tradeId })
	TradeUIEvent:FireClient(trade.playerB, "complete", { tradeId = tradeId })

	local UpdateHUD = Remotes:FindFirstChild("UpdateHUD")
	if UpdateHUD then
		UpdateHUD:FireClient(trade.playerA, { inventoryCount = #dataA.inventory })
		UpdateHUD:FireClient(trade.playerB, { inventoryCount = #dataB.inventory })
	end

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
-- Cleanup on player leave
-- ═══════════════════════════════════════════════════════════════════

Players.PlayerRemoving:Connect(function(player)
	local tradeId = playerTradeMap[player.UserId]
	if tradeId then
		cancelTrade(tradeId, player.Name .. " left the game")
	end
end)

print("[DeepDig] Trading + Duplicate system loaded")
