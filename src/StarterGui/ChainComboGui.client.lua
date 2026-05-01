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
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ChainComboUpdate = Remotes:WaitForChild("ChainComboUpdate", 10)
if not ChainComboUpdate then return end

local SHOW_THRESHOLD = 5 -- match ChainCombo.server.lua's first tier

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeepDigChainCombo"
screenGui.ResetOnSpawn = false
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

local barFillCorner = Instance.new("UICorner")
barFillCorner.CornerRadius = UDim.new(1, 0)
barFillCorner.Parent = barFill

local state = {
	streak = 0,
	mult = 1.0,
	expiresAt = 0,
	window = 3,
}

local function refreshLabels()
	streakLabel.Text = "x" .. state.streak
	multLabel.Text = string.format("%.2f×", state.mult)

	-- Stroke + multLabel color shift as multiplier rises
	if state.mult >= 3.0 then
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

ChainComboUpdate.OnClientEvent:Connect(function(streak, mult, secondsLeft, window)
	state.streak = streak or 0
	state.mult = mult or 1.0
	state.window = window or state.window
	state.expiresAt = os.clock() + (secondsLeft or 0)

	if state.streak >= SHOW_THRESHOLD then
		frame.Visible = true
		refreshLabels()
		-- Pop scale on tier-up
		frame.Size = UDim2.new(0, 240, 0, 60)
		TweenService:Create(
			frame,
			TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.new(0, 220, 0, 56) }
		):Play()
	else
		-- Below threshold (or 0): hide
		frame.Visible = false
	end
end)

RunService.RenderStepped:Connect(function()
	if not frame.Visible then return end
	local timeLeft = math.max(0, state.expiresAt - os.clock())
	local pct = math.clamp(timeLeft / state.window, 0, 1)
	barFill.Size = UDim2.new(pct, 0, 1, 0)
	if timeLeft <= 0 then
		frame.Visible = false
	end
end)
