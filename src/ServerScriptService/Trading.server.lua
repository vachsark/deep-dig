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

local TRADE_PROXIMITY_STUDS = 20
local MAX_OFFER_ITEMS = 20

-- Player A requests trade with Player B
RequestTradeEvent.OnServerEvent:Connect(function(playerA, playerBId)
	local playerB = Players:GetPlayerByUserId(playerBId)
	if not playerB then
		Remotes.Notify:FireClient(playerA, "Player not found", "Common")
		return
	end

	-- Proximity check (20 studs). Both characters MUST exist; if either side is
	-- mid-respawn, deny the trade rather than silently allowing across-map asks.
	local charA = playerA.Character
	local charB = playerB.Character
	local hrpA = charA and charA:FindFirstChild("HumanoidRootPart")
	local hrpB = charB and charB:FindFirstChild("HumanoidRootPart")
	if not (hrpA and hrpB) then
		Remotes.Notify:FireClient(playerA, "Can't trade — partner is respawning.", "Common")
		return
	end
	local dist = (hrpA.Position - hrpB.Position).Magnitude
	if dist > TRADE_PROXIMITY_STUDS then
		Remotes.Notify:FireClient(playerA, "Too far away! Get within " .. TRADE_PROXIMITY_STUDS .. " studs.", "Common")
		return
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

-- Player updates their offer.
-- SECURITY: client supplies itemIndices. We must (a) reject non-table input,
-- (b) cap length, (c) ensure each entry is an integer in inventory range,
-- (d) reject duplicate indices — without dedup a malicious client can submit
-- {1,1,1,1,1} and dupe item #1 five times into the partner's inventory.
-- Snapshots `{name, rarity, sellValue}` at offer time so executeTrade can
-- re-validate the underlying item didn't change between offer and confirm.
SetTradeOfferEvent.OnServerEvent:Connect(function(player, tradeId, itemIndices)
	local trade = activeTrades[tradeId]
	if not trade or trade.state ~= "selecting" then return end
	if player ~= trade.playerA and player ~= trade.playerB then return end

	if type(itemIndices) ~= "table" then return end

	local data = getData(player)
	if not data then return end

	local invSize = #data.inventory
	local cleaned = {}
	local snapshots = {}
	local seen = {}
	for _, idx in ipairs(itemIndices) do
		if type(idx) ~= "number" then return end
		idx = math.floor(idx)
		if idx < 1 or idx > invSize then return end
		if seen[idx] then return end -- duplicate index in offer
		seen[idx] = true
		local item = data.inventory[idx]
		if not item then return end
		table.insert(cleaned, idx)
		table.insert(snapshots, {
			idx = idx,
			name = item.name,
			rarity = item.rarity,
			sellValue = item.sellValue,
		})
		if #cleaned >= MAX_OFFER_ITEMS then break end
	end

	if player == trade.playerA then
		trade.offerA = cleaned
		trade.snapshotA = snapshots
	else
		trade.offerB = cleaned
		trade.snapshotB = snapshots
	end
	-- Both confirms reset on ANY offer change so neither side can pre-confirm
	-- before they see the final swap composition.
	trade.confirmA = false
	trade.confirmB = false

	local partner = (player == trade.playerA) and trade.playerB or trade.playerA
	TradeUIEvent:FireClient(partner, "partner_offer", {
		tradeId = tradeId,
		itemCount = #cleaned,
	})
end)

-- Forward declaration so the ConfirmTrade handler can call executeTrade
-- before its definition appears below.
local executeTrade

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

-- Verify a snapshot row still matches the underlying inventory item at that
-- index. If the player sold or moved the item between offer-time and
-- confirm-time, refuse the trade rather than swap a stale ghost.
local function snapshotsMatch(snapshots, inventory)
	if not snapshots then return false end
	local seen = {}
	for _, snap in ipairs(snapshots) do
		if seen[snap.idx] then return false end
		seen[snap.idx] = true
		local cur = inventory[snap.idx]
		if not cur then return false end
		if cur.name ~= snap.name
			or cur.rarity ~= snap.rarity
			or cur.sellValue ~= snap.sellValue then
			return false
		end
	end
	return true
end

local function hasTradeBackpackSpace(data, outgoingCount, incomingCount)
	local getBackpackCapacity = _G.DeepDig_getBackpackCapacity
	local capacity = getBackpackCapacity and getBackpackCapacity(data) or Config.DEFAULT_BACKPACK_CAPACITY
	if not capacity then
		return true
	end

	return #data.inventory - outgoingCount + incomingCount <= capacity
end

executeTrade = function(tradeId)
	local trade = activeTrades[tradeId]
	if not trade then return end

	local dataA = getData(trade.playerA)
	local dataB = getData(trade.playerB)
	if not dataA or not dataB then
		cancelTrade(tradeId, "trade aborted — player data not available")
		return
	end

	-- Re-validate against snapshots taken at SetTradeOffer time. Closes the
	-- dupe-by-duplicate-index vector AND the dupe-by-sell-then-trade vector.
	if not (snapshotsMatch(trade.snapshotA, dataA.inventory)
		and snapshotsMatch(trade.snapshotB, dataB.inventory)) then
		cancelTrade(tradeId, "trade aborted — items changed since offer was made")
		return
	end

	-- Sort offer indices descending so table.remove doesn't shift later picks.
	local offerA = {}
	for _, snap in ipairs(trade.snapshotA) do
		table.insert(offerA, { idx = snap.idx, item = dataA.inventory[snap.idx] })
	end
	local offerB = {}
	for _, snap in ipairs(trade.snapshotB) do
		table.insert(offerB, { idx = snap.idx, item = dataB.inventory[snap.idx] })
	end
	table.sort(offerA, function(a, b) return a.idx > b.idx end)
	table.sort(offerB, function(a, b) return a.idx > b.idx end)

	if not hasTradeBackpackSpace(dataA, #offerA, #offerB) then
		cancelTrade(tradeId, "trade aborted - " .. trade.playerA.Name .. "'s backpack is full")
		return
	end
	if not hasTradeBackpackSpace(dataB, #offerB, #offerA) then
		cancelTrade(tradeId, "trade aborted - " .. trade.playerB.Name .. "'s backpack is full")
		return
	end

	for _, entry in ipairs(offerA) do
		table.remove(dataA.inventory, entry.idx)
	end
	for _, entry in ipairs(offerB) do
		table.remove(dataB.inventory, entry.idx)
	end

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
		local getInventoryCapacityLabel = _G.DeepDig_getInventoryCapacityLabel
		UpdateHUD:FireClient(trade.playerA, {
			inventoryCount = #dataA.inventory,
			inventoryCapacity = getInventoryCapacityLabel and getInventoryCapacityLabel(dataA) or Config.DEFAULT_BACKPACK_CAPACITY,
		})
		UpdateHUD:FireClient(trade.playerB, {
			inventoryCount = #dataB.inventory,
			inventoryCapacity = getInventoryCapacityLabel and getInventoryCapacityLabel(dataB) or Config.DEFAULT_BACKPACK_CAPACITY,
		})
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
