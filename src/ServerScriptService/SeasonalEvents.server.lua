-- SeasonalEvents.server.lua — calendar-gated limited-time content
-- Place in: ServerScriptService/SeasonalEvents (Script)
--
-- Phase 3 of ROADMAP.md. Defines 4 seasonal events tied to the
-- server's calendar month and broadcasts them at boot + on player
-- join + on a periodic re-announce timer. Future GameManager hooks
-- can read `season.effect` to apply seasonal loot bonuses.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyEvent = Remotes:WaitForChild("Notify")
local EventTriggeredEvent = Remotes:WaitForChild("EventTriggered")

local ServerEvents = ReplicatedStorage:WaitForChild("ServerEvents")
local PlayerDataReady = ServerEvents:WaitForChild("PlayerDataReady")

-- ─── Season config ───────────────────────────────────────────────────────────

local SEASONS = {
	{
		id = "halloween",
		name = "🎃 The Bone Age",
		message = "🎃 THE BONE AGE! Loot drops are 50% more likely and ghost fossils can surface all month.",
		months = { 10 }, -- October
		effect = "halloween_loot", -- consumed by future GameManager hook
		announceInterval = 600, -- re-announce every 10 min while active
	},
	{
		id = "winter",
		name = "❄️ The Ice Age",
		message = "❄️ THE ICE AGE! Finds have a 25% chance to promote one rarity tier.",
		months = { 12, 1 }, -- December + January
		effect = "winter_loot",
		announceInterval = 600,
	},
	{
		id = "spring",
		name = "🌱 Fossil Rush",
		message = "🌱 FOSSIL RUSH! Every block grants +1 fragment and dino eggs can appear.",
		months = { 3, 4, 5 }, -- March + April + May
		effect = "spring_loot",
		announceInterval = 900,
	},
	{
		id = "summer",
		name = "☀️ Volcano Event",
		message = "☀️ VOLCANO EVENT! Random world events trigger twice as often and obsidian relics can surface.",
		months = { 6, 7, 8 }, -- June through August
		effect = "summer_loot",
		announceInterval = 900,
	},
}

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function getActiveSeason()
	local currentMonth = os.date("*t", os.time()).month
	for _, season in ipairs(SEASONS) do
		for _, m in ipairs(season.months) do
			if m == currentMonth then
				return season -- defensive: first match wins on overlap
			end
		end
	end
	return nil
end

local function broadcastSeasonalEvent(season, player)
	if not season then return end

	if player then
		EventTriggeredEvent:FireClient(player, season.name, season.message, 9999, season.effect)
	else
		EventTriggeredEvent:FireAllClients(season.name, season.message, 9999, season.effect)
	end
end

-- Wait for GameManager to populate player data via the PlayerDataReady
-- BindableEvent (mirrors the helper in Leaderboard.server.lua).
local function awaitPlayerData(player, timeoutSeconds)
	if _G.DeepDig_playerData and _G.DeepDig_playerData[player.UserId] then
		return _G.DeepDig_playerData[player.UserId]
	end
	local readyForThisPlayer = false
	local connection
	connection = PlayerDataReady.Event:Connect(function(p)
		if p == player then
			readyForThisPlayer = true
		end
	end)
	local elapsed = 0
	local step = 0.1
	local cap = timeoutSeconds or 30
	while not readyForThisPlayer and elapsed < cap and player.Parent do
		task.wait(step)
		elapsed = elapsed + step
	end
	connection:Disconnect()
	if _G.DeepDig_playerData then
		return _G.DeepDig_playerData[player.UserId]
	end
	return nil
end

-- ─── Active season ───────────────────────────────────────────────────────────

local activeSeason = getActiveSeason()

-- Expose the active season to other server scripts via a global accessor.
-- Mirrors the existing `_G.DeepDig_playerData` pattern. GameManager calls
-- this per-block to apply seasonal loot effects (halloween_loot, winter_loot,
-- spring_loot, summer_loot). Always recomputes so a calendar rollover
-- mid-server is reflected immediately.
_G.DeepDig_getActiveSeason = function()
	return getActiveSeason()
end

-- ─── Boot announcement ──────────────────────────────────────────────────────-
-- 9999 = "indefinite duration" — existing client camera shake / notify logic
-- handles long durations gracefully.

if activeSeason then
	broadcastSeasonalEvent(activeSeason)
end

-- ─── Re-announce loop ────────────────────────────────────────────────────────
-- Periodically re-broadcast for players who joined late. Notification only —
-- does not mutate game state, so it coexists with the random world-event loop.

if activeSeason then
	task.spawn(function()
		while true do
			task.wait(activeSeason.announceInterval)
			-- Re-check the season in case the calendar month rolled over mid-server.
			local currentSeason = getActiveSeason()
			if currentSeason then
				broadcastSeasonalEvent(currentSeason)
			end
		end
	end)
end

-- ─── Player join announcement + seen-state mark ──────────────────────────────

local function onPlayerAdded(player)
	local season = getActiveSeason()
	if not season then return end

	local data = awaitPlayerData(player, 30)
	if not data then return end

	-- Lazy-init seasonalSeen table; persisted via the existing player save flow.
	if type(data.seasonalSeen) ~= "table" then
		data.seasonalSeen = {}
	end
	data.seasonalSeen[season.id] = os.time()

	-- Private notify the joining player about the active season.
	NotifyEvent:FireClient(player, season.message, "Mythic")
	broadcastSeasonalEvent(season, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- Handle players already in the game when the script loads (Studio playtest /
-- script reorder races). Mirrors Leaderboard.server.lua.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		onPlayerAdded(player)
	end)
end

-- ─── Banner ──────────────────────────────────────────────────────────────────

print("[DeepDig] SeasonalEvents loaded — current season: " .. (activeSeason and activeSeason.name or "none"))
