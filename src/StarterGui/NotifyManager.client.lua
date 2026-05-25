-- NotifyManager.client.lua
-- Supplementary notification layer that:
--   1. Suppresses duplicate notifies of lower rarity that fire within a 1.5s window.
--   2. Renders a centered banner at the top of the screen for Legendary / Mythic
--      notifies (always shown, never suppressed). Up to 3 stacked banners; the
--      oldest is removed if a 4th tries to appear.
--
-- HudGui.client.lua already owns the standard side-toast notification surface.
-- This script does NOT touch or replace that surface — it only adds a parallel
-- banner layer for high-importance events and de-duplicates rapid same-text spam.
--
-- Notify signature on the server: Remotes.Notify:FireClient(player, text, rarity)
--   rarity ∈ "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	return
end

local playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
if not playerGui then
	return
end

-- Wait up to 5s for Remotes.Notify; bail gracefully if it never appears.
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if not Remotes then
	return
end
local NotifyEvent = Remotes:WaitForChild("Notify", 5)
if not NotifyEvent then
	return
end

-- ─────────────────────────────────────────────────────────────────────────
-- Tunables
-- ─────────────────────────────────────────────────────────────────────────

local SUPPRESS_WINDOW   = 1.5      -- seconds — duplicate text inside this window is dropped (low-rarity only)
local RING_BUFFER_SIZE  = 10
local BANNER_HOLD       = 2.0      -- seconds the banner is fully opaque
local BANNER_FADE       = 0.5      -- seconds to fade out
local BANNER_RISE       = 0.25     -- seconds to fade in / slide down
local BANNER_WIDTH      = 600
local BANNER_HEIGHT     = 80
local BANNER_TOP_OFFSET = 110      -- px below the top edge for the first banner
local BANNER_STACK_GAP  = 90       -- px between stacked banners
local MAX_BANNERS       = 3
local FLASH_FADE        = 0.55
local CAMERA_BUMP_BINDING_NAME = "NotifyManagerRarityCameraBump"

local RARITY_BORDER_COLOR = {
	Legendary = Color3.fromRGB(255, 195, 60),   -- warm gold
	Mythic    = Color3.fromRGB(220, 50, 80),    -- ruby
}

local RARITY_TEXT_COLOR = {
	Legendary = Color3.fromRGB(255, 230, 150),
	Mythic    = Color3.fromRGB(255, 210, 220),
}

local IMPORTANT_RARITIES = {
	Legendary = true,
	Mythic    = true,
}

local RARITY_FLASH = {
	Legendary = {
		color = Color3.fromRGB(255, 210, 70),
		startTransparency = 0.42,
		gradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 235, 150)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 180, 40)),
		}),
	},
	Mythic = {
		color = Color3.fromRGB(255, 80, 45),
		startTransparency = 0.28,
		gradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 55, 45)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 185, 55)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 20, 60)),
		}),
	},
}

local RARITY_CAMERA_BUMP = {
	Legendary = {
		duration = 0.16,
		positionStrength = 0.045,
		rotationStrength = 0.16,
	},
	Mythic = {
		duration = 0.20,
		positionStrength = 0.075,
		rotationStrength = 0.26,
	},
}

-- ─────────────────────────────────────────────────────────────────────────
-- Ring buffer for duplicate suppression
-- ─────────────────────────────────────────────────────────────────────────

local ringBuffer = {}   -- list of { text = string, rarity = string, t = number }
local ringIndex  = 0    -- monotonic write pointer

local function pushRing(text, rarity, t)
	ringIndex = (ringIndex % RING_BUFFER_SIZE) + 1
	ringBuffer[ringIndex] = { text = text, rarity = rarity, t = t }
end

local function isRecentDuplicate(text, now)
	for _, entry in pairs(ringBuffer) do
		if entry and entry.text == text and (now - entry.t) <= SUPPRESS_WINDOW then
			return true
		end
	end
	return false
end

-- ─────────────────────────────────────────────────────────────────────────
-- Banner ScreenGui (lazy-created on first qualifying notify)
-- ─────────────────────────────────────────────────────────────────────────

local bannerGui = nil
local flashFrame = nil
local flashTween = nil
local activeBanners = {}   -- ordered oldest→newest list of banner Frames
local cameraBumpSequence = 0
local cameraBumpState = nil
local cameraBumpBaseCFrame = nil
local cameraBumpBound = false

local function ensureBannerGui()
	if bannerGui and bannerGui.Parent then
		return bannerGui
	end

	bannerGui = Instance.new("ScreenGui")
	bannerGui.Name = "ImportantNotifyBanners"
	bannerGui.ResetOnSpawn = false
	bannerGui.IgnoreGuiInset = true
	bannerGui.DisplayOrder = 100
	bannerGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	bannerGui.Parent = playerGui
	return bannerGui
end

local function ensureFlashFrame()
	local gui = ensureBannerGui()
	if flashFrame and flashFrame.Parent == gui then
		return flashFrame
	end

	flashFrame = gui:FindFirstChild("RarityFlash")
	if not flashFrame then
		flashFrame = Instance.new("Frame")
		flashFrame.Name = "RarityFlash"
		flashFrame.Parent = gui
	end

	flashFrame.Active = false
	flashFrame.AnchorPoint = Vector2.new(0, 0)
	flashFrame.Position = UDim2.new(0, 0, 0, 0)
	flashFrame.Size = UDim2.fromScale(1, 1)
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.Visible = false
	flashFrame.ZIndex = 100

	local gradient = flashFrame:FindFirstChild("RarityFlashGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Name = "RarityFlashGradient"
		gradient.Parent = flashFrame
	end
	gradient.Rotation = 25

	return flashFrame
end

local function clearRarityCameraBump(sequence)
	if sequence and cameraBumpState and sequence ~= cameraBumpState.sequence then
		return
	end

	local camera = workspace.CurrentCamera
	if camera and cameraBumpBaseCFrame then
		camera.CFrame = cameraBumpBaseCFrame
	end

	cameraBumpState = nil
	cameraBumpBaseCFrame = nil

	if cameraBumpBound then
		RunService:UnbindFromRenderStep(CAMERA_BUMP_BINDING_NAME)
		cameraBumpBound = false
	end
end

local function playRarityCameraBump(rarity)
	local bumpConfig = RARITY_CAMERA_BUMP[rarity]
	if not bumpConfig then
		return
	end

	cameraBumpSequence = cameraBumpSequence + 1
	local sequence = cameraBumpSequence
	clearRarityCameraBump()

	cameraBumpState = {
		sequence = sequence,
		startTime = os.clock(),
		duration = bumpConfig.duration,
		positionStrength = bumpConfig.positionStrength,
		rotationStrength = bumpConfig.rotationStrength,
	}

	if cameraBumpBound then
		return
	end

	cameraBumpBound = true
	RunService:BindToRenderStep(CAMERA_BUMP_BINDING_NAME, Enum.RenderPriority.Camera.Value + 2, function()
		local camera = workspace.CurrentCamera
		local state = cameraBumpState

		if not camera or not state then
			clearRarityCameraBump()
			return
		end

		local elapsed = os.clock() - state.startTime
		local progress = elapsed / state.duration
		if progress >= 1 then
			cameraBumpBaseCFrame = camera.CFrame
			clearRarityCameraBump(state.sequence)
			return
		end

		local clampedProgress = math.clamp(progress, 0, 1)
		local falloff = 1 - clampedProgress
		local impulse = math.sin(clampedProgress * math.pi * 2) * falloff
		local lift = math.sin(clampedProgress * math.pi) * falloff
		local positionOffset = Vector3.new(
			0,
			state.positionStrength * 0.18 * lift,
			state.positionStrength * impulse
		)
		local rotationScale = math.rad(state.rotationStrength)
		local rotationOffset = CFrame.Angles(
			-impulse * rotationScale,
			0,
			impulse * rotationScale * 0.45
		)

		cameraBumpBaseCFrame = camera.CFrame
		camera.CFrame = cameraBumpBaseCFrame * CFrame.new(positionOffset) * rotationOffset
	end)
end

local function playRarityFlash(rarity)
	local flashConfig = RARITY_FLASH[rarity]
	if not flashConfig then
		return
	end

	local frame = ensureFlashFrame()
	local gradient = frame:FindFirstChild("RarityFlashGradient")
	if flashTween then
		flashTween:Cancel()
		flashTween = nil
	end

	frame.BackgroundColor3 = flashConfig.color
	frame.BackgroundTransparency = flashConfig.startTransparency
	frame.Visible = true
	if gradient then
		gradient.Color = flashConfig.gradient
	end

	local tween = TweenService:Create(
		frame,
		TweenInfo.new(FLASH_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	flashTween = tween
	tween.Completed:Connect(function(playbackState)
		if flashTween == tween and playbackState == Enum.PlaybackState.Completed then
			frame.Visible = false
			flashTween = nil
		end
	end)
	tween:Play()
	playRarityCameraBump(rarity)
end

local function targetYForSlot(slotIndex)
	-- slotIndex 1 == topmost, 2 below, 3 below that
	return BANNER_TOP_OFFSET + (slotIndex - 1) * BANNER_STACK_GAP
end

local function reflowBanners()
	for slot, frame in ipairs(activeBanners) do
		if frame and frame.Parent then
			local goalY = targetYForSlot(slot)
			local tween = TweenService:Create(
				frame,
				TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = UDim2.new(0.5, 0, 0, goalY) }
			)
			tween:Play()
		end
	end
end

local function destroyBanner(frame)
	for i, f in ipairs(activeBanners) do
		if f == frame then
			table.remove(activeBanners, i)
			break
		end
	end
	if frame and frame.Parent then
		frame:Destroy()
	end
	reflowBanners()
end

local function fadeAndDestroy(frame, stroke, label, shadow, star)
	if not frame or not frame.Parent then
		return
	end
	local fadeInfo = TweenInfo.new(BANNER_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(frame,  fadeInfo, { BackgroundTransparency = 1 }):Play()
	if stroke then
		TweenService:Create(stroke, fadeInfo, { Transparency = 1 }):Play()
	end
	if label then
		TweenService:Create(label,  fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end
	if shadow then
		TweenService:Create(shadow, fadeInfo, { TextTransparency = 1 }):Play()
	end
	if star then
		TweenService:Create(star,   fadeInfo, { TextTransparency = 1 }):Play()
	end
	task.delay(BANNER_FADE + 0.05, function()
		destroyBanner(frame)
	end)
end

local function createBanner(text, rarity)
	local gui = ensureBannerGui()

	-- Cap concurrent banners — drop the oldest if we're at capacity.
	if #activeBanners >= MAX_BANNERS then
		local oldest = activeBanners[1]
		if oldest and oldest.Parent then
			oldest:Destroy()
		end
		table.remove(activeBanners, 1)
	end

	local borderColor = RARITY_BORDER_COLOR[rarity] or Color3.fromRGB(255, 255, 255)
	local textColor   = RARITY_TEXT_COLOR[rarity]   or Color3.fromRGB(255, 255, 255)

	local frame = Instance.new("Frame")
	frame.Name = "Banner_" .. rarity
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Size = UDim2.new(0, BANNER_WIDTH, 0, BANNER_HEIGHT)
	frame.BackgroundColor3 = Color3.fromRGB(18, 16, 22)
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.ZIndex = 110

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = borderColor
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	-- Drop-shadow text (offset behind the main label)
	local shadow = Instance.new("TextLabel")
	shadow.Name = "Shadow"
	shadow.Size = UDim2.new(1, -80, 1, 0)
	shadow.Position = UDim2.new(0, 62, 0, 3)
	shadow.BackgroundTransparency = 1
	shadow.Text = text
	shadow.TextColor3 = Color3.fromRGB(0, 0, 0)
	shadow.TextTransparency = 0.45
	shadow.Font = Enum.Font.GothamBold
	shadow.TextSize = 26
	shadow.TextXAlignment = Enum.TextXAlignment.Left
	shadow.TextYAlignment = Enum.TextYAlignment.Center
	shadow.TextWrapped = true
	shadow.ZIndex = 111
	shadow.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -80, 1, 0)
	label.Position = UDim2.new(0, 60, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = textColor
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.4
	label.Font = Enum.Font.GothamBold
	label.TextSize = 26
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = true
	label.ZIndex = 112
	label.Parent = frame

	-- Rotating star on the left side
	local star = Instance.new("TextLabel")
	star.Name = "Star"
	star.Size = UDim2.new(0, 50, 0, 50)
	star.Position = UDim2.new(0, 8, 0.5, -25)
	star.AnchorPoint = Vector2.new(0, 0)
	star.BackgroundTransparency = 1
	star.Text = "★"
	star.TextColor3 = borderColor
	star.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	star.TextStrokeTransparency = 0.3
	star.Font = Enum.Font.GothamBlack
	star.TextSize = 38
	star.TextXAlignment = Enum.TextXAlignment.Center
	star.TextYAlignment = Enum.TextYAlignment.Center
	star.ZIndex = 113
	star.Parent = frame

	-- Rotation pivot for the star
	local rotateContainer = Instance.new("Frame")
	rotateContainer.Name = "StarRot"
	rotateContainer.Size = UDim2.new(0, 50, 0, 50)
	rotateContainer.Position = UDim2.new(0, 8, 0.5, -25)
	rotateContainer.BackgroundTransparency = 1
	rotateContainer.BorderSizePixel = 0
	rotateContainer.ZIndex = 113
	rotateContainer.Parent = frame
	-- Move the star into the rotating container
	star.Parent = rotateContainer
	star.Position = UDim2.new(0, 0, 0, 0)
	star.Size = UDim2.new(1, 0, 1, 0)

	frame.Parent = gui

	-- Slot in
	table.insert(activeBanners, frame)
	local slot = #activeBanners
	local startY = targetYForSlot(slot) - 20
	frame.Position = UDim2.new(0.5, 0, 0, startY)
	frame.BackgroundTransparency = 1
	stroke.Transparency = 1
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	shadow.TextTransparency = 1
	star.TextTransparency = 1
	star.TextStrokeTransparency = 1

	local riseInfo = TweenInfo.new(BANNER_RISE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(frame,  riseInfo, {
		BackgroundTransparency = 0.05,
		Position = UDim2.new(0.5, 0, 0, targetYForSlot(slot)),
	}):Play()
	TweenService:Create(stroke, riseInfo, { Transparency = 0 }):Play()
	TweenService:Create(label,  riseInfo, { TextTransparency = 0, TextStrokeTransparency = 0.4 }):Play()
	TweenService:Create(shadow, riseInfo, { TextTransparency = 0.45 }):Play()
	TweenService:Create(star,   riseInfo, { TextTransparency = 0, TextStrokeTransparency = 0.3 }):Play()

	-- Star rotation loop (cancelled when frame is destroyed)
	local rotConn
	local angle = 0
	rotConn = RunService.Heartbeat:Connect(function(dt)
		if not rotateContainer.Parent then
			if rotConn then
				rotConn:Disconnect()
			end
			return
		end
		angle = (angle + dt * 90) % 360 -- 90°/s
		rotateContainer.Rotation = angle
	end)

	-- Hold then fade
	task.delay(BANNER_HOLD, function()
		if rotConn then
			rotConn:Disconnect()
		end
		fadeAndDestroy(frame, stroke, label, shadow, star)
	end)

	reflowBanners()
end

-- ─────────────────────────────────────────────────────────────────────────
-- Notify handler
-- ─────────────────────────────────────────────────────────────────────────

local function onNotify(text, rarity)
	if typeof(text) ~= "string" then
		return
	end
	rarity = rarity or "Common"
	if typeof(rarity) ~= "string" then
		rarity = "Common"
	end

	local now = os.clock()
	local important = IMPORTANT_RARITIES[rarity] == true

	-- Suppression: only for non-important rarities. Important rarities ALWAYS render.
	if not important and isRecentDuplicate(text, now) then
		-- Still record it so we keep tracking the burst.
		pushRing(text, rarity, now)
		return
	end

	pushRing(text, rarity, now)

	if important then
		-- Wrap in pcall so a malformed notify cannot break the listener.
		local flashOk, flashErr = pcall(playRarityFlash, rarity)
		if not flashOk then
			warn("[NotifyManager] rarity flash failed: " .. tostring(flashErr))
		end
		local ok, err = pcall(createBanner, text, rarity)
		if not ok then
			warn("[NotifyManager] banner render failed: " .. tostring(err))
		end
	end
end

NotifyEvent.OnClientEvent:Connect(onNotify)
