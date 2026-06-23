-- DepthPressureFX.client.lua
-- Subtle screen-edge pressure that grows with deeper depth tiers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if not Remotes then
	return
end

local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD", 5)
if not UpdateHUDEvent then
	return
end

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local DISPLAY_ORDER = 9
local TWEEN_DURATION = 0.7
local EDGE_Z_INDEX = 1
local PARTICLE_Z_INDEX = 2
local PARTICLE_POOL_SIZE = 24
local PARTICLE_DRIFT_MIN_SECONDS = 5
local PARTICLE_DRIFT_MAX_SECONDS = 10

local TIER_PROFILES = {
	Surface = {
		color = Color3.fromRGB(20, 18, 18),
		transparency = 1,
		particleCount = 0,
		particleTransparency = 1,
		particleSize = 2,
	},
	Modern = {
		color = Color3.fromRGB(82, 70, 58),
		transparency = 0.96,
		particleCount = 0,
		depthParticleBoost = 1,
		particleTransparency = 0.92,
		particleSize = 2,
	},
	Industrial = {
		color = Color3.fromRGB(94, 82, 66),
		transparency = 0.9,
		particleCount = 4,
		depthParticleBoost = 2,
		particleTransparency = 0.86,
		particleSize = 3,
	},
	Medieval = {
		color = Color3.fromRGB(82, 72, 60),
		transparency = 0.84,
		particleCount = 7,
		depthParticleBoost = 3,
		particleTransparency = 0.8,
		particleSize = 3,
	},
	Ancient = {
		color = Color3.fromRGB(76, 62, 48),
		transparency = 0.76,
		particleCount = 10,
		depthParticleBoost = 4,
		particleTransparency = 0.73,
		particleSize = 4,
	},
	Prehistoric = {
		color = Color3.fromRGB(54, 46, 38),
		transparency = 0.67,
		particleCount = 14,
		depthParticleBoost = 5,
		particleTransparency = 0.66,
		particleSize = 4,
	},
	Unknown = {
		color = Color3.fromRGB(44, 22, 60),
		transparency = 0.54,
		particleCount = 18,
		depthParticleBoost = 6,
		particleTransparency = 0.56,
		particleSize = 5,
	},
}

local previousGui = playerGui:FindFirstChild("DepthPressureFX")
if previousGui then
	previousGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DepthPressureFX"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = DISPLAY_ORDER
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local edgeConfigs = {
	{
		name = "TopPressure",
		size = UDim2.new(1, 0, 0, 28),
		position = UDim2.fromScale(0, 0),
		gradientRotation = 90,
		transparencyOffset = 0.07,
	},
	{
		name = "BottomPressure",
		size = UDim2.new(1, 0, 0, 82),
		position = UDim2.new(0, 0, 1, -82),
		gradientRotation = 270,
		transparencyOffset = 0,
	},
	{
		name = "LeftPressure",
		size = UDim2.new(0, 54, 1, 0),
		position = UDim2.fromScale(0, 0),
		gradientRotation = 0,
		transparencyOffset = 0.03,
	},
	{
		name = "RightPressure",
		size = UDim2.new(0, 54, 1, 0),
		position = UDim2.new(1, -54, 0, 0),
		gradientRotation = 180,
		transparencyOffset = 0.03,
	},
}

local edges = {}
local activeTweens = {}
local currentTierName = nil
local rng = Random.new()
local particles = {}
local cleanupStarted = false

local particleContainer = Instance.new("Frame")
particleContainer.Name = "PressureMotes"
particleContainer.Size = UDim2.fromScale(1, 1)
particleContainer.Position = UDim2.fromScale(0, 0)
particleContainer.BackgroundTransparency = 1
particleContainer.BorderSizePixel = 0
particleContainer.Active = false
particleContainer.ZIndex = PARTICLE_Z_INDEX
particleContainer.Parent = screenGui

local function clampTransparency(value)
	if value < 0 then
		return 0
	end

	if value > 1 then
		return 1
	end

	return value
end

local function clampNumber(value, minValue, maxValue)
	if value < minValue then
		return minValue
	end

	if value > maxValue then
		return maxValue
	end

	return value
end

local function makeEdge(config)
	local edge = Instance.new("Frame")
	edge.Name = config.name
	edge.Size = config.size
	edge.Position = config.position
	edge.BackgroundColor3 = TIER_PROFILES.Surface.color
	edge.BackgroundTransparency = 1
	edge.BorderSizePixel = 0
	edge.Active = false
	edge.Visible = true
	edge.ZIndex = EDGE_Z_INDEX
	edge.Parent = screenGui

	local gradient = Instance.new("UIGradient")
	gradient.Name = "EdgeFade"
	gradient.Rotation = config.gradientRotation
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = edge

	table.insert(edges, {
		frame = edge,
		transparencyOffset = config.transparencyOffset,
	})
end

local function makeParticle(index)
	local particle = Instance.new("Frame")
	particle.Name = "PressureMote" .. tostring(index)
	particle.AnchorPoint = Vector2.new(0.5, 0.5)
	particle.Size = UDim2.fromOffset(2, 2)
	particle.Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber())
	particle.BackgroundColor3 = Color3.fromRGB(180, 160, 125)
	particle.BackgroundTransparency = 1
	particle.BorderSizePixel = 0
	particle.Active = false
	particle.Visible = false
	particle.ZIndex = PARTICLE_Z_INDEX
	particle.Parent = particleContainer

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = particle

	table.insert(particles, {
		frame = particle,
		active = false,
		driftId = 0,
		sizeJitter = rng:NextNumber(0.65, 1.45),
		sparkWeight = index % 6 == 0 and rng:NextNumber(0.25, 0.55) or 0,
		driftTween = nil,
		fadeTween = nil,
	})
end

local function cancelParticleDrift(particleData)
	if particleData.driftTween then
		particleData.driftTween:Cancel()
		particleData.driftTween = nil
	end
end

local function cancelParticleFade(particleData)
	if particleData.fadeTween then
		particleData.fadeTween:Cancel()
		particleData.fadeTween = nil
	end
end

local startParticleDrift

startParticleDrift = function(particleData)
	if cleanupStarted or not particleData.active or not particleData.frame.Parent then
		return
	end

	particleData.driftId = particleData.driftId + 1
	local driftId = particleData.driftId
	local frame = particleData.frame
	local duration = rng:NextNumber(PARTICLE_DRIFT_MIN_SECONDS, PARTICLE_DRIFT_MAX_SECONDS)
	local targetPosition = UDim2.fromScale(
		rng:NextNumber(-0.04, 1.04),
		rng:NextNumber(-0.04, 1.04)
	)

	cancelParticleDrift(particleData)
	particleData.driftTween = TweenService:Create(
		frame,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ Position = targetPosition }
	)

	particleData.driftTween.Completed:Connect(function(playbackState)
		if playbackState ~= Enum.PlaybackState.Completed then
			return
		end

		if particleData.driftId ~= driftId then
			return
		end

		particleData.driftTween = nil
		startParticleDrift(particleData)
	end)

	particleData.driftTween:Play()
end

local function hideParticle(particleData)
	particleData.active = false
	particleData.driftId = particleData.driftId + 1
	cancelParticleDrift(particleData)
	cancelParticleFade(particleData)

	local frame = particleData.frame
	local fadeTween = TweenService:Create(
		frame,
		TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)

	particleData.fadeTween = fadeTween
	fadeTween.Completed:Connect(function()
		if particleData.fadeTween == fadeTween then
			particleData.fadeTween = nil
		end

		if not particleData.active and frame.Parent then
			frame.Visible = false
		end
	end)
	fadeTween:Play()
end

local function updateParticle(particleData, profile, depthRatio)
	local frame = particleData.frame
	local particleSize = math.max(2, math.floor((profile.particleSize or 2) * particleData.sizeJitter))
	local baseColor = profile.color or TIER_PROFILES.Modern.color
	local sparkColor = Color3.fromRGB(255, 226, 154)
	local particleColor = baseColor:Lerp(sparkColor, particleData.sparkWeight)
	local targetTransparency = clampTransparency((profile.particleTransparency or 0.9) - depthRatio * 0.09)

	frame.Size = UDim2.fromOffset(particleSize, particleSize)
	frame.BackgroundColor3 = particleColor
	frame.Visible = true

	local fadeTween = TweenService:Create(
		frame,
		TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ BackgroundTransparency = targetTransparency }
	)

	cancelParticleFade(particleData)
	particleData.fadeTween = fadeTween
	fadeTween.Completed:Connect(function(playbackState)
		if particleData.fadeTween == fadeTween then
			particleData.fadeTween = nil
		end

		if playbackState == Enum.PlaybackState.Completed and particleData.active and not particleData.driftTween then
			startParticleDrift(particleData)
		end
	end)
	fadeTween:Play()
end

local function getDepthRatio(depth)
	local numericDepth = tonumber(depth) or 0
	local maxDepth = Config.GRID_DEPTH_BLOCKS or 200

	if maxDepth <= 0 then
		return 0
	end

	return clampNumber(numericDepth / maxDepth, 0, 1)
end

local function applyParticleProfile(tierName, depth)
	local profile = TIER_PROFILES[tierName] or TIER_PROFILES.Modern
	local depthRatio = getDepthRatio(depth)
	local depthBoost = math.floor((profile.depthParticleBoost or 0) * depthRatio)
	local targetCount = clampNumber((profile.particleCount or 0) + depthBoost, 0, PARTICLE_POOL_SIZE)

	for index, particleData in ipairs(particles) do
		if index <= targetCount then
			if not particleData.active then
				particleData.frame.Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber())
			end

			particleData.active = true
			updateParticle(particleData, profile, depthRatio)
		elseif particleData.active or particleData.frame.Visible then
			hideParticle(particleData)
		end
	end
end

local function getTierNameFromDepth(depth)
	local numericDepth = tonumber(depth)
	if not numericDepth then
		return nil
	end

	local fallbackTierName = nil
	for _, tier in ipairs(Config.TIERS or {}) do
		if numericDepth >= tier.minDepth and numericDepth <= tier.maxDepth then
			return tier.name
		end

		if numericDepth > tier.maxDepth then
			fallbackTierName = tier.name
		end
	end

	return fallbackTierName or "Modern"
end

local function getTierName(data)
	if type(data) ~= "table" then
		return nil
	end

	if type(data.tierName) == "string" and data.tierName ~= "" then
		return data.tierName
	end

	return getTierNameFromDepth(data.depth)
end

local function cancelTweens()
	for _, tween in ipairs(activeTweens) do
		tween:Cancel()
	end

	activeTweens = {}
end

local function stopEffectsOnly()
	if cleanupStarted then
		return
	end

	cleanupStarted = true
	cancelTweens()

	for _, particleData in ipairs(particles) do
		particleData.active = false
		particleData.driftId = particleData.driftId + 1
		cancelParticleDrift(particleData)
		cancelParticleFade(particleData)
	end
end

local function cleanup()
	stopEffectsOnly()

	if screenGui.Parent then
		screenGui:Destroy()
	end
end

local function applyTierProfile(tierName, depth)
	local profile = TIER_PROFILES[tierName] or TIER_PROFILES.Modern
	applyParticleProfile(tierName, depth)

	if currentTierName == tierName then
		return
	end

	currentTierName = tierName
	cancelTweens()

	for _, edgeData in ipairs(edges) do
		local edge = edgeData.frame
		local targetTransparency = clampTransparency(profile.transparency + edgeData.transparencyOffset)
		local tween = TweenService:Create(
			edge,
			TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{
				BackgroundColor3 = profile.color,
				BackgroundTransparency = targetTransparency,
			}
		)

		table.insert(activeTweens, tween)
		tween:Play()
	end
end

for _, config in ipairs(edgeConfigs) do
	makeEdge(config)
end

for index = 1, PARTICLE_POOL_SIZE do
	makeParticle(index)
end

script.Destroying:Connect(cleanup)
screenGui.Destroying:Connect(function()
	stopEffectsOnly()
end)

UpdateHUDEvent.OnClientEvent:Connect(function(data)
	local tierName = getTierName(data)
	if not tierName then
		return
	end

	applyTierProfile(tierName, type(data) == "table" and data.depth or nil)
end)
