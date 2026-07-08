-- ChainComboGui.client.lua — Streak counter HUD widget
--
-- Shows the player's active dig chain (streak count, current sellValue
-- multiplier, and a horizontal decay bar). Hidden until the streak hits
-- the first multiplier tier (5). Listens to ChainComboUpdate fired by
-- ChainCombo.server.lua. Decay countdown runs locally — server only
-- pushes on streak changes and when the chain expires.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ChainComboUpdate = Remotes:WaitForChild("ChainComboUpdate", 10)
if not ChainComboUpdate then return end
local LOCAL_PLAY_SOUND_NAME = "DeepDigLocalPlaySound"

local SHOW_THRESHOLD = 5 -- match ChainCombo.server.lua's first tier
local URGENCY_WINDOW = 0.75
local MILESTONE_THRESHOLDS = { 10, 20 }

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeepDigChainCombo"
screenGui.ResetOnSpawn = false
-- Sit above the HUD overlays (DisplayOrder 0) and notification toasts in
-- DeepDigHUD, but below modal panels (StatsGui=20, CrewGui=58, QuestGui/
-- TradeGui=60), notify banners (100), and FTUE arrows (1000).
screenGui.DisplayOrder = 15
screenGui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "Combo"
frame.AnchorPoint = Vector2.new(0.5, 0)
frame.Position = UDim2.new(0.5, 0, 0, 70)
frame.Size = UDim2.new(0, 220, 0, 56)
frame.BackgroundColor3 = Color3.fromRGB(20, 14, 30)
frame.BackgroundTransparency = 0.15
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = screenGui
local FRAME_BASE_POSITION = frame.Position

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Thickness = 2
stroke.Color = Color3.fromRGB(255, 200, 60)
stroke.Parent = frame

local streakLabel = Instance.new("TextLabel")
streakLabel.Name = "Streak"
streakLabel.Size = UDim2.new(0.5, 0, 0, 32)
streakLabel.Position = UDim2.new(0, 0, 0, 4)
streakLabel.BackgroundTransparency = 1
streakLabel.Text = "x0"
streakLabel.TextColor3 = Color3.fromRGB(255, 230, 110)
streakLabel.TextSize = 26
streakLabel.Font = Enum.Font.GothamBlack
streakLabel.TextXAlignment = Enum.TextXAlignment.Center
streakLabel.Parent = frame

local multLabel = Instance.new("TextLabel")
multLabel.Name = "Mult"
multLabel.Size = UDim2.new(0.5, 0, 0, 32)
multLabel.Position = UDim2.new(0.5, 0, 0, 4)
multLabel.BackgroundTransparency = 1
multLabel.Text = "1.0×"
multLabel.TextColor3 = Color3.fromRGB(255, 200, 60)
multLabel.TextSize = 22
multLabel.Font = Enum.Font.GothamBold
multLabel.TextXAlignment = Enum.TextXAlignment.Center
multLabel.Parent = frame

local barBg = Instance.new("Frame")
barBg.Name = "DecayBar"
barBg.Size = UDim2.new(1, -20, 0, 6)
barBg.Position = UDim2.new(0, 10, 1, -14)
barBg.BackgroundColor3 = Color3.fromRGB(40, 30, 50)
barBg.BorderSizePixel = 0
barBg.Parent = frame

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = barBg

local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.new(1, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
barFill.BorderSizePixel = 0
barFill.Parent = barBg
local BAR_FILL_BASE_COLOR = barFill.BackgroundColor3
local BAR_FILL_URGENCY_COLOR = Color3.fromRGB(255, 70, 70)

local barFillCorner = Instance.new("UICorner")
barFillCorner.CornerRadius = UDim.new(1, 0)
barFillCorner.Parent = barFill

local milestoneFrame = Instance.new("Frame")
milestoneFrame.Name = "MilestoneBurst"
milestoneFrame.AnchorPoint = Vector2.new(0.5, 0)
milestoneFrame.Position = UDim2.new(0.5, 0, 0, 18)
milestoneFrame.Size = UDim2.new(0, 186, 0, 46)
milestoneFrame.BackgroundColor3 = Color3.fromRGB(32, 22, 44)
milestoneFrame.BackgroundTransparency = 1
milestoneFrame.BorderSizePixel = 0
milestoneFrame.Visible = false
milestoneFrame.Parent = screenGui
local MILESTONE_BASE_POSITION = milestoneFrame.Position
local MILESTONE_BASE_SIZE = milestoneFrame.Size

local milestoneCorner = Instance.new("UICorner")
milestoneCorner.CornerRadius = UDim.new(0, 10)
milestoneCorner.Parent = milestoneFrame

local milestoneStroke = Instance.new("UIStroke")
milestoneStroke.Thickness = 2
milestoneStroke.Color = Color3.fromRGB(255, 214, 82)
milestoneStroke.Transparency = 1
milestoneStroke.Parent = milestoneFrame

local milestoneTitle = Instance.new("TextLabel")
milestoneTitle.Name = "Title"
milestoneTitle.Size = UDim2.new(1, -16, 0, 25)
milestoneTitle.Position = UDim2.new(0, 8, 0, 4)
milestoneTitle.BackgroundTransparency = 1
milestoneTitle.Text = "x10 Chain"
milestoneTitle.TextColor3 = Color3.fromRGB(255, 232, 112)
milestoneTitle.TextTransparency = 1
milestoneTitle.TextSize = 22
milestoneTitle.Font = Enum.Font.GothamBlack
milestoneTitle.TextXAlignment = Enum.TextXAlignment.Center
milestoneTitle.Parent = milestoneFrame

local milestoneMult = Instance.new("TextLabel")
milestoneMult.Name = "Multiplier"
milestoneMult.Size = UDim2.new(1, -16, 0, 16)
milestoneMult.Position = UDim2.new(0, 8, 0, 28)
milestoneMult.BackgroundTransparency = 1
milestoneMult.Text = "1.50× sell value"
milestoneMult.TextColor3 = Color3.fromRGB(255, 196, 74)
milestoneMult.TextTransparency = 1
milestoneMult.TextSize = 14
milestoneMult.Font = Enum.Font.GothamBold
milestoneMult.TextXAlignment = Enum.TextXAlignment.Center
milestoneMult.Parent = milestoneFrame

local state = {
	streak = 0,
	mult = 1.0,
	expiresAt = 0,
	window = 3,
}

local urgencyActive = false
local chainExpiringSoundArmed = true
local lastCelebratedThreshold = 0
local milestoneSequence = 0
local milestoneTweens = {}

local LocalPlaySound = SoundService:FindFirstChild(LOCAL_PLAY_SOUND_NAME)
if not LocalPlaySound then
	LocalPlaySound = Instance.new("BindableEvent")
	LocalPlaySound.Name = LOCAL_PLAY_SOUND_NAME
	LocalPlaySound.Parent = SoundService
end

local function playChainExpiringSound()
	if LocalPlaySound and LocalPlaySound:IsA("BindableEvent") then
		LocalPlaySound:Fire("chain_expiring")
	end
end

local function cancelMilestoneTweens()
	for _, tween in ipairs(milestoneTweens) do
		tween:Cancel()
	end
	milestoneTweens = {}
end

local function resetMilestoneBurst()
	milestoneSequence = milestoneSequence + 1
	cancelMilestoneTweens()
	milestoneFrame.Visible = false
	milestoneFrame.Position = MILESTONE_BASE_POSITION
	milestoneFrame.Size = MILESTONE_BASE_SIZE
	milestoneFrame.BackgroundTransparency = 1
	milestoneStroke.Transparency = 1
	milestoneTitle.TextTransparency = 1
	milestoneMult.TextTransparency = 1
end

local function resetCelebratedThreshold()
	lastCelebratedThreshold = 0
	resetMilestoneBurst()
end

local function findCrossedMilestone(prevStreak, nextStreak)
	local crossedThreshold = nil
	for _, threshold in ipairs(MILESTONE_THRESHOLDS) do
		if prevStreak < threshold and nextStreak >= threshold and threshold > lastCelebratedThreshold then
			crossedThreshold = threshold
		end
	end
	return crossedThreshold
end

local function playMilestoneBurst(threshold)
	milestoneSequence = milestoneSequence + 1
	local sequence = milestoneSequence
	cancelMilestoneTweens()

	local strong = threshold >= 20
	local baseWidth = strong and 218 or 186
	local baseHeight = strong and 54 or 46
	local popWidth = strong and 250 or 214
	local popHeight = strong and 64 or 54

	milestoneTitle.Text = "x" .. threshold .. " Chain"
	milestoneMult.Text = string.format("%.2f× sell value", state.mult)
	milestoneFrame.Size = UDim2.new(0, popWidth, 0, popHeight)
	milestoneFrame.Position = MILESTONE_BASE_POSITION + UDim2.new(0, 0, 0, strong and -4 or 0)
	milestoneFrame.BackgroundColor3 = strong and Color3.fromRGB(32, 24, 54) or Color3.fromRGB(32, 22, 44)
	milestoneFrame.BackgroundTransparency = 0.08
	milestoneStroke.Color = strong and Color3.fromRGB(255, 124, 84) or Color3.fromRGB(255, 214, 82)
	milestoneStroke.Transparency = 0
	milestoneTitle.TextColor3 = strong and Color3.fromRGB(255, 176, 104) or Color3.fromRGB(255, 232, 112)
	milestoneTitle.TextTransparency = 0
	milestoneTitle.TextSize = strong and 25 or 22
	milestoneMult.TextColor3 = strong and Color3.fromRGB(255, 222, 132) or Color3.fromRGB(255, 196, 74)
	milestoneMult.TextTransparency = 0
	milestoneFrame.Visible = true

	local settleTween = TweenService:Create(
		milestoneFrame,
		TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{
			Size = UDim2.new(0, baseWidth, 0, baseHeight),
			Position = MILESTONE_BASE_POSITION,
		}
	)
	table.insert(milestoneTweens, settleTween)
	settleTween:Play()

	task.delay(strong and 0.68 or 0.58, function()
		if sequence ~= milestoneSequence then return end

		local fadeTweens = {
			TweenService:Create(
				milestoneFrame,
				TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					Position = MILESTONE_BASE_POSITION + UDim2.new(0, 0, 0, -12),
					BackgroundTransparency = 1,
				}
			),
			TweenService:Create(
				milestoneStroke,
				TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Transparency = 1 }
			),
			TweenService:Create(
				milestoneTitle,
				TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ TextTransparency = 1 }
			),
			TweenService:Create(
				milestoneMult,
				TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ TextTransparency = 1 }
			),
		}
		for _, tween in ipairs(fadeTweens) do
			table.insert(milestoneTweens, tween)
			tween:Play()
		end

		task.delay(0.24, function()
			if sequence ~= milestoneSequence then return end
			resetMilestoneBurst()
		end)
	end)
end

local function setUrgency(active)
	if urgencyActive == active then return end
	urgencyActive = active

	if active then
		barFill.BackgroundColor3 = BAR_FILL_URGENCY_COLOR
		if chainExpiringSoundArmed then
			chainExpiringSoundArmed = false
			playChainExpiringSound()
		end
	else
		barFill.BackgroundColor3 = BAR_FILL_BASE_COLOR
		frame.Position = FRAME_BASE_POSITION
		chainExpiringSoundArmed = true
	end
end

local function refreshLabels()
	streakLabel.Text = "x" .. state.streak
	multLabel.Text = string.format("%.2f×", state.mult)

	-- Stroke + multLabel color shift as multiplier rises
	if state.mult >= 4.0 then
		stroke.Color = Color3.fromRGB(120, 220, 255)
		multLabel.TextColor3 = Color3.fromRGB(160, 235, 255)
	elseif state.mult >= 3.0 then
		stroke.Color = Color3.fromRGB(255, 90, 200)
		multLabel.TextColor3 = Color3.fromRGB(255, 130, 220)
	elseif state.mult >= 2.0 then
		stroke.Color = Color3.fromRGB(255, 120, 80)
		multLabel.TextColor3 = Color3.fromRGB(255, 150, 90)
	elseif state.mult >= 1.5 then
		stroke.Color = Color3.fromRGB(255, 200, 60)
		multLabel.TextColor3 = Color3.fromRGB(255, 220, 90)
	else
		stroke.Color = Color3.fromRGB(180, 220, 255)
		multLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
	end
end

local STREAK_BASE_SIZE = streakLabel.TextSize -- 26

ChainComboUpdate.OnClientEvent:Connect(function(streak, mult, secondsLeft, window)
	local prevMult = state.mult
	local prevStreak = state.streak
	state.streak = streak or 0
	state.mult = mult or 1.0
	state.window = window or state.window
	state.expiresAt = os.clock() + (secondsLeft or 0)
	setUrgency(false)

	if state.streak >= SHOW_THRESHOLD then
		local wasHidden = not frame.Visible
		frame.Visible = true
		refreshLabels()

		-- Pop only on first appearance OR tier-up. Don't pop on every dig
		-- — that's the chain rolling, not a noteworthy moment.
		if wasHidden or state.mult > prevMult then
			frame.Size = UDim2.new(0, 248, 0, 62)
			TweenService:Create(
				frame,
				TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = UDim2.new(0, 220, 0, 56) }
			):Play()

			-- Scale-pulse the streak number too, but only on real tier-up
			-- (not the initial appearance — that already has the frame pop).
			if state.mult > prevMult and not wasHidden then
				streakLabel.TextSize = STREAK_BASE_SIZE + 10
				TweenService:Create(
					streakLabel,
					TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ TextSize = STREAK_BASE_SIZE }
				):Play()
			end
		end

		local crossedThreshold = findCrossedMilestone(prevStreak, state.streak)
		if crossedThreshold then
			lastCelebratedThreshold = crossedThreshold
			playMilestoneBurst(crossedThreshold)
		end
	else
		-- Below threshold (or 0): hide
		setUrgency(false)
		resetCelebratedThreshold()
		frame.Visible = false
	end
end)

RunService.RenderStepped:Connect(function()
	if not frame.Visible then
		setUrgency(false)
		return
	end

	local timeLeft = math.max(0, state.expiresAt - os.clock())
	local pct = math.clamp(timeLeft / state.window, 0, 1)
	barFill.Size = UDim2.new(pct, 0, 1, 0)

	local shouldWarn = timeLeft > 0 and timeLeft < URGENCY_WINDOW
	setUrgency(shouldWarn)
	if urgencyActive then
		local shakeX = math.sin(os.clock() * 46) * 3
		frame.Position = FRAME_BASE_POSITION + UDim2.new(0, shakeX, 0, 0)
	end

	if timeLeft <= 0 then
		setUrgency(false)
		resetCelebratedThreshold()
		frame.Visible = false
	end
end)
