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
local LOCAL_PLAY_SOUND_NAME = "DeepDigLocalPlaySound"

-- ───────────── Sound groups (mix bus) ────────────────────────────────────
-- A single SFX group lets us duck volume cleanly when fanfare hits.
local sfxGroup = Instance.new("SoundGroup")
sfxGroup.Name = "DeepDigSFX"
sfxGroup.Volume = 0.7
sfxGroup.Parent = SoundService

local LocalPlaySound = SoundService:FindFirstChild(LOCAL_PLAY_SOUND_NAME)
if not LocalPlaySound then
	LocalPlaySound = Instance.new("BindableEvent")
	LocalPlaySound.Name = LOCAL_PLAY_SOUND_NAME
	LocalPlaySound.Parent = SoundService
end

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
	earthquake_rumble = {
		id = "rbxassetid://9114013169", -- low dirt impact rumble
		volume = 0.35,
		playbackSpeed = 0.72,
		replaceExisting = true,
		cleanupDelay = 5,
	},
	enemy_hit = {
		id = "rbxassetid://9114013169", -- short impact thud
		volume = 0.55,
		pitchRange = { 1.05, 1.16 },
	},
	enemy_aggro = {
		id = "rbxassetid://5982968246", -- short warning horn
		volume = 0.45,
		playbackSpeed = 1.35,
	},
	enemy_attack_warning = {
		id = "rbxassetid://5982968246", -- compact attack windup warning
		volume = 0.36,
		playbackSpeed = 1.65,
	},
	enemy_spawn = {
		id = "rbxassetid://9114013169", -- soft dirt surfacing thud
		volume = 0.32,
		playbackSpeed = 0.82,
		pitchRange = { 0.96, 1.04 },
	},
	enemy_defeated = {
		id = "rbxassetid://5852285683", -- stronger defeated cue
		volume = 0.85,
		playbackSpeed = 0.88,
	},
	enemy_miniboss_defeated = {
		id = "rbxassetid://5852285683", -- reused defeated cue, pitched down for boss clear
		volume = 1.0,
		playbackSpeed = 0.68,
	},
	enemy_miniboss_spawn = {
		id = "rbxassetid://5982968246", -- deep warning horn
		volume = 0.9,
		playbackSpeed = 0.72,
	},
	enemy_miniboss_enrage = {
		id = "rbxassetid://5982968246", -- sharper warning horn
		volume = 0.82,
		playbackSpeed = 1.08,
	},
	resurface_fanfare = {
		id = "rbxassetid://6079316752", -- triumphant fanfare
		volume = 1.0,
	},
}

local activeSounds = {}

local function play(key)
	local def = SOUNDS[key]
	if not def then return end

	if def.replaceExisting and activeSounds[key] then
		activeSounds[key]:Destroy()
		activeSounds[key] = nil
	end

	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = def.volume or 0.7
	sound.PlaybackSpeed = def.playbackSpeed or 1
	sound.SoundGroup = sfxGroup

	if def.pitchRange then
		local pitchShift = Instance.new("PitchShiftSoundEffect")
		pitchShift.Octave = def.pitchRange[1] +
			(def.pitchRange[2] - def.pitchRange[1]) * math.random()
		pitchShift.Parent = sound
	end

	sound.Parent = SoundService
	if def.replaceExisting then
		activeSounds[key] = sound
	end

	sound.Ended:Once(function()
		if activeSounds[key] == sound then
			activeSounds[key] = nil
		end
		sound:Destroy()
	end)
	sound:Play()

	-- Safety net in case Ended doesn't fire (asset failed to load).
	task.delay(def.cleanupDelay or 8, function()
		if sound.Parent then
			if activeSounds[key] == sound then
				activeSounds[key] = nil
			end
			sound:Destroy()
		end
	end)
end

PlaySound.OnClientEvent:Connect(play)
LocalPlaySound.Event:Connect(play)

print("[DeepDig] AudioPlayer loaded")
