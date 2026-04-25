-- DailyStreak.server.lua — Daily login streaks with escalating rewards
-- Place in: ServerScriptService/DailyStreak (Script)
--
-- Streak cycle (days 1–7), restarting at day 1 after day 7:
--   Day 1: 200 coins
--   Day 2: 400 coins
--   Day 3: 800 coins
--   Day 4: 25 fragments
--   Day 5: 1500 coins
--   Day 6: 50 fragments
--   Day 7: guaranteed Rare item from player's deepest tier
--
-- After day 7 the cycle restarts with 1.5x multiplier on coin/fragment
-- rewards.  The cycle position is computed from (loginStreak - 1) % 7 + 1
-- so we never need to store a separate "cycle day" field.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local ItemDatabase = require(ReplicatedStorage:WaitForChild("ItemDatabase"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyEvent = Remotes:WaitForChild("Notify")
local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD")
local GetPlayerDataFunc = Remotes:WaitForChild("GetPlayerData")

local RequestStreakReviveEvent = Remotes:FindFirstChild("RequestStreakRevive")
if not RequestStreakReviveEvent then
	RequestStreakReviveEvent = Instance.new("RemoteEvent")
	RequestStreakReviveEvent.Name = "RequestStreakRevive"
	RequestStreakReviveEvent.Parent = Remotes
end

local STREAK_REVIVE_PRODUCT_ID = 1234567890 -- TODO replace placeholder before launch
assert(STREAK_REVIVE_PRODUCT_ID ~= 1234567890,
	"[DeepDig] STREAK_REVIVE_PRODUCT_ID is the placeholder; replace with a real Roblox developer product id before shipping the streak revive flow")
local STREAK_REVIVE_PRICE = 50

-- ─── Helpers ────────────────────────────────────────────────────────────────

-- Returns today's date as "YYYY-MM-DD" using os.date on the server.
-- os.date is available in server-side Luau scripts.
local function todayString()
	return os.date("%Y-%m-%d")
end

-- Parse a "YYYY-MM-DD" string into a Unix timestamp at midnight UTC.
-- We use os.time with a table to get comparable values.
local function dateToTimestamp(dateStr)
	local y, m, d = dateStr:match("(%d+)-(%d+)-(%d+)")
	if not y then return 0 end
	return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0, min = 0, sec = 0 })
end

-- Returns the number of calendar days between two "YYYY-MM-DD" strings.
local function daysBetween(olderStr, newerStr)
	if olderStr == "" then return math.huge end -- no previous login
	local t1 = dateToTimestamp(olderStr)
	local t2 = dateToTimestamp(newerStr)
	return math.floor((t2 - t1) / 86400 + 0.5)
end

-- ─── Reward table ────────────────────────────────────────────────────────────

-- Returns the day-within-cycle (1–7) for a given total streak count.
local function cycleDay(streak)
	return (streak - 1) % 7 + 1
end

-- cycleMultiplier: after each full 7-day cycle the coin/fragment rewards
-- grow by 1.5x.  Cycle 1 = ×1.0, cycle 2 = ×1.5, cycle 3 = ×2.25 …
local function cycleMultiplier(streak)
	local completedCycles = math.floor((streak - 1) / 7)
	return 1.5 ^ completedCycles
end

-- Base reward definitions (no multiplier applied yet).
local BASE_REWARDS = {
	[1] = { type = "coins",     amount = 200  },
	[2] = { type = "coins",     amount = 400  },
	[3] = { type = "coins",     amount = 800  },
	[4] = { type = "fragments", amount = 25   },
	[5] = { type = "coins",     amount = 1500 },
	[6] = { type = "fragments", amount = 50   },
	[7] = { type = "rare_item"                },
}

-- Build the actual reward for the player's current streak position.
-- Returns a table: { type, amount (optional), label }
local function buildReward(streak, deepestBlock)
	local day = cycleDay(streak)
	local base = BASE_REWARDS[day]
	local mult = cycleMultiplier(streak)

	if base.type == "coins" then
		local amount = math.floor(base.amount * mult)
		return { type = "coins", amount = amount, label = amount .. " coins" }

	elseif base.type == "fragments" then
		local amount = math.floor(base.amount * mult)
		return { type = "fragments", amount = amount, label = amount .. " fragments" }

	elseif base.type == "rare_item" then
		-- Roll a guaranteed Rare from the player's deepest tier
		local tierName = ItemDatabase.getTierForDepth(deepestBlock or 0)
		local tierItems = ItemDatabase.ITEMS[tierName]
		local candidates = {}
		if tierItems then
			for _, item in ipairs(tierItems) do
				if item.rarity == "Rare" then
					table.insert(candidates, item)
				end
			end
		end
		-- Fallback: if tier has no Rare items, give a large coin bonus
		if #candidates == 0 then
			local coinFallback = math.floor(1000 * mult)
			return { type = "coins", amount = coinFallback, label = coinFallback .. " coins (rare fallback)" }
		end
		local chosen = candidates[math.random(#candidates)]
		local rarityData = ItemDatabase.RARITY[chosen.rarity]
		local itemRecord = {
			name = chosen.name,
			rarity = chosen.rarity,
			sellValue = chosen.baseValue * rarityData.multiplier,
		}
		return { type = "rare_item", item = itemRecord, label = "Rare " .. chosen.name }
	end

	return { type = "coins", amount = 0, label = "nothing (bug)" }
end

-- ─── Apply reward to player data ─────────────────────────────────────────────

-- playerData table is read via GetPlayerData RemoteFunction which returns a copy.
-- For mutations we need direct access.  Since GameManager owns playerData,
-- DailyStreak communicates through the shared Remotes folder.
--
-- Design: DailyStreak fires StreakReward → GameManager (or this script)
-- handles it.  But to keep things self-contained and avoid a cross-script
-- dependency, we store player data in a module.
--
-- Simple approach used here: we use _G.playerData which GameManager exposes.
-- In a production game this would be a shared ModuleScript (PlayerDataService).
-- For the current project structure we hook into PlayerAdded after a small delay
-- to let GameManager load first, then access _G.DeepDig_playerData.

-- GameManager exposes its cache via a global so DailyStreak can mutate it.
-- Add this ONE line to GameManager after `local playerData = {}`:
--   _G.DeepDig_playerData = playerData
--
-- This is the minimal-coupling pattern for multi-script data sharing when
-- a shared module isn't in the project structure yet.

local function getSharedData(player)
	local cache = _G.DeepDig_playerData
	if cache then
		return cache[player.UserId]
	end
	return nil
end

local function getStreakHudPayload(data)
	return {
		coins = data.coins,
		fragments = data.fragments or 0,
		inventoryCount = #data.inventory,
		loginStreak = data.loginStreak,
		streakReviveEligible = data.streakReviveEligible == true,
		streakRevivePending = data.streakRevivePending == true,
		streakReviveBaseStreak = data.streakReviveBaseStreak or 0,
		streakRevivePrice = STREAK_REVIVE_PRICE,
	}
end

local function clearStreakReviveState(data)
	data.streakReviveEligible = false
	data.streakRevivePending = false
	data.streakReviveBaseStreak = 0
	data.streakReviveOfferDate = ""
end

local function applyStreakHudUpdate(player, data)
	UpdateHUDEvent:FireClient(player, getStreakHudPayload(data))
end

local function applyReward(player, reward)
	local data = getSharedData(player)
	if not data then return end

	if reward.type == "coins" then
		-- VIP gamepass gives +50% coins
		local bonus = 1
		if data.ownedGamepasses and data.ownedGamepasses[2] then
			bonus = 1.5
		end
		local finalAmount = math.floor(reward.amount * bonus)
		data.coins = data.coins + finalAmount
		reward.label = finalAmount .. " coins" .. (bonus > 1 and " (VIP bonus)" or "")

	elseif reward.type == "fragments" then
		data.fragments = (data.fragments or 0) + reward.amount

	elseif reward.type == "rare_item" then
		table.insert(data.inventory, reward.item)
		data.collections[reward.item.name] = true
	end
end

local function grantDailyStreakReward(player, data, rewardSource)
	local streak = data.loginStreak or 0
	local day = cycleDay(streak)
	local reward = buildReward(streak, data.deepestBlock)

	applyReward(player, reward)
	applyStreakHudUpdate(player, data)

	local streakEmoji = day == 7 and "🏆" or "🔥"
	local cycleNum = math.floor((streak - 1) / 7) + 1
	local cycleLabel = cycleNum > 1 and (" (Cycle " .. cycleNum .. ", ×" .. string.format("%.1f", cycleMultiplier(streak)) .. ")") or ""
	local rewardPrefix = rewardSource == "revive" and "Streak revived! " or ""

	NotifyEvent:FireClient(
		player,
		rewardPrefix .. streakEmoji .. " Day " .. day .. " Streak!" .. cycleLabel .. "  Reward: " .. reward.label,
		day >= 7 and "Legendary" or (day >= 5 and "Epic" or (day >= 3 and "Rare" or "Uncommon"))
	)

	if day == 7 then
		NotifyEvent:FireAllClients(
			"🏆 " .. player.Name .. " hit a 7-day login streak!",
			"Legendary"
		)
	end

	print("[DailyStreak] " .. player.Name .. " — streak: " .. streak ..
		", day: " .. day .. ", reward: " .. reward.label ..
		(rewardSource == "revive" and " (revived)" or ""))

	return reward
end

-- ─── Streak processing ───────────────────────────────────────────────────────

local function processLoginStreak(player)
	-- Small delay to ensure GameManager has loaded and registered _G.DeepDig_playerData
	task.wait(2)

	local data = getSharedData(player)
	if not data then
		warn("[DailyStreak] Could not find player data for " .. player.Name ..
			". Ensure _G.DeepDig_playerData = playerData is set in GameManager.")
		return
	end

	local today = todayString()
	local lastDate = data.lastLoginDate or ""

	if lastDate == today then
		-- Already logged in today — nothing to do
		applyStreakHudUpdate(player, data)
		return
	end

	local days = daysBetween(lastDate, today)

	if days == 1 then
		-- Consecutive day — increment streak
		data.loginStreak = (data.loginStreak or 0) + 1
		data.lastLoginDate = today
		clearStreakReviveState(data)
		grantDailyStreakReward(player, data)
		return
	elseif days == 2 and (data.loginStreak or 0) >= 2 then
		-- Missed exactly one day. Offer a one-time revive before resetting.
		data.streakReviveEligible = true
		data.streakRevivePending = true
		data.streakReviveBaseStreak = data.loginStreak or 0
		data.streakReviveOfferDate = today
		applyStreakHudUpdate(player, data)
		NotifyEvent:FireClient(
			player,
			"Missed one day. Revive your streak for 50 Robux to keep your momentum.",
			"Epic"
		)
		return
	else
		-- Missed one or more days (or first ever login) — reset to 1
		data.loginStreak = 1
		data.lastLoginDate = today
		clearStreakReviveState(data)
		grantDailyStreakReward(player, data)
		return
	end
end

local function finalizeStreakDecline(player, data)
	data.loginStreak = 1
	data.lastLoginDate = todayString()
	clearStreakReviveState(data)
	grantDailyStreakReward(player, data)
end

local function completeStreakRevive(player, data, receiptId)
	if data.streakReviveProcessedReceiptId == receiptId then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if (data.streakReviveBaseStreak or 0) < 2 then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	data.loginStreak = (data.streakReviveBaseStreak or 0) + 1
	data.lastLoginDate = todayString()
	data.streakReviveProcessedReceiptId = receiptId
	clearStreakReviveState(data)

	grantDailyStreakReward(player, data, "revive")

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local previousProcessReceipt = MarketplaceService.ProcessReceipt
MarketplaceService.ProcessReceipt = function(receiptInfo)
	if receiptInfo.ProductId ~= STREAK_REVIVE_PRODUCT_ID then
		if previousProcessReceipt then
			local ok, decision = pcall(previousProcessReceipt, receiptInfo)
			if ok and decision ~= nil then
				return decision
			end
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local data = getSharedData(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return completeStreakRevive(player, data, receiptInfo.PurchaseId)
end

-- ─── Hooks ───────────────────────────────────────────────────────────────────

RequestStreakReviveEvent.OnServerEvent:Connect(function(player, action)
	local data = getSharedData(player)
	if not data then return end
	if not data.streakRevivePending then return end

	if action == "decline" then
		finalizeStreakDecline(player, data)
		return
	end

	if action ~= "buy" then return end
	if not data.streakReviveEligible then return end

	MarketplaceService:PromptProductPurchase(player, STREAK_REVIVE_PRODUCT_ID)
end)

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		processLoginStreak(player)
	end)
end)

-- Handle players already in-game when script loads (Studio playtest)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		processLoginStreak(player)
	end)
end

print("[DeepDig] DailyStreak loaded")
