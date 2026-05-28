-- CombatRespawnFeedback.client.lua - local enemy knockout resurface feedback
-- Place in: StarterGui/CombatRespawnFeedback (LocalScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if not Remotes then
	warn("[CombatRespawnFeedback] Remotes folder not found - skipping.")
	return
end

local CombatRespawnFeedback = Remotes:WaitForChild("CombatRespawnFeedback", 5)
if not CombatRespawnFeedback then
	warn("[CombatRespawnFeedback] CombatRespawnFeedback remote missing - skipping.")
	return
end

local EFFECT_TYPE = "enemy_knockout_resurface"
local DISPLAY_ORDER = 150
local CAMERA_BINDING_NAME = "DeepDigCombatRespawnBump"
local CAMERA_BUMP_DURATION = 0.34
local CAMERA_POSITION_STRENGTH = 0.11
local CAMERA_ROTATION_STRENGTH = math.rad(0.34)
local DEFAULT_GRACE_DURATION = 0

local effectSequence = 0
local activeGui = nil
local cameraBumpBaseCFrame = nil
local cameraBumpBound = false

local function clearCameraBump(sequence)
	if sequence and sequence ~= effectSequence then
		return
	end

	local camera = workspace.CurrentCamera
	if camera and cameraBumpBaseCFrame then
		camera.CFrame = cameraBumpBaseCFrame
	end

	cameraBumpBaseCFrame = nil

	if cameraBumpBound then
		RunService:UnbindFromRenderStep(CAMERA_BINDING_NAME)
		cameraBumpBound = false
	end
end

local function playCameraBump(sequence)
	clearCameraBump()

	local startedAt = os.clock()
	cameraBumpBound = true

	RunService:BindToRenderStep(CAMERA_BINDING_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		if sequence ~= effectSequence then
			clearCameraBump(sequence)
			return
		end

		local camera = workspace.CurrentCamera
		if not camera then
			clearCameraBump(sequence)
			return
		end

		local elapsed = os.clock() - startedAt
		local progress = elapsed / CAMERA_BUMP_DURATION
		if progress >= 1 then
			clearCameraBump(sequence)
			return
		end

		local falloff = 1 - math.clamp(progress, 0, 1)
		local snap = math.sin(progress * math.pi * 2)
		local settle = math.sin(progress * math.pi * 7)

		cameraBumpBaseCFrame = camera.CFrame
		camera.CFrame = cameraBumpBaseCFrame
			* CFrame.new(0, -CAMERA_POSITION_STRENGTH * falloff * math.abs(snap), 0)
			* CFrame.Angles(CAMERA_ROTATION_STRENGTH * settle * falloff, 0, 0)
	end)
end

local function makeLabel(parent, name, text, position, size, textSize, color)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 1
	label.TextSize = textSize
	label.TextScaled = false
	label.Font = Enum.Font.GothamBlack
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = 12
	label.Parent = parent
	return label
end

local function playResurfaceFeedback(graceDuration)
	graceDuration = math.max(tonumber(graceDuration) or DEFAULT_GRACE_DURATION, 0)
	effectSequence = effectSequence + 1
	local sequence = effectSequence

	if activeGui then
		activeGui:Destroy()
		activeGui = nil
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CombatRespawnFeedback"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = DISPLAY_ORDER
	screenGui.Parent = playerGui
	activeGui = screenGui

	local cleaned = false
	local function cleanup()
		if cleaned then
			return
		end

		cleaned = true
		clearCameraBump(sequence)

		if activeGui == screenGui then
			activeGui = nil
		end
		if screenGui and screenGui.Parent then
			screenGui:Destroy()
		end
	end

	local overlay = Instance.new("Frame")
	overlay.Name = "KnockoutOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(12, 5, 8)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 10
	overlay.Parent = screenGui

	local redWash = Instance.new("Frame")
	redWash.Name = "RedWash"
	redWash.AnchorPoint = Vector2.new(0.5, 0.5)
	redWash.Position = UDim2.fromScale(0.5, 0.5)
	redWash.Size = UDim2.fromScale(1, 1)
	redWash.BackgroundColor3 = Color3.fromRGB(125, 18, 28)
	redWash.BackgroundTransparency = 1
	redWash.BorderSizePixel = 0
	redWash.ZIndex = 11
	redWash.Parent = screenGui

	local protectionGlow = Instance.new("Frame")
	protectionGlow.Name = "ProtectionGlow"
	protectionGlow.Size = UDim2.fromScale(1, 1)
	protectionGlow.BackgroundColor3 = Color3.fromRGB(80, 220, 255)
	protectionGlow.BackgroundTransparency = 1
	protectionGlow.BorderSizePixel = 0
	protectionGlow.ZIndex = 10
	protectionGlow.Parent = screenGui

	local title = makeLabel(
		screenGui,
		"Title",
		"RESURFACED",
		UDim2.fromScale(0.5, 0.42),
		UDim2.fromOffset(420, 44),
		32,
		Color3.fromRGB(255, 238, 226)
	)

	local subtitle = makeLabel(
		screenGui,
		"Subtitle",
		"Knocked out - safely returned",
		UDim2.fromScale(0.5, 0.48),
		UDim2.fromOffset(460, 28),
		18,
		Color3.fromRGB(255, 155, 142)
	)
	subtitle.Font = Enum.Font.GothamBold

	local protectionPanel = Instance.new("Frame")
	protectionPanel.Name = "ProtectionPanel"
	protectionPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	protectionPanel.Position = UDim2.fromScale(0.5, 0.56)
	protectionPanel.Size = UDim2.fromOffset(250, 46)
	protectionPanel.BackgroundColor3 = Color3.fromRGB(17, 37, 43)
	protectionPanel.BackgroundTransparency = 1
	protectionPanel.BorderSizePixel = 0
	protectionPanel.ZIndex = 12
	protectionPanel.Visible = graceDuration > 0
	protectionPanel.Parent = screenGui

	local protectionStroke = Instance.new("UIStroke")
	protectionStroke.Name = "ProtectionStroke"
	protectionStroke.Color = Color3.fromRGB(128, 238, 255)
	protectionStroke.Transparency = 1
	protectionStroke.Thickness = 2
	protectionStroke.Parent = protectionPanel

	local protectionLabel = makeLabel(
		protectionPanel,
		"ProtectionLabel",
		"PROTECTED",
		UDim2.fromScale(0.5, 0.36),
		UDim2.fromOffset(220, 20),
		16,
		Color3.fromRGB(220, 252, 255)
	)
	protectionLabel.ZIndex = 13
	protectionLabel.Font = Enum.Font.GothamBlack

	local countdownLabel = makeLabel(
		protectionPanel,
		"CountdownLabel",
		"",
		UDim2.fromScale(0.5, 0.7),
		UDim2.fromOffset(220, 16),
		13,
		Color3.fromRGB(142, 232, 255)
	)
	countdownLabel.ZIndex = 13
	countdownLabel.Font = Enum.Font.GothamBold

	local barBack = Instance.new("Frame")
	barBack.Name = "CountdownBack"
	barBack.AnchorPoint = Vector2.new(0.5, 1)
	barBack.Position = UDim2.fromScale(0.5, 1)
	barBack.Size = UDim2.new(1, -18, 0, 3)
	barBack.BackgroundColor3 = Color3.fromRGB(35, 72, 78)
	barBack.BackgroundTransparency = 1
	barBack.BorderSizePixel = 0
	barBack.ZIndex = 13
	barBack.Parent = protectionPanel

	local barFill = Instance.new("Frame")
	barFill.Name = "CountdownFill"
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(128, 238, 255)
	barFill.BackgroundTransparency = 1
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 14
	barFill.Parent = barBack

	local scale = Instance.new("UIScale")
	scale.Scale = 0.96
	scale.Parent = title

	playCameraBump(sequence)

	local fadeInInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local settleInfo = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local fadeOutInfo = TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	TweenService:Create(overlay, fadeInInfo, { BackgroundTransparency = 0.32 }):Play()
	TweenService:Create(redWash, fadeInInfo, { BackgroundTransparency = 0.72 }):Play()
	TweenService:Create(protectionGlow, fadeInInfo, { BackgroundTransparency = graceDuration > 0 and 0.86 or 1 }):Play()
	TweenService:Create(title, fadeInInfo, { TextTransparency = 0 }):Play()
	TweenService:Create(subtitle, fadeInInfo, { TextTransparency = 0.08 }):Play()
	TweenService:Create(scale, settleInfo, { Scale = 1 }):Play()

	if graceDuration > 0 then
		TweenService:Create(protectionPanel, fadeInInfo, { BackgroundTransparency = 0.18 }):Play()
		TweenService:Create(protectionStroke, fadeInInfo, { Transparency = 0.15 }):Play()
		TweenService:Create(protectionLabel, fadeInInfo, { TextTransparency = 0 }):Play()
		TweenService:Create(countdownLabel, fadeInInfo, { TextTransparency = 0.02 }):Play()
		TweenService:Create(barBack, fadeInInfo, { BackgroundTransparency = 0.2 }):Play()
		TweenService:Create(barFill, fadeInInfo, { BackgroundTransparency = 0 }):Play()

		local graceStartedAt = os.clock()
		task.spawn(function()
			while sequence == effectSequence and not cleaned do
				local remaining = math.max(graceDuration - (os.clock() - graceStartedAt), 0)
				countdownLabel.Text = string.format("%.1fs shield", remaining)
				barFill.Size = UDim2.fromScale(graceDuration > 0 and remaining / graceDuration or 0, 1)

				if remaining <= 0 then
					break
				end
				task.wait(0.05)
			end

			if sequence ~= effectSequence or cleaned then
				return
			end

			countdownLabel.Text = "Shield ended"
			barFill.Size = UDim2.fromScale(0, 1)
			TweenService:Create(protectionGlow, fadeOutInfo, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(protectionPanel, fadeOutInfo, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(protectionStroke, fadeOutInfo, { Transparency = 1 }):Play()
			TweenService:Create(protectionLabel, fadeOutInfo, { TextTransparency = 1 }):Play()
			TweenService:Create(countdownLabel, fadeOutInfo, { TextTransparency = 1 }):Play()
			TweenService:Create(barBack, fadeOutInfo, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(barFill, fadeOutInfo, { BackgroundTransparency = 1 }):Play()
		end)
	end

	task.delay(0.56, function()
		if sequence ~= effectSequence or cleaned then
			return
		end

		TweenService:Create(overlay, fadeOutInfo, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(redWash, fadeOutInfo, { BackgroundTransparency = 1 }):Play()
		if graceDuration <= 0 then
			TweenService:Create(protectionGlow, fadeOutInfo, { BackgroundTransparency = 1 }):Play()
		end
		TweenService:Create(title, fadeOutInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(subtitle, fadeOutInfo, { TextTransparency = 1 }):Play()
	end)

	task.delay(math.max(0.94, graceDuration + 0.38), function()
		if sequence ~= effectSequence then
			return
		end

		cleanup()
	end)
end

CombatRespawnFeedback.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.type ~= EFFECT_TYPE then
		return
	end

	playResurfaceFeedback(payload.graceDuration)
end)
