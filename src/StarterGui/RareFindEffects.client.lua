-- RareFindEffects.client.lua - full-screen client effects for high-rarity finds
-- Place in: StarterGui/RareFindEffects (LocalScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ItemFoundEvent = Remotes:WaitForChild("ItemFound")

local RARITY_RANK = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
}

local MIN_FLASH_RANK = RARITY_RANK.Legendary
local LOW_RARITIES = {
	Common = true,
	Uncommon = true,
	Rare = true,
	Epic = true,
}

local FLASH_COLOR = Color3.fromRGB(255, 218, 82)
local FLASH_PEAK_TRANSPARENCY = 0.18
local FLASH_IN_DURATION = 0.07
local FLASH_OUT_DURATION = 0.42

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RareFindEffects"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 98
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local overlay = Instance.new("Frame")
overlay.Name = "GoldFlash"
overlay.Size = UDim2.fromScale(1, 1)
overlay.Position = UDim2.fromScale(0, 0)
overlay.BackgroundColor3 = FLASH_COLOR
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Active = false
overlay.Visible = false
overlay.ZIndex = 1
overlay.Parent = screenGui

local gradient = Instance.new("UIGradient")
gradient.Name = "GoldFlashGradient"
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 248, 190)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 218, 82)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 178, 36)),
})
gradient.Rotation = 25
gradient.Parent = overlay

local sequence = 0
local flashInTween = nil
local flashOutTween = nil

local function shouldFlashForRarity(rarity)
	if typeof(rarity) ~= "string" then
		return false
	end

	local rank = RARITY_RANK[rarity]
	if rank then
		return rank >= MIN_FLASH_RANK
	end

	return LOW_RARITIES[rarity] ~= true
end

local function cancelTween(tween)
	if tween then
		tween:Cancel()
	end
end

local function playGoldFlash()
	sequence = sequence + 1
	local currentSequence = sequence

	cancelTween(flashInTween)
	cancelTween(flashOutTween)
	flashInTween = nil
	flashOutTween = nil

	overlay.BackgroundTransparency = 1
	overlay.Visible = true

	flashInTween = TweenService:Create(
		overlay,
		TweenInfo.new(FLASH_IN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = FLASH_PEAK_TRANSPARENCY }
	)

	flashInTween.Completed:Connect(function(playbackState)
		if currentSequence ~= sequence or playbackState ~= Enum.PlaybackState.Completed then
			return
		end

		flashOutTween = TweenService:Create(
			overlay,
			TweenInfo.new(FLASH_OUT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)

		flashOutTween.Completed:Connect(function(outPlaybackState)
			if currentSequence ~= sequence or outPlaybackState ~= Enum.PlaybackState.Completed then
				return
			end

			overlay.BackgroundTransparency = 1
			overlay.Visible = false
			flashOutTween = nil
		end)

		flashOutTween:Play()
	end)

	flashInTween:Play()
end

ItemFoundEvent.OnClientEvent:Connect(function(item)
	if type(item) ~= "table" or not shouldFlashForRarity(item.rarity) then
		return
	end

	playGoldFlash()
end)
