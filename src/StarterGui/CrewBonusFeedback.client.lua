-- CrewBonusFeedback.client.lua - local co-op fragment bonus burst
-- Place in: StarterGui/CrewBonusFeedback (LocalScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if not Remotes then
	warn("[CrewBonusFeedback] Remotes folder missing - feedback disabled.")
	return
end

local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD", 5)
if not UpdateHUDEvent then
	warn("[CrewBonusFeedback] UpdateHUD remote missing - feedback disabled.")
	return
end

local LOCAL_PLAY_SOUND_NAME = "DeepDigLocalPlaySound"
local LocalPlaySound = SoundService:FindFirstChild(LOCAL_PLAY_SOUND_NAME)
if not LocalPlaySound then
	LocalPlaySound = Instance.new("BindableEvent")
	LocalPlaySound.Name = LOCAL_PLAY_SOUND_NAME
	LocalPlaySound.Parent = SoundService
end

local DISPLAY_ORDER = 118
local BURST_LIFETIME_SECONDS = 0.86

local feedbackSequence = 0
local activeGui = nil

local function clearActiveGui(sequence)
	if sequence and sequence ~= feedbackSequence then
		return
	end

	if activeGui then
		activeGui:Destroy()
		activeGui = nil
	end
end

local function playCrewBonusBurst(amount)
	feedbackSequence = feedbackSequence + 1
	local sequence = feedbackSequence
	clearActiveGui()

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CrewBonusFeedback"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = DISPLAY_ORDER
	screenGui.Parent = playerGui
	activeGui = screenGui

	local frame = Instance.new("Frame")
	frame.Name = "Burst"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.73)
	frame.Size = UDim2.fromOffset(242, 38)
	frame.BackgroundColor3 = Color3.fromRGB(33, 30, 41)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = 20
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 236, 180)
	stroke.Thickness = 1
	stroke.Transparency = 1
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "AmountLabel"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.new(1, -18, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "+" .. tostring(amount) .. " Crew Fragments"
	label.TextColor3 = Color3.fromRGB(230, 255, 239)
	label.TextTransparency = 1
	label.TextSize = 18
	label.Font = Enum.Font.GothamBlack
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = 21
	label.Parent = frame

	local scale = Instance.new("UIScale")
	scale.Scale = 0.88
	scale.Parent = frame

	LocalPlaySound:Fire("crew_bonus")

	TweenService:Create(frame, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.12,
		Position = UDim2.fromScale(0.5, 0.7),
	}):Play()
	TweenService:Create(stroke, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 0.18,
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	task.delay(0.46, function()
		if sequence ~= feedbackSequence or activeGui ~= screenGui then
			return
		end

		TweenService:Create(frame, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.67),
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
		}):Play()
		TweenService:Create(label, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		}):Play()
	end)

	task.delay(BURST_LIFETIME_SECONDS, function()
		clearActiveGui(sequence)
	end)
end

UpdateHUDEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	local bonus = payload.crewDigBonus
	if type(bonus) ~= "number" or bonus <= 0 then
		return
	end

	playCrewBonusBurst(math.floor(bonus))
end)
