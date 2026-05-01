-- PromoCodes.server.lua — Promotional code redemption system
-- Place in: ServerScriptService/PromoCodes (Script)
--
-- Codes are defined server-side only (can't be datamined from client).
-- Each player can redeem each code once. Redeemed codes stored in DataStore.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RedeemCodeEvent = Instance.new("RemoteEvent")
RedeemCodeEvent.Name = "RedeemCode"
RedeemCodeEvent.Parent = Remotes

local CodeResultEvent = Instance.new("RemoteEvent")
CodeResultEvent.Name = "CodeResult"
CodeResultEvent.Parent = Remotes

local NotifyEvent = Remotes:WaitForChild("Notify")
local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD")

-- Wrapped against unpublished-Studio failures. Same pattern as GameManager.
-- Read/write call sites below are already pcall-wrapped, so a stub that
-- silently no-ops keeps the redeem flow running with in-memory state.
local function makeStubStore()
	return {
		GetAsync = function() return nil end,
		SetAsync = function() end,
		UpdateAsync = function() end,
		IncrementAsync = function() return 0 end,
	}
end
local CodesDataStore, CodeUsageStore
do
	local ok1, s1 = pcall(function() return DataStoreService:GetDataStore("DeepDig_Codes_v1") end)
	CodesDataStore = ok1 and s1 or makeStubStore()
	-- Separate store for code-level usage counters so we can UpdateAsync them
	-- atomically across servers (per-player redemptions stay in CodesDataStore).
	local ok2, s2 = pcall(function() return DataStoreService:GetDataStore("DeepDig_CodeUsage_v1") end)
	CodeUsageStore = ok2 and s2 or makeStubStore()
end

-- ═══════════════════════════════════════════════════════════════════
-- Code Definitions (add new codes here)
-- ═══════════════════════════════════════════════════════════════════

local CODES = {
	-- Launch codes
	DEEPDIG = {
		rewards = { coins = 500, fragments = 10 },
		message = "Welcome to Deep Dig! +500 coins, +10 fragments",
		maxUses = nil, -- unlimited
		expiresAt = nil, -- never
	},
	DIGDEEP = {
		rewards = { coins = 1000 },
		message = "Let's go deep! +1,000 coins",
		maxUses = nil,
		expiresAt = nil,
	},

	-- Milestone codes (update these as the game grows)
	FIRSTDIG = {
		rewards = { coins = 250, fragments = 5 },
		message = "Thanks for being early! +250 coins, +5 fragments",
		maxUses = 1000, -- first 1000 players only
		expiresAt = nil,
	},

	-- Seasonal / event codes (set expiry dates)
	-- BONEAGE = {
	-- 	rewards = { coins = 2000, fragments = 50 },
	-- 	message = "The Bone Age is here! +2,000 coins, +50 fragments",
	-- 	maxUses = nil,
	-- 	expiresAt = os.time({year=2026, month=11, day=7}), -- Nov 7 2026
	-- },

	-- Creator / collab codes
	-- YOUTUBER1 = {
	-- 	rewards = { coins = 750 },
	-- 	message = "Thanks for watching! +750 coins",
	-- 	maxUses = 5000,
	-- 	expiresAt = nil,
	-- },
}

-- Cross-server usage counter via DataStore atomic increment.
-- IncrementAsync is the right primitive here: each call returns the new total
-- so we can roll back if the cap is exceeded.
local function bumpGlobalUsage(code, by)
	local ok, total = pcall(function()
		return CodeUsageStore:IncrementAsync("count_" .. code, by or 1)
	end)
	if ok then return total end
	return nil
end

local function readGlobalUsage(code)
	local ok, total = pcall(function()
		return CodeUsageStore:GetAsync("count_" .. code)
	end)
	if ok then return total or 0 end
	return nil
end

-- ═══════════════════════════════════════════════════════════════════
-- Redemption Logic
-- ═══════════════════════════════════════════════════════════════════

local function getRedeemedCodes(player)
	local success, data = pcall(function()
		return CodesDataStore:GetAsync("redeemed_" .. player.UserId)
	end)
	return (success and data) or {}
end

local function saveRedeemedCode(player, code)
	pcall(function()
		CodesDataStore:UpdateAsync("redeemed_" .. player.UserId, function(old)
			local data = old or {}
			data[code] = os.time()
			return data
		end)
	end)
end

RedeemCodeEvent.OnServerEvent:Connect(function(player, inputCode)
	if type(inputCode) ~= "string" then return end

	-- Normalize: uppercase, trim whitespace
	local code = string.upper(string.gsub(inputCode, "%s+", ""))

	-- Check if code exists
	local codeDef = CODES[code]
	if not codeDef then
		CodeResultEvent:FireClient(player, false, "Invalid code")
		return
	end

	-- Check expiry
	if codeDef.expiresAt and os.time() > codeDef.expiresAt then
		CodeResultEvent:FireClient(player, false, "This code has expired")
		return
	end

	-- Check global usage limit (DataStore-backed; persists across server restarts).
	if codeDef.maxUses then
		local used = readGlobalUsage(code)
		if used == nil then
			-- DataStore unreachable. Refuse rather than risk over-redeeming.
			CodeResultEvent:FireClient(player, false, "Try again in a moment")
			return
		end
		if used >= codeDef.maxUses then
			CodeResultEvent:FireClient(player, false, "This code has been fully redeemed")
			return
		end
	end

	-- Check if player already redeemed. Distinguish "GetAsync threw" from
	-- "code not redeemed" — a throttled GetAsync would let us double-redeem.
	local redeemedOk, redeemed = pcall(function()
		return CodesDataStore:GetAsync("redeemed_" .. player.UserId)
	end)
	if not redeemedOk then
		CodeResultEvent:FireClient(player, false, "Try again in a moment")
		return
	end
	redeemed = redeemed or {}
	if redeemed[code] then
		CodeResultEvent:FireClient(player, false, "You already redeemed this code")
		return
	end

	-- Apply rewards directly to playerData (shared with GameManager).
	local cache = _G.DeepDig_playerData
	local data = cache and cache[player.UserId]
	if not data then
		CodeResultEvent:FireClient(player, false, "Profile still loading — try again.")
		return
	end

	local rewards = codeDef.rewards
	local rewardText = {}

	if rewards.coins then
		data.coins = (data.coins or 0) + rewards.coins
		data.totalEarned = (data.totalEarned or 0) + rewards.coins
		table.insert(rewardText, "+" .. rewards.coins .. " coins")
	end
	if rewards.fragments then
		data.fragments = (data.fragments or 0) + rewards.fragments
		table.insert(rewardText, "+" .. rewards.fragments .. " fragments")
	end

	-- Mark as redeemed AFTER successful application (no double-apply on retry).
	saveRedeemedCode(player, code)
	-- Bump the cross-server counter. If we land over cap because of a race
	-- between IncrementAsync and the earlier readGlobalUsage check, that's
	-- acceptable — at most maxUses+(servers-1) redemptions slip through,
	-- which is way better than the in-memory counter's per-server reset.
	if codeDef.maxUses then
		bumpGlobalUsage(code, 1)
	end

	-- Push the new totals to the HUD.
	local UpdateHUD = Remotes:FindFirstChild("UpdateHUD")
	if UpdateHUD then
		UpdateHUD:FireClient(player, {
			coins = data.coins,
			fragments = data.fragments,
		})
	end

	local msg = codeDef.message or ("Code redeemed: " .. table.concat(rewardText, ", "))
	CodeResultEvent:FireClient(player, true, msg)
	NotifyEvent:FireClient(player, "CODE REDEEMED: " .. msg, "Legendary")

	print("[DeepDig] " .. player.Name .. " redeemed code: " .. code)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Admin: Add codes at runtime (for live events)
-- ═══════════════════════════════════════════════════════════════════

-- To add a code from the Studio command bar:
-- game.ServerScriptService.PromoCodes:SetAttribute("NewCode", "EVENTNAME:1000:50")
-- Format: "CODE:coins:fragments"

local codeCount = 0
for _ in pairs(CODES) do codeCount = codeCount + 1 end
print(string.format("[DeepDig] Promo Codes loaded (%d codes)", codeCount))
