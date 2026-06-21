-- EnemyHealthBar.client.lua - floating enemy names and HP bars
-- Place in: StarterGui/EnemyHealthBar (LocalScript)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
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
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EnemyCombatFeedback = Remotes:WaitForChild("EnemyCombatFeedback")
local LOCAL_PLAY_SOUND_NAME = "DeepDigLocalPlaySound"

local HEALTH_BAR_NAME = "DeepDigEnemyHealthBar"
local DAMAGE_NUMBER_NAME = "DeepDigEnemyDamageNumber"
local REWARD_BURST_NAME = "DeepDigEnemyRewardBurst"
local ENEMY_SPAWN_CUE_NAME = "DeepDigEnemySpawnCue"
local AGGRO_WARNING_NAME = "DeepDigEnemyAggroWarning"
local ATTACK_WARNING_NAME = "DeepDigEnemyAttackWarning"
local ATTACK_WARNING_RING_NAME = "DeepDigEnemyAttackWarningRing"
local MINIBOSS_WARNING_NAME = "DeepDigEnemyMinibossWarning"
local MINIBOSS_ENRAGE_WARNING_NAME = "DeepDigEnemyMinibossEnrageWarning"
local BOSS_BAR_GUI_NAME = "DeepDigMinibossBossBar"
local MINIBOSS_DEFEAT_GUI_NAME = "DeepDigMinibossDefeatClear"
local ENEMY_THREAT_GUI_NAME = "DeepDigEnemyThreatIndicator"
local MAX_DISTANCE = 80
local BAR_WIDTH = 120
local BAR_HEIGHT = 36
local HIT_COLOR = Color3.fromRGB(255, 245, 160)
local COIN_REWARD_COLOR = Color3.fromRGB(255, 214, 92)
local FRAGMENT_REWARD_COLOR = Color3.fromRGB(124, 230, 255)
local STREAK_REWARD_COLOR = Color3.fromRGB(255, 145, 85)
local ENEMY_SPAWN_COLOR = Color3.fromRGB(198, 132, 62)
local DEFEAT_COLOR = Color3.fromRGB(255, 95, 70)
local MINIBOSS_DEFEAT_COLOR = Color3.fromRGB(255, 214, 92)
local MINIBOSS_VOID_COLOR = Color3.fromRGB(98, 38, 145)
local AGGRO_COLOR = Color3.fromRGB(255, 175, 45)
local ATTACK_WARNING_COLOR = Color3.fromRGB(255, 70, 45)
local MINIBOSS_COLOR = Color3.fromRGB(210, 85, 255)
local ENRAGE_COLOR = Color3.fromRGB(255, 70, 45)
local HIT_SCALE = 1.08
local DAMAGE_NUMBER_DURATION = 0.42
local REWARD_BURST_DURATION = 1.05
local MINIBOSS_REWARD_BURST_DURATION = 1.35
local ENEMY_SPAWN_SCALE = 1.06
local DEFEAT_SCALE = 1.16
local AGGRO_SCALE = 1.12
local ATTACK_WARNING_SCALE = 1.12
local MINIBOSS_SCALE = 1.32
local ENRAGE_SCALE = 1.22
local ENEMY_SPAWN_CUE_DURATION = 0.52
local ENEMY_EMERGENCE_CUE_MAX_DURATION = 1.65
local AGGRO_WARNING_DURATION = 0.58
local ATTACK_WARNING_DURATION = 0.38
local ATTACK_WARNING_RING_START_DIAMETER = 4.2
local ATTACK_WARNING_RING_END_DIAMETER = 7.4
local ATTACK_WARNING_RING_THICKNESS = 0.08
local ATTACK_WARNING_RING_SEGMENTS = 18
local ATTACK_WARNING_RING_SEGMENT_WIDTH = 0.16
local MINIBOSS_WARNING_DURATION = 1.05
local MINIBOSS_ENRAGE_WARNING_DURATION = 0.82
local BOSS_BAR_ENRAGE_PULSE_DURATION = 0.42
local BOSS_BAR_DEFEAT_PULSE_DURATION = 0.68
local MINIBOSS_DEFEAT_DURATION = 1.35
local PLAYER_HIT_DISPLAY_ORDER = 80
local PLAYER_HIT_FLASH_TRANSPARENCY = 0.48
local PLAYER_HIT_FLASH_FADE = 0.2
local PLAYER_HIT_READOUT_NAME = "PlayerDamageReadout"
local PLAYER_HIT_READOUT_DURATION = 0.5
local PLAYER_HIT_JOLT_BIND_NAME = "DeepDigPlayerHitCameraJolt"
local PLAYER_HIT_JOLT_DURATION = 0.14
local PLAYER_HIT_JOLT_POSITION = 0.32
local PLAYER_HIT_JOLT_ROTATION = 0.75
local LOW_HEALTH_WARNING_GUI_NAME = "DeepDigLowHealthWarning"
local LOW_HEALTH_THRESHOLD = 0.35
local LOW_HEALTH_DISPLAY_ORDER = PLAYER_HIT_DISPLAY_ORDER - 1
local LOW_HEALTH_EDGE_THICKNESS = 124
local LOW_HEALTH_PULSE_IN_TRANSPARENCY = 0.4
local LOW_HEALTH_PULSE_OUT_TRANSPARENCY = 0.72
local LOW_HEALTH_CLEAR_TRANSPARENCY = 1
local LOW_HEALTH_PULSE_DURATION = 0.42
local LOW_HEALTH_SOUND_INTERVAL = LOW_HEALTH_PULSE_DURATION * 2
local LOW_HEALTH_CLEAR_DURATION = 0.12
local BOSS_BAR_DISPLAY_ORDER = 70
local MINIBOSS_DEFEAT_DISPLAY_ORDER = 95
local ENEMY_THREAT_DISPLAY_ORDER = 64
local BOSS_BAR_WIDTH = 380
local BOSS_BAR_HEIGHT = 52
local ENEMY_THREAT_WIDTH = 112
local ENEMY_THREAT_HEIGHT = 34
local ENEMY_THREAT_EDGE_PADDING = 38
local HAPTIC_INPUT_TYPE = Enum.UserInputType.Gamepad1
local HAPTIC_SMALL_MOTOR = Enum.VibrationMotor.Small
local HAPTIC_LARGE_MOTOR = Enum.VibrationMotor.Large

local trackedEnemies = {}
local trackedEnemyOrder = {}
local activeFeedback = {}
activeFeedback.enemyThreatState = {
	stroke = nil,
	urgentActive = false,
	lastWarningAt = 0,
	urgentDistance = 28,
	warningCooldown = 2.6,
	urgentPulseSpeed = 8,
}
local bossBarGui = nil
local bossBarFrame = nil
local bossBarFill = nil
local bossBarStroke = nil
local bossBarNameLabel = nil
local bossBarPercentLabel = nil
local activeBossModel = nil
local bossBarPulseSequence = 0
local minibossDefeatGui = nil
local minibossDefeatSequence = 0
local playerHitGui = nil
local playerHitOverlay = nil
local playerHitFlashTween = nil
local playerHitFlashSequence = 0
local playerHitReadoutSequence = 0
local playerHitJoltSequence = 0
local playerHitJoltState = nil
local playerHitJoltBound = false
local lastPlayerHitJoltCFrame = CFrame.new()
local lastPlayerHitJoltActive = false
local lowHealthGui = nil
local lowHealthEdges = {}
local lowHealthPulseTweens = {}
local lowHealthPulseSequence = 0
local lowHealthSoundSequence = 0
local lowHealthActive = false
local lowHealthCurrentHumanoid = nil
local lowHealthHumanoidConnection = nil
local lowHealthDiedConnection = nil
local enemyThreatGui = nil
local enemyThreatFrame = nil
local enemyThreatArrow = nil
local enemyThreatDistanceLabel = nil
local activeAttackWarningRing = nil
local CombatStreak = {
	guiName = "DeepDigCombatStreakMeter",
	displayOrder = 72,
	width = 218,
	height = 56,
	fadeDuration = 0.24,
	pulseDuration = 0.22,
	gui = nil,
	frame = nil,
	stroke = nil,
	titleLabel = nil,
	titleStroke = nil,
	bonusLabel = nil,
	bonusStroke = nil,
	fillBack = nil,
	fill = nil,
	scale = nil,
	fadeTweens = {},
	visible = false,
	sequence = 0,
	expiresAt = 0,
	window = 1,
	firstEnemyHintGuiName = "DeepDigFirstEnemyCombatHint",
	firstEnemyHintSeenAttribute = "DeepDigFirstEnemyCombatHintSeen",
	firstEnemyHintDisplayOrder = 74,
	firstEnemyHintDuration = 3.6,
	firstEnemyHintFadeDuration = 0.34,
	firstEnemyHintShown = false,
	firstEnemyHintGui = nil,
	firstEnemyHintSequence = 0,
}
activeFeedback.combatPressure = {
	guiName = "DeepDigCombatPressureChip",
	displayOrder = 66,
	width = 146,
	height = 38,
	cap = 5,
	gui = nil,
	frame = nil,
	stroke = nil,
	countLabel = nil,
	threatLabel = nil,
	wasUrgent = false,
	lastWarningAt = 0,
}
activeFeedback.playerHitDirection = {
	thickness = 132,
	pulseTransparency = 0.18,
	clearTransparency = 1,
	fadeDuration = 0.24,
	edges = {},
	tweens = {},
	sequence = 0,
}
activeFeedback.playerHitImpact = {
	damageBase = 10,
	minIntensity = 0.85,
	maxIntensity = 1.35,
}
activeFeedback.digBlockedDirection = {
	thickness = 86,
	pulseTransparency = 0.34,
	clearTransparency = 1,
	fadeDuration = 0.16,
	centerDeadZoneRatio = 0.18,
	edges = {},
	tweens = {},
	sequence = 0,
}
activeFeedback.minibossSpawnOverlay = {
	guiName = "DeepDigMinibossSpawnOverlay",
	displayOrder = 94,
	edgeThickness = 150,
	duration = 1.18,
	pulseTransparency = 0.18,
	clearTransparency = 1,
	fadeDuration = 0.62,
	gui = nil,
	panel = nil,
	titleLabel = nil,
	nameLabel = nil,
	stroke = nil,
	scale = nil,
	edges = {},
	tweens = {},
	sequence = 0,
}
local hapticSupportChecked = false
local hapticSupported = false
local hapticMotorSupport = {}
local hapticSequence = 0

activeFeedback.enemySpawnRing = {
	records = {},
	name = "DeepDigEnemySpawnRing",
	startDiameter = 3.4,
	endDiameter = 6.8,
	thickness = 0.07,
	segments = 20,
	segmentWidth = 0.18,
	pulseDuration = 0.72,
	fadeDuration = 0.22,
}

local LocalPlaySound = SoundService:FindFirstChild(LOCAL_PLAY_SOUND_NAME)
if not LocalPlaySound then
	LocalPlaySound = Instance.new("BindableEvent")
	LocalPlaySound.Name = LOCAL_PLAY_SOUND_NAME
	LocalPlaySound.Parent = SoundService
end

local function getHealthColor(ratio)
	if ratio > 0.5 then
		local t = (ratio - 0.5) / 0.5
		return Color3.fromRGB(245, 210, 65):Lerp(Color3.fromRGB(70, 220, 95), t)
	end

	local t = ratio / 0.5
	return Color3.fromRGB(220, 55, 45):Lerp(Color3.fromRGB(245, 210, 65), t)
end

local function findHumanoid(model, timeoutSeconds)
	local elapsed = 0
	local step = 0.1
	local timeout = timeoutSeconds or 5

	while elapsed < timeout and model.Parent do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid
		end

		task.wait(step)
		elapsed = elapsed + step
	end

	return nil
end

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		if connection then
			connection:Disconnect()
		end
	end
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

local function ensureEnemyThreatIndicator()
	if enemyThreatFrame and enemyThreatFrame.Parent then
		return
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")

	enemyThreatGui = Instance.new("ScreenGui")
	enemyThreatGui.Name = ENEMY_THREAT_GUI_NAME
	enemyThreatGui.ResetOnSpawn = false
	enemyThreatGui.IgnoreGuiInset = true
	enemyThreatGui.DisplayOrder = ENEMY_THREAT_DISPLAY_ORDER
	enemyThreatGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	enemyThreatGui.Parent = playerGui

	enemyThreatFrame = Instance.new("Frame")
	enemyThreatFrame.Name = "ThreatMarker"
	enemyThreatFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	enemyThreatFrame.Size = UDim2.fromOffset(ENEMY_THREAT_WIDTH, ENEMY_THREAT_HEIGHT)
	enemyThreatFrame.BackgroundColor3 = Color3.fromRGB(34, 20, 18)
	enemyThreatFrame.BackgroundTransparency = 0.08
	enemyThreatFrame.BorderSizePixel = 0
	enemyThreatFrame.Visible = false
	enemyThreatFrame.ZIndex = 1
	enemyThreatFrame.Parent = enemyThreatGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = enemyThreatFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = ATTACK_WARNING_COLOR
	stroke.Transparency = 0.16
	stroke.Thickness = 1
	stroke.Parent = enemyThreatFrame
	activeFeedback.enemyThreatState.stroke = stroke

	enemyThreatArrow = Instance.new("TextLabel")
	enemyThreatArrow.Name = "Direction"
	enemyThreatArrow.Position = UDim2.fromOffset(6, 4)
	enemyThreatArrow.Size = UDim2.fromOffset(26, 26)
	enemyThreatArrow.BackgroundTransparency = 1
	enemyThreatArrow.Text = ">"
	enemyThreatArrow.TextColor3 = ATTACK_WARNING_COLOR
	enemyThreatArrow.TextStrokeTransparency = 0.22
	enemyThreatArrow.TextSize = 25
	enemyThreatArrow.Font = Enum.Font.GothamBlack
	enemyThreatArrow.ZIndex = 2
	enemyThreatArrow.Parent = enemyThreatFrame

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Label"
	nameLabel.Position = UDim2.fromOffset(34, 4)
	nameLabel.Size = UDim2.fromOffset(70, 14)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "ENEMY"
	nameLabel.TextColor3 = Color3.fromRGB(255, 236, 224)
	nameLabel.TextStrokeTransparency = 0.38
	nameLabel.TextSize = 13
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 2
	nameLabel.Parent = enemyThreatFrame

	enemyThreatDistanceLabel = Instance.new("TextLabel")
	enemyThreatDistanceLabel.Name = "Distance"
	enemyThreatDistanceLabel.Position = UDim2.fromOffset(34, 18)
	enemyThreatDistanceLabel.Size = UDim2.fromOffset(70, 12)
	enemyThreatDistanceLabel.BackgroundTransparency = 1
	enemyThreatDistanceLabel.TextColor3 = Color3.fromRGB(255, 190, 158)
	enemyThreatDistanceLabel.TextStrokeTransparency = 0.52
	enemyThreatDistanceLabel.TextSize = 10
	enemyThreatDistanceLabel.Font = Enum.Font.GothamBold
	enemyThreatDistanceLabel.TextXAlignment = Enum.TextXAlignment.Left
	enemyThreatDistanceLabel.TextTruncate = Enum.TextTruncate.AtEnd
	enemyThreatDistanceLabel.ZIndex = 2
	enemyThreatDistanceLabel.Parent = enemyThreatFrame
end

activeFeedback.resetEnemyThreatIndicatorVisuals = function()
	local threatState = activeFeedback.enemyThreatState
	threatState.urgentActive = false

	if enemyThreatFrame then
		enemyThreatFrame.BackgroundColor3 = Color3.fromRGB(34, 20, 18)
		enemyThreatFrame.BackgroundTransparency = 0.08
	end
	if threatState.stroke then
		threatState.stroke.Color = ATTACK_WARNING_COLOR
		threatState.stroke.Transparency = 0.16
		threatState.stroke.Thickness = 1
	end
	if enemyThreatArrow then
		enemyThreatArrow.TextColor3 = ATTACK_WARNING_COLOR
		enemyThreatArrow.TextStrokeTransparency = 0.22
		enemyThreatArrow.TextSize = 25
	end
	if enemyThreatDistanceLabel then
		enemyThreatDistanceLabel.TextColor3 = Color3.fromRGB(255, 190, 158)
		enemyThreatDistanceLabel.TextStrokeTransparency = 0.52
	end
end

local function hideEnemyThreatIndicator()
	if enemyThreatFrame then
		enemyThreatFrame.Visible = false
	end
	activeFeedback.resetEnemyThreatIndicatorVisuals()
end

local function getPlayerReferencePosition(camera)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end

	return camera.CFrame.Position
end

local function getLiveOwnedEnemyRoot(model, record)
	if not record or not model or not model.Parent then
		return nil
	end

	if model:GetAttribute("OwnerUserId") ~= player.UserId then
		return nil
	end

	if model:GetAttribute("IsEmerging") == true then
		return nil
	end

	if not record.humanoid or record.humanoid.Health <= 0 then
		return nil
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end

	return root
end

function activeFeedback.ensureCombatPressureChip()
	local config = activeFeedback.combatPressure
	if config.frame and config.frame.Parent then
		return
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")

	config.gui = Instance.new("ScreenGui")
	config.gui.Name = config.guiName
	config.gui.ResetOnSpawn = false
	config.gui.IgnoreGuiInset = true
	config.gui.DisplayOrder = config.displayOrder
	config.gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	config.gui.Parent = playerGui

	config.frame = Instance.new("Frame")
	config.frame.Name = "PressureChip"
	config.frame.AnchorPoint = Vector2.new(0.5, 0)
	config.frame.Position = UDim2.new(0.5, 0, 0, 118)
	config.frame.Size = UDim2.fromOffset(config.width, config.height)
	config.frame.BackgroundColor3 = Color3.fromRGB(29, 24, 26)
	config.frame.BackgroundTransparency = 0.08
	config.frame.BorderSizePixel = 0
	config.frame.Active = false
	config.frame.Visible = false
	config.frame.ZIndex = 1
	config.frame.Parent = config.gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = config.frame

	config.stroke = Instance.new("UIStroke")
	config.stroke.Color = Color3.fromRGB(255, 178, 84)
	config.stroke.Transparency = 0.3
	config.stroke.Thickness = 1
	config.stroke.Parent = config.frame

	config.countLabel = Instance.new("TextLabel")
	config.countLabel.Name = "Count"
	config.countLabel.Position = UDim2.fromOffset(10, 5)
	config.countLabel.Size = UDim2.new(1, -20, 0, 15)
	config.countLabel.BackgroundTransparency = 1
	config.countLabel.Text = "Enemies 0/5"
	config.countLabel.TextColor3 = Color3.fromRGB(255, 239, 218)
	config.countLabel.TextStrokeTransparency = 0.45
	config.countLabel.TextSize = 13
	config.countLabel.Font = Enum.Font.GothamBlack
	config.countLabel.TextXAlignment = Enum.TextXAlignment.Center
	config.countLabel.TextTruncate = Enum.TextTruncate.AtEnd
	config.countLabel.ZIndex = 2
	config.countLabel.Parent = config.frame

	config.threatLabel = Instance.new("TextLabel")
	config.threatLabel.Name = "Threat"
	config.threatLabel.Position = UDim2.fromOffset(10, 20)
	config.threatLabel.Size = UDim2.new(1, -20, 0, 12)
	config.threatLabel.BackgroundTransparency = 1
	config.threatLabel.Text = "LOW THREAT"
	config.threatLabel.TextColor3 = Color3.fromRGB(255, 192, 128)
	config.threatLabel.TextStrokeTransparency = 0.58
	config.threatLabel.TextSize = 10
	config.threatLabel.Font = Enum.Font.GothamBold
	config.threatLabel.TextXAlignment = Enum.TextXAlignment.Center
	config.threatLabel.TextTruncate = Enum.TextTruncate.AtEnd
	config.threatLabel.ZIndex = 2
	config.threatLabel.Parent = config.frame
end

function activeFeedback.getOwnedEnemyPressure()
	local count = 0
	local hasMiniboss = false

	for _, model in ipairs(trackedEnemyOrder) do
		local record = trackedEnemies[model]
		local root = getLiveOwnedEnemyRoot(model, record)
		if root then
			count = count + 1
			if record.isMiniboss then
				hasMiniboss = true
			end
		end
	end

	return count, hasMiniboss
end

function activeFeedback.getCombatPressureLabel(count, hasMiniboss)
	if hasMiniboss then
		return "MINIBOSS LIVE"
	end
	if count >= 4 then
		return "CAP NEAR"
	end
	if count >= 2 then
		return "RISING THREAT"
	end

	return "LOW THREAT"
end

function activeFeedback.updateCombatPressureChip()
	local count, hasMiniboss = activeFeedback.getOwnedEnemyPressure()
	local config = activeFeedback.combatPressure
	if count <= 0 then
		config.wasUrgent = false
		if config.frame then
			config.frame.Visible = false
		end
		return
	end

	activeFeedback.ensureCombatPressureChip()

	local displayCount = math.min(count, config.cap)
	local isUrgent = count >= 4 or hasMiniboss
	local now = os.clock()
	config.frame.Visible = true
	config.countLabel.Text = string.format("Enemies %d/%d", displayCount, config.cap)
	config.threatLabel.Text = activeFeedback.getCombatPressureLabel(count, hasMiniboss)

	if isUrgent then
		if not config.wasUrgent and now - config.lastWarningAt >= 3.5 then
			config.lastWarningAt = now
			if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
				LocalPlaySound:Fire("enemy_pressure_warning")
			end
		end

		local pulse = (math.sin(now * 7.5) + 1) * 0.5
		config.frame.BackgroundColor3 = Color3.fromRGB(68, 13, 12):Lerp(Color3.fromRGB(116, 64, 14), pulse)
		config.frame.BackgroundTransparency = 0.02
		config.stroke.Color = Color3.fromRGB(255, 74, 48):Lerp(Color3.fromRGB(255, 219, 96), pulse)
		config.stroke.Transparency = 0.04 + (1 - pulse) * 0.12
		config.stroke.Thickness = 2
		config.countLabel.TextColor3 = Color3.fromRGB(255, 238, 188)
		config.countLabel.TextStrokeTransparency = 0.22
		config.threatLabel.TextColor3 = Color3.fromRGB(255, 214, 92)
		config.threatLabel.TextStrokeTransparency = 0.32
	else
		config.frame.BackgroundColor3 = Color3.fromRGB(29, 24, 26)
		config.frame.BackgroundTransparency = 0.08
		config.stroke.Color = Color3.fromRGB(255, 178, 84)
		config.stroke.Transparency = 0.3
		config.stroke.Thickness = 1
		config.countLabel.TextColor3 = Color3.fromRGB(255, 239, 218)
		config.countLabel.TextStrokeTransparency = 0.45
		config.threatLabel.TextColor3 = Color3.fromRGB(255, 192, 128)
		config.threatLabel.TextStrokeTransparency = 0.58
	end

	config.wasUrgent = isUrgent
end

local function isViewportPointVisible(viewportPoint, onScreen, viewportSize)
	return onScreen
		and viewportPoint.Z > 0
		and viewportPoint.X >= 0
		and viewportPoint.X <= viewportSize.X
		and viewportPoint.Y >= 0
		and viewportPoint.Y <= viewportSize.Y
end

local function getOffscreenDirection(camera, rootPosition, viewportPoint, viewportSize)
	local x = viewportPoint.X
	local y = viewportPoint.Y
	if viewportPoint.Z < 0 then
		x = viewportSize.X - x
		y = viewportSize.Y - y
	end

	local center = Vector2.new(viewportSize.X * 0.5, viewportSize.Y * 0.5)
	local direction = Vector2.new(x - center.X, y - center.Y)
	if direction.Magnitude < 1 then
		local cameraSpace = camera.CFrame:PointToObjectSpace(rootPosition)
		direction = Vector2.new(cameraSpace.X, -cameraSpace.Y)
	end
	if direction.Magnitude < 1 then
		direction = Vector2.new(0, -1)
	end

	return direction.Unit
end

local function getDirectionAngle(direction)
	if math.abs(direction.X) < 0.001 then
		if direction.Y >= 0 then
			return 90
		end

		return -90
	end

	local angle = math.deg(math.atan(direction.Y / direction.X))
	if direction.X < 0 then
		angle = angle + 180
	end

	return angle
end

local function getEdgePosition(direction, viewportSize)
	local center = Vector2.new(viewportSize.X * 0.5, viewportSize.Y * 0.5)
	local minX = ENEMY_THREAT_EDGE_PADDING + ENEMY_THREAT_WIDTH * 0.5
	local maxX = viewportSize.X - ENEMY_THREAT_EDGE_PADDING - ENEMY_THREAT_WIDTH * 0.5
	local minY = ENEMY_THREAT_EDGE_PADDING + ENEMY_THREAT_HEIGHT * 0.5
	local maxY = viewportSize.Y - ENEMY_THREAT_EDGE_PADDING - ENEMY_THREAT_HEIGHT * 0.5

	if minX > maxX then
		minX = center.X
		maxX = center.X
	end
	if minY > maxY then
		minY = center.Y
		maxY = center.Y
	end

	local scaleX = math.huge
	if math.abs(direction.X) > 0.001 then
		if direction.X > 0 then
			scaleX = (maxX - center.X) / direction.X
		else
			scaleX = (minX - center.X) / direction.X
		end
	end

	local scaleY = math.huge
	if math.abs(direction.Y) > 0.001 then
		if direction.Y > 0 then
			scaleY = (maxY - center.Y) / direction.Y
		else
			scaleY = (minY - center.Y) / direction.Y
		end
	end

	local scale = math.max(math.min(scaleX, scaleY), 0)
	local position = center + direction * scale
	return Vector2.new(
		math.clamp(position.X, minX, maxX),
		math.clamp(position.Y, minY, maxY)
	)
end

local function updateEnemyThreatIndicator()
	local camera = workspace.CurrentCamera
	if not camera then
		hideEnemyThreatIndicator()
		return
	end

	local viewportSize = camera.ViewportSize
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		hideEnemyThreatIndicator()
		return
	end

	local referencePosition = getPlayerReferencePosition(camera)
	local nearestRoot = nil
	local nearestViewportPoint = nil
	local nearestDistance = math.huge

	for _, model in ipairs(trackedEnemyOrder) do
		local record = trackedEnemies[model]
		local root = getLiveOwnedEnemyRoot(model, record)
		if root then
			local viewportPoint, onScreen = camera:WorldToViewportPoint(root.Position)
			if not isViewportPointVisible(viewportPoint, onScreen, viewportSize) then
				local distance = (root.Position - referencePosition).Magnitude
				if distance < nearestDistance then
					nearestRoot = root
					nearestViewportPoint = viewportPoint
					nearestDistance = distance
				end
			end
		end
	end

	if not nearestRoot then
		hideEnemyThreatIndicator()
		return
	end

	ensureEnemyThreatIndicator()

	local direction = getOffscreenDirection(camera, nearestRoot.Position, nearestViewportPoint, viewportSize)
	local position = getEdgePosition(direction, viewportSize)
	enemyThreatFrame.Position = UDim2.fromOffset(position.X, position.Y)
	enemyThreatFrame.Visible = true
	enemyThreatArrow.Rotation = getDirectionAngle(direction)

	local roundedDistance = math.floor(nearestDistance + 0.5)
	local threatState = activeFeedback.enemyThreatState
	local isUrgent = nearestDistance <= threatState.urgentDistance
	if isUrgent then
		local now = os.clock()
		if not threatState.urgentActive and now - threatState.lastWarningAt >= threatState.warningCooldown then
			threatState.lastWarningAt = now
			if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
				LocalPlaySound:Fire("enemy_proximity_warning")
			end
		end

		threatState.urgentActive = true
		local pulse = (math.sin(now * threatState.urgentPulseSpeed) + 1) * 0.5
		enemyThreatFrame.BackgroundColor3 = Color3.fromRGB(62, 12, 10):Lerp(Color3.fromRGB(124, 20, 14), pulse)
		enemyThreatFrame.BackgroundTransparency = 0.02
		threatState.stroke.Color = Color3.fromRGB(255, 92, 55):Lerp(Color3.fromRGB(255, 222, 116), pulse)
		threatState.stroke.Transparency = 0.02 + (1 - pulse) * 0.1
		threatState.stroke.Thickness = 2
		enemyThreatArrow.TextColor3 = Color3.fromRGB(255, 82, 48):Lerp(Color3.fromRGB(255, 238, 126), pulse)
		enemyThreatArrow.TextStrokeTransparency = 0.08
		enemyThreatDistanceLabel.TextColor3 = Color3.fromRGB(255, 238, 126)
		enemyThreatDistanceLabel.TextStrokeTransparency = 0.28
		enemyThreatDistanceLabel.Text = string.format("CLOSE %d studs", roundedDistance)
	else
		activeFeedback.resetEnemyThreatIndicatorVisuals()
		enemyThreatDistanceLabel.Text = string.format("%d studs", roundedDistance)
	end
end

local function ensureBossBar()
	if bossBarFrame and bossBarFrame.Parent then
		return
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")

	bossBarGui = Instance.new("ScreenGui")
	bossBarGui.Name = BOSS_BAR_GUI_NAME
	bossBarGui.ResetOnSpawn = false
	bossBarGui.IgnoreGuiInset = true
	bossBarGui.DisplayOrder = BOSS_BAR_DISPLAY_ORDER
	bossBarGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	bossBarGui.Parent = playerGui

	bossBarFrame = Instance.new("Frame")
	bossBarFrame.Name = "BossBar"
	bossBarFrame.AnchorPoint = Vector2.new(0.5, 0)
	bossBarFrame.Position = UDim2.new(0.5, 0, 0, 58)
	bossBarFrame.Size = UDim2.fromOffset(BOSS_BAR_WIDTH, BOSS_BAR_HEIGHT)
	bossBarFrame.BackgroundColor3 = Color3.fromRGB(18, 15, 22)
	bossBarFrame.BackgroundTransparency = 0.08
	bossBarFrame.BorderSizePixel = 0
	bossBarFrame.Visible = false
	bossBarFrame.ZIndex = 1
	bossBarFrame.Parent = bossBarGui

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(260, BOSS_BAR_HEIGHT)
	sizeConstraint.MaxSize = Vector2.new(BOSS_BAR_WIDTH, BOSS_BAR_HEIGHT)
	sizeConstraint.Parent = bossBarFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = bossBarFrame

	bossBarStroke = Instance.new("UIStroke")
	bossBarStroke.Color = MINIBOSS_COLOR
	bossBarStroke.Transparency = 0.28
	bossBarStroke.Thickness = 1
	bossBarStroke.Parent = bossBarFrame

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Size = UDim2.new(1, 0, 0, 3)
	accent.BackgroundColor3 = MINIBOSS_COLOR
	accent.BorderSizePixel = 0
	accent.ZIndex = 2
	accent.Parent = bossBarFrame

	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 8)
	accentCorner.Parent = accent

	bossBarNameLabel = Instance.new("TextLabel")
	bossBarNameLabel.Name = "BossName"
	bossBarNameLabel.Position = UDim2.fromOffset(14, 8)
	bossBarNameLabel.Size = UDim2.new(1, -98, 0, 18)
	bossBarNameLabel.BackgroundTransparency = 1
	bossBarNameLabel.TextColor3 = Color3.fromRGB(255, 242, 255)
	bossBarNameLabel.TextStrokeTransparency = 0.55
	bossBarNameLabel.TextSize = 15
	bossBarNameLabel.Font = Enum.Font.GothamBlack
	bossBarNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	bossBarNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	bossBarNameLabel.ZIndex = 2
	bossBarNameLabel.Parent = bossBarFrame

	bossBarPercentLabel = Instance.new("TextLabel")
	bossBarPercentLabel.Name = "BossPercent"
	bossBarPercentLabel.Position = UDim2.new(1, -78, 0, 8)
	bossBarPercentLabel.Size = UDim2.fromOffset(64, 18)
	bossBarPercentLabel.BackgroundTransparency = 1
	bossBarPercentLabel.TextColor3 = Color3.fromRGB(255, 220, 255)
	bossBarPercentLabel.TextStrokeTransparency = 0.55
	bossBarPercentLabel.TextSize = 14
	bossBarPercentLabel.Font = Enum.Font.GothamBold
	bossBarPercentLabel.TextXAlignment = Enum.TextXAlignment.Right
	bossBarPercentLabel.ZIndex = 2
	bossBarPercentLabel.Parent = bossBarFrame

	local back = Instance.new("Frame")
	back.Name = "HealthBack"
	back.Position = UDim2.fromOffset(14, 31)
	back.Size = UDim2.new(1, -28, 0, 11)
	back.BackgroundColor3 = Color3.fromRGB(35, 28, 42)
	back.BackgroundTransparency = 0.08
	back.BorderSizePixel = 0
	back.ZIndex = 2
	back.Parent = bossBarFrame

	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 5)
	backCorner.Parent = back

	bossBarFill = Instance.new("Frame")
	bossBarFill.Name = "HealthFill"
	bossBarFill.Size = UDim2.fromScale(1, 1)
	bossBarFill.BackgroundColor3 = MINIBOSS_COLOR
	bossBarFill.BorderSizePixel = 0
	bossBarFill.ZIndex = 3
	bossBarFill.Parent = back

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = bossBarFill
end

local function getBossMaxHealth(model, humanoid)
	local attributeMaxHealth = model:GetAttribute("MaxHealth")
	if typeof(attributeMaxHealth) == "number" and attributeMaxHealth > 0 then
		return attributeMaxHealth
	end

	return math.max(humanoid.MaxHealth, 1)
end

local function getFirstLiveMiniboss()
	for _, model in ipairs(trackedEnemyOrder) do
		local record = trackedEnemies[model]
		if record and record.isMiniboss and model.Parent and record.humanoid and record.humanoid.Health > 0 then
			return model, record
		end
	end

	return nil, nil
end

local function updateBossBar()
	local model, record = getFirstLiveMiniboss()
	if not model or not record then
		activeBossModel = nil
		if bossBarFrame then
			bossBarFrame.Visible = false
		end
		return
	end

	ensureBossBar()

	activeBossModel = model
	local humanoid = record.humanoid
	local maxHealth = getBossMaxHealth(model, humanoid)
	local ratio = math.clamp(humanoid.Health / maxHealth, 0, 1)
	bossBarNameLabel.Text = model:GetAttribute("EnemyName") or model.Name
	bossBarPercentLabel.Text = string.format("%d%%", math.ceil(ratio * 100))
	bossBarFill.Size = UDim2.fromScale(ratio, 1)
	bossBarFill.BackgroundColor3 = getHealthColor(ratio):Lerp(MINIBOSS_COLOR, 0.35)
	bossBarFrame.Visible = true
end

function activeFeedback.enemySpawnRing.getCFrame(model, root)
	local config = activeFeedback.enemySpawnRing
	local modelCFrame, modelSize = model:GetBoundingBox()
	local y = modelCFrame.Position.Y - modelSize.Y * 0.5 + config.thickness * 0.5
	return CFrame.new(root.Position.X, y, root.Position.Z)
end

function activeFeedback.enemySpawnRing.setTransparency(record, transparency)
	for _, part in ipairs(record.parts) do
		if part and part.Parent then
			part.Transparency = transparency
		end
	end
end

function activeFeedback.enemySpawnRing.clear(model)
	local config = activeFeedback.enemySpawnRing
	local record = config.records[model]
	if not record then
		return
	end

	config.records[model] = nil
	if record.connection then
		record.connection:Disconnect()
		record.connection = nil
	end

	if record.folder and record.folder.Parent then
		config.setTransparency(record, 1)
		record.folder:Destroy()
	end
end

function activeFeedback.enemySpawnRing.fade(model)
	local config = activeFeedback.enemySpawnRing
	local record = config.records[model]
	if not record or record.fading then
		return
	end

	config.records[model] = nil
	record.fading = true
	if record.connection then
		record.connection:Disconnect()
		record.connection = nil
	end

	for _, part in ipairs(record.parts) do
		if part and part.Parent then
			TweenService:Create(part, TweenInfo.new(
				config.fadeDuration,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			), {
				Transparency = 1,
			}):Play()
		end
	end

	task.delay(config.fadeDuration + 0.04, function()
		if record.folder and record.folder.Parent then
			record.folder:Destroy()
		end
	end)
end

function activeFeedback.enemySpawnRing.update(record)
	local config = activeFeedback.enemySpawnRing
	local ringCFrame = config.getCFrame(record.model, record.root)
	local elapsed = os.clock() - record.startTime
	local pulse = (elapsed % config.pulseDuration) / config.pulseDuration
	local diameter = config.startDiameter
		+ (config.endDiameter - config.startDiameter) * pulse
	local radius = diameter * 0.5
	local segmentLength = (math.pi * diameter / config.segments) * 0.68
	local transparency = record.baseTransparency + pulse * 0.34
	local lift = math.sin(elapsed * math.pi * 4) * 0.03

	for index, part in ipairs(record.parts) do
		local angle = ((index - 1) / config.segments) * math.pi * 2
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local center = ringCFrame.Position + radial * radius + Vector3.new(0, lift, 0)

		part.Size = Vector3.new(segmentLength, config.thickness, config.segmentWidth)
		part.Transparency = transparency
		part.CFrame = CFrame.fromMatrix(center, tangent, Vector3.new(0, 1, 0), radial)
	end
end

function activeFeedback.enemySpawnRing.show(model, root)
	local config = activeFeedback.enemySpawnRing
	config.clear(model)

	local parent = workspace.CurrentCamera or workspace
	local folder = Instance.new("Folder")
	folder.Name = config.name
	folder.Parent = parent

	local isMiniboss = model:GetAttribute("IsMiniboss") == true
	local color = ENEMY_SPAWN_COLOR
	local baseTransparency = 0.36
	if isMiniboss then
		color = ENEMY_SPAWN_COLOR:Lerp(MINIBOSS_COLOR, 0.55)
		baseTransparency = 0.24
	end

	local parts = {}
	for index = 1, config.segments do
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. index
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.CastShadow = false
		segment.Material = Enum.Material.Neon
		segment.Color = color
		segment.Transparency = 1
		segment.Parent = folder
		table.insert(parts, segment)
	end

	local record = {
		model = model,
		root = root,
		folder = folder,
		parts = parts,
		connection = nil,
		startTime = os.clock(),
		baseTransparency = baseTransparency,
		fading = false,
	}
	config.records[model] = record

	config.update(record)
	record.connection = RunService.Heartbeat:Connect(function()
		if config.records[model] ~= record then
			return
		end
		if not model.Parent or not root.Parent or not folder.Parent then
			config.clear(model)
			return
		end
		if model:GetAttribute("IsEmerging") ~= true then
			config.fade(model)
			return
		end

		config.update(record)
	end)
end

local function getAttackWarningRingCFrame(model, root)
	local modelCFrame, modelSize = model:GetBoundingBox()
	local y = modelCFrame.Position.Y - modelSize.Y * 0.5 + ATTACK_WARNING_RING_THICKNESS * 0.5
	return CFrame.new(root.Position.X, y, root.Position.Z)
end

local function clearAttackWarningRing(model)
	local record = activeAttackWarningRing
	if not record or (model and record.model ~= model) then
		return
	end

	if record.connection then
		record.connection:Disconnect()
	end
	if record.folder and record.folder.Parent then
		for _, part in ipairs(record.parts) do
			if part and part.Parent then
				part.Transparency = 1
			end
		end
		record.folder:Destroy()
	end

	activeAttackWarningRing = nil
end

local function updateAttackWarningRing(record, progress)
	local ringCFrame = getAttackWarningRingCFrame(record.model, record.root)
	local diameter = ATTACK_WARNING_RING_START_DIAMETER
		+ (ATTACK_WARNING_RING_END_DIAMETER - ATTACK_WARNING_RING_START_DIAMETER) * progress
	local radius = diameter * 0.5
	local segmentLength = (math.pi * diameter / ATTACK_WARNING_RING_SEGMENTS) * 0.72
	local transparency = 0.24 + progress * 0.76

	for index, part in ipairs(record.parts) do
		local angle = ((index - 1) / ATTACK_WARNING_RING_SEGMENTS) * math.pi * 2
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local center = ringCFrame.Position + radial * radius

		part.Size = Vector3.new(segmentLength, ATTACK_WARNING_RING_THICKNESS, ATTACK_WARNING_RING_SEGMENT_WIDTH)
		part.Transparency = transparency
		part.CFrame = CFrame.fromMatrix(center, tangent, Vector3.new(0, 1, 0), radial)
	end
end

local function showAttackWarningRing(model, root)
	clearAttackWarningRing()

	local parent = workspace.CurrentCamera or workspace
	local folder = Instance.new("Folder")
	folder.Name = ATTACK_WARNING_RING_NAME
	folder.Parent = parent

	local parts = {}
	for index = 1, ATTACK_WARNING_RING_SEGMENTS do
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. index
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.CastShadow = false
		segment.Material = Enum.Material.Neon
		segment.Color = ATTACK_WARNING_COLOR
		segment.Parent = folder
		table.insert(parts, segment)
	end

	local record = {
		model = model,
		root = root,
		folder = folder,
		parts = parts,
		connection = nil,
		startTime = os.clock(),
	}
	activeAttackWarningRing = record

	updateAttackWarningRing(record, 0)
	record.connection = RunService.Heartbeat:Connect(function()
		if activeAttackWarningRing ~= record then
			return
		end
		if not model.Parent or not root.Parent or not folder.Parent then
			clearAttackWarningRing(model)
			return
		end

		local progress = math.clamp((os.clock() - record.startTime) / ATTACK_WARNING_DURATION, 0, 1)
		updateAttackWarningRing(record, progress)
		if progress >= 1 then
			clearAttackWarningRing(model)
		end
	end)

	task.delay(ATTACK_WARNING_DURATION + 0.08, function()
		if activeAttackWarningRing == record then
			clearAttackWarningRing(model)
		end
	end)
end

local function cleanupEnemy(model)
	local record = trackedEnemies[model]
	if record then
		trackedEnemies[model] = nil
		disconnectAll(record.connections)

		if record.gui and record.gui.Parent then
			record.gui:Destroy()
		end
	end

	for index, trackedModel in ipairs(trackedEnemyOrder) do
		if trackedModel == model then
			table.remove(trackedEnemyOrder, index)
			break
		end
	end

	local root = model and model:FindFirstChild("HumanoidRootPart")
	local enemySpawnCue = root and root:FindFirstChild(ENEMY_SPAWN_CUE_NAME)
	if enemySpawnCue then
		enemySpawnCue:Destroy()
	end
	activeFeedback.enemySpawnRing.clear(model)

	local aggroWarning = root and root:FindFirstChild(AGGRO_WARNING_NAME)
	if aggroWarning then
		aggroWarning:Destroy()
	end

	local attackWarning = root and root:FindFirstChild(ATTACK_WARNING_NAME)
	if attackWarning then
		attackWarning:Destroy()
	end
	clearAttackWarningRing(model)

	local minibossWarning = root and root:FindFirstChild(MINIBOSS_WARNING_NAME)
	if minibossWarning then
		minibossWarning:Destroy()
	end

	local minibossEnrageWarning = root and root:FindFirstChild(MINIBOSS_ENRAGE_WARNING_NAME)
	if minibossEnrageWarning then
		minibossEnrageWarning:Destroy()
	end

	local feedbackRecord = activeFeedback[model]
	if feedbackRecord then
		if feedbackRecord.tween then
			feedbackRecord.tween:Cancel()
		end
		activeFeedback[model] = nil
	end

	if activeBossModel == model or record then
		updateBossBar()
	end
end

local function createHealthBar(model, root)
	local existing = root:FindFirstChild(HEALTH_BAR_NAME)
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = HEALTH_BAR_NAME
	billboard.Adornee = root
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE
	billboard.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.Parent = root

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = model:GetAttribute("EnemyName") or model.Name
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeTransparency = 0.35
	nameLabel.TextSize = 13
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.Parent = billboard

	local back = Instance.new("Frame")
	back.Name = "HealthBack"
	back.Position = UDim2.fromOffset(8, 19)
	back.Size = UDim2.new(1, -16, 0, 10)
	back.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	back.BackgroundTransparency = 0.15
	back.BorderSizePixel = 0
	back.Parent = billboard

	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 4)
	backCorner.Parent = back

	local fill = Instance.new("Frame")
	fill.Name = "HealthFill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(70, 220, 95)
	fill.BorderSizePixel = 0
	fill.Parent = back

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.6
	stroke.Thickness = 1
	stroke.Parent = back

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HealthLabel"
	hpLabel.Size = UDim2.fromScale(1, 1)
	hpLabel.BackgroundTransparency = 1
	hpLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpLabel.TextStrokeTransparency = 0.55
	hpLabel.TextSize = 8
	hpLabel.Font = Enum.Font.GothamBold
	hpLabel.TextXAlignment = Enum.TextXAlignment.Center
	hpLabel.Parent = back

	return billboard, fill, hpLabel
end

local function trackEnemy(model)
	if trackedEnemies[model] or not model:IsA("Model") then
		return
	end

	task.spawn(function()
		if trackedEnemies[model] or not model.Parent then
			return
		end

		local root = model:FindFirstChild("HumanoidRootPart") or model:WaitForChild("HumanoidRootPart", 5)
		local humanoid = findHumanoid(model, 5)
		if not root or not humanoid or not model.Parent then
			return
		end

		local gui, fill, hpLabel = createHealthBar(model, root)
		local record = {
			gui = gui,
			connections = {},
			humanoid = humanoid,
			isMiniboss = model:GetAttribute("IsMiniboss") == true,
		}
		trackedEnemies[model] = record
		table.insert(trackedEnemyOrder, model)

		local function update()
			if not model.Parent or humanoid.Health <= 0 then
				cleanupEnemy(model)
				return
			end

			local maxHealth = math.max(humanoid.MaxHealth, 1)
			local ratio = math.clamp(humanoid.Health / maxHealth, 0, 1)
			fill.Size = UDim2.fromScale(ratio, 1)
			fill.BackgroundColor3 = getHealthColor(ratio)
			hpLabel.Text = string.format("%d/%d", math.ceil(humanoid.Health), math.ceil(maxHealth))
			updateBossBar()
		end

		table.insert(record.connections, humanoid.HealthChanged:Connect(update))
		table.insert(record.connections, model:GetAttributeChangedSignal("EnemyName"):Connect(updateBossBar))
		table.insert(record.connections, model:GetAttributeChangedSignal("MaxHealth"):Connect(updateBossBar))
		table.insert(record.connections, model:GetAttributeChangedSignal("IsMiniboss"):Connect(function()
			record.isMiniboss = model:GetAttribute("IsMiniboss") == true
			updateBossBar()
		end))
		table.insert(record.connections, humanoid.Died:Connect(function()
			cleanupEnemy(model)
		end))
		table.insert(record.connections, model.AncestryChanged:Connect(function(_, parent)
			if not parent then
				cleanupEnemy(model)
			end
		end))

		update()
	end)
end

local function getFeedbackRecord(model, root)
	local record = activeFeedback[model]
	if record and record.root == root then
		return record
	end

	record = {
		root = root,
		baselineColor = root.Color,
		baselineMaterial = root.Material,
		baselineSize = root.Size,
		baselineTransparency = root.Transparency,
		token = 0,
		tween = nil,
	}
	activeFeedback[model] = record
	return record
end

local function restoreFeedback(model, record, token)
	if activeFeedback[model] ~= record or record.token ~= token then
		return
	end

	if record.tween then
		record.tween:Cancel()
		record.tween = nil
	end

	if record.root and record.root.Parent then
		record.root.Color = record.baselineColor
		record.root.Material = record.baselineMaterial
		record.root.Size = record.baselineSize
		record.root.Transparency = record.baselineTransparency
	end

	activeFeedback[model] = nil
end

local function ensurePlayerHitOverlay()
	if playerHitOverlay and playerHitOverlay.Parent then
		return playerHitOverlay
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")

	playerHitGui = Instance.new("ScreenGui")
	playerHitGui.Name = "EnemyPlayerHitFeedback"
	playerHitGui.ResetOnSpawn = false
	playerHitGui.IgnoreGuiInset = true
	playerHitGui.DisplayOrder = PLAYER_HIT_DISPLAY_ORDER
	playerHitGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	playerHitGui.Parent = playerGui

	playerHitOverlay = Instance.new("Frame")
	playerHitOverlay.Name = "DamageFlash"
	playerHitOverlay.Size = UDim2.fromScale(1, 1)
	playerHitOverlay.BackgroundColor3 = Color3.fromRGB(210, 36, 32)
	playerHitOverlay.BackgroundTransparency = 1
	playerHitOverlay.BorderSizePixel = 0
	playerHitOverlay.Visible = false
	playerHitOverlay.ZIndex = 1
	playerHitOverlay.Parent = playerHitGui

	return playerHitOverlay
end

function activeFeedback.createPlayerHitDirectionEdge(name, position, size, rotation)
	local config = activeFeedback.playerHitDirection
	local edge = Instance.new("Frame")
	edge.Name = name
	edge.Position = position
	edge.Size = size
	edge.BackgroundColor3 = Color3.fromRGB(255, 42, 32)
	edge.BackgroundTransparency = config.clearTransparency
	edge.BorderSizePixel = 0
	edge.Visible = false
	edge.ZIndex = 2
	edge.Parent = playerHitGui

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = edge

	return edge
end

function activeFeedback.ensurePlayerHitDirectionEdges()
	ensurePlayerHitOverlay()

	local config = activeFeedback.playerHitDirection
	if config.edges.left and config.edges.left.Parent then
		return config.edges
	end

	config.edges = {
		top = activeFeedback.createPlayerHitDirectionEdge(
			"HitTopEdge",
			UDim2.fromScale(0, 0),
			UDim2.new(1, 0, 0, config.thickness),
			90
		),
		bottom = activeFeedback.createPlayerHitDirectionEdge(
			"HitBottomEdge",
			UDim2.new(0, 0, 1, -config.thickness),
			UDim2.new(1, 0, 0, config.thickness),
			270
		),
		left = activeFeedback.createPlayerHitDirectionEdge(
			"HitLeftEdge",
			UDim2.fromScale(0, 0),
			UDim2.new(0, config.thickness, 1, 0),
			0
		),
		right = activeFeedback.createPlayerHitDirectionEdge(
			"HitRightEdge",
			UDim2.new(1, -config.thickness, 0, 0),
			UDim2.new(0, config.thickness, 1, 0),
			180
		),
	}

	return config.edges
end

function activeFeedback.cancelPlayerHitDirectionTweens()
	local config = activeFeedback.playerHitDirection
	for _, tween in pairs(config.tweens) do
		if tween then
			tween:Cancel()
		end
	end

	config.tweens = {}
end

function activeFeedback.hidePlayerHitDirectionEdges()
	local config = activeFeedback.playerHitDirection
	for _, edge in pairs(config.edges) do
		if edge and edge.Parent then
			edge.BackgroundTransparency = config.clearTransparency
			edge.Visible = false
		end
	end
end

function activeFeedback.getPlayerHitEdgeDirection(enemyPosition)
	if typeof(enemyPosition) ~= "Vector3" then
		return nil
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	local viewportSize = camera.ViewportSize
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return nil
	end

	local ok, viewportPoint = pcall(function()
		return camera:WorldToViewportPoint(enemyPosition)
	end)
	if not ok or typeof(viewportPoint) ~= "Vector3" then
		return nil
	end

	local direction = getOffscreenDirection(camera, enemyPosition, viewportPoint, viewportSize)
	if math.abs(direction.X) >= math.abs(direction.Y) then
		if direction.X >= 0 then
			return "right"
		end

		return "left"
	end

	if direction.Y >= 0 then
		return "bottom"
	end

	return "top"
end

function activeFeedback.playPlayerHitDirectionPulse(enemyPosition)
	local edgeDirection = activeFeedback.getPlayerHitEdgeDirection(enemyPosition)
	if not edgeDirection then
		return
	end

	local config = activeFeedback.playerHitDirection
	local edges = activeFeedback.ensurePlayerHitDirectionEdges()
	local edge = edges[edgeDirection]
	if not edge or not edge.Parent then
		return
	end

	config.sequence = config.sequence + 1
	local sequence = config.sequence
	activeFeedback.cancelPlayerHitDirectionTweens()
	activeFeedback.hidePlayerHitDirectionEdges()

	edge.Visible = true
	edge.BackgroundTransparency = config.pulseTransparency

	local tween = TweenService:Create(edge, TweenInfo.new(
		config.fadeDuration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		BackgroundTransparency = config.clearTransparency,
	})
	config.tweens[edgeDirection] = tween
	tween:Play()
	tween.Completed:Once(function(playbackState)
		if sequence ~= config.sequence or config.tweens[edgeDirection] ~= tween then
			return
		end

		if playbackState == Enum.PlaybackState.Completed then
			edge.Visible = false
		end

		config.tweens[edgeDirection] = nil
	end)
end

function activeFeedback.createDigBlockedDirectionEdge(name, position, size, rotation)
	local config = activeFeedback.digBlockedDirection
	local edge = Instance.new("Frame")
	edge.Name = name
	edge.Position = position
	edge.Size = size
	edge.BackgroundColor3 = AGGRO_COLOR
	edge.BackgroundTransparency = config.clearTransparency
	edge.BorderSizePixel = 0
	edge.Visible = false
	edge.ZIndex = 3
	edge.Parent = playerHitGui

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.08),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = edge

	return edge
end

function activeFeedback.ensureDigBlockedDirectionEdges()
	ensurePlayerHitOverlay()

	local config = activeFeedback.digBlockedDirection
	if config.edges.left and config.edges.left.Parent then
		return config.edges
	end

	config.edges = {
		top = activeFeedback.createDigBlockedDirectionEdge(
			"DigBlockedTopEdge",
			UDim2.fromScale(0, 0),
			UDim2.new(1, 0, 0, config.thickness),
			90
		),
		bottom = activeFeedback.createDigBlockedDirectionEdge(
			"DigBlockedBottomEdge",
			UDim2.new(0, 0, 1, -config.thickness),
			UDim2.new(1, 0, 0, config.thickness),
			270
		),
		left = activeFeedback.createDigBlockedDirectionEdge(
			"DigBlockedLeftEdge",
			UDim2.fromScale(0, 0),
			UDim2.new(0, config.thickness, 1, 0),
			0
		),
		right = activeFeedback.createDigBlockedDirectionEdge(
			"DigBlockedRightEdge",
			UDim2.new(1, -config.thickness, 0, 0),
			UDim2.new(0, config.thickness, 1, 0),
			180
		),
	}

	return config.edges
end

function activeFeedback.cancelDigBlockedDirectionTweens()
	local config = activeFeedback.digBlockedDirection
	for _, tween in pairs(config.tweens) do
		if tween then
			tween:Cancel()
		end
	end

	config.tweens = {}
end

function activeFeedback.hideDigBlockedDirectionEdges()
	local config = activeFeedback.digBlockedDirection
	for _, edge in pairs(config.edges) do
		if edge and edge.Parent then
			edge.BackgroundTransparency = config.clearTransparency
			edge.Visible = false
		end
	end
end

function activeFeedback.getDigBlockedEdgeDirection(model)
	if not model or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return nil
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	local viewportSize = camera.ViewportSize
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return nil
	end

	local ok, viewportPoint = pcall(function()
		return camera:WorldToViewportPoint(root.Position)
	end)
	if not ok or typeof(viewportPoint) ~= "Vector3" then
		return nil
	end

	local direction = getOffscreenDirection(camera, root.Position, viewportPoint, viewportSize)
	local center = Vector2.new(viewportSize.X * 0.5, viewportSize.Y * 0.5)
	local offset = Vector2.new(viewportPoint.X - center.X, viewportPoint.Y - center.Y)
	local deadZone = math.min(viewportSize.X, viewportSize.Y) * activeFeedback.digBlockedDirection.centerDeadZoneRatio
	if viewportPoint.Z > 0 and offset.Magnitude < deadZone then
		return nil
	end

	if math.abs(direction.X) >= math.abs(direction.Y) then
		if direction.X >= 0 then
			return "right"
		end

		return "left"
	end

	if direction.Y >= 0 then
		return "bottom"
	end

	return "top"
end

function activeFeedback.playDigBlockedDirectionPulse(model)
	local edgeDirection = activeFeedback.getDigBlockedEdgeDirection(model)
	if not edgeDirection then
		return
	end

	local config = activeFeedback.digBlockedDirection
	local edges = activeFeedback.ensureDigBlockedDirectionEdges()
	local edge = edges[edgeDirection]
	if not edge or not edge.Parent then
		return
	end

	config.sequence = config.sequence + 1
	local sequence = config.sequence
	activeFeedback.cancelDigBlockedDirectionTweens()
	activeFeedback.hideDigBlockedDirectionEdges()

	edge.Visible = true
	edge.BackgroundTransparency = config.pulseTransparency

	local tween = TweenService:Create(edge, TweenInfo.new(
		config.fadeDuration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		BackgroundTransparency = config.clearTransparency,
	})
	config.tweens[edgeDirection] = tween
	tween:Play()
	tween.Completed:Once(function(playbackState)
		if sequence ~= config.sequence or config.tweens[edgeDirection] ~= tween then
			return
		end

		if playbackState == Enum.PlaybackState.Completed then
			edge.Visible = false
		end

		config.tweens[edgeDirection] = nil
	end)
end

function activeFeedback.createMinibossSpawnOverlayEdge(name, position, size, rotation, color)
	local config = activeFeedback.minibossSpawnOverlay
	local edge = Instance.new("Frame")
	edge.Name = name
	edge.Position = position
	edge.Size = size
	edge.BackgroundColor3 = color
	edge.BackgroundTransparency = config.clearTransparency
	edge.BorderSizePixel = 0
	edge.Visible = false
	edge.ZIndex = 1
	edge.Parent = config.gui

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = edge

	return edge
end

function activeFeedback.ensureMinibossSpawnOverlay()
	local config = activeFeedback.minibossSpawnOverlay
	if config.gui and config.gui.Parent and config.panel and config.panel.Parent then
		return config
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")

	config.gui = Instance.new("ScreenGui")
	config.gui.Name = config.guiName
	config.gui.ResetOnSpawn = false
	config.gui.IgnoreGuiInset = true
	config.gui.DisplayOrder = config.displayOrder
	config.gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	config.gui.Parent = playerGui

	config.edges = {
		top = activeFeedback.createMinibossSpawnOverlayEdge(
			"MinibossTopEdge",
			UDim2.fromScale(0, 0),
			UDim2.new(1, 0, 0, config.edgeThickness),
			90,
			MINIBOSS_VOID_COLOR
		),
		bottom = activeFeedback.createMinibossSpawnOverlayEdge(
			"MinibossBottomEdge",
			UDim2.new(0, 0, 1, -config.edgeThickness),
			UDim2.new(1, 0, 0, config.edgeThickness),
			270,
			ENRAGE_COLOR
		),
		left = activeFeedback.createMinibossSpawnOverlayEdge(
			"MinibossLeftEdge",
			UDim2.fromScale(0, 0),
			UDim2.new(0, config.edgeThickness, 1, 0),
			0,
			MINIBOSS_VOID_COLOR
		),
		right = activeFeedback.createMinibossSpawnOverlayEdge(
			"MinibossRightEdge",
			UDim2.new(1, -config.edgeThickness, 0, 0),
			UDim2.new(0, config.edgeThickness, 1, 0),
			180,
			ENRAGE_COLOR
		),
	}

	config.panel = Instance.new("Frame")
	config.panel.Name = "WarningPanel"
	config.panel.AnchorPoint = Vector2.new(0.5, 0.5)
	config.panel.Position = UDim2.fromScale(0.5, 0.34)
	config.panel.Size = UDim2.fromOffset(320, 72)
	config.panel.BackgroundColor3 = Color3.fromRGB(24, 8, 34)
	config.panel.BackgroundTransparency = 1
	config.panel.BorderSizePixel = 0
	config.panel.Visible = false
	config.panel.ZIndex = 3
	config.panel.Parent = config.gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = config.panel

	config.stroke = Instance.new("UIStroke")
	config.stroke.Color = MINIBOSS_COLOR
	config.stroke.Transparency = 1
	config.stroke.Thickness = 2
	config.stroke.Parent = config.panel

	config.scale = Instance.new("UIScale")
	config.scale.Scale = 0.92
	config.scale.Parent = config.panel

	config.titleLabel = Instance.new("TextLabel")
	config.titleLabel.Name = "Title"
	config.titleLabel.Position = UDim2.fromOffset(12, 11)
	config.titleLabel.Size = UDim2.new(1, -24, 0, 25)
	config.titleLabel.BackgroundTransparency = 1
	config.titleLabel.Text = "HOLLOW KING UNEARTHED"
	config.titleLabel.TextColor3 = MINIBOSS_COLOR
	config.titleLabel.TextStrokeTransparency = 1
	config.titleLabel.TextSize = 20
	config.titleLabel.Font = Enum.Font.GothamBlack
	config.titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	config.titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	config.titleLabel.ZIndex = 4
	config.titleLabel.Parent = config.panel

	config.nameLabel = Instance.new("TextLabel")
	config.nameLabel.Name = "Subtitle"
	config.nameLabel.Position = UDim2.fromOffset(12, 40)
	config.nameLabel.Size = UDim2.new(1, -24, 0, 18)
	config.nameLabel.BackgroundTransparency = 1
	config.nameLabel.Text = "MINIBOSS HAS BREACHED THE DIG SITE"
	config.nameLabel.TextColor3 = Color3.fromRGB(255, 180, 170)
	config.nameLabel.TextStrokeTransparency = 1
	config.nameLabel.TextSize = 11
	config.nameLabel.Font = Enum.Font.GothamBold
	config.nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	config.nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	config.nameLabel.ZIndex = 4
	config.nameLabel.Parent = config.panel

	return config
end

function activeFeedback.cancelMinibossSpawnOverlayTweens()
	local config = activeFeedback.minibossSpawnOverlay
	for _, tween in pairs(config.tweens) do
		if tween then
			tween:Cancel()
		end
	end

	config.tweens = {}
end

function activeFeedback.hideMinibossSpawnOverlay()
	local config = activeFeedback.minibossSpawnOverlay
	for _, edge in pairs(config.edges) do
		if edge and edge.Parent then
			edge.BackgroundTransparency = config.clearTransparency
			edge.Visible = false
		end
	end

	if config.panel and config.panel.Parent then
		config.panel.BackgroundTransparency = 1
		config.panel.Visible = false
	end
	if config.stroke and config.stroke.Parent then
		config.stroke.Transparency = 1
	end
	if config.scale and config.scale.Parent then
		config.scale.Scale = 0.92
	end
	if config.titleLabel and config.titleLabel.Parent then
		config.titleLabel.TextTransparency = 1
		config.titleLabel.TextStrokeTransparency = 1
	end
	if config.nameLabel and config.nameLabel.Parent then
		config.nameLabel.TextTransparency = 1
		config.nameLabel.TextStrokeTransparency = 1
	end
end

function activeFeedback.showMinibossSpawnOverlay(model)
	local config = activeFeedback.ensureMinibossSpawnOverlay()
	config.sequence = config.sequence + 1
	local sequence = config.sequence

	activeFeedback.cancelMinibossSpawnOverlayTweens()
	activeFeedback.hideMinibossSpawnOverlay()

	local enemyName = "Hollow King"
	if model and model:IsA("Model") then
		local attributeName = model:GetAttribute("EnemyName")
		if typeof(attributeName) == "string" and attributeName ~= "" then
			enemyName = attributeName
		end
	end

	config.titleLabel.Text = string.upper(enemyName) .. " UNEARTHED"
	config.nameLabel.Text = "MINIBOSS HAS BREACHED THE DIG SITE"

	for key, edge in pairs(config.edges) do
		if edge and edge.Parent then
			local tweenKey = "edge_" .. key
			edge.Visible = true
			edge.BackgroundTransparency = config.pulseTransparency
			local edgeTween = TweenService:Create(edge, TweenInfo.new(
				config.fadeDuration,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			), {
				BackgroundTransparency = config.clearTransparency,
			})
			config.tweens[tweenKey] = edgeTween
			edgeTween:Play()
			edgeTween.Completed:Once(function(playbackState)
				if sequence ~= config.sequence or config.tweens[tweenKey] ~= edgeTween then
					return
				end

				if playbackState == Enum.PlaybackState.Completed then
					edge.Visible = false
				end

				config.tweens[tweenKey] = nil
			end)
		end
	end

	config.panel.Visible = true
	config.panel.BackgroundTransparency = 0.1
	config.stroke.Transparency = 0.1
	config.scale.Scale = 0.92
	config.titleLabel.TextTransparency = 0
	config.titleLabel.TextStrokeTransparency = 0.14
	config.nameLabel.TextTransparency = 0
	config.nameLabel.TextStrokeTransparency = 0.34

	local scaleTween = TweenService:Create(config.scale, TweenInfo.new(
		0.18,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	), {
		Scale = 1,
	})
	config.tweens.scaleIn = scaleTween
	scaleTween:Play()

	local fadeInfo = TweenInfo.new(
		config.duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	local panelTween = TweenService:Create(config.panel, fadeInfo, {
		BackgroundTransparency = 1,
	})
	local strokeTween = TweenService:Create(config.stroke, fadeInfo, {
		Transparency = 1,
	})
	local titleTween = TweenService:Create(config.titleLabel, fadeInfo, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	local nameTween = TweenService:Create(config.nameLabel, fadeInfo, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	config.tweens.panel = panelTween
	config.tweens.stroke = strokeTween
	config.tweens.title = titleTween
	config.tweens.name = nameTween
	panelTween:Play()
	strokeTween:Play()
	titleTween:Play()
	nameTween:Play()
	panelTween.Completed:Once(function(playbackState)
		if sequence ~= config.sequence or config.tweens.panel ~= panelTween then
			return
		end

		if playbackState == Enum.PlaybackState.Completed then
			config.panel.Visible = false
		end

		config.tweens.panel = nil
		config.tweens.stroke = nil
		config.tweens.title = nil
		config.tweens.name = nil
	end)

	task.delay(config.duration + 0.08, function()
		if sequence == config.sequence then
			activeFeedback.hideMinibossSpawnOverlay()
		end
	end)
end

local function playPlayerHitFlash(intensity)
	local overlay = ensurePlayerHitOverlay()
	playerHitFlashSequence = playerHitFlashSequence + 1
	local sequence = playerHitFlashSequence

	if playerHitFlashTween then
		playerHitFlashTween:Cancel()
		playerHitFlashTween = nil
	end

	overlay.Visible = true
	overlay.BackgroundTransparency = math.clamp(
		PLAYER_HIT_FLASH_TRANSPARENCY - ((intensity or 1) - 1) * 0.22,
		0.34,
		0.56
	)

	local tween = TweenService:Create(overlay, TweenInfo.new(
		PLAYER_HIT_FLASH_FADE,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		BackgroundTransparency = 1,
	})
	playerHitFlashTween = tween
	tween:Play()
	tween.Completed:Connect(function(playbackState)
		if sequence ~= playerHitFlashSequence or playerHitFlashTween ~= tween then
			return
		end

		if playbackState == Enum.PlaybackState.Completed then
			overlay.Visible = false
		end

		playerHitFlashTween = nil
	end)
end

local function showPlayerHitReadout(damage)
	if typeof(damage) ~= "number" or damage <= 0 then
		return
	end

	ensurePlayerHitOverlay()
	playerHitReadoutSequence = playerHitReadoutSequence + 1
	local sequence = playerHitReadoutSequence

	local label = Instance.new("TextLabel")
	label.Name = PLAYER_HIT_READOUT_NAME
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.42)
	label.Size = UDim2.fromOffset(160, 48)
	label.BackgroundTransparency = 1
	label.Text = string.format("-%d", math.floor(damage + 0.5))
	label.TextColor3 = Color3.fromRGB(255, 82, 72)
	label.TextStrokeTransparency = 0.12
	label.TextSize = 36
	label.Font = Enum.Font.GothamBlack
	label.ZIndex = 2
	label.Parent = playerHitGui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 12, 8)
	stroke.Transparency = 0.04
	stroke.Thickness = 2
	stroke.Parent = label

	local moveTween = TweenService:Create(label, TweenInfo.new(
		PLAYER_HIT_READOUT_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		Position = UDim2.fromScale(0.5, 0.36),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	local strokeTween = TweenService:Create(stroke, TweenInfo.new(
		PLAYER_HIT_READOUT_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		Transparency = 1,
	})

	moveTween:Play()
	strokeTween:Play()
	moveTween.Completed:Once(function()
		if sequence == playerHitReadoutSequence and label.Parent then
			label:Destroy()
		end
	end)

	task.delay(PLAYER_HIT_READOUT_DURATION + 0.08, function()
		if label.Parent then
			label:Destroy()
		end
	end)
end

local function removeLastPlayerHitJolt(camera)
	if camera and lastPlayerHitJoltActive then
		camera.CFrame = camera.CFrame * lastPlayerHitJoltCFrame:Inverse()
	end

	lastPlayerHitJoltCFrame = CFrame.new()
	lastPlayerHitJoltActive = false
end

local function clearPlayerHitJolt(sequence)
	if sequence and sequence ~= playerHitJoltSequence then
		return
	end

	removeLastPlayerHitJolt(workspace.CurrentCamera)
	playerHitJoltState = nil

	if playerHitJoltBound then
		RunService:UnbindFromRenderStep(PLAYER_HIT_JOLT_BIND_NAME)
		playerHitJoltBound = false
	end
end

local function ensurePlayerHitJoltBinding()
	if playerHitJoltBound then
		return
	end

	playerHitJoltBound = true
	RunService:BindToRenderStep(PLAYER_HIT_JOLT_BIND_NAME, Enum.RenderPriority.Camera.Value + 3, function()
		local camera = workspace.CurrentCamera
		local state = playerHitJoltState
		if not camera or not state then
			clearPlayerHitJolt()
			return
		end

		removeLastPlayerHitJolt(camera)

		local elapsed = os.clock() - state.startTime
		local progress = elapsed / PLAYER_HIT_JOLT_DURATION
		if progress >= 1 then
			clearPlayerHitJolt(state.sequence)
			return
		end

		local falloff = 1 - math.clamp(progress, 0, 1)
		local snap = math.sin(progress * math.pi)
		local intensity = state.intensity or 1
		local offset = Vector3.new(
			state.direction * PLAYER_HIT_JOLT_POSITION * intensity * falloff,
			PLAYER_HIT_JOLT_POSITION * 0.25 * intensity * snap * falloff,
			0
		)
		local rotation = CFrame.Angles(
			0,
			0,
			math.rad(state.direction * PLAYER_HIT_JOLT_ROTATION * intensity * falloff)
		)

		lastPlayerHitJoltCFrame = CFrame.new(offset) * rotation
		lastPlayerHitJoltActive = true
		camera.CFrame = camera.CFrame * lastPlayerHitJoltCFrame
	end)
end

local function playPlayerHitJolt(intensity)
	playerHitJoltSequence = playerHitJoltSequence + 1
	local direction = 1
	if math.random() < 0.5 then
		direction = -1
	end

	playerHitJoltState = {
		sequence = playerHitJoltSequence,
		startTime = os.clock(),
		direction = direction,
		intensity = intensity or 1,
	}

	ensurePlayerHitJoltBinding()
end

local function playPlayerHitFeedback(damage, enemyPosition)
	local config = activeFeedback.playerHitImpact
	local intensity = 1
	if typeof(damage) == "number" and damage > 0 then
		intensity = math.clamp(damage / config.damageBase, config.minIntensity, config.maxIntensity)
	end

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("enemy_hit")
	end

	playHapticBump(0.08 * intensity, 0.12 * intensity, 0.1 + ((intensity - 1) * 0.04))
	playPlayerHitFlash(intensity)
	activeFeedback.playPlayerHitDirectionPulse(enemyPosition)
	showPlayerHitReadout(damage)
	playPlayerHitJolt(intensity)
end

local function createLowHealthEdge(name, position, size, rotation)
	local edge = Instance.new("Frame")
	edge.Name = name
	edge.Position = position
	edge.Size = size
	edge.BackgroundColor3 = Color3.fromRGB(210, 36, 32)
	edge.BackgroundTransparency = LOW_HEALTH_CLEAR_TRANSPARENCY
	edge.BorderSizePixel = 0
	edge.Visible = false
	edge.ZIndex = 1
	edge.Parent = lowHealthGui

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = edge

	return edge
end

local function ensureLowHealthWarning()
	if lowHealthGui and lowHealthGui.Parent then
		return
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")
	local existingGui = playerGui:FindFirstChild(LOW_HEALTH_WARNING_GUI_NAME)
	if existingGui and existingGui:IsA("ScreenGui") then
		existingGui:ClearAllChildren()
		lowHealthGui = existingGui
	else
		lowHealthGui = Instance.new("ScreenGui")
		lowHealthGui.Name = LOW_HEALTH_WARNING_GUI_NAME
		lowHealthGui.Parent = playerGui
	end
	lowHealthGui.ResetOnSpawn = false
	lowHealthGui.IgnoreGuiInset = true
	lowHealthGui.DisplayOrder = LOW_HEALTH_DISPLAY_ORDER
	lowHealthGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	lowHealthEdges = {
		createLowHealthEdge(
			"TopEdge",
			UDim2.fromScale(0, 0),
			UDim2.new(1, 0, 0, LOW_HEALTH_EDGE_THICKNESS),
			90
		),
		createLowHealthEdge(
			"BottomEdge",
			UDim2.new(0, 0, 1, -LOW_HEALTH_EDGE_THICKNESS),
			UDim2.new(1, 0, 0, LOW_HEALTH_EDGE_THICKNESS),
			270
		),
		createLowHealthEdge(
			"LeftEdge",
			UDim2.fromScale(0, 0),
			UDim2.new(0, LOW_HEALTH_EDGE_THICKNESS, 1, 0),
			0
		),
		createLowHealthEdge(
			"RightEdge",
			UDim2.new(1, -LOW_HEALTH_EDGE_THICKNESS, 0, 0),
			UDim2.new(0, LOW_HEALTH_EDGE_THICKNESS, 1, 0),
			180
		),
	}
end

local function cancelLowHealthPulseTweens()
	for _, tween in ipairs(lowHealthPulseTweens) do
		if tween then
			tween:Cancel()
		end
	end

	lowHealthPulseTweens = {}
end

local function setLowHealthWarningTransparency(transparency, visible)
	for _, edge in ipairs(lowHealthEdges) do
		if edge and edge.Parent then
			edge.BackgroundTransparency = transparency
			edge.Visible = visible
		end
	end
end

local function stopLowHealthWarning(fadeOut)
	if not lowHealthActive and not lowHealthGui then
		return
	end

	lowHealthActive = false
	lowHealthPulseSequence = lowHealthPulseSequence + 1
	lowHealthSoundSequence = lowHealthSoundSequence + 1
	local sequence = lowHealthPulseSequence
	cancelLowHealthPulseTweens()

	if not lowHealthGui or not lowHealthGui.Parent then
		return
	end

	if fadeOut then
		for _, edge in ipairs(lowHealthEdges) do
			if edge and edge.Parent then
				local tween = TweenService:Create(edge, TweenInfo.new(
					LOW_HEALTH_CLEAR_DURATION,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				), {
					BackgroundTransparency = LOW_HEALTH_CLEAR_TRANSPARENCY,
				})
				table.insert(lowHealthPulseTweens, tween)
				tween:Play()
			end
		end

		task.delay(LOW_HEALTH_CLEAR_DURATION + 0.03, function()
			if sequence ~= lowHealthPulseSequence then
				return
			end

			cancelLowHealthPulseTweens()
			setLowHealthWarningTransparency(LOW_HEALTH_CLEAR_TRANSPARENCY, false)
		end)
	else
		setLowHealthWarningTransparency(LOW_HEALTH_CLEAR_TRANSPARENCY, false)
	end
end

local function startLowHealthWarning()
	ensureLowHealthWarning()

	if lowHealthActive then
		return
	end

	lowHealthActive = true
	lowHealthPulseSequence = lowHealthPulseSequence + 1
	lowHealthSoundSequence = lowHealthSoundSequence + 1
	local sequence = lowHealthPulseSequence
	local soundSequence = lowHealthSoundSequence
	cancelLowHealthPulseTweens()
	setLowHealthWarningTransparency(LOW_HEALTH_PULSE_OUT_TRANSPARENCY, true)

	task.spawn(function()
		while lowHealthActive and sequence == lowHealthPulseSequence and soundSequence == lowHealthSoundSequence do
			if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
				LocalPlaySound:Fire("low_health_warning")
			end

			task.wait(LOW_HEALTH_SOUND_INTERVAL)
		end
	end)

	task.spawn(function()
		local pulseIn = true
		while lowHealthActive and sequence == lowHealthPulseSequence do
			local targetTransparency = LOW_HEALTH_PULSE_OUT_TRANSPARENCY
			if pulseIn then
				targetTransparency = LOW_HEALTH_PULSE_IN_TRANSPARENCY
			end

			cancelLowHealthPulseTweens()
			for _, edge in ipairs(lowHealthEdges) do
				if edge and edge.Parent then
					edge.Visible = true
					local tween = TweenService:Create(edge, TweenInfo.new(
						LOW_HEALTH_PULSE_DURATION,
						Enum.EasingStyle.Sine,
						Enum.EasingDirection.InOut
					), {
						BackgroundTransparency = targetTransparency,
					})
					table.insert(lowHealthPulseTweens, tween)
					tween:Play()
				end
			end

			pulseIn = not pulseIn
			task.wait(LOW_HEALTH_PULSE_DURATION)
		end
	end)
end

local function updateLowHealthWarning(humanoid)
	if humanoid ~= lowHealthCurrentHumanoid then
		return
	end

	local maxHealth = math.max(humanoid.MaxHealth, 1)
	local isLowHealth = humanoid.Health > 0 and humanoid.Health / maxHealth <= LOW_HEALTH_THRESHOLD
	if isLowHealth then
		startLowHealthWarning()
	else
		stopLowHealthWarning(true)
	end
end

local function disconnectLowHealthHumanoid()
	if lowHealthHumanoidConnection then
		lowHealthHumanoidConnection:Disconnect()
		lowHealthHumanoidConnection = nil
	end

	if lowHealthDiedConnection then
		lowHealthDiedConnection:Disconnect()
		lowHealthDiedConnection = nil
	end

	lowHealthCurrentHumanoid = nil
	stopLowHealthWarning(true)
end

local function attachLowHealthHumanoid(character)
	disconnectLowHealthHumanoid()
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid or not character.Parent then
		return
	end

	lowHealthCurrentHumanoid = humanoid
	lowHealthHumanoidConnection = humanoid.HealthChanged:Connect(function()
		updateLowHealthWarning(humanoid)
	end)
	lowHealthDiedConnection = humanoid.Died:Connect(function()
		if humanoid == lowHealthCurrentHumanoid then
			stopLowHealthWarning(true)
		end
	end)

	updateLowHealthWarning(humanoid)
end

local function showDamageNumber(model, damage)
	if typeof(damage) ~= "number" or damage <= 0 then
		return
	end

	if not model or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = DAMAGE_NUMBER_NAME
	billboard.Adornee = root
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE
	billboard.Size = UDim2.fromOffset(64, 24)
	billboard.StudsOffset = Vector3.new(math.random(-12, 12) / 100, 4.15, 0)
	billboard.Parent = root

	local label = Instance.new("TextLabel")
	label.Name = "Damage"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = string.format("-%d", math.floor(damage + 0.5))
	label.TextColor3 = HIT_COLOR
	label.TextStrokeTransparency = 0.18
	label.TextSize = 18
	label.Font = Enum.Font.GothamBlack
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(65, 46, 8)
	stroke.Transparency = 0.08
	stroke.Thickness = 1
	stroke.Parent = label

	local riseTween = TweenService:Create(billboard, TweenInfo.new(
		DAMAGE_NUMBER_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		Size = UDim2.fromOffset(72, 28),
		StudsOffset = billboard.StudsOffset + Vector3.new(0, 0.72, 0),
	})
	local fadeTween = TweenService:Create(label, TweenInfo.new(
		DAMAGE_NUMBER_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	local strokeTween = TweenService:Create(stroke, TweenInfo.new(
		DAMAGE_NUMBER_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		Transparency = 1,
	})

	riseTween:Play()
	fadeTween:Play()
	strokeTween:Play()

	fadeTween.Completed:Once(function()
		if billboard.Parent then
			billboard:Destroy()
		end
	end)

	task.delay(DAMAGE_NUMBER_DURATION + 0.08, function()
		if billboard.Parent then
			billboard:Destroy()
		end
	end)
end

local function addRewardLabel(parent, text, color, textSize, strokeColor)
	local label = Instance.new("TextLabel")
	label.Name = "RewardLine"
	label.Size = UDim2.new(1, 0, 0, textSize + 4)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.12
	label.TextSize = textSize
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = parent

	local sizeConstraint = Instance.new("UITextSizeConstraint")
	sizeConstraint.MinTextSize = 10
	sizeConstraint.MaxTextSize = textSize
	sizeConstraint.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor
	stroke.Transparency = 0.04
	stroke.Thickness = 1
	stroke.Parent = label

	return label, stroke
end

local function showRewardBurst(model, reward)
	if typeof(reward) ~= "table" then
		return
	end

	if not model or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local existing = root:FindFirstChild(REWARD_BURST_NAME)
	if existing then
		existing:Destroy()
	end

	local coins = tonumber(reward.coins) or 0
	local fragments = tonumber(reward.fragments) or 0
	local streakCount = tonumber(reward.streakCount) or 1
	local streakBonusCoins = tonumber(reward.streakBonusCoins) or 0
	local item = reward.item
	local isMiniboss = reward.isMiniboss == true
	local hasItem = typeof(item) == "table" and item.name ~= nil
	local hasStreakBonus = streakCount >= 2 and streakBonusCoins > 0
	local lineCount = 2
	if hasStreakBonus then
		lineCount = lineCount + 1
	end
	if hasItem then
		lineCount = lineCount + 1
	end
	if isMiniboss then
		lineCount = lineCount + 1
	end

	local width = isMiniboss and 184 or 148
	local height = isMiniboss and (lineCount * 24 + 12) or (lineCount * 21 + 10)
	local startOffset = isMiniboss and Vector3.new(0, 6.25, 0) or Vector3.new(0, 5.35, 0)
	local duration = isMiniboss and MINIBOSS_REWARD_BURST_DURATION or REWARD_BURST_DURATION

	local billboard = Instance.new("BillboardGui")
	billboard.Name = REWARD_BURST_NAME
	billboard.Adornee = root
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE
	billboard.Size = UDim2.fromOffset(width, height)
	billboard.StudsOffset = startOffset
	billboard.Parent = root

	local container = Instance.new("Frame")
	container.Name = "Rewards"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.Parent = billboard

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, isMiniboss and 1 or 0)
	listLayout.Parent = container

	local fadeTargets = {}
	if isMiniboss then
		local label, stroke = addRewardLabel(
			container,
			"BOUNTY",
			MINIBOSS_DEFEAT_COLOR,
			18,
			Color3.fromRGB(62, 25, 5)
		)
		table.insert(fadeTargets, { label = label, stroke = stroke })
	end

	local coinLabel, coinStroke = addRewardLabel(
		container,
		string.format("+%d coins", math.floor(coins + 0.5)),
		COIN_REWARD_COLOR,
		isMiniboss and 22 or 18,
		Color3.fromRGB(72, 43, 5)
	)
	table.insert(fadeTargets, { label = coinLabel, stroke = coinStroke })

	local fragmentLabel, fragmentStroke = addRewardLabel(
		container,
		string.format("+%d fragments", math.floor(fragments + 0.5)),
		FRAGMENT_REWARD_COLOR,
		isMiniboss and 19 or 16,
		Color3.fromRGB(8, 45, 62)
	)
	table.insert(fadeTargets, { label = fragmentLabel, stroke = fragmentStroke })

	if hasStreakBonus then
		local streakLabel, streakStroke = addRewardLabel(
			container,
			string.format("x%d streak +%d bonus", streakCount, math.floor(streakBonusCoins + 0.5)),
			STREAK_REWARD_COLOR,
			isMiniboss and 17 or 14,
			Color3.fromRGB(70, 24, 10)
		)
		table.insert(fadeTargets, { label = streakLabel, stroke = streakStroke })
	end

	if hasItem then
		local itemColor = item.color
		if typeof(itemColor) ~= "Color3" then
			itemColor = MINIBOSS_DEFEAT_COLOR
		end

		local itemLabel, itemStroke = addRewardLabel(
			container,
			tostring(item.name),
			itemColor,
			isMiniboss and 18 or 15,
			Color3.fromRGB(18, 12, 28)
		)
		table.insert(fadeTargets, { label = itemLabel, stroke = itemStroke })
	end

	local moveTween = TweenService:Create(billboard, TweenInfo.new(
		duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		Size = UDim2.fromOffset(width + (isMiniboss and 34 or 18), height + (isMiniboss and 16 or 8)),
		StudsOffset = startOffset + Vector3.new(0, isMiniboss and 1.25 or 0.9, 0),
	})

	moveTween:Play()
	for _, target in ipairs(fadeTargets) do
		local label = target.label
		local stroke = target.stroke
		local fadeTween = TweenService:Create(label, TweenInfo.new(
			duration,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		local strokeTween = TweenService:Create(stroke, TweenInfo.new(
			duration,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		), {
			Transparency = 1,
		})

		fadeTween:Play()
		strokeTween:Play()
	end

	task.delay(duration + 0.08, function()
		if billboard.Parent then
			billboard:Destroy()
		end
	end)
end

function CombatStreak.getSyncedServerTime()
	local ok, serverTime = pcall(function()
		return workspace:GetServerTimeNow()
	end)

	if ok and type(serverTime) == "number" then
		return serverTime
	end

	return os.clock()
end

function CombatStreak.cancelTweens()
	for _, tween in ipairs(CombatStreak.fadeTweens) do
		if tween then
			tween:Cancel()
		end
	end

	CombatStreak.fadeTweens = {}
end

function CombatStreak.setTransparency(alpha)
	if not CombatStreak.frame then
		return
	end

	alpha = math.clamp(alpha, 0, 1)
	CombatStreak.frame.BackgroundTransparency = 0.08 + (alpha * 0.92)
	CombatStreak.stroke.Transparency = 0.12 + (alpha * 0.88)
	CombatStreak.titleLabel.TextTransparency = alpha
	CombatStreak.titleLabel.TextStrokeTransparency = 0.32 + (alpha * 0.68)
	CombatStreak.titleStroke.Transparency = 0.04 + (alpha * 0.96)
	CombatStreak.bonusLabel.TextTransparency = alpha
	CombatStreak.bonusLabel.TextStrokeTransparency = 0.42 + (alpha * 0.58)
	CombatStreak.bonusStroke.Transparency = 0.1 + (alpha * 0.9)
	CombatStreak.fillBack.BackgroundTransparency = 0.28 + (alpha * 0.72)
	CombatStreak.fill.BackgroundTransparency = alpha
end

function CombatStreak.ensure()
	if CombatStreak.frame and CombatStreak.frame.Parent then
		return
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")
	local existingGui = playerGui:FindFirstChild(CombatStreak.guiName)
	if existingGui and existingGui:IsA("ScreenGui") then
		existingGui:ClearAllChildren()
		CombatStreak.gui = existingGui
	else
		CombatStreak.gui = Instance.new("ScreenGui")
		CombatStreak.gui.Name = CombatStreak.guiName
		CombatStreak.gui.Parent = playerGui
	end
	CombatStreak.gui.ResetOnSpawn = false
	CombatStreak.gui.IgnoreGuiInset = true
	CombatStreak.gui.DisplayOrder = CombatStreak.displayOrder
	CombatStreak.gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	CombatStreak.frame = Instance.new("Frame")
	CombatStreak.frame.Name = "Meter"
	CombatStreak.frame.AnchorPoint = Vector2.new(0.5, 0)
	CombatStreak.frame.Position = UDim2.new(0.5, 0, 0, 116)
	CombatStreak.frame.Size = UDim2.fromOffset(CombatStreak.width, CombatStreak.height)
	CombatStreak.frame.BackgroundColor3 = Color3.fromRGB(32, 18, 15)
	CombatStreak.frame.BackgroundTransparency = 1
	CombatStreak.frame.BorderSizePixel = 0
	CombatStreak.frame.Visible = false
	CombatStreak.frame.ZIndex = 1
	CombatStreak.frame.Parent = CombatStreak.gui

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(184, CombatStreak.height)
	sizeConstraint.MaxSize = Vector2.new(CombatStreak.width, CombatStreak.height)
	sizeConstraint.Parent = CombatStreak.frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = CombatStreak.frame

	CombatStreak.stroke = Instance.new("UIStroke")
	CombatStreak.stroke.Color = STREAK_REWARD_COLOR
	CombatStreak.stroke.Transparency = 1
	CombatStreak.stroke.Thickness = 1
	CombatStreak.stroke.Parent = CombatStreak.frame

	CombatStreak.scale = Instance.new("UIScale")
	CombatStreak.scale.Scale = 1
	CombatStreak.scale.Parent = CombatStreak.frame

	CombatStreak.titleLabel = Instance.new("TextLabel")
	CombatStreak.titleLabel.Name = "Title"
	CombatStreak.titleLabel.Position = UDim2.fromOffset(12, 7)
	CombatStreak.titleLabel.Size = UDim2.new(1, -24, 0, 22)
	CombatStreak.titleLabel.BackgroundTransparency = 1
	CombatStreak.titleLabel.Text = "x2 Combat Streak"
	CombatStreak.titleLabel.TextColor3 = Color3.fromRGB(255, 222, 180)
	CombatStreak.titleLabel.TextStrokeTransparency = 1
	CombatStreak.titleLabel.TextSize = 18
	CombatStreak.titleLabel.Font = Enum.Font.GothamBlack
	CombatStreak.titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	CombatStreak.titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	CombatStreak.titleLabel.ZIndex = 2
	CombatStreak.titleLabel.Parent = CombatStreak.frame

	CombatStreak.titleStroke = Instance.new("UIStroke")
	CombatStreak.titleStroke.Color = Color3.fromRGB(74, 24, 9)
	CombatStreak.titleStroke.Transparency = 1
	CombatStreak.titleStroke.Thickness = 1
	CombatStreak.titleStroke.Parent = CombatStreak.titleLabel

	CombatStreak.bonusLabel = Instance.new("TextLabel")
	CombatStreak.bonusLabel.Name = "Bonus"
	CombatStreak.bonusLabel.Position = UDim2.fromOffset(12, 29)
	CombatStreak.bonusLabel.Size = UDim2.new(1, -24, 0, 16)
	CombatStreak.bonusLabel.BackgroundTransparency = 1
	CombatStreak.bonusLabel.Text = "+0 bonus coins"
	CombatStreak.bonusLabel.TextColor3 = COIN_REWARD_COLOR
	CombatStreak.bonusLabel.TextStrokeTransparency = 1
	CombatStreak.bonusLabel.TextSize = 13
	CombatStreak.bonusLabel.Font = Enum.Font.GothamBold
	CombatStreak.bonusLabel.TextXAlignment = Enum.TextXAlignment.Left
	CombatStreak.bonusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	CombatStreak.bonusLabel.ZIndex = 2
	CombatStreak.bonusLabel.Parent = CombatStreak.frame

	CombatStreak.bonusStroke = Instance.new("UIStroke")
	CombatStreak.bonusStroke.Color = Color3.fromRGB(72, 43, 5)
	CombatStreak.bonusStroke.Transparency = 1
	CombatStreak.bonusStroke.Thickness = 1
	CombatStreak.bonusStroke.Parent = CombatStreak.bonusLabel

	CombatStreak.fillBack = Instance.new("Frame")
	CombatStreak.fillBack.Name = "CountdownBack"
	CombatStreak.fillBack.Position = UDim2.fromOffset(12, 47)
	CombatStreak.fillBack.Size = UDim2.new(1, -24, 0, 5)
	CombatStreak.fillBack.BackgroundColor3 = Color3.fromRGB(83, 45, 29)
	CombatStreak.fillBack.BackgroundTransparency = 1
	CombatStreak.fillBack.BorderSizePixel = 0
	CombatStreak.fillBack.ZIndex = 2
	CombatStreak.fillBack.Parent = CombatStreak.frame

	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 3)
	backCorner.Parent = CombatStreak.fillBack

	CombatStreak.fill = Instance.new("Frame")
	CombatStreak.fill.Name = "CountdownFill"
	CombatStreak.fill.Size = UDim2.fromScale(1, 1)
	CombatStreak.fill.BackgroundColor3 = STREAK_REWARD_COLOR
	CombatStreak.fill.BackgroundTransparency = 1
	CombatStreak.fill.BorderSizePixel = 0
	CombatStreak.fill.ZIndex = 3
	CombatStreak.fill.Parent = CombatStreak.fillBack

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = CombatStreak.fill
end

function CombatStreak.fade(sequence)
	if not CombatStreak.frame or not CombatStreak.frame.Visible then
		return
	end
	if sequence and sequence ~= CombatStreak.sequence then
		return
	end

	CombatStreak.visible = false
	CombatStreak.cancelTweens()

	local tweenInfo = TweenInfo.new(
		CombatStreak.fadeDuration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	local tweens = {
		TweenService:Create(CombatStreak.frame, tweenInfo, {
			BackgroundTransparency = 1,
		}),
		TweenService:Create(CombatStreak.stroke, tweenInfo, {
			Transparency = 1,
		}),
		TweenService:Create(CombatStreak.titleLabel, tweenInfo, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}),
		TweenService:Create(CombatStreak.titleStroke, tweenInfo, {
			Transparency = 1,
		}),
		TweenService:Create(CombatStreak.bonusLabel, tweenInfo, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}),
		TweenService:Create(CombatStreak.bonusStroke, tweenInfo, {
			Transparency = 1,
		}),
		TweenService:Create(CombatStreak.fillBack, tweenInfo, {
			BackgroundTransparency = 1,
		}),
		TweenService:Create(CombatStreak.fill, tweenInfo, {
			BackgroundTransparency = 1,
		}),
	}

	CombatStreak.fadeTweens = tweens
	for _, tween in ipairs(tweens) do
		tween:Play()
	end

	task.delay(CombatStreak.fadeDuration + 0.04, function()
		if sequence and sequence ~= CombatStreak.sequence then
			return
		end
		if CombatStreak.frame then
			CombatStreak.frame.Visible = false
			CombatStreak.scale.Scale = 1
		end
		CombatStreak.cancelTweens()
	end)
end

function CombatStreak.pulse()
	if not CombatStreak.scale then
		return
	end

	CombatStreak.scale.Scale = 1.08
	local pulseTween = TweenService:Create(CombatStreak.scale, TweenInfo.new(
		CombatStreak.pulseDuration,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	), {
		Scale = 1,
	})
	pulseTween:Play()
end

function CombatStreak.update()
	if not CombatStreak.visible or not CombatStreak.frame or not CombatStreak.frame.Visible then
		return
	end

	local remaining = CombatStreak.expiresAt - CombatStreak.getSyncedServerTime()
	if remaining <= 0 then
		CombatStreak.fade(CombatStreak.sequence)
		return
	end

	local ratio = math.clamp(remaining / math.max(CombatStreak.window, 0.1), 0, 1)
	CombatStreak.fill.Size = UDim2.fromScale(ratio, 1)
	CombatStreak.fill.BackgroundColor3 = ATTACK_WARNING_COLOR:Lerp(STREAK_REWARD_COLOR, ratio)
end

function CombatStreak.show(reward)
	if typeof(reward) ~= "table" then
		return
	end

	local streakCount = tonumber(reward.streakCount) or 1
	local streakBonusCoins = tonumber(reward.streakBonusCoins) or 0
	if streakCount < 2 or streakBonusCoins <= 0 then
		return
	end

	local window = tonumber(reward.killStreakWindow) or 1
	local expiresAt = tonumber(reward.streakExpiresAt) or (CombatStreak.getSyncedServerTime() + window)
	if expiresAt <= CombatStreak.getSyncedServerTime() then
		return
	end

	CombatStreak.ensure()
	CombatStreak.sequence = CombatStreak.sequence + 1
	CombatStreak.visible = true
	CombatStreak.expiresAt = expiresAt
	CombatStreak.window = math.max(window, 0.1)
	CombatStreak.cancelTweens()

	CombatStreak.frame.Visible = true
	CombatStreak.setTransparency(0)
	CombatStreak.titleLabel.Text = string.format("x%d Combat Streak", math.floor(streakCount + 0.5))
	CombatStreak.bonusLabel.Text = string.format("+%d bonus coins", math.floor(streakBonusCoins + 0.5))
	CombatStreak.update()
	CombatStreak.pulse()
end

function CombatStreak.showFirstEnemyCombatHint()
	if CombatStreak.firstEnemyHintShown then
		return
	end

	local ok, hasSeen = pcall(function()
		return player:GetAttribute(CombatStreak.firstEnemyHintSeenAttribute)
	end)
	if ok and hasSeen == true then
		CombatStreak.firstEnemyHintShown = true
		return
	end

	CombatStreak.firstEnemyHintShown = true
	pcall(function()
		player:SetAttribute(CombatStreak.firstEnemyHintSeenAttribute, true)
	end)

	CombatStreak.firstEnemyHintSequence = CombatStreak.firstEnemyHintSequence + 1
	local sequence = CombatStreak.firstEnemyHintSequence

	if CombatStreak.firstEnemyHintGui and CombatStreak.firstEnemyHintGui.Parent then
		CombatStreak.firstEnemyHintGui:Destroy()
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = CombatStreak.firstEnemyHintGuiName
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = CombatStreak.firstEnemyHintDisplayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	CombatStreak.firstEnemyHintGui = gui

	local frame = Instance.new("Frame")
	frame.Name = "HintPanel"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 106)
	frame.Size = UDim2.new(0.84, 0, 0, 76)
	frame.BackgroundColor3 = Color3.fromRGB(28, 19, 14)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = 1
	frame.Parent = gui

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(260, 76)
	sizeConstraint.MaxSize = Vector2.new(360, 76)
	sizeConstraint.Parent = frame

	local scale = Instance.new("UIScale")
	scale.Scale = 0.94
	scale.Parent = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = ENEMY_SPAWN_COLOR
	stroke.Transparency = 1
	stroke.Thickness = 1
	stroke.Parent = frame

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Position = UDim2.fromOffset(0, 0)
	accent.Size = UDim2.new(0, 4, 1, 0)
	accent.BackgroundColor3 = ENEMY_SPAWN_COLOR
	accent.BackgroundTransparency = 1
	accent.BorderSizePixel = 0
	accent.ZIndex = 2
	accent.Parent = frame

	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 8)
	accentCorner.Parent = accent

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Position = UDim2.fromOffset(15, 18)
	icon.Size = UDim2.fromOffset(38, 38)
	icon.BackgroundColor3 = Color3.fromRGB(58, 34, 18)
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.Text = "!"
	icon.TextColor3 = ENEMY_SPAWN_COLOR
	icon.TextTransparency = 1
	icon.TextStrokeTransparency = 1
	icon.TextSize = 28
	icon.Font = Enum.Font.GothamBlack
	icon.ZIndex = 3
	icon.Parent = frame

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 8)
	iconCorner.Parent = icon

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(64, 11)
	title.Size = UDim2.new(1, -80, 0, 22)
	title.BackgroundTransparency = 1
	title.Text = "Enemy unearthed"
	title.TextColor3 = Color3.fromRGB(255, 238, 210)
	title.TextTransparency = 1
	title.TextStrokeTransparency = 1
	title.TextSize = 17
	title.Font = Enum.Font.GothamBlack
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 3
	title.Parent = frame

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(64, 35)
	body.Size = UDim2.new(1, -80, 0, 34)
	body.BackgroundTransparency = 1
	body.Text = "Tap or click it with your tool equipped."
	body.TextColor3 = Color3.fromRGB(255, 207, 160)
	body.TextTransparency = 1
	body.TextStrokeTransparency = 1
	body.TextSize = 13
	body.Font = Enum.Font.GothamBold
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.ZIndex = 3
	body.Parent = frame

	local inTweenInfo = TweenInfo.new(
		0.22,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	)
	TweenService:Create(scale, inTweenInfo, {
		Scale = 1,
	}):Play()
	TweenService:Create(frame, inTweenInfo, {
		BackgroundTransparency = 0.08,
	}):Play()
	TweenService:Create(stroke, inTweenInfo, {
		Transparency = 0.16,
	}):Play()
	TweenService:Create(accent, inTweenInfo, {
		BackgroundTransparency = 0,
	}):Play()
	TweenService:Create(icon, inTweenInfo, {
		BackgroundTransparency = 0.16,
		TextTransparency = 0,
		TextStrokeTransparency = 0.2,
	}):Play()
	TweenService:Create(title, inTweenInfo, {
		TextTransparency = 0,
		TextStrokeTransparency = 0.45,
	}):Play()
	TweenService:Create(body, inTweenInfo, {
		TextTransparency = 0,
		TextStrokeTransparency = 0.55,
	}):Play()

	task.delay(CombatStreak.firstEnemyHintDuration, function()
		if sequence ~= CombatStreak.firstEnemyHintSequence or not gui.Parent then
			return
		end

		local fadeTweenInfo = TweenInfo.new(
			CombatStreak.firstEnemyHintFadeDuration,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		TweenService:Create(frame, fadeTweenInfo, {
			Position = UDim2.new(0.5, 0, 0, 94),
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(stroke, fadeTweenInfo, {
			Transparency = 1,
		}):Play()
		TweenService:Create(accent, fadeTweenInfo, {
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(icon, fadeTweenInfo, {
			BackgroundTransparency = 1,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		TweenService:Create(title, fadeTweenInfo, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		TweenService:Create(body, fadeTweenInfo, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()

		task.delay(CombatStreak.firstEnemyHintFadeDuration + 0.05, function()
			if sequence == CombatStreak.firstEnemyHintSequence and gui.Parent then
				gui:Destroy()
			end
		end)
	end)
end

local function showEnemySpawnCue(model)
	if not model or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local existing = root:FindFirstChild(ENEMY_SPAWN_CUE_NAME)
	if existing then
		existing:Destroy()
		activeFeedback.enemySpawnRing.clear(model)
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = ENEMY_SPAWN_CUE_NAME
	billboard.Adornee = root
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE
	billboard.Size = UDim2.fromOffset(104, 28)
	billboard.StudsOffset = Vector3.new(0, 4.25, 0)
	billboard.Parent = root

	local isEmerging = model:GetAttribute("IsEmerging") == true

	local label = Instance.new("TextLabel")
	label.Name = "Cue"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = isEmerging and "emerging!" or "surfaced"
	label.TextColor3 = ENEMY_SPAWN_COLOR
	label.TextStrokeTransparency = 0.28
	label.TextSize = isEmerging and 16 or 14
	label.Font = isEmerging and Enum.Font.GothamBlack or Enum.Font.GothamBold
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 36, 18)
	stroke.Transparency = 0.22
	stroke.Thickness = 1
	stroke.Parent = label

	local closing = false
	local attributeConnection = nil
	local function finishCue()
		if closing or not billboard.Parent then
			return
		end
		closing = true
		if attributeConnection then
			attributeConnection:Disconnect()
			attributeConnection = nil
		end
		activeFeedback.enemySpawnRing.fade(model)

		label.Text = "surfaced"
		label.TextSize = 14
		label.Font = Enum.Font.GothamBold

		local moveTween = TweenService:Create(billboard, TweenInfo.new(
			ENEMY_SPAWN_CUE_DURATION,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		), {
			Size = UDim2.fromOffset(94, 28),
			StudsOffset = Vector3.new(0, 4.55, 0),
		})
		local fadeTween = TweenService:Create(label, TweenInfo.new(
			ENEMY_SPAWN_CUE_DURATION,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		local strokeTween = TweenService:Create(stroke, TweenInfo.new(
			ENEMY_SPAWN_CUE_DURATION,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		), {
			Transparency = 1,
		})

		moveTween:Play()
		fadeTween:Play()
		strokeTween:Play()
	end

	if isEmerging then
		activeFeedback.enemySpawnRing.show(model, root)

		local pulseTween = TweenService:Create(billboard, TweenInfo.new(
			0.34,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.InOut,
			-1,
			true
		), {
			Size = UDim2.fromOffset(116, 32),
			StudsOffset = Vector3.new(0, 4.55, 0),
		})
		pulseTween:Play()

		attributeConnection = model:GetAttributeChangedSignal("IsEmerging"):Connect(function()
			if model:GetAttribute("IsEmerging") ~= true then
				pulseTween:Cancel()
				finishCue()
			end
		end)

		task.delay(ENEMY_EMERGENCE_CUE_MAX_DURATION, function()
			if billboard.Parent then
				pulseTween:Cancel()
				finishCue()
			end
		end)
	else
		finishCue()
	end

	task.delay(ENEMY_EMERGENCE_CUE_MAX_DURATION + ENEMY_SPAWN_CUE_DURATION + 0.08, function()
		if attributeConnection then
			attributeConnection:Disconnect()
			attributeConnection = nil
		end
		if billboard.Parent then
			billboard:Destroy()
		end
	end)
end

local function showAggroWarning(model)
	if not model or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local existing = root:FindFirstChild(AGGRO_WARNING_NAME)
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = AGGRO_WARNING_NAME
	billboard.Adornee = root
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE
	billboard.Size = UDim2.fromOffset(38, 38)
	billboard.StudsOffset = Vector3.new(0, 4.7, 0)
	billboard.Parent = root

	local label = Instance.new("TextLabel")
	label.Name = "Warning"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "!"
	label.TextColor3 = AGGRO_COLOR
	label.TextStrokeTransparency = 0.2
	label.TextSize = 32
	label.Font = Enum.Font.GothamBlack
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 22, 12)
	stroke.Transparency = 0.12
	stroke.Thickness = 2
	stroke.Parent = label

	local moveTween = TweenService:Create(billboard, TweenInfo.new(
		AGGRO_WARNING_DURATION,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	), {
		Size = UDim2.fromOffset(62, 62),
		StudsOffset = Vector3.new(0, 5.45, 0),
	})
	local fadeTween = TweenService:Create(label, TweenInfo.new(
		AGGRO_WARNING_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	local strokeTween = TweenService:Create(stroke, TweenInfo.new(
		AGGRO_WARNING_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		Transparency = 1,
	})

	moveTween:Play()
	fadeTween:Play()
	strokeTween:Play()

	task.delay(AGGRO_WARNING_DURATION + 0.05, function()
		if billboard.Parent then
			billboard:Destroy()
		end
	end)
end

local function showAttackWarning(model)
	if not model or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local existing = root:FindFirstChild(ATTACK_WARNING_NAME)
	if existing then
		existing:Destroy()
	end
	showAttackWarningRing(model, root)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = ATTACK_WARNING_NAME
	billboard.Adornee = root
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE
	billboard.Size = UDim2.fromOffset(42, 34)
	billboard.StudsOffset = Vector3.new(0, 4.55, 0)
	billboard.Parent = root

	local label = Instance.new("TextLabel")
	label.Name = "Warning"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "!"
	label.TextColor3 = ATTACK_WARNING_COLOR
	label.TextStrokeTransparency = 0.16
	label.TextSize = 30
	label.Font = Enum.Font.GothamBlack
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(75, 8, 5)
	stroke.Transparency = 0.08
	stroke.Thickness = 2
	stroke.Parent = label

	local moveTween = TweenService:Create(billboard, TweenInfo.new(
		ATTACK_WARNING_DURATION,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	), {
		Size = UDim2.fromOffset(56, 46),
		StudsOffset = Vector3.new(0, 5.1, 0),
	})
	local fadeTween = TweenService:Create(label, TweenInfo.new(
		ATTACK_WARNING_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	local strokeTween = TweenService:Create(stroke, TweenInfo.new(
		ATTACK_WARNING_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		Transparency = 1,
	})

	moveTween:Play()
	fadeTween:Play()
	strokeTween:Play()

	task.delay(ATTACK_WARNING_DURATION + 0.05, function()
		if billboard.Parent then
			billboard:Destroy()
		end
	end)
end

local function showMinibossWarning(model)
	if not model or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local existing = root:FindFirstChild(MINIBOSS_WARNING_NAME)
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = MINIBOSS_WARNING_NAME
	billboard.Adornee = root
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE
	billboard.Size = UDim2.fromOffset(150, 42)
	billboard.StudsOffset = Vector3.new(0, 5.25, 0)
	billboard.Parent = root

	local label = Instance.new("TextLabel")
	label.Name = "Warning"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "MINIBOSS"
	label.TextColor3 = MINIBOSS_COLOR
	label.TextStrokeTransparency = 0.12
	label.TextSize = 22
	label.Font = Enum.Font.GothamBlack
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(25, 5, 40)
	stroke.Transparency = 0.05
	stroke.Thickness = 2
	stroke.Parent = label

	local moveTween = TweenService:Create(billboard, TweenInfo.new(
		MINIBOSS_WARNING_DURATION,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	), {
		Size = UDim2.fromOffset(190, 54),
		StudsOffset = Vector3.new(0, 6.15, 0),
	})
	local fadeTween = TweenService:Create(label, TweenInfo.new(
		MINIBOSS_WARNING_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	local strokeTween = TweenService:Create(stroke, TweenInfo.new(
		MINIBOSS_WARNING_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		Transparency = 1,
	})

	moveTween:Play()
	fadeTween:Play()
	strokeTween:Play()

	task.delay(MINIBOSS_WARNING_DURATION + 0.05, function()
		if billboard.Parent then
			billboard:Destroy()
		end
	end)
end

local function showMinibossEnrageWarning(model)
	if not model or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local existing = root:FindFirstChild(MINIBOSS_ENRAGE_WARNING_NAME)
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = MINIBOSS_ENRAGE_WARNING_NAME
	billboard.Adornee = root
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE
	billboard.Size = UDim2.fromOffset(142, 38)
	billboard.StudsOffset = Vector3.new(0, 5.35, 0)
	billboard.Parent = root

	local label = Instance.new("TextLabel")
	label.Name = "Warning"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "ENRAGED"
	label.TextColor3 = ENRAGE_COLOR
	label.TextStrokeTransparency = 0.1
	label.TextSize = 22
	label.Font = Enum.Font.GothamBlack
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(70, 8, 5)
	stroke.Transparency = 0.04
	stroke.Thickness = 2
	stroke.Parent = label

	local moveTween = TweenService:Create(billboard, TweenInfo.new(
		MINIBOSS_ENRAGE_WARNING_DURATION,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	), {
		Size = UDim2.fromOffset(178, 48),
		StudsOffset = Vector3.new(0, 6.05, 0),
	})
	local fadeTween = TweenService:Create(label, TweenInfo.new(
		MINIBOSS_ENRAGE_WARNING_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	local strokeTween = TweenService:Create(stroke, TweenInfo.new(
		MINIBOSS_ENRAGE_WARNING_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		Transparency = 1,
	})

	moveTween:Play()
	fadeTween:Play()
	strokeTween:Play()

	task.delay(MINIBOSS_ENRAGE_WARNING_DURATION + 0.05, function()
		if billboard.Parent then
			billboard:Destroy()
		end
	end)
end

local function pulseBossBarEnrage(model)
	if not model or not model:IsA("Model") or model:GetAttribute("IsMiniboss") ~= true then
		return
	end

	ensureBossBar()
	updateBossBar()
	if activeBossModel ~= model or not bossBarFrame or not bossBarFill or not bossBarStroke then
		return
	end

	bossBarPulseSequence = bossBarPulseSequence + 1
	local sequence = bossBarPulseSequence
	local frameColor = bossBarFrame.BackgroundColor3
	local frameTransparency = bossBarFrame.BackgroundTransparency
	local fillColor = bossBarFill.BackgroundColor3

	bossBarFrame.BackgroundColor3 = Color3.fromRGB(44, 13, 12)
	bossBarFrame.BackgroundTransparency = 0
	bossBarFill.BackgroundColor3 = ENRAGE_COLOR
	bossBarStroke.Color = ENRAGE_COLOR
	bossBarStroke.Transparency = 0
	bossBarStroke.Thickness = 3

	local frameTween = TweenService:Create(bossBarFrame, TweenInfo.new(
		BOSS_BAR_ENRAGE_PULSE_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		BackgroundColor3 = frameColor,
		BackgroundTransparency = frameTransparency,
	})
	local fillTween = TweenService:Create(bossBarFill, TweenInfo.new(
		BOSS_BAR_ENRAGE_PULSE_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		BackgroundColor3 = fillColor,
	})
	local strokeTween = TweenService:Create(bossBarStroke, TweenInfo.new(
		BOSS_BAR_ENRAGE_PULSE_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		Color = MINIBOSS_COLOR,
		Transparency = 0.28,
		Thickness = 1,
	})

	frameTween:Play()
	fillTween:Play()
	strokeTween:Play()
	strokeTween.Completed:Once(function()
		if sequence == bossBarPulseSequence then
			updateBossBar()
		end
	end)
end

local function ensureMinibossDefeatGui()
	if minibossDefeatGui and minibossDefeatGui.Parent then
		return minibossDefeatGui
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")

	minibossDefeatGui = Instance.new("ScreenGui")
	minibossDefeatGui.Name = MINIBOSS_DEFEAT_GUI_NAME
	minibossDefeatGui.ResetOnSpawn = false
	minibossDefeatGui.IgnoreGuiInset = true
	minibossDefeatGui.DisplayOrder = MINIBOSS_DEFEAT_DISPLAY_ORDER
	minibossDefeatGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	minibossDefeatGui.Parent = playerGui

	return minibossDefeatGui
end

local function pulseBossBarDefeated(model)
	if not model or not model:IsA("Model") or model:GetAttribute("IsMiniboss") ~= true then
		return
	end

	ensureBossBar()
	if not bossBarFrame or not bossBarFill or not bossBarStroke then
		return
	end

	bossBarPulseSequence = bossBarPulseSequence + 1
	local sequence = bossBarPulseSequence
	local originalPosition = bossBarFrame.Position
	local originalSize = bossBarFrame.Size
	local originalBackgroundColor = bossBarFrame.BackgroundColor3
	local originalBackgroundTransparency = bossBarFrame.BackgroundTransparency

	activeBossModel = model
	bossBarNameLabel.Text = model:GetAttribute("EnemyName") or model.Name
	bossBarPercentLabel.Text = "CLEAR"
	bossBarFill.Size = UDim2.fromScale(0, 1)
	bossBarFill.BackgroundColor3 = MINIBOSS_DEFEAT_COLOR
	bossBarFrame.BackgroundColor3 = Color3.fromRGB(35, 23, 12)
	bossBarFrame.BackgroundTransparency = 0
	bossBarFrame.Visible = true
	bossBarStroke.Color = MINIBOSS_DEFEAT_COLOR
	bossBarStroke.Transparency = 0
	bossBarStroke.Thickness = 3

	local frameTween = TweenService:Create(bossBarFrame, TweenInfo.new(
		BOSS_BAR_DEFEAT_PULSE_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		Position = UDim2.new(
			originalPosition.X.Scale,
			originalPosition.X.Offset,
			originalPosition.Y.Scale,
			originalPosition.Y.Offset - 10
		),
		Size = UDim2.fromOffset(BOSS_BAR_WIDTH + 54, BOSS_BAR_HEIGHT + 10),
		BackgroundTransparency = 1,
	})
	local fillTween = TweenService:Create(bossBarFill, TweenInfo.new(
		BOSS_BAR_DEFEAT_PULSE_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		BackgroundColor3 = MINIBOSS_VOID_COLOR,
	})
	local strokeTween = TweenService:Create(bossBarStroke, TweenInfo.new(
		BOSS_BAR_DEFEAT_PULSE_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		Transparency = 1,
		Thickness = 1,
	})

	frameTween:Play()
	fillTween:Play()
	strokeTween:Play()

	task.delay(BOSS_BAR_DEFEAT_PULSE_DURATION + 0.04, function()
		if sequence ~= bossBarPulseSequence then
			return
		end

		bossBarFrame.Position = originalPosition
		bossBarFrame.Size = originalSize
		bossBarFrame.BackgroundColor3 = originalBackgroundColor
		bossBarFrame.BackgroundTransparency = originalBackgroundTransparency
		bossBarStroke.Color = MINIBOSS_COLOR
		bossBarStroke.Transparency = 0.28
		bossBarStroke.Thickness = 1
		if activeBossModel == model then
			activeBossModel = nil
		end
		updateBossBar()
	end)
end

function CombatStreak.getHollowKingCooldownLine(reward)
	if typeof(reward) ~= "table" then
		return nil
	end

	local cooldown = reward.hollowKingCooldown
	if typeof(cooldown) ~= "table" or cooldown.enemyId ~= "hollow_king" then
		return nil
	end

	local seconds = tonumber(cooldown.durationSeconds)
	if not seconds then
		local expiresAt = tonumber(cooldown.expiresAt)
		if expiresAt then
			seconds = math.max(0, expiresAt - CombatStreak.getSyncedServerTime())
		end
	end
	if not seconds or seconds <= 0 then
		return nil
	end

	local minutes = math.max(1, math.floor((seconds + 59) / 60))
	local enemyName = cooldown.enemyName
	if type(enemyName) ~= "string" or enemyName == "" then
		enemyName = "Hollow King"
	end

	return string.format("%s driven off for %dm", enemyName, minutes)
end

local function showMinibossDefeatCelebration(model, reward)
	if not model or not model:IsA("Model") or model:GetAttribute("IsMiniboss") ~= true then
		return
	end

	local gui = ensureMinibossDefeatGui()
	minibossDefeatSequence = minibossDefeatSequence + 1
	local sequence = minibossDefeatSequence
	local cooldownLine = CombatStreak.getHollowKingCooldownLine(reward)
	local bannerHeight = cooldownLine and 116 or 92
	local bannerStartHeight = cooldownLine and 104 or 82
	gui:ClearAllChildren()

	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and root:IsDescendantOf(workspace) then
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = { model }

		local origin = root.Position - Vector3.new(0, root.Size.Y * 0.5, 0)
		local raycastResult = workspace:Raycast(root.Position, Vector3.new(0, -14, 0), raycastParams)
		if raycastResult then
			origin = raycastResult.Position + Vector3.new(0, 0.08, 0)
		else
			origin = origin + Vector3.new(0, 0.08, 0)
		end

		local folder = Instance.new("Folder")
		folder.Name = "DeepDigMinibossDefeatShockwave"
		folder.Parent = workspace

		local ringSegments = 20
		local startRadius = 1.4
		local endRadius = 7.2
		local startSegmentLength = (math.pi * startRadius * 2 / ringSegments) * 0.72
		local endSegmentLength = (math.pi * endRadius * 2 / ringSegments) * 0.72
		for index = 1, ringSegments do
			local angle = ((index - 1) / ringSegments) * math.pi * 2
			local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
			local startCenter = origin + radial * startRadius
			local endCenter = origin + radial * endRadius

			local segment = Instance.new("Part")
			segment.Name = "ShockwaveSegment" .. index
			segment.Anchored = true
			segment.CanCollide = false
			segment.CanQuery = false
			segment.CanTouch = false
			segment.CastShadow = false
			segment.Material = Enum.Material.Neon
			segment.Color = index % 2 == 0 and MINIBOSS_DEFEAT_COLOR or MINIBOSS_VOID_COLOR
			segment.Size = Vector3.new(startSegmentLength, 0.05, 0.14)
			segment.Transparency = 0.18
			segment.CFrame = CFrame.fromMatrix(startCenter, tangent, Vector3.new(0, 1, 0), radial)
			segment.Parent = folder

			TweenService:Create(segment, TweenInfo.new(
				0.48,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			), {
				Size = Vector3.new(endSegmentLength, 0.035, 0.08),
				Transparency = 1,
				CFrame = CFrame.fromMatrix(endCenter, tangent, Vector3.new(0, 1, 0), radial),
			}):Play()
		end

		for index = 1, 8 do
			local angle = ((index - 1) / 8) * math.pi * 2 + math.rad(math.random(-12, 12))
			local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local startOffset = radial * math.random(8, 16) * 0.1
			local endOffset = radial * math.random(18, 34) * 0.1
			local shard = Instance.new("Part")
			shard.Name = "VoidGoldShard" .. index
			shard.Anchored = true
			shard.CanCollide = false
			shard.CanQuery = false
			shard.CanTouch = false
			shard.CastShadow = false
			shard.Material = Enum.Material.Neon
			shard.Color = index % 2 == 0 and MINIBOSS_DEFEAT_COLOR or MINIBOSS_VOID_COLOR
			shard.Size = Vector3.new(0.16, math.random(26, 42) * 0.01, 0.16)
			shard.Transparency = 0.04
			shard.CFrame = CFrame.new(origin + startOffset + Vector3.new(0, 0.18, 0))
				* CFrame.Angles(math.rad(math.random(18, 72)), math.rad(math.random(0, 360)), math.rad(math.random(18, 72)))
			shard.Parent = folder

			TweenService:Create(shard, TweenInfo.new(
				0.62,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			), {
				Transparency = 1,
				Size = Vector3.new(0.04, 0.12, 0.04),
				CFrame = CFrame.new(origin + endOffset + Vector3.new(0, math.random(24, 42) * 0.1, 0))
					* CFrame.Angles(math.rad(math.random(80, 170)), math.rad(math.random(0, 360)), math.rad(math.random(80, 170))),
			}):Play()
		end

		task.delay(0.76, function()
			if folder.Parent then
				folder:Destroy()
			end
		end)
	end

	local goldFlash = Instance.new("Frame")
	goldFlash.Name = "GoldFlash"
	goldFlash.Size = UDim2.fromScale(1, 1)
	goldFlash.BackgroundColor3 = MINIBOSS_DEFEAT_COLOR
	goldFlash.BackgroundTransparency = 0.34
	goldFlash.BorderSizePixel = 0
	goldFlash.ZIndex = 1
	goldFlash.Parent = gui

	local voidFlash = Instance.new("Frame")
	voidFlash.Name = "VoidFlash"
	voidFlash.Size = UDim2.fromScale(1, 1)
	voidFlash.BackgroundColor3 = MINIBOSS_VOID_COLOR
	voidFlash.BackgroundTransparency = 0.72
	voidFlash.BorderSizePixel = 0
	voidFlash.ZIndex = 2
	voidFlash.Parent = gui

	local banner = Instance.new("Frame")
	banner.Name = "BossClearBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.34)
	banner.Size = UDim2.new(0.86, 0, 0, bannerHeight)
	banner.BackgroundColor3 = Color3.fromRGB(21, 12, 28)
	banner.BackgroundTransparency = 0.06
	banner.BorderSizePixel = 0
	banner.ZIndex = 3
	banner.Parent = gui

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(280, bannerStartHeight)
	sizeConstraint.MaxSize = Vector2.new(430, bannerHeight)
	sizeConstraint.Parent = banner

	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 8)
	bannerCorner.Parent = banner

	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Color = MINIBOSS_DEFEAT_COLOR
	bannerStroke.Transparency = 0.06
	bannerStroke.Thickness = 2
	bannerStroke.Parent = banner

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(18, 12)
	title.Size = UDim2.new(1, -36, 0, 34)
	title.BackgroundTransparency = 1
	title.Text = "BOSS CLEAR"
	title.TextColor3 = MINIBOSS_DEFEAT_COLOR
	title.TextStrokeTransparency = 0.12
	title.TextSize = 32
	title.Font = Enum.Font.GothamBlack
	title.ZIndex = 4
	title.Parent = banner

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "BossName"
	nameLabel.Position = UDim2.fromOffset(18, 49)
	nameLabel.Size = UDim2.new(1, -36, 0, 24)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = model:GetAttribute("EnemyName") or model.Name
	nameLabel.TextColor3 = Color3.fromRGB(244, 223, 255)
	nameLabel.TextStrokeTransparency = 0.35
	nameLabel.TextSize = 18
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.ZIndex = 4
	nameLabel.Parent = banner

	local cooldownLabel = nil
	if cooldownLine then
		cooldownLabel = Instance.new("TextLabel")
		cooldownLabel.Name = "CooldownLine"
		cooldownLabel.Position = UDim2.fromOffset(18, 76)
		cooldownLabel.Size = UDim2.new(1, -36, 0, 22)
		cooldownLabel.BackgroundTransparency = 1
		cooldownLabel.Text = cooldownLine
		cooldownLabel.TextColor3 = Color3.fromRGB(255, 210, 138)
		cooldownLabel.TextStrokeTransparency = 0.42
		cooldownLabel.TextSize = 16
		cooldownLabel.Font = Enum.Font.GothamMedium
		cooldownLabel.TextTruncate = Enum.TextTruncate.AtEnd
		cooldownLabel.ZIndex = 4
		cooldownLabel.Parent = banner
	end

	local startSize = UDim2.new(0.76, 0, 0, bannerStartHeight)
	banner.Size = startSize

	local flashTween = TweenService:Create(goldFlash, TweenInfo.new(
		0.55,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		BackgroundTransparency = 1,
	})
	local voidTween = TweenService:Create(voidFlash, TweenInfo.new(
		MINIBOSS_DEFEAT_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		BackgroundTransparency = 1,
	})
	local bannerTween = TweenService:Create(banner, TweenInfo.new(
		0.24,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	), {
		Size = UDim2.new(0.86, 0, 0, bannerHeight),
	})
	local bannerFadeTween = TweenService:Create(banner, TweenInfo.new(
		0.38,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	), {
		Position = UDim2.fromScale(0.5, 0.31),
		BackgroundTransparency = 1,
	})
	local strokeFadeTween = TweenService:Create(bannerStroke, TweenInfo.new(
		0.38,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	), {
		Transparency = 1,
	})
	local titleFadeTween = TweenService:Create(title, TweenInfo.new(
		0.38,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	local nameFadeTween = TweenService:Create(nameLabel, TweenInfo.new(
		0.38,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	local cooldownFadeTween = nil
	if cooldownLabel then
		cooldownFadeTween = TweenService:Create(cooldownLabel, TweenInfo.new(
			0.38,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
	end

	flashTween:Play()
	voidTween:Play()
	bannerTween:Play()
	task.delay(0.86, function()
		if sequence ~= minibossDefeatSequence or not banner.Parent then
			return
		end

		bannerFadeTween:Play()
		strokeFadeTween:Play()
		titleFadeTween:Play()
		nameFadeTween:Play()
		if cooldownFadeTween then
			cooldownFadeTween:Play()
		end
	end)

	task.delay(MINIBOSS_DEFEAT_DURATION + 0.06, function()
		if sequence == minibossDefeatSequence and gui.Parent then
			gui:ClearAllChildren()
		end
	end)

	pulseBossBarDefeated(model)
	playPlayerHitJolt()
end

local function pulseEnemy(model, feedbackType)
	if not model or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local record = getFeedbackRecord(model, root)
	record.token = record.token + 1
	local token = record.token

	if record.tween then
		record.tween:Cancel()
		record.tween = nil
	end

	root.Color = record.baselineColor
	root.Material = record.baselineMaterial
	root.Size = record.baselineSize
	root.Transparency = record.baselineTransparency

	local isDefeated = feedbackType == "defeated"
	local isAggro = feedbackType == "aggro"
	local isAttackWarning = feedbackType == "enemy_attack_warning"
	local isEnemySpawn = feedbackType == "enemy_spawn"
	local isMinibossSpawn = feedbackType == "miniboss_spawn"
	local isMinibossEnrage = feedbackType == "miniboss_enrage"
	local pulseColor = HIT_COLOR
	local pulseScale = HIT_SCALE
	local pulseDuration = 0.16
	local restoreDelay = 0.3
	if isEnemySpawn then
		pulseColor = ENEMY_SPAWN_COLOR
		pulseScale = ENEMY_SPAWN_SCALE
		pulseDuration = 0.18
		restoreDelay = 0.32
	elseif isDefeated then
		pulseColor = DEFEAT_COLOR
		pulseScale = DEFEAT_SCALE
		pulseDuration = 0.28
		restoreDelay = 0.45
	elseif isAggro then
		pulseColor = AGGRO_COLOR
		pulseScale = AGGRO_SCALE
		pulseDuration = 0.24
		restoreDelay = 0.4
	elseif isAttackWarning then
		pulseColor = ATTACK_WARNING_COLOR
		pulseScale = ATTACK_WARNING_SCALE
		pulseDuration = 0.18
		restoreDelay = 0.36
	elseif isMinibossSpawn then
		pulseColor = MINIBOSS_COLOR
		pulseScale = MINIBOSS_SCALE
		pulseDuration = 0.38
		restoreDelay = 0.72
	elseif isMinibossEnrage then
		pulseColor = ENRAGE_COLOR
		pulseScale = ENRAGE_SCALE
		pulseDuration = 0.28
		restoreDelay = 0.5
	end

	root.Color = pulseColor
	root.Material = Enum.Material.Neon
	root.Size = record.baselineSize * pulseScale

	record.tween = TweenService:Create(root, TweenInfo.new(
		pulseDuration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		Color = record.baselineColor,
		Size = record.baselineSize,
		Transparency = record.baselineTransparency,
	})

	record.tween:Play()
	record.tween.Completed:Once(function()
		restoreFeedback(model, record, token)
	end)

	task.delay(restoreDelay, function()
		restoreFeedback(model, record, token)
	end)
end

player.CharacterAdded:Connect(attachLowHealthHumanoid)
player.CharacterRemoving:Connect(function(character)
	local humanoid = lowHealthCurrentHumanoid
	if humanoid and humanoid.Parent == character then
		disconnectLowHealthHumanoid()
	end
end)

if player.Character then
	task.spawn(function()
		attachLowHealthHumanoid(player.Character)
	end)
end

EnemyCombatFeedback.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local feedbackType = payload.type
	if feedbackType == "player_damaged" or feedbackType == "player_hit" then
		playPlayerHitFeedback(payload.damage, payload.enemyPosition)
		return
	end

	if feedbackType ~= "hit" and feedbackType ~= "defeated" and feedbackType ~= "aggro" and feedbackType ~= "enemy_attack_warning" and feedbackType ~= "enemy_spawn" and feedbackType ~= "miniboss_spawn" and feedbackType ~= "miniboss_enrage" and feedbackType ~= "miniboss_defeated" then
		return
	end

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		if feedbackType == "aggro" then
			LocalPlaySound:Fire("enemy_aggro")
		elseif feedbackType == "enemy_attack_warning" then
			LocalPlaySound:Fire("enemy_attack_warning")
		elseif feedbackType == "enemy_spawn" then
			LocalPlaySound:Fire("enemy_spawn")
		elseif feedbackType == "miniboss_spawn" then
			LocalPlaySound:Fire("enemy_miniboss_spawn")
		elseif feedbackType == "miniboss_enrage" then
			LocalPlaySound:Fire("enemy_miniboss_enrage")
		elseif feedbackType == "miniboss_defeated" then
			LocalPlaySound:Fire("enemy_miniboss_defeated")
		else
			LocalPlaySound:Fire(feedbackType == "defeated" and "enemy_defeated" or "enemy_hit")
		end
	end

	if feedbackType == "hit" then
		playHapticBump(0.07, 0.04, 0.08)
	elseif feedbackType == "defeated" then
		playHapticBump(0.12, 0.18, 0.16)
	elseif feedbackType == "miniboss_spawn" then
		playHapticBump(0.16, 0.24, 0.2)
	elseif feedbackType == "miniboss_enrage" then
		playHapticBump(0.2, 0.3, 0.18)
	elseif feedbackType == "miniboss_defeated" then
		playHapticBump(0.24, 0.36, 0.28)
	end

	if feedbackType == "hit" then
		showDamageNumber(payload.model, payload.damage)
	elseif feedbackType == "defeated" then
		showRewardBurst(payload.model, payload.reward)
		CombatStreak.show(payload.reward)
		if payload.reward and LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
			LocalPlaySound:Fire("enemy_reward")
		end
	end

	if feedbackType == "aggro" then
		showAggroWarning(payload.model)
		if payload.reason == "dig_blocked" then
			activeFeedback.playDigBlockedDirectionPulse(payload.model)
		end
	elseif feedbackType == "enemy_attack_warning" then
		showAttackWarning(payload.model)
	elseif feedbackType == "enemy_spawn" then
		showEnemySpawnCue(payload.model)
		CombatStreak.showFirstEnemyCombatHint()
	elseif feedbackType == "miniboss_spawn" then
		showEnemySpawnCue(payload.model)
		showMinibossWarning(payload.model)
		activeFeedback.showMinibossSpawnOverlay(payload.model)
	elseif feedbackType == "miniboss_enrage" then
		pulseBossBarEnrage(payload.model)
		showMinibossEnrageWarning(payload.model)
	elseif feedbackType == "miniboss_defeated" then
		showMinibossDefeatCelebration(payload.model, payload.reward)
		return
	end

	pulseEnemy(payload.model, feedbackType)
end)

local enemiesFolder = workspace:WaitForChild("Enemies")

for _, child in ipairs(enemiesFolder:GetChildren()) do
	trackEnemy(child)
end

enemiesFolder.ChildAdded:Connect(trackEnemy)
enemiesFolder.ChildRemoved:Connect(cleanupEnemy)
RunService.RenderStepped:Connect(function()
	activeFeedback.updateCombatPressureChip()
	updateEnemyThreatIndicator()
	CombatStreak.update()
end)

print("[DeepDig] EnemyHealthBar loaded")
