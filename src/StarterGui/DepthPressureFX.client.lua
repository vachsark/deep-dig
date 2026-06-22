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

local TIER_PROFILES = {
	Surface = {
		color = Color3.fromRGB(20, 18, 18),
		transparency = 1,
	},
	Modern = {
		color = Color3.fromRGB(82, 70, 58),
		transparency = 0.96,
	},
	Industrial = {
		color = Color3.fromRGB(94, 82, 66),
		transparency = 0.9,
	},
	Medieval = {
		color = Color3.fromRGB(82, 72, 60),
		transparency = 0.84,
	},
	Ancient = {
		color = Color3.fromRGB(76, 62, 48),
		transparency = 0.76,
	},
	Prehistoric = {
		color = Color3.fromRGB(54, 46, 38),
		transparency = 0.67,
	},
	Unknown = {
		color = Color3.fromRGB(44, 22, 60),
		transparency = 0.54,
	},
}

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

local function clampTransparency(value)
	if value < 0 then
		return 0
	end

	if value > 1 then
		return 1
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

local function applyTierProfile(tierName)
	local profile = TIER_PROFILES[tierName] or TIER_PROFILES.Modern
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

UpdateHUDEvent.OnClientEvent:Connect(function(data)
	local tierName = getTierName(data)
	if not tierName then
		return
	end

	applyTierProfile(tierName)
end)
