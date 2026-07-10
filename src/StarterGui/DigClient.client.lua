-- DigClient.client.lua — Client-side dig detection
-- Place in: StarterGui/DigClient (LocalScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
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
local mouse = player:GetMouse()
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DigRequest = Remotes:WaitForChild("DigRequest", 10)
local EnemyHitEvent = Remotes:WaitForChild("EnemyHitEvent", 10)
local BlockBreakFeedback = Remotes:WaitForChild("BlockBreakFeedback", 10)

local TARGET_DIG_BLOCK = "DigBlock"
local TARGET_ENEMY = "Enemy"
local CLIENT_ATTACK_RANGE = 8
local DEBUG_DIG_CLIENT = false
local IMPACT_LIFETIME = 0.2
local ENEMY_SPARK_LIFETIME = 0.28
local BLOCK_BREAK_KICK_BIND_NAME = "DeepDigBlockBreakCameraKick"
local BLOCK_BREAK_KICK_DURATION = 0.08
local BLOCK_BREAK_KICK_POSITION = 0.08
local BLOCK_BREAK_KICK_ROTATION = 0.28
local HAPTIC_INPUT_TYPE = Enum.UserInputType.Gamepad1
local HAPTIC_SMALL_MOTOR = Enum.VibrationMotor.Small
local HAPTIC_LARGE_MOTOR = Enum.VibrationMotor.Large

local character = player.Character or player.CharacterAdded:Wait()
local equippedExcavator = nil
local playerGui = player:WaitForChild("PlayerGui")
local moveCloserCueToken = 0
local combatState = {
	attackCooldown = 0.5,
	nextAttackAt = 0,
	recoveryCueUntil = 0,
}
local hapticSupportChecked = false
local hapticSupported = false
local hapticMotorSupport = {}
local hapticSequence = 0
local blockBreakKickSequence = 0
local blockBreakKickState = nil
local blockBreakKickBound = false
local lastBlockBreakKickCFrame = CFrame.new()
local lastBlockBreakKickActive = false

local targetHighlight = Instance.new("Highlight")
targetHighlight.Name = "DeepDigTargetHighlight"
targetHighlight.Enabled = false
targetHighlight.FillTransparency = 0.86
targetHighlight.OutlineTransparency = 0.12
targetHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
targetHighlight.Parent = workspace

local attackRangeRingPart = Instance.new("Part")
attackRangeRingPart.Name = "DeepDigEnemyAttackRangeRing"
attackRangeRingPart.Anchored = true
attackRangeRingPart.CanCollide = false
attackRangeRingPart.CanQuery = false
attackRangeRingPart.CanTouch = false
attackRangeRingPart.CastShadow = false
attackRangeRingPart.Transparency = 1
attackRangeRingPart.Size = Vector3.new(CLIENT_ATTACK_RANGE * 2, 0.05, CLIENT_ATTACK_RANGE * 2)
attackRangeRingPart.Parent = workspace

local attackRangeRingGui = Instance.new("SurfaceGui")
attackRangeRingGui.Name = "RangeRingGui"
attackRangeRingGui.AlwaysOnTop = true
attackRangeRingGui.CanvasSize = Vector2.new(256, 256)
attackRangeRingGui.Enabled = false
attackRangeRingGui.Face = Enum.NormalId.Top
attackRangeRingGui.LightInfluence = 0
attackRangeRingGui.Parent = attackRangeRingPart

local attackRangeRingFrame = Instance.new("Frame")
attackRangeRingFrame.Name = "Ring"
attackRangeRingFrame.AnchorPoint = Vector2.new(0.5, 0.5)
attackRangeRingFrame.BackgroundTransparency = 1
attackRangeRingFrame.BorderSizePixel = 0
attackRangeRingFrame.Position = UDim2.fromScale(0.5, 0.5)
attackRangeRingFrame.Size = UDim2.fromScale(0.94, 0.94)
attackRangeRingFrame.Parent = attackRangeRingGui

local attackRangeRingCorner = Instance.new("UICorner")
attackRangeRingCorner.CornerRadius = UDim.new(1, 0)
attackRangeRingCorner.Parent = attackRangeRingFrame

local attackRangeRingStroke = Instance.new("UIStroke")
attackRangeRingStroke.Color = Color3.fromRGB(255, 118, 46)
attackRangeRingStroke.Thickness = 5
attackRangeRingStroke.Transparency = 0.36
attackRangeRingStroke.Parent = attackRangeRingFrame

local moveCloserCue = Instance.new("BillboardGui")
moveCloserCue.Name = "DeepDigMoveCloserCue"
moveCloserCue.Enabled = false
moveCloserCue.AlwaysOnTop = true
moveCloserCue.Size = UDim2.fromOffset(120, 32)
moveCloserCue.StudsOffset = Vector3.new(0, 3.2, 0)
moveCloserCue.MaxDistance = 120
moveCloserCue.Parent = playerGui

local moveCloserLabel = Instance.new("TextLabel")
moveCloserLabel.Name = "Label"
moveCloserLabel.BackgroundTransparency = 1
moveCloserLabel.Size = UDim2.fromScale(1, 1)
moveCloserLabel.Font = Enum.Font.GothamBold
moveCloserLabel.Text = "Move closer"
moveCloserLabel.TextColor3 = Color3.fromRGB(255, 210, 190)
moveCloserLabel.TextStrokeColor3 = Color3.fromRGB(45, 25, 20)
moveCloserLabel.TextStrokeTransparency = 0.25
moveCloserLabel.TextScaled = true
moveCloserLabel.Parent = moveCloserCue

local function debugLog(...)
	if DEBUG_DIG_CLIENT then
		print(...)
	end
end

local function clearMoveCloserCue()
	moveCloserCue.Enabled = false
	moveCloserCue.Adornee = nil
	moveCloserCue.Size = UDim2.fromOffset(120, 32)
	moveCloserCue.StudsOffset = Vector3.new(0, 3.2, 0)
	moveCloserLabel.Text = "Move closer"
	moveCloserLabel.TextColor3 = Color3.fromRGB(255, 210, 190)
	moveCloserLabel.TextStrokeColor3 = Color3.fromRGB(45, 25, 20)
end

local function clearAttackRangeRing()
	attackRangeRingGui.Enabled = false
end

local function clearTargetHighlight()
	targetHighlight.Enabled = false
	targetHighlight.Adornee = nil
	clearMoveCloserCue()
	clearAttackRangeRing()
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

local function clearHapticBump(sequence)
	if sequence and sequence ~= hapticSequence then
		return
	end

	setHapticMotor(HAPTIC_SMALL_MOTOR, 0)
	setHapticMotor(HAPTIC_LARGE_MOTOR, 0)
end

local function playHapticBump(smallStrength, largeStrength, duration)
	hapticSequence = hapticSequence + 1
	local sequence = hapticSequence

	setHapticMotor(HAPTIC_SMALL_MOTOR, smallStrength)
	setHapticMotor(HAPTIC_LARGE_MOTOR, largeStrength)

	task.delay(duration, function()
		clearHapticBump(sequence)
	end)
end

local function removeLastBlockBreakKick(camera)
	if camera and lastBlockBreakKickActive then
		camera.CFrame = camera.CFrame * lastBlockBreakKickCFrame:Inverse()
	end

	lastBlockBreakKickCFrame = CFrame.new()
	lastBlockBreakKickActive = false
end

local function clearBlockBreakKick(sequence)
	if sequence and sequence ~= blockBreakKickSequence then
		return
	end

	removeLastBlockBreakKick(workspace.CurrentCamera)
	blockBreakKickState = nil

	if blockBreakKickBound then
		RunService:UnbindFromRenderStep(BLOCK_BREAK_KICK_BIND_NAME)
		blockBreakKickBound = false
	end
end

local function ensureBlockBreakKickBinding()
	if blockBreakKickBound then
		return
	end

	blockBreakKickBound = true
	RunService:BindToRenderStep(BLOCK_BREAK_KICK_BIND_NAME, Enum.RenderPriority.Camera.Value + 2, function()
		local camera = workspace.CurrentCamera
		local state = blockBreakKickState
		if not camera or not state then
			clearBlockBreakKick()
			return
		end

		removeLastBlockBreakKick(camera)

		local progress = (os.clock() - state.startTime) / BLOCK_BREAK_KICK_DURATION
		if progress >= 1 then
			clearBlockBreakKick(state.sequence)
			return
		end

		local falloff = 1 - math.clamp(progress, 0, 1)
		local snap = math.sin(progress * math.pi)
		lastBlockBreakKickCFrame = CFrame.new(
			state.direction * BLOCK_BREAK_KICK_POSITION * falloff,
			BLOCK_BREAK_KICK_POSITION * 0.24 * snap * falloff,
			0
		) * CFrame.Angles(0, 0, math.rad(state.direction * BLOCK_BREAK_KICK_ROTATION * falloff))
		lastBlockBreakKickActive = true
		camera.CFrame = camera.CFrame * lastBlockBreakKickCFrame
	end)
end

local function playBlockBreakFeedback()
	blockBreakKickSequence = blockBreakKickSequence + 1
	local direction = 1
	if math.random() < 0.5 then
		direction = -1
	end

	removeLastBlockBreakKick(workspace.CurrentCamera)
	blockBreakKickState = {
		sequence = blockBreakKickSequence,
		startTime = os.clock(),
		direction = direction,
	}

	ensureBlockBreakKickBinding()
	playHapticBump(0.04, 0.055, 0.06)
end

local function getModelRoot(model)
	if not model then
		return nil
	end

	if model.PrimaryPart then
		return model.PrimaryPart
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	root = model:FindFirstChild("RootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	root = model:FindFirstChild("UpperTorso")
	if root and root:IsA("BasePart") then
		return root
	end

	root = model:FindFirstChild("Torso")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function getPlayerRoot()
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function isEnemyInClientAttackRange(enemyModel)
	local playerRoot = getPlayerRoot()
	local enemyRoot = getModelRoot(enemyModel)
	if not playerRoot or not enemyRoot then
		return true, enemyRoot
	end

	return (playerRoot.Position - enemyRoot.Position).Magnitude <= CLIENT_ATTACK_RANGE, enemyRoot
end

local function showAttackRangeRing(enemyModel, enemyRoot)
	if not enemyModel or not enemyRoot then
		clearAttackRangeRing()
		return
	end

	local modelCFrame, modelSize = enemyModel:GetBoundingBox()
	local baseY = modelCFrame.Position.Y - (modelSize.Y * 0.5) + 0.08
	local ringDiameter = CLIENT_ATTACK_RANGE * 2

	attackRangeRingPart.Size = Vector3.new(ringDiameter, 0.05, ringDiameter)
	attackRangeRingPart.CFrame = CFrame.new(enemyRoot.Position.X, baseY, enemyRoot.Position.Z)
	attackRangeRingGui.Enabled = true
end

local function showMoveCloserCue(enemyModel)
	local enemyRoot = getModelRoot(enemyModel)
	if not enemyRoot then
		clearMoveCloserCue()
		return
	end

	moveCloserCue.Adornee = enemyRoot
	moveCloserLabel.Text = "Move closer"
	moveCloserLabel.TextColor3 = Color3.fromRGB(255, 210, 190)
	moveCloserLabel.TextStrokeColor3 = Color3.fromRGB(45, 25, 20)
	moveCloserCue.Enabled = true
end

local function nudgeMoveCloserCue(enemyModel)
	showMoveCloserCue(enemyModel)
	if not moveCloserCue.Enabled then
		return
	end

	moveCloserCueToken = moveCloserCueToken + 1
	local cueToken = moveCloserCueToken
	moveCloserCue.Size = UDim2.fromOffset(132, 36)
	moveCloserCue.StudsOffset = Vector3.new(0, 3.55, 0)

	local settleTween = TweenService:Create(moveCloserCue, TweenInfo.new(
		0.14,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	), {
		Size = UDim2.fromOffset(120, 32),
		StudsOffset = Vector3.new(0, 3.2, 0),
	})
	settleTween:Play()
	settleTween.Completed:Connect(function()
		if cueToken ~= moveCloserCueToken then
			return
		end

		moveCloserCue.Size = UDim2.fromOffset(120, 32)
		moveCloserCue.StudsOffset = Vector3.new(0, 3.2, 0)
	end)
end

local function showRecoveryCue(enemyModel)
	local enemyRoot = getModelRoot(enemyModel)
	if not enemyRoot then
		clearMoveCloserCue()
		return
	end

	moveCloserCue.Adornee = enemyRoot
	moveCloserLabel.Text = "Recovering"
	moveCloserLabel.TextColor3 = Color3.fromRGB(255, 242, 150)
	moveCloserLabel.TextStrokeColor3 = Color3.fromRGB(62, 42, 8)
	moveCloserCue.Enabled = true
end

local function nudgeRecoveryCue(enemyModel)
	combatState.recoveryCueUntil = os.clock() + 0.35
	showRecoveryCue(enemyModel)
	if not moveCloserCue.Enabled then
		return
	end

	moveCloserCueToken = moveCloserCueToken + 1
	local cueToken = moveCloserCueToken
	moveCloserCue.Size = UDim2.fromOffset(136, 36)
	moveCloserCue.StudsOffset = Vector3.new(0, 3.55, 0)

	local settleTween = TweenService:Create(moveCloserCue, TweenInfo.new(
		0.16,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	), {
		Size = UDim2.fromOffset(120, 32),
		StudsOffset = Vector3.new(0, 3.2, 0),
	})
	settleTween:Play()
	settleTween.Completed:Connect(function()
		if cueToken ~= moveCloserCueToken then
			return
		end

		moveCloserCue.Size = UDim2.fromOffset(120, 32)
		moveCloserCue.StudsOffset = Vector3.new(0, 3.2, 0)
	end)

	task.delay(0.35, function()
		if cueToken ~= moveCloserCueToken or moveCloserLabel.Text ~= "Recovering" then
			return
		end

		combatState.recoveryCueUntil = 0
		clearMoveCloserCue()
	end)
end

local function getClickWorldPosition(targetPart)
	local hit = mouse.Hit
	if hit then
		return hit.Position
	end

	return targetPart.Position
end

local function showImpactPulse(targetPart, color, isSlash)
	if not targetPart or not targetPart:IsA("BasePart") then
		return
	end

	local pulse = Instance.new("BillboardGui")
	pulse.Name = "DeepDigImpactPulse"
	pulse.AlwaysOnTop = true
	pulse.LightInfluence = 0
	pulse.MaxDistance = 120
	pulse.Size = UDim2.fromOffset(18, 18)
	pulse.Adornee = targetPart
	pulse.StudsOffsetWorldSpace = getClickWorldPosition(targetPart) - targetPart.Position
	pulse.Parent = playerGui

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundColor3 = color
	ring.BackgroundTransparency = 0.82
	ring.BorderSizePixel = 0
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1, 1)
	ring.Parent = pulse

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Transparency = 0.08
	stroke.Parent = ring

	local slash = nil
	if isSlash then
		slash = Instance.new("TextLabel")
		slash.Name = "Slash"
		slash.BackgroundTransparency = 1
		slash.Font = Enum.Font.GothamBlack
		slash.Text = "/"
		slash.TextColor3 = color
		slash.TextScaled = true
		slash.TextStrokeColor3 = Color3.fromRGB(45, 10, 10)
		slash.TextStrokeTransparency = 0.35
		slash.Rotation = -12
		slash.Size = UDim2.fromScale(1, 1)
		slash.Parent = pulse
	end

	local growTween = TweenService:Create(pulse, TweenInfo.new(
		IMPACT_LIFETIME,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		Size = UDim2.fromOffset(42, 42),
	})
	local fadeTween = TweenService:Create(ring, TweenInfo.new(
		IMPACT_LIFETIME,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		BackgroundTransparency = 1,
	})
	local strokeTween = TweenService:Create(stroke, TweenInfo.new(
		IMPACT_LIFETIME,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		Transparency = 1,
		Thickness = 0,
	})

	growTween:Play()
	fadeTween:Play()
	strokeTween:Play()
	if slash then
		TweenService:Create(slash, TweenInfo.new(
			IMPACT_LIFETIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	end

	growTween.Completed:Connect(function()
		if pulse then
			pulse:Destroy()
		end
	end)
	task.delay(IMPACT_LIFETIME + 0.1, function()
		if pulse and pulse.Parent then
			pulse:Destroy()
		end
	end)
end

local function showEnemySparkBurst(enemyRoot)
	if not enemyRoot or not enemyRoot:IsA("BasePart") then
		return
	end

	local origin = getClickWorldPosition(enemyRoot)
	for index = 1, 6 do
		local shard = Instance.new("Part")
		shard.Name = "DeepDigEnemyHitSpark"
		shard.Anchored = true
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CanTouch = false
		shard.Material = Enum.Material.Neon
		shard.Color = index % 2 == 0 and Color3.fromRGB(255, 196, 74) or Color3.fromRGB(255, 76, 58)
		shard.Size = Vector3.new(0.08, 0.08, 0.34)
		shard.CFrame = CFrame.new(origin) * CFrame.Angles(
			math.rad(math.random(-35, 35)),
			math.rad(math.random(0, 360)),
			math.rad(math.random(-35, 35))
		)
		shard.Parent = workspace

		local drift = Vector3.new(
			math.random(-100, 100) / 100,
			math.random(20, 95) / 100,
			math.random(-100, 100) / 100
		).Unit * (math.random(5, 10) / 10)
		local targetCFrame = shard.CFrame + drift
		local shardTween = TweenService:Create(shard, TweenInfo.new(
			ENEMY_SPARK_LIFETIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		), {
			CFrame = targetCFrame,
			Transparency = 1,
			Size = Vector3.new(0.03, 0.03, 0.18),
		})
		shardTween:Play()
		Debris:AddItem(shard, ENEMY_SPARK_LIFETIME + 0.08)
	end
end

local function classifyTarget(target)
	if not target or not DigRequest or not EnemyHitEvent then
		return nil
	end

	local enemiesFolder = workspace:FindFirstChild("Enemies")
	local enemyModel = target:FindFirstAncestorOfClass("Model")
	if enemiesFolder and enemyModel and enemyModel:IsDescendantOf(enemiesFolder) then
		return TARGET_ENEMY, enemyModel
	end

	if not target:GetAttribute("Depth") then
		return nil
	end

	local digSite = workspace:FindFirstChild("DigSite")
	if not digSite or not target:IsDescendantOf(digSite) then
		return nil
	end

	return TARGET_DIG_BLOCK, target
end

local function updateTargetHighlight()
	if not equippedExcavator or not equippedExcavator.Parent then
		clearTargetHighlight()
		return
	end

	local targetType, targetInstance = classifyTarget(mouse.Target)
	if targetType == TARGET_ENEMY then
		local isInRange, enemyRoot = isEnemyInClientAttackRange(targetInstance)
		targetHighlight.Adornee = targetInstance
		if isInRange then
			clearAttackRangeRing()
			if os.clock() < combatState.recoveryCueUntil then
				targetHighlight.FillColor = Color3.fromRGB(255, 172, 70)
				targetHighlight.OutlineColor = Color3.fromRGB(255, 222, 110)
				targetHighlight.FillTransparency = 0.82
				targetHighlight.OutlineTransparency = 0.08
				showRecoveryCue(targetInstance)
			else
				targetHighlight.FillColor = Color3.fromRGB(255, 65, 65)
				targetHighlight.OutlineColor = Color3.fromRGB(255, 35, 35)
				targetHighlight.FillTransparency = 0.86
				targetHighlight.OutlineTransparency = 0.12
				clearMoveCloserCue()
			end
		else
			targetHighlight.FillColor = Color3.fromRGB(120, 78, 78)
			targetHighlight.OutlineColor = Color3.fromRGB(150, 110, 110)
			targetHighlight.FillTransparency = 0.92
			targetHighlight.OutlineTransparency = 0.35
			showMoveCloserCue(targetInstance)
			showAttackRangeRing(targetInstance, enemyRoot)
		end
		targetHighlight.Enabled = true
	elseif targetType == TARGET_DIG_BLOCK then
		targetHighlight.Adornee = targetInstance
		targetHighlight.FillColor = Color3.fromRGB(255, 190, 70)
		targetHighlight.OutlineColor = Color3.fromRGB(255, 170, 35)
		targetHighlight.FillTransparency = 0.86
		targetHighlight.OutlineTransparency = 0.12
		targetHighlight.Enabled = true
		clearMoveCloserCue()
		clearAttackRangeRing()
	else
		clearTargetHighlight()
	end
end

-- When the Excavator tool is activated (clicked), check what we're pointing at
local function onToolActivated()
	local target = mouse.Target
	if not target then
		debugLog("[DeepDig dig] click ignored: no mouse target (clicked sky/void?)")
		return
	end

	local targetType, targetInstance = classifyTarget(target)
	if targetType == TARGET_ENEMY then
		local isInRange = isEnemyInClientAttackRange(targetInstance)
		if not isInRange then
			debugLog("[DeepDig dig] enemy hit ignored: move closer:", targetInstance.Name)
			nudgeMoveCloserCue(targetInstance)
			return
		end

		local now = os.clock()
		if now < combatState.nextAttackAt then
			debugLog("[DeepDig dig] enemy hit ignored: recovering:", targetInstance.Name)
			nudgeRecoveryCue(targetInstance)
			return
		end

		debugLog("[DeepDig dig] enemy hit:", targetInstance.Name)
		local _, enemyRoot = isEnemyInClientAttackRange(targetInstance)
		combatState.nextAttackAt = now + combatState.attackCooldown
		showImpactPulse(enemyRoot, Color3.fromRGB(255, 70, 70), true)
		showEnemySparkBurst(enemyRoot)
		EnemyHitEvent:FireServer(targetInstance)
		return
	end

	if targetType ~= TARGET_DIG_BLOCK then
		debugLog("[DeepDig dig] click ignored: invalid target:", target:GetFullName())
		return
	end

	-- Send the block reference to the server
	debugLog(("[DeepDig dig] firing DigRequest for %s (depth=%s)"):format(targetInstance.Name, tostring(targetInstance:GetAttribute("Depth"))))
	showImpactPulse(targetInstance, Color3.fromRGB(255, 185, 65), false)
	DigRequest:FireServer(targetInstance)
end

-- Watch for the Excavator tool being equipped
local hookedExcavators = {}
local function watchTool(tool)
	if tool:IsA("Tool") and tool.Name == "Excavator" and not hookedExcavators[tool] then
		hookedExcavators[tool] = true
		tool.Activated:Connect(onToolActivated)
		tool.Equipped:Connect(function()
			equippedExcavator = tool
			updateTargetHighlight()
		end)
		tool.Unequipped:Connect(function()
			if equippedExcavator == tool then
				equippedExcavator = nil
			end
			clearTargetHighlight()
		end)
		tool.AncestryChanged:Connect(function()
			if equippedExcavator == tool and not tool.Parent then
				equippedExcavator = nil
				clearTargetHighlight()
			end
		end)
		if tool.Parent == character then
			equippedExcavator = tool
			updateTargetHighlight()
		end
		debugLog("[DeepDig dig] Excavator detected and Activated bound:", tool:GetFullName())
	end
end

-- Watch current and future tools
for _, child in ipairs(player.Backpack:GetChildren()) do
	watchTool(child)
end
player.Backpack.ChildAdded:Connect(watchTool)

-- Also watch character (tool moves there when equipped)
character.ChildAdded:Connect(watchTool)
for _, child in ipairs(character:GetChildren()) do
	watchTool(child)
end

-- Handle respawn
player.CharacterAdded:Connect(function(newChar)
	character = newChar
	equippedExcavator = nil
	clearTargetHighlight()
	newChar.ChildAdded:Connect(watchTool)
end)

RunService.RenderStepped:Connect(updateTargetHighlight)

if BlockBreakFeedback then
	BlockBreakFeedback.OnClientEvent:Connect(playBlockBreakFeedback)
else
	warn("[DeepDig dig] block break feedback disabled: BlockBreakFeedback remote missing")
end

if not DigRequest or not EnemyHitEvent then
	warn("[DeepDig dig] targeting disabled: DigRequest or EnemyHitEvent remote missing")
	clearTargetHighlight()
end

print("[DeepDig] DigClient loaded")
