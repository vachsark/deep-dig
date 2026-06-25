-- EggOpenAnimation.client.lua — full-screen egg-hatch reveal
-- Place in: StarterGui/EggOpenAnimation (LocalScript)
--
-- Listens to Remotes.Notify and matches the hatch text format from
-- PetSystem.server.lua (`"You hatched a <Rarity> <Name>!"`). On match,
-- plays a ~3 second cinematic: dark overlay fade-in, egg pop + shake +
-- white-flash crack, pet-name flourish in rarity color with particle
-- burst, overlay fade-out. Tap/click to skip. Concurrent hatches queue
-- (one plays at a time).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HapticService = nil

do
	local ok, service = pcall(function()
		return game:GetService("HapticService")
	end)

	if ok then
		HapticService = service
	end
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local LOCAL_PLAY_SOUND_NAME = "DeepDigLocalPlaySound"
local LocalPlaySound = SoundService:FindFirstChild(LOCAL_PLAY_SOUND_NAME)
if not LocalPlaySound then
	LocalPlaySound = Instance.new("BindableEvent")
	LocalPlaySound.Name = LOCAL_PLAY_SOUND_NAME
	LocalPlaySound.Parent = SoundService
end

-- ═══════════════════════════════════════════════════════════════════
-- Remotes — graceful no-op if PetSystem isn't loaded
-- ═══════════════════════════════════════════════════════════════════

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if not Remotes then
	warn("[EggOpenAnimation] Remotes folder not found — skipping.")
	return
end

local NotifyEvent = Remotes:WaitForChild("Notify", 5)
if not NotifyEvent then
	warn("[EggOpenAnimation] Notify remote missing — skipping.")
	return
end

-- PetDatabase is optional; we only use it for the per-pet color tint
-- on particles. If unavailable we fall back to the rarity color.
local petDatabaseModule = ReplicatedStorage:FindFirstChild("PetDatabase")
local PetDatabase = nil
if petDatabaseModule then
	local ok, mod = pcall(require, petDatabaseModule)
	if ok then
		PetDatabase = mod
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Style — mirror PetGui.client.lua palette
-- ═══════════════════════════════════════════════════════════════════

local RarityColors = {
	Common    = Color3.fromRGB(180, 180, 180),
	Uncommon  = Color3.fromRGB(30, 200, 30),
	Rare      = Color3.fromRGB(30, 100, 255),
	Epic      = Color3.fromRGB(160, 50, 255),
	Legendary = Color3.fromRGB(255, 170, 0),
	Mythic    = Color3.fromRGB(255, 50, 50),
}

-- ═══════════════════════════════════════════════════════════════════
-- Concurrency state
-- ═══════════════════════════════════════════════════════════════════

local playing = false
local pending = {}
local skipRequested = false
local hapticSupportChecked = false
local hapticSupported = false
local hapticMotorSupport = {}
local hapticSequence = 0

local HAPTIC_INPUT_TYPE = Enum.UserInputType.Gamepad1
local HAPTIC_SMALL_MOTOR = Enum.VibrationMotor.Small
local HAPTIC_LARGE_MOTOR = Enum.VibrationMotor.Large
local CRACK_HAPTIC_DURATION = 0.055
local CRACK_HAPTIC_SMALL_STRENGTH = 0.08
local CRACK_HAPTIC_LARGE_STRENGTH = 0.14

local RevealHapticProfiles = {
	Common = { small = 0.06, large = 0.12, duration = 0.12 },
	Uncommon = { small = 0.07, large = 0.14, duration = 0.14 },
	Rare = { small = 0.08, large = 0.17, duration = 0.16 },
	Epic = { small = 0.11, large = 0.24, duration = 0.2 },
	Legendary = { small = 0.16, large = 0.36, duration = 0.28 },
	Mythic = { small = 0.2, large = 0.45, duration = 0.34 },
}

-- ═══════════════════════════════════════════════════════════════════
-- Animation
-- ═══════════════════════════════════════════════════════════════════

local function canUseHaptics()
	if hapticSupportChecked then
		return hapticSupported
	end

	hapticSupportChecked = true
	if not HapticService then
		return false
	end

	local ok, supported = pcall(function()
		return HapticService:IsVibrationSupported(HAPTIC_INPUT_TYPE)
	end)
	hapticSupported = ok and supported == true
	return hapticSupported
end

local function canUseHapticMotor(motor)
	if not canUseHaptics() then
		return false
	end

	if hapticMotorSupport[motor] ~= nil then
		return hapticMotorSupport[motor]
	end

	local ok, supported = pcall(function()
		return HapticService:IsMotorSupported(HAPTIC_INPUT_TYPE, motor)
	end)
	hapticMotorSupport[motor] = ok and supported == true
	return hapticMotorSupport[motor]
end

local function setHapticMotor(motor, strength)
	if not canUseHapticMotor(motor) then
		return
	end

	pcall(function()
		HapticService:SetMotor(HAPTIC_INPUT_TYPE, motor, strength)
	end)
end

local function clearHapticPulse(sequence)
	if sequence and sequence ~= hapticSequence then
		return
	end

	setHapticMotor(HAPTIC_SMALL_MOTOR, 0)
	setHapticMotor(HAPTIC_LARGE_MOTOR, 0)
end

local function playHapticPulse(smallStrength, largeStrength, duration)
	hapticSequence = hapticSequence + 1
	local sequence = hapticSequence

	setHapticMotor(HAPTIC_SMALL_MOTOR, smallStrength)
	setHapticMotor(HAPTIC_LARGE_MOTOR, largeStrength)

	task.delay(duration, function()
		clearHapticPulse(sequence)
	end)
end

local function stopHaptics()
	hapticSequence = hapticSequence + 1
	clearHapticPulse()
end

local function playCrackHaptics()
	playHapticPulse(CRACK_HAPTIC_SMALL_STRENGTH, CRACK_HAPTIC_LARGE_STRENGTH, CRACK_HAPTIC_DURATION)
end

local function playRevealHaptics(rarity)
	local profile = RevealHapticProfiles[rarity] or RevealHapticProfiles.Common
	playHapticPulse(profile.small, profile.large, profile.duration)
end

local function getPetColor(name)
	if PetDatabase and type(PetDatabase.getPet) == "function" then
		local ok, record = pcall(PetDatabase.getPet, name)
		if ok and type(record) == "table" and typeof(record.color) == "Color3" then
			return record.color
		end
	end
	return nil
end

-- Wait for either `seconds` to elapse OR for skipRequested to flip true.
-- Returns true if a skip was requested during the wait.
local function waitOrSkip(seconds)
	local elapsed = 0
	local step = 1 / 30
	while elapsed < seconds do
		if skipRequested then return true end
		task.wait(step)
		elapsed = elapsed + step
	end
	return skipRequested
end

local function tweenAndWait(instance, info, props)
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	-- Honor mid-tween skip without blocking the whole sequence on Completed.
	local done = false
	tween.Completed:Connect(function()
		done = true
	end)
	while not done and not skipRequested do
		task.wait(1 / 30)
	end
	if skipRequested and not done then
		tween:Cancel()
	end
end

local function playLocalSound(key)
	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire(key)
	end
end

local function playRevealAnimation(rarity, name)
	skipRequested = false
	local rarityColor = RarityColors[rarity] or RarityColors.Common
	local petColor = getPetColor(name) or rarityColor
	local revealSoundKey = "pet_hatch_reveal"
	if rarity == "Legendary" or rarity == "Mythic" then
		revealSoundKey = "pet_hatch_reveal_strong"
	end

	-- ─── ScreenGui scaffold ─────────────────────────────────────
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "EggOpenAnimation"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 100
	screenGui.Parent = playerGui

	-- Cleanup helper closes over screenGui so any deferred work bails out.
	local cleaned = false
	local function cleanup()
		if cleaned then return end
		cleaned = true
		if screenGui and screenGui.Parent then
			screenGui:Destroy()
		end
	end

	-- ─── Skip handler — click/tap anywhere ──────────────────────
	-- Use a transparent full-screen TextButton to absorb input. Cheaper
	-- and more reliable than UIS:InputBegan because it auto-cleans with
	-- the ScreenGui.
	local skipCatcher = Instance.new("TextButton")
	skipCatcher.Name = "SkipCatcher"
	skipCatcher.Size = UDim2.new(1, 0, 1, 0)
	skipCatcher.BackgroundTransparency = 1
	skipCatcher.Text = ""
	skipCatcher.AutoButtonColor = false
	skipCatcher.ZIndex = 200
	skipCatcher.Parent = screenGui

	local skipConn
	skipConn = skipCatcher.Activated:Connect(function()
		skipRequested = true
	end)

	-- Belt-and-suspenders: also accept raw input in case the catcher
	-- somehow doesn't receive Activated (e.g. controller).
	local uisConn
	uisConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.Gamepad1 then
			skipRequested = true
		end
	end)

	-- Single bail-out helper — disconnects input listeners and tears down
	-- the GUI. Always returns true so callers can write `if bail() then return end`.
	local function bail()
		if skipConn then
			skipConn:Disconnect()
			skipConn = nil
		end
		if uisConn then
			uisConn:Disconnect()
			uisConn = nil
		end
		stopHaptics()
		cleanup()
		return true
	end

	-- ─── Dark overlay ───────────────────────────────────────────
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 1
	overlay.Parent = screenGui

	-- ─── Egg placeholder (centered) ─────────────────────────────
	local eggHolder = Instance.new("Frame")
	eggHolder.Name = "EggHolder"
	-- Anchor at center so we can tween position offsets symmetrically.
	eggHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	eggHolder.Position = UDim2.new(0.5, 0, 0.5, 0)
	eggHolder.Size = UDim2.new(0, 180, 0, 220)
	eggHolder.BackgroundTransparency = 1
	eggHolder.ZIndex = 10
	eggHolder.Parent = screenGui

	local eggScale = Instance.new("UIScale")
	eggScale.Scale = 0.01
	eggScale.Parent = eggHolder

	local egg = Instance.new("Frame")
	egg.Name = "Egg"
	egg.AnchorPoint = Vector2.new(0.5, 0.5)
	egg.Position = UDim2.new(0.5, 0, 0.5, 0)
	egg.Size = UDim2.new(1, 0, 1, 0)
	egg.BackgroundColor3 = rarityColor
	egg.BackgroundTransparency = 0.05
	egg.BorderSizePixel = 0
	egg.ZIndex = 10
	egg.Parent = eggHolder

	-- An "egg" shape is just a rounded rectangle here. The corner radius
	-- is large enough to read as an egg silhouette without needing art.
	local eggCorner = Instance.new("UICorner")
	eggCorner.CornerRadius = UDim.new(0.5, 0)
	eggCorner.Parent = egg

	local eggStroke = Instance.new("UIStroke")
	eggStroke.Color = Color3.fromRGB(255, 255, 255)
	eggStroke.Thickness = 3
	eggStroke.Transparency = 0.3
	eggStroke.Parent = egg

	local eggGradient = Instance.new("UIGradient")
	eggGradient.Rotation = 90
	eggGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.4, rarityColor),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 40, 50)),
	})
	eggGradient.Parent = egg

	-- White flash overlay on the egg — used for the "crack" moment.
	local eggFlash = Instance.new("Frame")
	eggFlash.Name = "Flash"
	eggFlash.Size = UDim2.new(1, 0, 1, 0)
	eggFlash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	eggFlash.BackgroundTransparency = 1
	eggFlash.BorderSizePixel = 0
	eggFlash.ZIndex = 11
	eggFlash.Parent = egg

	local flashCorner = Instance.new("UICorner")
	flashCorner.CornerRadius = UDim.new(0.5, 0)
	flashCorner.Parent = eggFlash

	-- ─── Pet name flourish (built but hidden until reveal) ──────
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PetName"
	nameLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	nameLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	nameLabel.Size = UDim2.new(0, 600, 0, 110)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = string.format("%s\n%s", rarity, name)
	nameLabel.TextColor3 = rarityColor
	nameLabel.TextTransparency = 1
	nameLabel.TextSize = 48
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextScaled = false
	nameLabel.ZIndex = 20
	nameLabel.Visible = false
	nameLabel.Parent = screenGui

	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = Color3.fromRGB(0, 0, 0)
	nameStroke.Thickness = 3
	nameStroke.Transparency = 1
	nameStroke.Parent = nameLabel

	local nameScale = Instance.new("UIScale")
	nameScale.Scale = 0.6
	nameScale.Parent = nameLabel

	-- ═══════════════════════════════════════════════════════════
	-- Sequence
	-- ═══════════════════════════════════════════════════════════

	-- (1) Overlay fade in — 0.5s
	tweenAndWait(
		overlay,
		TweenInfo.new(0.5, Enum.EasingStyle.Linear),
		{ BackgroundTransparency = 0.25 }
	)
	if skipRequested and bail() then return end

	-- (2) Egg pop — 0% → 100% with Back easing for the bounce — 0.6s
	playLocalSound("egg_pop")
	tweenAndWait(
		eggScale,
		TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	if skipRequested and bail() then return end

	-- (3) Shake — 3 wobbles via tiny offset tweens (no Position changes
	-- on the egg itself — we shift the holder's anchor offset and snap
	-- back). 0.4s total.
	do
		local origPos = eggHolder.Position
		local wobbles = {
			UDim2.new(0.5, 14, 0.5, 0),
			UDim2.new(0.5, -14, 0.5, 0),
			UDim2.new(0.5, 10, 0.5, 0),
			UDim2.new(0.5, -10, 0.5, 0),
			UDim2.new(0.5, 6, 0.5, 0),
			origPos,
		}
		for i, target in ipairs(wobbles) do
			if skipRequested then break end
			if i == 1 or i == 3 or i == 5 then
				playCrackHaptics()
			end
			tweenAndWait(
				eggHolder,
				TweenInfo.new(0.4 / #wobbles, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Position = target }
			)
		end
		eggHolder.Position = origPos
	end
	if skipRequested and bail() then return end

	-- (4) White flash — fade IN to fully white, then OUT while the egg
	-- shrinks to nothing. The crack moment.
	playLocalSound("egg_crack")
	playCrackHaptics()
	local flashIn = TweenService:Create(
		eggFlash,
		TweenInfo.new(0.1, Enum.EasingStyle.Linear),
		{ BackgroundTransparency = 0 }
	)
	flashIn:Play()
	waitOrSkip(0.1)

	local flashOut = TweenService:Create(
		eggFlash,
		TweenInfo.new(0.2, Enum.EasingStyle.Linear),
		{ BackgroundTransparency = 1 }
	)
	flashOut:Play()
	local eggOut = TweenService:Create(
		eggScale,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = 0 }
	)
	eggOut:Play()
	waitOrSkip(0.2)
	-- Egg is gone now — hide the holder so it can't visually intrude.
	eggHolder.Visible = false

	if skipRequested and bail() then return end

	-- (5) Pet-name flourish — fade in + scale up to slightly past 1, then
	-- settle, then hold. 1.0s total display.
	playLocalSound(revealSoundKey)
	playRevealHaptics(rarity)
	nameLabel.Visible = true
	local nameTextIn = TweenService:Create(
		nameLabel,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 0 }
	)
	nameTextIn:Play()
	local nameStrokeIn = TweenService:Create(
		nameStroke,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = 0 }
	)
	nameStrokeIn:Play()
	local nameScalePop = TweenService:Create(
		nameScale,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.1 }
	)
	nameScalePop:Play()
	waitOrSkip(0.35)

	if not skipRequested then
		local settle = TweenService:Create(
			nameScale,
			TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Scale = 1.0 }
		)
		settle:Play()
		waitOrSkip(0.15)
	end

	-- (6) Particle burst — 10 small ImageLabels (using a built-in
	-- circle decal) scatter outward from the name's center and fade.
	-- We use ImageLabels not ParticleEmitter (the latter requires a 3D
	-- BasePart). Cheap, deterministic, and self-cleans with the GUI.
	if not skipRequested then
		local particleCount = 10
		for i = 1, particleCount do
			local p = Instance.new("Frame")
			p.Name = "Particle_" .. i
			p.AnchorPoint = Vector2.new(0.5, 0.5)
			p.Position = UDim2.new(0.5, 0, 0.5, 0)
			p.Size = UDim2.new(0, 12, 0, 12)
			p.BackgroundColor3 = petColor
			p.BackgroundTransparency = 0
			p.BorderSizePixel = 0
			p.ZIndex = 19
			p.Parent = screenGui

			local pCorner = Instance.new("UICorner")
			pCorner.CornerRadius = UDim.new(1, 0)
			pCorner.Parent = p

			-- Distribute around a circle; jitter the radius a bit.
			local angle = (i / particleCount) * math.pi * 2
			local radius = 180 + math.random(0, 80)
			local dx = math.cos(angle) * radius
			local dy = math.sin(angle) * radius

			local outTween = TweenService:Create(
				p,
				TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{
					Position = UDim2.new(0.5, dx, 0.5, dy),
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 4, 0, 4),
				}
			)
			outTween:Play()
		end
		waitOrSkip(0.55)
	end

	-- (7) Hold the name briefly so it's readable, then fade everything.
	if not skipRequested then
		waitOrSkip(0.3)
	end

	-- (8) Final overlay + name fade out — 0.5s
	local fadeOverlay = TweenService:Create(
		overlay,
		TweenInfo.new(0.5, Enum.EasingStyle.Linear),
		{ BackgroundTransparency = 1 }
	)
	fadeOverlay:Play()
	local fadeName = TweenService:Create(
		nameLabel,
		TweenInfo.new(0.5, Enum.EasingStyle.Linear),
		{ TextTransparency = 1 }
	)
	fadeName:Play()
	local fadeStroke = TweenService:Create(
		nameStroke,
		TweenInfo.new(0.5, Enum.EasingStyle.Linear),
		{ Transparency = 1 }
	)
	fadeStroke:Play()
	waitOrSkip(0.5)

	-- (9) Cleanup
	bail()
end

-- ═══════════════════════════════════════════════════════════════════
-- Queue runner
-- ═══════════════════════════════════════════════════════════════════

local function processQueue()
	if playing then return end
	playing = true
	while #pending > 0 do
		local job = table.remove(pending, 1)
		local ok, err = pcall(playRevealAnimation, job.rarity, job.name)
		if not ok then
			warn("[EggOpenAnimation] reveal error: " .. tostring(err))
		end
	end
	playing = false
end

-- ═══════════════════════════════════════════════════════════════════
-- Listener
-- ═══════════════════════════════════════════════════════════════════

NotifyEvent.OnClientEvent:Connect(function(text, _rarityHint)
	if type(text) ~= "string" then return end

	-- PetSystem format: "You hatched a <Rarity> <Name>!" — no leading
	-- emoji on single-target FireClient calls. Be lenient on trailing
	-- text and on any prefix that might get added later.
	local rarity, name = text:match("hatched a (%w+) (.-)!")
	if not rarity or not name or name == "" then return end

	-- Sanity check: the name must look like a pet name (letters + spaces),
	-- not a stray numeric placeholder. If the format ever changes to
	-- include unicode/punctuation we'll still let it through — the
	-- reveal doesn't care, it just renders text.
	if #name > 80 then return end

	table.insert(pending, { rarity = rarity, name = name })
	processQueue()
end)
