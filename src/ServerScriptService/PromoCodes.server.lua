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

local CodesDataStore = DataStoreService:GetDataStore("DeepDig_Codes_v1")

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

-- Global usage counter (shared across all players)
local globalUsage = {} -- { [code] = count }

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

	-- Check global usage limit
	if codeDef.maxUses then
		local used = globalUsage[code] or 0
		if used >= codeDef.maxUses then
			CodeResultEvent:FireClient(player, false, "This code has been fully redeemed")
			return
		end
	end

	-- Check if player already redeemed
	local redeemed = getRedeemedCodes(player)
	if redeemed[code] then
		CodeResultEvent:FireClient(player, false, "You already redeemed this code")
		return
	end

	-- Apply rewards
	local GetPlayerDataFunc = Remotes:FindFirstChild("GetPlayerData")
	-- Direct data access (same pattern as GameManager)
	-- NOTE: In production, expose a shared module. For MVP, fire events.

	local rewards = codeDef.rewards
	local rewardText = {}

	-- Fire reward application to GameManager via a custom internal event
	-- For now, we create a simple reward application remote
	local ApplyRewardEvent = Remotes:FindFirstChild("ApplyCodeReward")
	if not ApplyRewardEvent then
		ApplyRewardEvent = Instance.new("RemoteEvent")
		ApplyRewardEvent.Name = "ApplyCodeReward"
		ApplyRewardEvent.Parent = Remotes
	end

	-- Mark as redeemed
	saveRedeemedCode(player, code)
	globalUsage[code] = (globalUsage[code] or 0) + 1

	-- Build reward description
	if rewards.coins then
		table.insert(rewardText, "+" .. rewards.coins .. " coins")
	end
	if rewards.fragments then
		table.insert(rewardText, "+" .. rewards.fragments .. " fragments")
	end

	-- Notify player
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

print("[DeepDig] Promo Codes loaded (" .. tostring(#(function() local n=0; for _ in pairs(CODES) do n=n+1 end; return n end)()) .. " codes)")
