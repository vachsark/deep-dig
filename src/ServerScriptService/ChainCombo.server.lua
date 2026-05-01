-- ChainCombo.server.lua — Streak-based dig multiplier
--
-- Players who break blocks in quick succession build a "chain" that
-- multiplies the sellValue of items they find while the chain is hot.
-- The combo decays after CHAIN_WINDOW seconds of no dig.
--
-- Exposes two helpers (matches the _G.DeepDig_get* convention used by
-- SeasonalEvents and CrewSystem):
--   _G.DeepDig_recordDigForCombo(player) — call once per BlockBroken
--   _G.DeepDig_getChainComboMultiplier(player) — read at loot-roll time
--
-- HUD wiring: fires ChainComboUpdate(streak, multiplier, secondsLeft,
-- window) to the player on every change, and fires (0, 1.0, 0, window)
-- when the chain decays to nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CHAIN_WINDOW = 3.0    -- seconds between digs to keep the chain alive
local CHAIN_MAX_STREAK = 99 -- hard cap on tracked streak

-- Mirrors ChainComboGui.client.lua's SHOW_THRESHOLD. Server uses it to skip
-- pushing ChainComboUpdate at streaks 1..N-1, when the client widget would
-- be hidden anyway. The client only displays from this streak onwards.
local SHOW_THRESHOLD = 5

-- Streak threshold → sellValue multiplier. Highest matched threshold wins.
local CHAIN_TIERS = {
	{ threshold = 5,  mult = 1.25 },
	{ threshold = 10, mult = 1.5 },
	{ threshold = 20, mult = 2.0 },
	{ threshold = 40, mult = 3.0 },
	{ threshold = 60, mult = 4.0 },
}

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local ChainComboUpdate = Remotes:FindFirstChild("ChainComboUpdate")
if not ChainComboUpdate then
	ChainComboUpdate = Instance.new("RemoteEvent")
	ChainComboUpdate.Name = "ChainComboUpdate"
	ChainComboUpdate.Parent = Remotes
end

-- Looked up lazily so we don't race the script that creates it.
local function firePlaySound(player, soundKey)
	local rem = Remotes:FindFirstChild("PlaySound")
	if rem then rem:FireClient(player, soundKey) end
end

local function fireNotify(player, message, rarity)
	local rem = Remotes:FindFirstChild("Notify")
	if rem then rem:FireClient(player, message, rarity or "Common") end
end

local stateByUserId = {} -- [userId] = { streak, lastDigAt }

local function multiplierForStreak(streak)
	local mult = 1.0
	for _, tier in ipairs(CHAIN_TIERS) do
		if streak >= tier.threshold then
			mult = tier.mult
		end
	end
	return mult
end

local function tierIndexForStreak(streak)
	local idx = 0
	for i, tier in ipairs(CHAIN_TIERS) do
		if streak >= tier.threshold then
			idx = i
		end
	end
	return idx
end

local function pushUpdate(player, state)
	-- Skip the network round-trip while the chain is below the client's
	-- display threshold — the widget is hidden, so streaks 1..N-1 don't
	-- need a refresh. Decay still pushes streak=0 separately.
	if state.streak < SHOW_THRESHOLD then
		return
	end
	local timeLeft = math.max(0, CHAIN_WINDOW - (os.clock() - state.lastDigAt))
	ChainComboUpdate:FireClient(player, state.streak, multiplierForStreak(state.streak), timeLeft, CHAIN_WINDOW)
end

_G.DeepDig_recordDigForCombo = function(player)
	if not player or not player.Parent then return end
	local now = os.clock()
	local s = stateByUserId[player.UserId]
	local prevTierIdx
	if not s or (now - s.lastDigAt) > CHAIN_WINDOW then
		prevTierIdx = 0
		stateByUserId[player.UserId] = { streak = 1, lastDigAt = now }
	else
		prevTierIdx = tierIndexForStreak(s.streak)
		s.streak = math.min(s.streak + 1, CHAIN_MAX_STREAK)
		s.lastDigAt = now
	end
	local newTierIdx = tierIndexForStreak(stateByUserId[player.UserId].streak)
	-- Tier-up audio cue: only on threshold crossings, never on every dig.
	if newTierIdx > prevTierIdx then
		firePlaySound(player, "upgrade_whoosh")
		-- Persistent celebration toast on the rare top tier (currently 4×).
		-- Fires at most once per chain (only when crossing INTO the top
		-- index, never on continued digs within it). Tier ceilings near
		-- the top are 60+ consecutive digs — earned, worth flagging.
		if newTierIdx == #CHAIN_TIERS then
			local topTier = CHAIN_TIERS[#CHAIN_TIERS]
			fireNotify(player,
				string.format("🔥 x%d chain — %.1f× sell value!", topTier.threshold, topTier.mult),
				"Mythic")
		end
	end
	pushUpdate(player, stateByUserId[player.UserId])
end

_G.DeepDig_getChainComboMultiplier = function(player)
	if not player then return 1.0 end
	local s = stateByUserId[player.UserId]
	if not s or s.streak <= 0 then return 1.0 end
	if (os.clock() - s.lastDigAt) > CHAIN_WINDOW then return 1.0 end
	return multiplierForStreak(s.streak)
end

-- Read-only getter so other systems (QuestSystem progress feeder) can
-- observe the current streak without reaching into our state table.
_G.DeepDig_getChainComboStreak = function(player)
	if not player then return 0 end
	local s = stateByUserId[player.UserId]
	if not s or s.streak <= 0 then return 0 end
	if (os.clock() - s.lastDigAt) > CHAIN_WINDOW then return 0 end
	return s.streak
end

-- Manual reset hook for state-changing events outside this script (e.g.
-- Rebirth.server.lua calls this on resurface so the new run starts clean
-- instead of inheriting the pre-resurface streak).
_G.DeepDig_resetChainCombo = function(player)
	if not player then return end
	local s = stateByUserId[player.UserId]
	if s and s.streak > 0 then
		s.streak = 0
		ChainComboUpdate:FireClient(player, 0, 1.0, 0, CHAIN_WINDOW)
	end
end

-- Decay sweeper: when a chain's window expires, push a final
-- "streak=0" update so the client clears the HUD widget without
-- needing its own timer authority.
task.spawn(function()
	while true do
		task.wait(0.25)
		local now = os.clock()
		for userId, s in pairs(stateByUserId) do
			if s.streak > 0 and (now - s.lastDigAt) > CHAIN_WINDOW then
				s.streak = 0
				local player = Players:GetPlayerByUserId(userId)
				if player then
					ChainComboUpdate:FireClient(player, 0, 1.0, 0, CHAIN_WINDOW)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	stateByUserId[player.UserId] = nil
end)

-- Reset chain on death. Without this, the streak survives the respawn
-- back to the surface — the player dies mid-chain, walks back down, and
-- their next dig extends a chain that was never broken in their hands.
-- Game design: dying breaks the streak.
local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then return end
	humanoid.Died:Connect(function()
		local s = stateByUserId[player.UserId]
		if s and s.streak > 0 then
			s.streak = 0
			ChainComboUpdate:FireClient(player, 0, 1.0, 0, CHAIN_WINDOW)
		end
	end)
end

local function onPlayerAdded(player)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	player.CharacterAdded:Connect(function(c) onCharacterAdded(player, c) end)
end

for _, existing in ipairs(Players:GetPlayers()) do
	onPlayerAdded(existing)
end
Players.PlayerAdded:Connect(onPlayerAdded)
