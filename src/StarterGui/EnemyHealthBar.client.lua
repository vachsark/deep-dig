-- EnemyHealthBar.client.lua - floating enemy names and HP bars
-- Place in: StarterGui/EnemyHealthBar (LocalScript)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EnemyCombatFeedback = Remotes:WaitForChild("EnemyCombatFeedback")
local LOCAL_PLAY_SOUND_NAME = "DeepDigLocalPlaySound"

local HEALTH_BAR_NAME = "DeepDigEnemyHealthBar"
local MAX_DISTANCE = 80
local BAR_WIDTH = 120
local BAR_HEIGHT = 36
local HIT_COLOR = Color3.fromRGB(255, 245, 160)
local DEFEAT_COLOR = Color3.fromRGB(255, 95, 70)
local HIT_SCALE = 1.08
local DEFEAT_SCALE = 1.16
local PLAYER_HIT_DISPLAY_ORDER = 80
local PLAYER_HIT_FLASH_TRANSPARENCY = 0.48
local PLAYER_HIT_FLASH_FADE = 0.2
local PLAYER_HIT_JOLT_BIND_NAME = "DeepDigPlayerHitCameraJolt"
local PLAYER_HIT_JOLT_DURATION = 0.14
local PLAYER_HIT_JOLT_POSITION = 0.32
local PLAYER_HIT_JOLT_ROTATION = 0.75

local trackedEnemies = {}
local activeFeedback = {}
local playerHitGui = nil
local playerHitOverlay = nil
local playerHitFlashTween = nil
local playerHitFlashSequence = 0
local playerHitJoltSequence = 0
local playerHitJoltState = nil
local playerHitJoltBound = false
local lastPlayerHitJoltCFrame = CFrame.new()
local lastPlayerHitJoltActive = false

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

local function cleanupEnemy(model)
	local record = trackedEnemies[model]
	if record then
		trackedEnemies[model] = nil
		disconnectAll(record.connections)

		if record.gui and record.gui.Parent then
			record.gui:Destroy()
		end
	end

	local feedbackRecord = activeFeedback[model]
	if feedbackRecord then
		if feedbackRecord.tween then
			feedbackRecord.tween:Cancel()
		end
		activeFeedback[model] = nil
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
		}
		trackedEnemies[model] = record

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
		end

		table.insert(record.connections, humanoid.HealthChanged:Connect(update))
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

local function playPlayerHitFlash()
	local overlay = ensurePlayerHitOverlay()
	playerHitFlashSequence = playerHitFlashSequence + 1
	local sequence = playerHitFlashSequence

	if playerHitFlashTween then
		playerHitFlashTween:Cancel()
		playerHitFlashTween = nil
	end

	overlay.Visible = true
	overlay.BackgroundTransparency = PLAYER_HIT_FLASH_TRANSPARENCY

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
		local offset = Vector3.new(
			state.direction * PLAYER_HIT_JOLT_POSITION * falloff,
			PLAYER_HIT_JOLT_POSITION * 0.25 * snap * falloff,
			0
		)
		local rotation = CFrame.Angles(
			0,
			0,
			math.rad(state.direction * PLAYER_HIT_JOLT_ROTATION * falloff)
		)

		lastPlayerHitJoltCFrame = CFrame.new(offset) * rotation
		lastPlayerHitJoltActive = true
		camera.CFrame = camera.CFrame * lastPlayerHitJoltCFrame
	end)
end

local function playPlayerHitJolt()
	playerHitJoltSequence = playerHitJoltSequence + 1
	local direction = 1
	if math.random() < 0.5 then
		direction = -1
	end

	playerHitJoltState = {
		sequence = playerHitJoltSequence,
		startTime = os.clock(),
		direction = direction,
	}

	ensurePlayerHitJoltBinding()
end

local function playPlayerHitFeedback()
	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("enemy_hit")
	end

	playPlayerHitFlash()
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
	root.Color = isDefeated and DEFEAT_COLOR or HIT_COLOR
	root.Material = Enum.Material.Neon
	root.Size = record.baselineSize * (isDefeated and DEFEAT_SCALE or HIT_SCALE)

	record.tween = TweenService:Create(root, TweenInfo.new(
		isDefeated and 0.28 or 0.16,
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

	task.delay(isDefeated and 0.45 or 0.3, function()
		restoreFeedback(model, record, token)
	end)
end

EnemyCombatFeedback.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local feedbackType = payload.type
	if feedbackType == "player_hit" then
		playPlayerHitFeedback()
		return
	end

	if feedbackType ~= "hit" and feedbackType ~= "defeated" then
		return
	end

	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire(feedbackType == "defeated" and "enemy_defeated" or "enemy_hit")
	end

	pulseEnemy(payload.model, feedbackType)
end)

local enemiesFolder = workspace:WaitForChild("Enemies")

for _, child in ipairs(enemiesFolder:GetChildren()) do
	trackEnemy(child)
end

enemiesFolder.ChildAdded:Connect(trackEnemy)
enemiesFolder.ChildRemoved:Connect(cleanupEnemy)

print("[DeepDig] EnemyHealthBar loaded")
