-- BadgeSystem.server.lua — Roblox BadgeService milestone awards
-- Place in: ServerScriptService/BadgeSystem (Script)
--
-- Phase 2 from ROADMAP.md. Holds an array of badge id placeholders that
-- map vault-side milestones onto Roblox profile badges via BadgeService.
-- The actual badges must be created on the Creator Dashboard; the
-- numeric `badgeId` fields below are placeholders (0) until then —
-- AwardBadge is short-circuited when badgeId is 0 so the in-game toast
-- still fires for testing.
--
-- Out of scope (TODOs):
--   * Replacing badgeId=0 placeholders with real Creator Dashboard ids.
--   * Persisting `data.badgesAwarded` lives in GameManager's DEFAULT_DATA
--     merge; new players are initialized lazily here on first event.
--
-- Rare-find detection now uses ServerEvents.ItemFoundBindable (fired by
-- GameManager on every inventory add), so the rarity_found badges no
-- longer depend on inspecting data.inventory[last] after a BlockBroken
-- event — that approach was vulnerable to re-processing old finds when
-- a block break didn't drop a new item. blocks_dug / depth_tier still
-- listen to BlockBroken; resurface_count still runs on the slow polling loop,
-- and museum_displays now listens to the museum's dedicated display event.

local Players = game:GetService("Players")
local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyEvent = Remotes:WaitForChild("Notify")
local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD")

-- ServerEvents folder + BlockBroken BindableEvent are created by
-- GameManager. Wait so we don't race the load order on hot-reload.
local ServerEvents = ReplicatedStorage:WaitForChild("ServerEvents")
local BlockBrokenEvent = ServerEvents:WaitForChild("BlockBroken")
-- ItemFoundBindable is also created by GameManager (idempotent find-or-create)
-- and fired on every inventory add. WaitForChild blocks until present —
-- safe even if BadgeSystem somehow loads before GameManager.
local ItemFoundBindable = ServerEvents:WaitForChild("ItemFoundBindable")
local EnemyKilledBindable = ServerEvents:FindFirstChild("EnemyKilledBindable")
if not EnemyKilledBindable then
	EnemyKilledBindable = Instance.new("BindableEvent")
	EnemyKilledBindable.Name = "EnemyKilledBindable"
	EnemyKilledBindable.Parent = ServerEvents
end
local MuseumItemDisplayedBindable = ServerEvents:FindFirstChild("MuseumItemDisplayedBindable")
if not MuseumItemDisplayedBindable then
	MuseumItemDisplayedBindable = Instance.new("BindableEvent")
	MuseumItemDisplayedBindable.Name = "MuseumItemDisplayedBindable"
	MuseumItemDisplayedBindable.Parent = ServerEvents
end

-- ═══════════════════════════════════════════════════════════════════
-- Badge definitions
-- ═══════════════════════════════════════════════════════════════════
-- trigger.type values handled below:
--   blocks_dug              → data.totalBlocksDug >= value
--   rarity_found            → ItemFoundBindable payload rarity == value
--                             (driven by dedicated listener — NOT evaluateAll)
--   depth_tier              → tier name reached (uses data.deepestBlock)
--   resurface_count         → data.rebirths >= value
--   museum_displays         → MuseumItemDisplayedBindable totalDisplayed >= value
--   enemy_kills             → data.enemyKills >= value
local BADGES = {
	{
		id = "first_dig",
		badgeId = 0,           -- TODO: replace with real Roblox badge id from Creator Dashboard
		description = "Dig your first block",
		trigger = { type = "blocks_dug", value = 1 },
	},
	{
		id = "hundred_blocks",
		badgeId = 0,           -- TODO: replace with real Roblox badge id
		description = "Dig 100 blocks",
		trigger = { type = "blocks_dug", value = 100 },
	},
	{
		id = "thousand_blocks",
		badgeId = 0,           -- TODO: replace with real Roblox badge id
		description = "Dig 1,000 blocks",
		trigger = { type = "blocks_dug", value = 1000 },
	},
	{
		id = "first_rare_find",
		badgeId = 0,           -- TODO: replace with real Roblox badge id
		description = "Discover your first Rare item",
		trigger = { type = "rarity_found", value = "Rare" },
	},
	{
		id = "first_legendary",
		badgeId = 0,           -- TODO: replace with real Roblox badge id
		description = "Discover your first Legendary item",
		trigger = { type = "rarity_found", value = "Legendary" },
	},
	{
		id = "depth_unknown_tier",
		badgeId = 0,           -- TODO: replace with real Roblox badge id
		description = "Reach the Unknown depth tier",
		trigger = { type = "depth_tier", value = "Unknown" },
	},
	{
		id = "first_resurface",
		badgeId = 0,           -- TODO: replace with real Roblox badge id
		description = "Resurface for the first time",
		trigger = { type = "resurface_count", value = 1 },
	},
	{
		id = "first_museum_display",
		badgeId = 0,           -- TODO: replace with real Roblox badge id
		description = "Display your first item in the museum",
		trigger = { type = "museum_displays", value = 1 },
	},
	{
		id = "first_enemy_kill",
		badgeId = 0,           -- TODO: replace with real Roblox badge id
		description = "Defeat your first buried enemy",
		trigger = { type = "enemy_kills", value = 1 },
	},
	{
		id = "enemy_count_100",
		badgeId = 0,           -- TODO: replace with real Roblox badge id
		description = "Defeat 100 buried enemies",
		trigger = { type = "enemy_kills", value = 100 },
	},
}

-- Tier-name → required minDepth lookup. Hardcoded (small constant table)
-- to avoid pulling Config just for a name match; if Config.TIERS is
-- renamed, this table must be updated in lockstep.
local TIER_MIN_DEPTH = {
	Modern = 0,
	Industrial = 13,
	Medieval = 38,
	Ancient = 76,
	Prehistoric = 126,
	Unknown = 188,
}

-- ═══════════════════════════════════════════════════════════════════
-- Player data access (shared cache from GameManager)
-- ═══════════════════════════════════════════════════════════════════

local function getData(player)
	local cache = _G.DeepDig_playerData
	if not cache then return nil end
	return cache[player.UserId]
end

local function ensureBadgeField(data)
	if not data then return end
	if data.badgesAwarded == nil then
		data.badgesAwarded = {}
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Award helper (idempotent, race-safe)
-- ═══════════════════════════════════════════════════════════════════

local function awardBadge(player, badgeKey)
	local data = getData(player)
	if not data then return end
	ensureBadgeField(data)
	if data.badgesAwarded[badgeKey] then return end

	local entry
	for _, b in ipairs(BADGES) do
		if b.id == badgeKey then
			entry = b
			break
		end
	end
	if not entry then return end

	-- Mark first so a re-entrant trigger in the same frame can't double-fire.
	data.badgesAwarded[badgeKey] = os.time()

	if entry.badgeId and entry.badgeId > 0 then
		local ok, err = pcall(function()
			BadgeService:AwardBadge(player.UserId, entry.badgeId)
		end)
		if not ok then
			warn("[DeepDig] BadgeService:AwardBadge failed for " .. badgeKey .. ": " .. tostring(err))
		end
	end

	if UpdateHUDEvent then
		UpdateHUDEvent:FireClient(player, {
			badgeUnlock = {
				id = entry.id,
				badgeId = entry.badgeId,
				description = entry.description,
			},
		})
	end

	if NotifyEvent then
		NotifyEvent:FireClient(player, "🏆 Badge unlocked: " .. entry.description, "Legendary")
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Trigger evaluation
-- ═══════════════════════════════════════════════════════════════════

-- Evaluate every badge for a player. Cheap (10 entries, simple comparisons)
-- and idempotency-protected by awardBadge, so we just brute-force on every
-- relevant signal.
--
-- NOTE: rarity_found triggers are NOT evaluated here — they're driven by
-- the dedicated ItemFoundBindable listener below, so we don't accidentally
-- re-process old finds when an unrelated BlockBroken event (or polling tick)
-- runs evaluateAll. museum_displays is also event-driven because collections
-- tracks ownership, not actual museum placement.
local function evaluateAll(player)
	local data = getData(player)
	if not data then return end
	ensureBadgeField(data)

	for _, entry in ipairs(BADGES) do
		if not data.badgesAwarded[entry.id] then
			local trigger = entry.trigger
			local fired = false

			if trigger.type == "blocks_dug" then
				if (data.totalBlocksDug or 0) >= trigger.value then
					fired = true
				end

			elseif trigger.type == "rarity_found" then
				-- Skip — handled by ItemFoundBindable listener (race-free).

			elseif trigger.type == "depth_tier" then
				local needed = TIER_MIN_DEPTH[trigger.value]
				if needed and (data.deepestBlock or 0) >= needed then
					fired = true
				end

			elseif trigger.type == "resurface_count" then
				if (data.rebirths or 0) >= trigger.value then
					fired = true
				end

			elseif trigger.type == "museum_displays" then
				-- Skip — handled by MuseumItemDisplayedBindable listener.

			elseif trigger.type == "enemy_kills" then
				if (data.enemyKills or 0) >= trigger.value then
					fired = true
				end
			end

			if fired then
				awardBadge(player, entry.id)
			end
		end
	end
end

-- Dedicated rare-find handler. Fires once per real inventory add. Idempotency
-- comes from awardBadge's badgesAwarded check, so even if Rare→Epic→Legendary
-- arrive in a single dig sequence, each badge awards at most once.
ItemFoundBindable.Event:Connect(function(player, item)
	if not player or not item then return end
	local data = getData(player)
	if not data then return end
	ensureBadgeField(data)

	local rarity = item.rarity
	if rarity == "Rare" or rarity == "Epic" or rarity == "Legendary" or rarity == "Mythic" then
		if not data.badgesAwarded.first_rare_find then
			awardBadge(player, "first_rare_find")
		end
		if (rarity == "Legendary" or rarity == "Mythic") and not data.badgesAwarded.first_legendary then
			awardBadge(player, "first_legendary")
		end
	end
end)

-- Museum display progress is driven only by Museum.server.lua after a valid
-- inventory item is placed on its pedestal and removed from inventory.
MuseumItemDisplayedBindable.Event:Connect(function(player, _item, totalDisplayed)
	if not player then return end
	local data = getData(player)
	if not data then return end
	ensureBadgeField(data)

	if (totalDisplayed or 0) >= 1 then
		awardBadge(player, "first_museum_display")
	end
end)

-- EnemySystem increments persisted kill progress on the confirmed reward path;
-- this listener only awards milestone badges from that saved count.
EnemyKilledBindable.Event:Connect(function(player, _enemy)
	if not player then return end
	local data = getData(player)
	if not data then return end
	ensureBadgeField(data)

	local enemyKills = math.max(0, math.floor(tonumber(data.enemyKills) or 0))

	if enemyKills >= 1 then
		awardBadge(player, "first_enemy_kill")
	end
	if enemyKills >= 100 then
		awardBadge(player, "enemy_count_100")
	end

	UpdateHUDEvent:FireClient(player, {
		enemyKills = enemyKills,
		enemyKillCounts = data.enemyKillCounts,
	})
end)

-- ═══════════════════════════════════════════════════════════════════
-- Wire up signals
-- ═══════════════════════════════════════════════════════════════════

-- Fires for every block any player breaks. We re-evaluate that player's
-- badges; covers blocks_dug, rarity_found, depth_tier in one place.
BlockBrokenEvent.Event:Connect(function(player, _blockPosition)
	if not player then return end
	evaluateAll(player)
end)

-- Per-player init + slow polling loop for resurface/museum gating.
-- 30s cadence keeps server cost negligible while still catching events
-- driven from systems we don't (and shouldn't) couple to directly.
local function startPlayerLoop(player)
	task.spawn(function()
		-- Wait briefly for GameManager to populate _G.DeepDig_playerData.
		local data
		for _ = 1, 20 do
			data = getData(player)
			if data then break end
			task.wait(0.5)
		end
		if not data then return end
		ensureBadgeField(data)

		-- Initial sweep covers cases where data was loaded with progress
		-- already in place (Studio playtest / hot-reload).
		evaluateAll(player)

		while player.Parent do
			task.wait(30)
			if not getData(player) then return end
			evaluateAll(player)
		end
	end)
end

Players.PlayerAdded:Connect(startPlayerLoop)

-- Handle players already in-game when the script loads (Studio playtest).
for _, player in ipairs(Players:GetPlayers()) do
	startPlayerLoop(player)
end

print("[DeepDig] BadgeSystem loaded — " .. #BADGES .. " badges configured")
