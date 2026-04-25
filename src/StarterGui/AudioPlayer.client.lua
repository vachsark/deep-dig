-- AudioPlayer.client.lua — listens for PlaySound and plays mapped Roblox audio.
-- Place in: StarterGui/AudioPlayer (LocalScript)
--
-- Replace the placeholder rbxassetid:// IDs with real Creator Store IDs that
-- you've verified are licensed for use. The current values use Roblox's
-- built-in royalty-free SFX library where possible; when an exact match is
-- not available the entry is `nil` which disables that hook silently
-- (PlaySound:Connect simply skips nil sounds).

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlaySound = Remotes:WaitForChild("PlaySound")

-- ───────────── Sound groups (mix bus) ────────────────────────────────────
-- A single SFX group lets us duck volume cleanly when fanfare hits.
local sfxGroup = Instance.new("SoundGroup")
sfxGroup.Name = "DeepDigSFX"
sfxGroup.Volume = 0.7
sfxGroup.Parent = SoundService

-- ───────────── Asset registry ────────────────────────────────────────────
-- Format: { id = "rbxassetid://<ID>", volume = 0..1, pitchRange = {lo, hi} }
-- pitchRange (optional) randomizes pitch a bit so repeated sounds don't
-- become grating; useful for block_break which fires constantly.
local SOUNDS = {
	block_break = {
		id = "rbxassetid://9114013169", -- generic dirt-hit thud (Roblox-provided)
		volume = 0.6,
		pitchRange = { 0.92, 1.08 },
	},
	item_found = {
		id = "rbxassetid://4612375287", -- soft sparkle chime
		volume = 0.7,
	},
	rare_reveal = {
		id = "rbxassetid://5852285683", -- rising boom + shimmer
		volume = 0.85,
	},
	sell_coins = {
		id = "rbxassetid://6837730320", -- coin clink jingle
		volume = 0.8,
	},
	upgrade_whoosh = {
		id = "rbxassetid://9114011668", -- ascending whoosh
		volume = 0.8,
	},
	event_alarm = {
		id = "rbxassetid://5982968246", -- alert horn
		volume = 0.9,
	},
	resurface_fanfare = {
		id = "rbxassetid://6079316752", -- triumphant fanfare
		volume = 1.0,
	},
}

local function play(key)
	local def = SOUNDS[key]
	if not def then return end

	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = def.volume or 0.7
	sound.SoundGroup = sfxGroup

	if def.pitchRange then
		local pitchShift = Instance.new("PitchShiftSoundEffect")
		pitchShift.Octave = def.pitchRange[1] +
			(def.pitchRange[2] - def.pitchRange[1]) * math.random()
		pitchShift.Parent = sound
	end

	sound.Parent = SoundService

	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()

	-- Safety net in case Ended doesn't fire (asset failed to load).
	task.delay(8, function()
		if sound.Parent then sound:Destroy() end
	end)
end

PlaySound.OnClientEvent:Connect(play)

print("[DeepDig] AudioPlayer loaded")
