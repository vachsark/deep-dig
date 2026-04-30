-- EarthquakeFX.client.lua
-- Dedicated client-side VFX for the earthquake world event.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

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
local MAX_DURATION = 60
local SHAKE_MAX_OFFSET = 0.5
local SHAKE_STEP = 0.05

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

local screenGui = nil
local vignetteFrame = nil
local vignetteTween = nil
local dustPart = nil
local dustEmitter = nil

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

local function playEarthquakeSound()
	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("earthquake_rumble")
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
end

EventTriggered.OnClientEvent:Connect(function(eventName, message, duration, effectId)
	if isEarthquakeTrigger(eventName, message, effectId) then
		beginEarthquake(duration)
	end
end)

player.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		cleanup(effectSession)
	end
end)
