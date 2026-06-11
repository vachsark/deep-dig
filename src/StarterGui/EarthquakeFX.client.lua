-- EarthquakeFX.client.lua
-- Dedicated client-side VFX for the earthquake world event.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if not Remotes then
	return
end

local EventTriggered = Remotes:WaitForChild("EventTriggered", 5)
if not EventTriggered then
	return
end

local LOCAL_PLAY_SOUND_NAME = "DeepDigLocalPlaySound"
local CAMERA_BIND_NAME = "EarthquakeFXCameraShake"
local EVENT_PULSE_BIND_NAME = "EarthquakeFXEventPulse"
local MAX_DURATION = 60
local SHAKE_MAX_OFFSET = 0.5
local SHAKE_STEP = 0.05
local EVENT_PULSE_DURATION = 0.45
local EVENT_PULSE_MAX_OFFSET = 0.18
local EVENT_PULSE_STEP = 0.035
local EVENT_PULSE_RING_START_SIZE = 0.52
local EVENT_PULSE_RING_END_SIZE = 1.22
local EVENT_PULSE_RING_THICKNESS = 8
local EVENT_PULSE_HAPTIC_DURATION = 0.1
local EVENT_PULSE_HAPTIC_SMALL_STRENGTH = 0.1
local EVENT_PULSE_HAPTIC_LARGE_STRENGTH = 0.18
local VOLCANO_VENT_MAX_DURATION = 24
local VOLCANO_VENT_DEFAULT_DURATION = 8
local VOLCANO_VENT_PULSE_DURATION = 0.65
local VOLCANO_VENT_CRACK_COUNT = 9
local VOLCANO_VENT_EMBER_COUNT = 14
local VOLCANO_VENT_HEAT_STEP = 0.55
local HAPTIC_INPUT_TYPE = Enum.UserInputType.Gamepad1
local HAPTIC_SMALL_MOTOR = Enum.VibrationMotor.Small
local HAPTIC_LARGE_MOTOR = Enum.VibrationMotor.Large
local EARTHQUAKE_HAPTIC_INTERVAL = 0.36
local EARTHQUAKE_HAPTIC_DURATION = 0.18
local EARTHQUAKE_HAPTIC_SMALL_STRENGTH = 0.12
local EARTHQUAKE_HAPTIC_LARGE_STRENGTH = 0.24

local EVENT_PULSE_SETTINGS = {
	["2x_rare"] = {
		color = Color3.fromRGB(245, 230, 190),
		peakTransparency = 0.68,
	},
	["bonus_loot"] = {
		color = Color3.fromRGB(142, 170, 190),
		peakTransparency = 0.72,
	},
	["gold_rush"] = {
		color = Color3.fromRGB(255, 205, 65),
		peakTransparency = 0.62,
	},
	["lucky_hour"] = {
		color = Color3.fromRGB(166, 225, 84),
		peakTransparency = 0.64,
	},
	["echo_blocks"] = {
		color = Color3.fromRGB(116, 96, 230),
		peakTransparency = 0.66,
	},
	["halloween_loot"] = {
		color = Color3.fromRGB(255, 135, 52),
		peakTransparency = 0.6,
	},
	["winter_loot"] = {
		color = Color3.fromRGB(155, 225, 255),
		peakTransparency = 0.62,
	},
	["spring_loot"] = {
		color = Color3.fromRGB(154, 224, 88),
		peakTransparency = 0.64,
	},
	["summer_loot"] = {
		color = Color3.fromRGB(255, 82, 48),
		peakTransparency = 0.61,
	},
	["volcano_vent"] = {
		color = Color3.fromRGB(255, 44, 18),
		peakTransparency = 0.5,
	},
}

local LocalPlaySound = SoundService:FindFirstChild(LOCAL_PLAY_SOUND_NAME)
if not LocalPlaySound then
	LocalPlaySound = Instance.new("BindableEvent")
	LocalPlaySound.Name = LOCAL_PLAY_SOUND_NAME
	LocalPlaySound.Parent = SoundService
end

local active = false
local effectSession = 0
local effectEndTime = 0
local currentShakeOffset = Vector3.new(0, 0, 0)
local lastAppliedShakeOffset = Vector3.new(0, 0, 0)
local renderBound = false
local eventPulseActive = false
local eventPulseSession = 0
local eventPulseEndTime = 0
local eventPulseOffset = Vector3.new(0, 0, 0)
local lastAppliedEventPulseOffset = Vector3.new(0, 0, 0)
local eventPulseRenderBound = false

local screenGui = nil
local vignetteFrame = nil
local vignetteTween = nil
local dustPart = nil
local dustEmitter = nil
local eventPulseGui = nil
local eventPulseFrame = nil
local eventPulseRing = nil
local eventPulseRingStroke = nil
local eventPulseTween = nil
local eventPulseRingTween = nil
local eventPulseRingStrokeTween = nil
local volcanoVentActive = false
local volcanoVentSession = 0
local volcanoVentEndTime = 0
local volcanoVentGui = nil
local volcanoHeatFrame = nil
local volcanoSurgeFrame = nil
local volcanoCrackFrames = {}
local volcanoCrackStrokes = {}
local volcanoEmberFrames = {}
local volcanoTweens = {}
local hapticSupportChecked = false
local hapticSupported = false
local hapticMotorSupport = {}
local hapticSequence = 0

local function isEarthquakeTrigger(eventName, message, effectId)
	local function matches(text)
		if type(text) ~= "string" then
			return false
		end

		local lowered = string.lower(text)
		return lowered:find("earthquake", 1, true) ~= nil
			or lowered:find("quake", 1, true) ~= nil
			or lowered:find("tremble", 1, true) ~= nil
	end

	return matches(effectId) or matches(eventName) or matches(message)
end

local function getIsLowEndDevice()
	if RunService:IsStudio() then
		return true
	end

	local platform = UserInputService:GetPlatform()
	local lowEndPlatforms = {
		Android = true,
		IOS = true,
		UWP = true,
		XboxOne = true,
		PlayStation4 = true,
		PlayStation5 = true,
		NintendoSwitch = true,
	}

	return lowEndPlatforms[platform.Name] == true
end

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

local function randomShakeOffset()
	local x = math.random() * 2 - 1
	local y = math.random() * 2 - 1
	local z = math.random() * 2 - 1
	local dir = Vector3.new(x, y, z)
	if dir.Magnitude < 1e-3 then
		dir = Vector3.new(1, 0, 0)
	end

	local magnitude = math.random() * SHAKE_MAX_OFFSET
	return dir.Unit * magnitude
end

local function randomEventPulseOffset()
	local x = math.random() * 2 - 1
	local y = math.random() * 2 - 1
	local dir = Vector3.new(x, y, 0)
	if dir.Magnitude < 1e-3 then
		dir = Vector3.new(1, 0, 0)
	end

	local magnitude = EVENT_PULSE_MAX_OFFSET * (0.45 + math.random() * 0.55)
	return dir.Unit * magnitude
end

local function ensureUi()
	if screenGui then
		return
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "EarthquakeFX"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 10000
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	vignetteFrame = Instance.new("Frame")
	vignetteFrame.Name = "Vignette"
	vignetteFrame.Size = UDim2.fromScale(1, 1)
	vignetteFrame.Position = UDim2.fromScale(0.5, 0.5)
	vignetteFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	vignetteFrame.BackgroundColor3 = Color3.fromRGB(92, 62, 24)
	vignetteFrame.BackgroundTransparency = 0.9
	vignetteFrame.BorderSizePixel = 0
	vignetteFrame.ZIndex = 100
	vignetteFrame.Parent = screenGui
end

local function ensureEventPulseUi()
	if eventPulseGui then
		return
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")

	eventPulseGui = Instance.new("ScreenGui")
	eventPulseGui.Name = "EventPulseFX"
	eventPulseGui.ResetOnSpawn = false
	eventPulseGui.IgnoreGuiInset = true
	eventPulseGui.DisplayOrder = 10001
	eventPulseGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	eventPulseGui.Parent = playerGui

	eventPulseFrame = Instance.new("Frame")
	eventPulseFrame.Name = "TintPulse"
	eventPulseFrame.Size = UDim2.fromScale(1, 1)
	eventPulseFrame.Position = UDim2.fromScale(0.5, 0.5)
	eventPulseFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	eventPulseFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	eventPulseFrame.BackgroundTransparency = 1
	eventPulseFrame.BorderSizePixel = 0
	eventPulseFrame.ZIndex = 110
	eventPulseFrame.Parent = eventPulseGui

	eventPulseRing = Instance.new("Frame")
	eventPulseRing.Name = "ImpactRing"
	eventPulseRing.Size = UDim2.fromScale(EVENT_PULSE_RING_START_SIZE, EVENT_PULSE_RING_START_SIZE)
	eventPulseRing.Position = UDim2.fromScale(0.5, 0.5)
	eventPulseRing.AnchorPoint = Vector2.new(0.5, 0.5)
	eventPulseRing.BackgroundTransparency = 1
	eventPulseRing.BorderSizePixel = 0
	eventPulseRing.ZIndex = 111
	eventPulseRing.Parent = eventPulseGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = eventPulseRing

	eventPulseRingStroke = Instance.new("UIStroke")
	eventPulseRingStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	eventPulseRingStroke.LineJoinMode = Enum.LineJoinMode.Round
	eventPulseRingStroke.Thickness = EVENT_PULSE_RING_THICKNESS
	eventPulseRingStroke.Transparency = 1
	eventPulseRingStroke.Parent = eventPulseRing
end

local function addVolcanoTween(tween)
	table.insert(volcanoTweens, tween)
	tween:Play()
	return tween
end

local function cancelVolcanoTweens()
	for _, tween in ipairs(volcanoTweens) do
		if tween then
			tween:Cancel()
		end
	end

	volcanoTweens = {}
end

local function ensureVolcanoVentUi()
	if volcanoVentGui then
		return
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")

	volcanoVentGui = Instance.new("ScreenGui")
	volcanoVentGui.Name = "VolcanoVentFX"
	volcanoVentGui.ResetOnSpawn = false
	volcanoVentGui.IgnoreGuiInset = true
	volcanoVentGui.DisplayOrder = 10002
	volcanoVentGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	volcanoVentGui.Parent = playerGui

	volcanoHeatFrame = Instance.new("Frame")
	volcanoHeatFrame.Name = "HeatHaze"
	volcanoHeatFrame.Size = UDim2.fromScale(1, 1)
	volcanoHeatFrame.Position = UDim2.fromScale(0.5, 0.5)
	volcanoHeatFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	volcanoHeatFrame.BackgroundColor3 = Color3.fromRGB(255, 83, 28)
	volcanoHeatFrame.BackgroundTransparency = 1
	volcanoHeatFrame.BorderSizePixel = 0
	volcanoHeatFrame.ZIndex = 120
	volcanoHeatFrame.Parent = volcanoVentGui

	volcanoSurgeFrame = Instance.new("Frame")
	volcanoSurgeFrame.Name = "LavaSurge"
	volcanoSurgeFrame.Size = UDim2.fromScale(1, 1)
	volcanoSurgeFrame.Position = UDim2.fromScale(0.5, 0.5)
	volcanoSurgeFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	volcanoSurgeFrame.BackgroundColor3 = Color3.fromRGB(255, 36, 10)
	volcanoSurgeFrame.BackgroundTransparency = 1
	volcanoSurgeFrame.BorderSizePixel = 0
	volcanoSurgeFrame.ZIndex = 121
	volcanoSurgeFrame.Parent = volcanoVentGui

	local crackSpecs = {
		{ position = UDim2.fromScale(0.12, 0.16), size = UDim2.fromScale(0.009, 0.22), rotation = -38 },
		{ position = UDim2.fromScale(0.2, 0.34), size = UDim2.fromScale(0.007, 0.14), rotation = 23 },
		{ position = UDim2.fromScale(0.78, 0.18), size = UDim2.fromScale(0.008, 0.18), rotation = 32 },
		{ position = UDim2.fromScale(0.88, 0.38), size = UDim2.fromScale(0.006, 0.14), rotation = -28 },
		{ position = UDim2.fromScale(0.1, 0.78), size = UDim2.fromScale(0.008, 0.18), rotation = 30 },
		{ position = UDim2.fromScale(0.32, 0.88), size = UDim2.fromScale(0.007, 0.15), rotation = -62 },
		{ position = UDim2.fromScale(0.72, 0.84), size = UDim2.fromScale(0.009, 0.2), rotation = 49 },
		{ position = UDim2.fromScale(0.92, 0.74), size = UDim2.fromScale(0.007, 0.16), rotation = -44 },
		{ position = UDim2.fromScale(0.53, 0.12), size = UDim2.fromScale(0.006, 0.13), rotation = 68 },
	}

	for i = 1, VOLCANO_VENT_CRACK_COUNT do
		local spec = crackSpecs[i]
		local crack = Instance.new("Frame")
		crack.Name = "LavaCrack" .. i
		crack.Size = spec.size
		crack.Position = spec.position
		crack.AnchorPoint = Vector2.new(0.5, 0.5)
		crack.Rotation = spec.rotation
		crack.BackgroundColor3 = Color3.fromRGB(42, 9, 4)
		crack.BackgroundTransparency = 1
		crack.BorderSizePixel = 0
		crack.ZIndex = 122
		crack.Parent = volcanoVentGui

		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = Color3.fromRGB(255, 128, 24)
		stroke.Thickness = 2
		stroke.Transparency = 1
		stroke.Parent = crack

		table.insert(volcanoCrackFrames, crack)
		table.insert(volcanoCrackStrokes, stroke)
	end

	for i = 1, VOLCANO_VENT_EMBER_COUNT do
		local ember = Instance.new("Frame")
		ember.Name = "Ember" .. i
		ember.Size = UDim2.fromOffset(5 + (i % 4) * 2, 5 + (i % 4) * 2)
		ember.Position = UDim2.fromScale((i % 7 + 1) / 8, 1.05)
		ember.AnchorPoint = Vector2.new(0.5, 0.5)
		ember.BackgroundColor3 = i % 3 == 0 and Color3.fromRGB(255, 214, 96) or Color3.fromRGB(255, 91, 31)
		ember.BackgroundTransparency = 1
		ember.BorderSizePixel = 0
		ember.ZIndex = 123
		ember.Parent = volcanoVentGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = ember

		table.insert(volcanoEmberFrames, ember)
	end
end

local function getDustRate()
	return getIsLowEndDevice() and 18 or 50
end

local function ensureDust()
	if dustPart and dustEmitter then
		return
	end

	dustPart = Instance.new("Part")
	dustPart.Name = "EarthquakeDustAnchor"
	dustPart.Anchored = true
	dustPart.CanCollide = false
	dustPart.CanQuery = false
	dustPart.CanTouch = false
	dustPart.CastShadow = false
	dustPart.Transparency = 1
	dustPart.Size = Vector3.new(1, 1, 1)
	dustPart.Parent = workspace

	dustEmitter = Instance.new("ParticleEmitter")
	dustEmitter.Name = "EarthquakeDust"
	dustEmitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dustEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(132, 112, 89)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(92, 86, 78)),
	})
	dustEmitter.LightEmission = 0
	dustEmitter.Rate = getDustRate()
	dustEmitter.Lifetime = NumberRange.new(1.6, 2.2)
	dustEmitter.Speed = NumberRange.new(1.5, 4.0)
	dustEmitter.SpreadAngle = Vector2.new(180, 180)
	dustEmitter.Acceleration = Vector3.new(0, 1.2, 0)
	dustEmitter.Drag = 3
	dustEmitter.Rotation = NumberRange.new(0, 360)
	dustEmitter.RotSpeed = NumberRange.new(-12, 12)
	dustEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.5, 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	dustEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.7, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	dustEmitter.EmissionDirection = Enum.NormalId.Top
	dustEmitter.Parent = dustPart
end

local function cleanup(session)
	if session and session ~= effectSession then
		return
	end

	active = false
	effectEndTime = 0
	stopHaptics()

	local camera = workspace.CurrentCamera
	if camera and lastAppliedShakeOffset.Magnitude > 0 then
		camera.CFrame = camera.CFrame * CFrame.new(-lastAppliedShakeOffset)
	end

	currentShakeOffset = Vector3.new(0, 0, 0)
	lastAppliedShakeOffset = Vector3.new(0, 0, 0)

	if renderBound then
		RunService:UnbindFromRenderStep(CAMERA_BIND_NAME)
		renderBound = false
	end

	if vignetteTween then
		vignetteTween:Cancel()
		vignetteTween = nil
	end

	if screenGui then
		screenGui:Destroy()
		screenGui = nil
		vignetteFrame = nil
	end

	if dustEmitter then
		dustEmitter:Destroy()
		dustEmitter = nil
	end

	if dustPart then
		dustPart:Destroy()
		dustPart = nil
	end
end

local function cleanupEventPulse(session)
	if session and session ~= eventPulseSession then
		return
	end

	eventPulseActive = false
	eventPulseEndTime = 0

	local camera = workspace.CurrentCamera
	if camera and lastAppliedEventPulseOffset.Magnitude > 0 then
		camera.CFrame = camera.CFrame * CFrame.new(-lastAppliedEventPulseOffset)
	end

	eventPulseOffset = Vector3.new(0, 0, 0)
	lastAppliedEventPulseOffset = Vector3.new(0, 0, 0)

	if eventPulseRenderBound then
		RunService:UnbindFromRenderStep(EVENT_PULSE_BIND_NAME)
		eventPulseRenderBound = false
	end

	if eventPulseTween then
		eventPulseTween:Cancel()
		eventPulseTween = nil
	end

	if eventPulseRingTween then
		eventPulseRingTween:Cancel()
		eventPulseRingTween = nil
	end

	if eventPulseRingStrokeTween then
		eventPulseRingStrokeTween:Cancel()
		eventPulseRingStrokeTween = nil
	end

	if eventPulseGui then
		eventPulseGui:Destroy()
		eventPulseGui = nil
		eventPulseFrame = nil
		eventPulseRing = nil
		eventPulseRingStroke = nil
	end
end

local function cleanupVolcanoVent(session)
	if session and session ~= volcanoVentSession then
		return
	end

	volcanoVentActive = false
	volcanoVentEndTime = 0
	cancelVolcanoTweens()

	if volcanoVentGui then
		volcanoVentGui:Destroy()
		volcanoVentGui = nil
		volcanoHeatFrame = nil
		volcanoSurgeFrame = nil
	end

	volcanoCrackFrames = {}
	volcanoCrackStrokes = {}
	volcanoEmberFrames = {}
end

local function startEventImpactRing(settings)
	if not eventPulseRing or not eventPulseRingStroke then
		return
	end

	if eventPulseRingTween then
		eventPulseRingTween:Cancel()
	end

	if eventPulseRingStrokeTween then
		eventPulseRingStrokeTween:Cancel()
	end

	eventPulseRing.Size = UDim2.fromScale(EVENT_PULSE_RING_START_SIZE, EVENT_PULSE_RING_START_SIZE)
	eventPulseRingStroke.Color = settings.color
	eventPulseRingStroke.Thickness = EVENT_PULSE_RING_THICKNESS
	eventPulseRingStroke.Transparency = math.max(settings.peakTransparency - 0.22, 0.18)

	eventPulseRingTween = TweenService:Create(
		eventPulseRing,
		TweenInfo.new(EVENT_PULSE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(EVENT_PULSE_RING_END_SIZE, EVENT_PULSE_RING_END_SIZE) }
	)
	eventPulseRingStrokeTween = TweenService:Create(
		eventPulseRingStroke,
		TweenInfo.new(EVENT_PULSE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Thickness = 1,
			Transparency = 1,
		}
	)

	eventPulseRingTween:Play()
	eventPulseRingStrokeTween:Play()
end

local function ensureRenderBinding()
	if renderBound then
		return
	end

	renderBound = true
	RunService:BindToRenderStep(CAMERA_BIND_NAME, Enum.RenderPriority.Camera.Value + 2, function()
		if not active then
			return
		end

		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		if lastAppliedShakeOffset.Magnitude > 0 then
			camera.CFrame = camera.CFrame * CFrame.new(-lastAppliedShakeOffset)
		end

		if currentShakeOffset.Magnitude > 0 then
			camera.CFrame = camera.CFrame * CFrame.new(currentShakeOffset)
		end

		lastAppliedShakeOffset = currentShakeOffset

		if dustPart then
			local focus = camera.Focus
			dustPart.CFrame = CFrame.new(focus.Position)
		end
	end)
end

local function ensureEventPulseRenderBinding()
	if eventPulseRenderBound then
		return
	end

	eventPulseRenderBound = true
	RunService:BindToRenderStep(EVENT_PULSE_BIND_NAME, Enum.RenderPriority.Camera.Value + 3, function()
		if not eventPulseActive then
			return
		end

		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		if lastAppliedEventPulseOffset.Magnitude > 0 then
			camera.CFrame = camera.CFrame * CFrame.new(-lastAppliedEventPulseOffset)
		end

		if eventPulseOffset.Magnitude > 0 then
			camera.CFrame = camera.CFrame * CFrame.new(eventPulseOffset)
		end

		lastAppliedEventPulseOffset = eventPulseOffset
	end)
end

local function playEarthquakeSound()
	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("earthquake_rumble")
	end
end

local function playEventAlarmSound()
	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("event_alarm")
	end
end

local function startVignettePulse(session)
	task.spawn(function()
		local useBright = false
		while active and session == effectSession and os.clock() < effectEndTime do
			if not vignetteFrame then
				break
			end

			useBright = not useBright
			local targetTransparency = useBright and 0.85 or 0.95
			if vignetteTween then
				vignetteTween:Cancel()
			end

			vignetteTween = TweenService:Create(
				vignetteFrame,
				TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ BackgroundTransparency = targetTransparency }
			)
			vignetteTween:Play()

			task.wait(0.5)
		end
	end)
end

local function startShakeLoop(session)
	task.spawn(function()
		while active and session == effectSession and os.clock() < effectEndTime do
			currentShakeOffset = randomShakeOffset()
			task.wait(SHAKE_STEP)
		end

		if session == effectSession then
			cleanup(session)
		end
	end)
end

local function startHapticLoop(session)
	task.spawn(function()
		while active and session == effectSession and os.clock() < effectEndTime do
			playHapticPulse(
				EARTHQUAKE_HAPTIC_SMALL_STRENGTH,
				EARTHQUAKE_HAPTIC_LARGE_STRENGTH,
				EARTHQUAKE_HAPTIC_DURATION
			)
			task.wait(EARTHQUAKE_HAPTIC_INTERVAL)
		end

		if session == effectSession then
			stopHaptics()
		end
	end)
end

local function beginEarthquake(duration)
	local now = os.clock()
	local effectiveDuration = math.min(tonumber(duration) or 30, MAX_DURATION)
	local newEndTime = math.min(now + effectiveDuration, now + MAX_DURATION)

	if active then
		effectEndTime = math.min(math.max(effectEndTime, newEndTime), now + MAX_DURATION)
		playEarthquakeSound()
		return
	end

	effectSession = effectSession + 1
	active = true
	effectEndTime = newEndTime
	currentShakeOffset = Vector3.new(0, 0, 0)
	lastAppliedShakeOffset = Vector3.new(0, 0, 0)

	ensureUi()
	ensureDust()
	ensureRenderBinding()
	playEarthquakeSound()

	startVignettePulse(effectSession)
	startShakeLoop(effectSession)
	startHapticLoop(effectSession)
end

local function startEventPulseLoop(session)
	task.spawn(function()
		while eventPulseActive and session == eventPulseSession and os.clock() < eventPulseEndTime do
			local remaining = eventPulseEndTime - os.clock()
			local fade = math.clamp(remaining / EVENT_PULSE_DURATION, 0, 1)
			eventPulseOffset = randomEventPulseOffset() * fade
			task.wait(EVENT_PULSE_STEP)
		end

		if session == eventPulseSession then
			cleanupEventPulse(session)
		end
	end)
end

local function beginEventPulse(effectId)
	local settings = EVENT_PULSE_SETTINGS[effectId]
	if not settings then
		return
	end

	if eventPulseActive then
		cleanupEventPulse(eventPulseSession)
	end

	eventPulseSession = eventPulseSession + 1
	eventPulseActive = true
	eventPulseEndTime = os.clock() + EVENT_PULSE_DURATION
	eventPulseOffset = Vector3.new(0, 0, 0)
	lastAppliedEventPulseOffset = Vector3.new(0, 0, 0)

	playEventAlarmSound()
	ensureEventPulseUi()
	ensureEventPulseRenderBinding()

	if eventPulseFrame then
		eventPulseFrame.BackgroundColor3 = settings.color
		eventPulseFrame.BackgroundTransparency = 1

		if eventPulseTween then
			eventPulseTween:Cancel()
		end

		eventPulseTween = TweenService:Create(
			eventPulseFrame,
			TweenInfo.new(EVENT_PULSE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		)
		eventPulseFrame.BackgroundTransparency = settings.peakTransparency
		eventPulseTween:Play()
	end

	startEventImpactRing(settings)
	playHapticPulse(
		EVENT_PULSE_HAPTIC_SMALL_STRENGTH,
		EVENT_PULSE_HAPTIC_LARGE_STRENGTH,
		EVENT_PULSE_HAPTIC_DURATION
	)

	startEventPulseLoop(eventPulseSession)
end

local function getVolcanoVentDuration(duration)
	local effectiveDuration = tonumber(duration) or VOLCANO_VENT_DEFAULT_DURATION
	if effectiveDuration <= 0 then
		effectiveDuration = VOLCANO_VENT_DEFAULT_DURATION
	end

	return math.min(effectiveDuration, VOLCANO_VENT_MAX_DURATION)
end

local function startVolcanoVentPulse(session)
	if not volcanoHeatFrame or not volcanoSurgeFrame then
		return
	end

	volcanoHeatFrame.BackgroundTransparency = 0.88
	volcanoSurgeFrame.BackgroundTransparency = 0.38

	addVolcanoTween(TweenService:Create(
		volcanoSurgeFrame,
		TweenInfo.new(VOLCANO_VENT_PULSE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	))

	for i, crack in ipairs(volcanoCrackFrames) do
		local stroke = volcanoCrackStrokes[i]
		crack.BackgroundTransparency = 0.16
		if stroke then
			stroke.Transparency = 0.08
		end

		addVolcanoTween(TweenService:Create(
			crack,
			TweenInfo.new(1.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0.6 }
		))

		if stroke then
			addVolcanoTween(TweenService:Create(
				stroke,
				TweenInfo.new(1.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ Transparency = 0.46 }
			))
		end
	end

	task.delay(VOLCANO_VENT_PULSE_DURATION, function()
		if session ~= volcanoVentSession or not volcanoVentActive or not volcanoSurgeFrame then
			return
		end

		volcanoSurgeFrame.BackgroundTransparency = 1
	end)
end

local function startVolcanoVentLoop(session)
	task.spawn(function()
		local useBrightHeat = false
		while volcanoVentActive and session == volcanoVentSession and os.clock() < volcanoVentEndTime do
			useBrightHeat = not useBrightHeat

			if volcanoHeatFrame then
				local heatTransparency = useBrightHeat and 0.88 or 0.94
				addVolcanoTween(TweenService:Create(
					volcanoHeatFrame,
					TweenInfo.new(VOLCANO_VENT_HEAT_STEP, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ BackgroundTransparency = heatTransparency }
				))
			end

			for i, crack in ipairs(volcanoCrackFrames) do
				local stroke = volcanoCrackStrokes[i]
				local crackTransparency = useBrightHeat and 0.52 or 0.66
				local strokeTransparency = useBrightHeat and 0.34 or 0.55

				addVolcanoTween(TweenService:Create(
					crack,
					TweenInfo.new(VOLCANO_VENT_HEAT_STEP, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ BackgroundTransparency = crackTransparency }
				))

				if stroke then
					addVolcanoTween(TweenService:Create(
						stroke,
						TweenInfo.new(VOLCANO_VENT_HEAT_STEP, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
						{ Transparency = strokeTransparency }
					))
				end
			end

			for i, ember in ipairs(volcanoEmberFrames) do
				if ember then
					local size = 4 + math.random(0, 6)
					local startX = math.random(8, 92) / 100
					local endX = math.clamp(startX + (math.random(-10, 10) / 100), 0.04, 0.96)
					local endY = math.random(12, 82) / 100
					local travelTime = 0.8 + math.random() * 0.7

					ember.Size = UDim2.fromOffset(size, size)
					ember.Position = UDim2.fromScale(startX, 1.04)
					ember.BackgroundTransparency = i % 2 == 0 and 0.12 or 0.28

					addVolcanoTween(TweenService:Create(
						ember,
						TweenInfo.new(travelTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{
							Position = UDim2.fromScale(endX, endY),
							BackgroundTransparency = 1,
						}
					))
				end
			end

			task.wait(VOLCANO_VENT_HEAT_STEP)
		end

		if session == volcanoVentSession then
			cleanupVolcanoVent(session)
		end
	end)
end

local function beginVolcanoVent(duration)
	if volcanoVentActive then
		cleanupVolcanoVent(volcanoVentSession)
	end

	volcanoVentSession = volcanoVentSession + 1
	volcanoVentActive = true
	volcanoVentEndTime = os.clock() + getVolcanoVentDuration(duration)

	playEventAlarmSound()
	ensureVolcanoVentUi()
	startVolcanoVentPulse(volcanoVentSession)
	playHapticPulse(
		EVENT_PULSE_HAPTIC_SMALL_STRENGTH,
		EVENT_PULSE_HAPTIC_LARGE_STRENGTH,
		EVENT_PULSE_HAPTIC_DURATION
	)
	startVolcanoVentLoop(volcanoVentSession)
end

EventTriggered.OnClientEvent:Connect(function(eventName, message, duration, effectId)
	if isEarthquakeTrigger(eventName, message, effectId) then
		beginEarthquake(duration)
		return
	end

	if effectId == "volcano_vent" then
		beginVolcanoVent(duration)
		return
	end

	beginEventPulse(effectId)
end)

player.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		cleanup(effectSession)
		cleanupEventPulse(eventPulseSession)
		cleanupVolcanoVent(volcanoVentSession)
	end
end)
