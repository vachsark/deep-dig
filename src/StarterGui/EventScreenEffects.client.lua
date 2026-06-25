-- EventScreenEffects.client.lua - lightweight camera feedback for random event starts
-- Place in: StarterGui/EventScreenEffects (LocalScript)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if not Remotes then
	warn("[EventScreenEffects] Remotes folder missing - event camera shake disabled.")
	return
end

local EventTriggered = Remotes:WaitForChild("EventTriggered", 5)
if not EventTriggered then
	warn("[EventScreenEffects] EventTriggered remote missing - event camera shake disabled.")
	return
end

local BIND_NAME = "DeepDigEventScreenEffectsShake"

local LIGHT_SHAKE = {
	duration = 0.34,
	positionStrength = 0.09,
	rotationStrength = 0.22,
	noiseFrequency = 22,
}

local EARTHQUAKE_SHAKE = {
	duration = 0.58,
	positionStrength = 0.24,
	rotationStrength = 0.72,
	noiseFrequency = 18,
}

local LIGHT_EVENT_KEYS = {
	fossillayer = true,
	["2xrare"] = true,
	goldvein = true,
	goldrush = true,
	cavesystem = true,
	bonusloot = true,
}

local EARTHQUAKE_EVENT_KEYS = {
	earthquake = true,
	instantdig = true,
}

local sequence = 0
local state = nil
local bound = false

local function normalizeKey(value)
	if type(value) ~= "string" then
		return ""
	end

	return string.gsub(string.lower(value), "[^%w]", "")
end

local function getShakeProfile(eventName, effectId)
	local nameKey = normalizeKey(eventName)
	local effectKey = normalizeKey(effectId)

	if EARTHQUAKE_EVENT_KEYS[nameKey] or EARTHQUAKE_EVENT_KEYS[effectKey] then
		return EARTHQUAKE_SHAKE
	end

	if LIGHT_EVENT_KEYS[nameKey] or LIGHT_EVENT_KEYS[effectKey] then
		return LIGHT_SHAKE
	end

	return nil
end

local function removeAppliedOffset()
	if not state or not state.appliedOffset then
		return
	end

	local camera = workspace.CurrentCamera
	if camera then
		camera.CFrame = camera.CFrame * state.appliedOffset:Inverse()
	end

	state.appliedOffset = nil
end

local function clearShake(clearSequence)
	if clearSequence and clearSequence ~= sequence then
		return
	end

	removeAppliedOffset()
	state = nil

	if bound then
		RunService:UnbindFromRenderStep(BIND_NAME)
		bound = false
	end
end

local function bindShake()
	if bound then
		return
	end

	bound = true
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 4, function()
		local camera = workspace.CurrentCamera
		if not camera or not state then
			clearShake()
			return
		end

		removeAppliedOffset()

		local elapsed = os.clock() - state.startTime
		local progress = elapsed / state.duration
		if progress >= 1 then
			clearShake(state.sequence)
			return
		end

		local clampedProgress = math.clamp(progress, 0, 1)
		local falloff = (1 - clampedProgress) * (1 - clampedProgress)
		local shakeTime = elapsed * state.noiseFrequency
		local seed = state.seed

		local xNoise = math.noise(seed, shakeTime, 0)
		local yNoise = math.noise(shakeTime, seed, 1)
		local zNoise = math.noise(0, seed, shakeTime)
		local rollNoise = math.noise(shakeTime, 2, seed)

		local positionOffset = Vector3.new(xNoise, yNoise * 0.75, zNoise * 0.35) * state.positionStrength * falloff
		local rotationOffset = CFrame.Angles(0, 0, math.rad(rollNoise * state.rotationStrength * falloff))
		local offset = CFrame.new(positionOffset) * rotationOffset

		state.appliedOffset = offset
		camera.CFrame = camera.CFrame * offset
	end)
end

local function playShake(profile)
	clearShake()
	sequence = sequence + 1

	state = {
		sequence = sequence,
		startTime = os.clock(),
		duration = profile.duration,
		positionStrength = profile.positionStrength,
		rotationStrength = profile.rotationStrength,
		noiseFrequency = profile.noiseFrequency,
		seed = sequence * 0.37,
		appliedOffset = nil,
	}

	bindShake()
end

EventTriggered.OnClientEvent:Connect(function(eventName, _message, _duration, effectId)
	local profile = getShakeProfile(eventName, effectId)
	if not profile then
		return
	end

	playShake(profile)
end)
