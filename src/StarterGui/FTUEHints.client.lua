-- FTUEHints.client.lua — First-time user experience
-- Place in: StarterGui/FTUEHints (LocalScript)
--
-- Two phases:
--   1. Objective tracker (new players, shown IMMEDIATELY on spawn): a small
--      checklist card teaching the core loop — dig 5 blocks, sell your finds,
--      upgrade your tool. Steps tick live off UpdateHUD payloads.
--   2. Spotlight tour of the advanced panels (Pets, Quests, Stats,
--      Leaderboard, Trade) with dim overlay + cutout — runs after the
--      checklist completes (or after a short delay for returning players).
--
-- Tour completion/skip is persisted through server-owned player data.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- ═══════════════════════════════════════════════════════════════════
-- Config
-- ═══════════════════════════════════════════════════════════════════

local TOUR_ONLY_DELAY_SECONDS = 12 -- returning players: tour after a short settle
local NEW_PLAYER_MAX_BLOCKS = 30   -- at most this many lifetime digs = "new"
local DIG_STEP_GOAL = 5
local INTER_HINT_PAUSE_SECONDS = 0.5
local OVERLAY_FADE_SECONDS = 0.35
local DIM_TRANSPARENCY = 0.3 -- 70% opacity dim (0 = opaque, 1 = clear)

-- Tour hints, in order. Position is the approximate panel button corner used
-- to place the spotlight cutout. The actual cutout box is loose (~±20px).
local HINTS = {
	{
		title = "🐾 Pets",
		text = "Hatch pets to boost your dig power!",
		-- bottom-left
		buttonPos = UDim2.new(0, 20, 1, -60),
		buttonSize = UDim2.new(0, 110, 0, 50),
		anchorPoint = Vector2.new(0, 1),
		bubbleAnchor = "center",
	},
	{
		title = "Quests",
		text = "Daily quests reward coins and fragments.",
		-- bottom-right
		buttonPos = UDim2.new(1, -130, 1, -60),
		buttonSize = UDim2.new(0, 110, 0, 50),
		anchorPoint = Vector2.new(0, 1),
		bubbleAnchor = "center",
	},
	{
		title = "📊 Stats",
		text = "Track your progress and collection.",
		-- top-right
		buttonPos = UDim2.new(1, -130, 0, 20),
		buttonSize = UDim2.new(0, 110, 0, 40),
		anchorPoint = Vector2.new(0, 0),
		bubbleAnchor = "center",
	},
	{
		title = "🏆 Leaderboard",
		text = "See where you rank globally.",
		-- top-right, below stats
		buttonPos = UDim2.new(1, -130, 0, 70),
		buttonSize = UDim2.new(0, 110, 0, 40),
		anchorPoint = Vector2.new(0, 0),
		bubbleAnchor = "center",
	},
	{
		title = "🤝 Trade",
		text = "Trade items with other players (must be near them).",
		-- right side, vertical middle
		buttonPos = UDim2.new(1, -130, 0.5, -20),
		buttonSize = UDim2.new(0, 110, 0, 40),
		anchorPoint = Vector2.new(0, 0),
		bubbleAnchor = "center",
	},
}

-- ═══════════════════════════════════════════════════════════════════
-- Helpers + early-outs
-- ═══════════════════════════════════════════════════════════════════

local function safeGetAttribute(name)
	local ok, value = pcall(function()
		return player:GetAttribute(name)
	end)
	if ok then
		return value
	end
	return nil
end

local function safeSetAttribute(name, value)
	pcall(function()
		player:SetAttribute(name, value)
	end)
end

local function waitForChildTimeout(parent, childName, timeoutSeconds)
	if not parent then return nil end
	return parent:WaitForChild(childName, timeoutSeconds or 5)
end

local Remotes = waitForChildTimeout(ReplicatedStorage, "Remotes", 10)
local GetPlayerDataFunction = Remotes and waitForChildTimeout(Remotes, "GetPlayerData", 10)
local MarkFTUEHintsSeenEvent = Remotes and waitForChildTimeout(Remotes, "MarkFTUEHintsSeen", 10)
local UpdateHUDEvent = Remotes and waitForChildTimeout(Remotes, "UpdateHUD", 10)

local function fetchPlayerDataSnapshot()
	if not GetPlayerDataFunction then
		return nil
	end

	local ok, result = pcall(function()
		return GetPlayerDataFunction:InvokeServer()
	end)

	if ok and type(result) == "table" then
		return result
	end

	return nil
end

local function markFTUEHintsSeen()
	if MarkFTUEHintsSeenEvent then
		MarkFTUEHintsSeenEvent:FireServer()
	end
end

if safeGetAttribute("FTUE_HintsShown") then
	return
end

if not (GetPlayerDataFunction and MarkFTUEHintsSeenEvent) then
	return
end

if not player.Character then
	player.CharacterAdded:Wait()
end

-- Snapshot may not be loaded yet right after spawn; retry briefly.
local playerData = fetchPlayerDataSnapshot()
for _ = 1, 10 do
	if playerData then break end
	task.wait(1)
	playerData = fetchPlayerDataSnapshot()
end
if not playerData then
	return
end

if playerData.ftueHintsSeen == true then
	safeSetAttribute("FTUE_HintsShown", true)
	return
end

local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════════════
-- Phase 1: Objective tracker (new players only)
-- ═══════════════════════════════════════════════════════════════════

local function runObjectiveTracker()
	local digBaseline = playerData.totalBlocksDug or 0
	local digGoal = digBaseline + DIG_STEP_GOAL

	local steps = {
		{ icon = "⛏", text = "Dig " .. DIG_STEP_GOAL .. " blocks", done = false, progress = 0 },
		{ icon = "💰", text = "Sell your finds (Sell All button)", done = false },
		{ icon = "⬆", text = "Upgrade your tool", done = (playerData.toolTier or 1) >= 2 },
	}

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DeepDigObjectives"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 900
	screenGui.Parent = playerGui

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 10)
	card.Size = UDim2.fromOffset(330, 138)
	card.BackgroundColor3 = Color3.fromRGB(30, 32, 40)
	card.BackgroundTransparency = 0.12
	card.BorderSizePixel = 0
	card.Parent = screenGui

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 10)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Thickness = 2
	cardStroke.Color = Color3.fromRGB(255, 220, 80)
	cardStroke.Transparency = 0.3
	cardStroke.Parent = card

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -20, 0, 28)
	title.Position = UDim2.new(0, 10, 0, 6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = Color3.fromRGB(255, 220, 80)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "GETTING STARTED"
	title.Parent = card

	local rows = {}
	for i, step in ipairs(steps) do
		local row = Instance.new("TextLabel")
		row.Name = "Step" .. i
		row.Size = UDim2.new(1, -20, 0, 26)
		row.Position = UDim2.new(0, 10, 0, 30 + (i - 1) * 28)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.Gotham
		row.TextSize = 16
		row.TextColor3 = Color3.fromRGB(225, 225, 235)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Text = ""
		row.Parent = card
		rows[i] = row
	end

	local function renderRow(i)
		local step = steps[i]
		local row = rows[i]
		if step.done then
			row.Text = "✅ " .. step.icon .. " " .. step.text
			row.TextColor3 = Color3.fromRGB(130, 230, 140)
		else
			local suffix = ""
			if i == 1 then
				suffix = string.format(" (%d/%d)", step.progress, DIG_STEP_GOAL)
			end
			row.Text = "⬜ " .. step.icon .. " " .. step.text .. suffix
			row.TextColor3 = Color3.fromRGB(225, 225, 235)
		end
	end

	local function completeStep(i)
		if steps[i].done then
			return
		end
		steps[i].done = true
		renderRow(i)
		-- Brief green pulse on the card stroke for feedback
		cardStroke.Color = Color3.fromRGB(130, 230, 140)
		TweenService:Create(cardStroke, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Color = Color3.fromRGB(255, 220, 80),
		}):Play()
	end

	for i in ipairs(steps) do
		renderRow(i)
	end

	local allDoneEvent = Instance.new("BindableEvent")

	local function checkAllDone()
		for _, step in ipairs(steps) do
			if not step.done then
				return
			end
		end
		allDoneEvent:Fire()
	end

	local hudConn
	if UpdateHUDEvent then
		hudConn = UpdateHUDEvent.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end

			if not steps[1].done and type(payload.blocksDug) == "number" then
				steps[1].progress = math.clamp(payload.blocksDug - digBaseline, 0, DIG_STEP_GOAL)
				if payload.blocksDug >= digGoal then
					completeStep(1)
				else
					renderRow(1)
				end
			end

			if not steps[2].done and (payload.sellAllSummary ~= nil or payload.soldItem == true) then
				completeStep(2)
			end

			if not steps[3].done and type(payload.toolTier) == "number" and payload.toolTier >= 2 then
				completeStep(3)
			end

			checkAllDone()
		end)
	end

	-- Also resolve immediately in case a step was already satisfied
	checkAllDone()

	-- Wait until all steps complete (or give up after 15 minutes so the
	-- listener doesn't live forever for a player who ignores it).
	local finished = false
	task.delay(15 * 60, function()
		if not finished then
			allDoneEvent:Fire()
		end
	end)
	allDoneEvent.Event:Wait()
	finished = true

	if hudConn then
		hudConn:Disconnect()
	end

	title.Text = "🎉 YOU'RE READY!"
	task.wait(2.5)

	TweenService:Create(card, TweenInfo.new(OVERLAY_FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	for _, child in ipairs(card:GetChildren()) do
		if child:IsA("TextLabel") then
			TweenService:Create(child, TweenInfo.new(OVERLAY_FADE_SECONDS), { TextTransparency = 1 }):Play()
		elseif child:IsA("UIStroke") then
			TweenService:Create(child, TweenInfo.new(OVERLAY_FADE_SECONDS), { Transparency = 1 }):Play()
		end
	end
	task.wait(OVERLAY_FADE_SECONDS + 0.05)
	screenGui:Destroy()
	allDoneEvent:Destroy()
end

-- ═══════════════════════════════════════════════════════════════════
-- Phase 2: Spotlight tour
-- ═══════════════════════════════════════════════════════════════════

local function runSpotlightTour()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DeepDigFTUE"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 1000
	screenGui.Parent = playerGui

	-- Dim overlay (full-screen). We draw a "hole" by stacking 4 darker
	-- Frames around the spotlight rect (top/bottom/left/right bands).
	local dimContainer = Instance.new("Frame")
	dimContainer.Name = "DimContainer"
	dimContainer.Size = UDim2.fromScale(1, 1)
	dimContainer.Position = UDim2.fromScale(0, 0)
	dimContainer.BackgroundTransparency = 1
	dimContainer.BorderSizePixel = 0
	dimContainer.Parent = screenGui

	local function makeBand(name)
		local band = Instance.new("Frame")
		band.Name = name
		band.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		band.BackgroundTransparency = 1 -- fade in later
		band.BorderSizePixel = 0
		band.Parent = dimContainer
		return band
	end

	local bandTop = makeBand("BandTop")
	local bandBottom = makeBand("BandBottom")
	local bandLeft = makeBand("BandLeft")
	local bandRight = makeBand("BandRight")

	-- Spotlight outline (for visual emphasis around the cutout)
	local spotlight = Instance.new("Frame")
	spotlight.Name = "Spotlight"
	spotlight.BackgroundTransparency = 1
	spotlight.BorderSizePixel = 0
	spotlight.Parent = screenGui

	local spotlightStroke = Instance.new("UIStroke")
	spotlightStroke.Thickness = 3
	spotlightStroke.Color = Color3.fromRGB(255, 220, 80)
	spotlightStroke.Transparency = 1
	spotlightStroke.Parent = spotlight

	local spotlightCorner = Instance.new("UICorner")
	spotlightCorner.CornerRadius = UDim.new(0, 8)
	spotlightCorner.Parent = spotlight

	-- Hint bubble (centered)
	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.AnchorPoint = Vector2.new(0.5, 0.5)
	bubble.Position = UDim2.fromScale(0.5, 0.5)
	bubble.Size = UDim2.fromOffset(420, 200)
	bubble.BackgroundColor3 = Color3.fromRGB(30, 32, 40)
	bubble.BackgroundTransparency = 0.05
	bubble.BorderSizePixel = 0
	bubble.Parent = screenGui

	local bubbleCorner = Instance.new("UICorner")
	bubbleCorner.CornerRadius = UDim.new(0, 12)
	bubbleCorner.Parent = bubble

	local bubbleStroke = Instance.new("UIStroke")
	bubbleStroke.Thickness = 2
	bubbleStroke.Color = Color3.fromRGB(255, 220, 80)
	bubbleStroke.Parent = bubble

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -24, 0, 36)
	titleLabel.Position = UDim2.new(0, 12, 0, 12)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 24
	titleLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = ""
	titleLabel.Parent = bubble

	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "Progress"
	progressLabel.Size = UDim2.new(0, 60, 0, 22)
	progressLabel.AnchorPoint = Vector2.new(1, 0)
	progressLabel.Position = UDim2.new(1, -12, 0, 14)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Font = Enum.Font.Gotham
	progressLabel.TextSize = 14
	progressLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
	progressLabel.TextXAlignment = Enum.TextXAlignment.Right
	progressLabel.Text = ""
	progressLabel.Parent = bubble

	local bodyLabel = Instance.new("TextLabel")
	bodyLabel.Name = "Body"
	bodyLabel.Size = UDim2.new(1, -24, 0, 90)
	bodyLabel.Position = UDim2.new(0, 12, 0, 54)
	bodyLabel.BackgroundTransparency = 1
	bodyLabel.Font = Enum.Font.Gotham
	bodyLabel.TextSize = 18
	bodyLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
	bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
	bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
	bodyLabel.TextWrapped = true
	bodyLabel.Text = ""
	bodyLabel.Parent = bubble

	local gotItButton = Instance.new("TextButton")
	gotItButton.Name = "GotIt"
	gotItButton.Size = UDim2.new(0, 140, 0, 38)
	gotItButton.AnchorPoint = Vector2.new(0.5, 1)
	gotItButton.Position = UDim2.new(0.5, 0, 1, -12)
	gotItButton.BackgroundColor3 = Color3.fromRGB(80, 180, 100)
	gotItButton.BorderSizePixel = 0
	gotItButton.AutoButtonColor = true
	gotItButton.Font = Enum.Font.GothamBold
	gotItButton.TextSize = 18
	gotItButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	gotItButton.Text = "Got it"
	gotItButton.Parent = bubble

	local gotItCorner = Instance.new("UICorner")
	gotItCorner.CornerRadius = UDim.new(0, 8)
	gotItCorner.Parent = gotItButton

	-- Skip-all button (top-right of screen)
	local skipButton = Instance.new("TextButton")
	skipButton.Name = "SkipAll"
	skipButton.Size = UDim2.new(0, 110, 0, 32)
	skipButton.AnchorPoint = Vector2.new(1, 0)
	skipButton.Position = UDim2.new(1, -16, 0, 16)
	skipButton.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	skipButton.BackgroundTransparency = 0.15
	skipButton.BorderSizePixel = 0
	skipButton.AutoButtonColor = true
	skipButton.Font = Enum.Font.Gotham
	skipButton.TextSize = 14
	skipButton.TextColor3 = Color3.fromRGB(220, 220, 230)
	skipButton.Text = "Skip all ✕"
	skipButton.Parent = screenGui

	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 6)
	skipCorner.Parent = skipButton

	-- ── Cutout placement ────────────────────────────────────────────

	local CUTOUT_PADDING = 20 -- ±20px loose box around the button

	-- Compute viewport-pixel rect (x, y, w, h) for a given hint button position.
	local function resolveButtonRect(hint)
		local cam = workspace.CurrentCamera
		local viewportSize = cam and cam.ViewportSize or Vector2.new(1280, 720)

		local pos = hint.buttonPos
		local size = hint.buttonSize
		local anchor = hint.anchorPoint or Vector2.new(0, 0)

		local px = pos.X.Scale * viewportSize.X + pos.X.Offset
		local py = pos.Y.Scale * viewportSize.Y + pos.Y.Offset
		local sx = size.X.Scale * viewportSize.X + size.X.Offset
		local sy = size.Y.Scale * viewportSize.Y + size.Y.Offset

		-- Adjust for anchor point (so we get the top-left of the rect)
		local left = px - sx * anchor.X
		local top = py - sy * anchor.Y

		-- Apply loose padding
		left = left - CUTOUT_PADDING
		top = top - CUTOUT_PADDING
		local width = sx + CUTOUT_PADDING * 2
		local height = sy + CUTOUT_PADDING * 2

		-- Clamp to viewport so bands don't go negative
		if left < 0 then
			width = width + left
			left = 0
		end
		if top < 0 then
			height = height + top
			top = 0
		end
		if left + width > viewportSize.X then
			width = viewportSize.X - left
		end
		if top + height > viewportSize.Y then
			height = viewportSize.Y - top
		end
		if width < 1 then
			width = 1
		end
		if height < 1 then
			height = 1
		end

		return left, top, width, height, viewportSize
	end

	local function placeCutout(hint)
		local left, top, width, height, viewportSize = resolveButtonRect(hint)

		-- Position spotlight outline directly over the cutout area
		spotlight.Position = UDim2.fromOffset(left, top)
		spotlight.Size = UDim2.fromOffset(width, height)

		-- Top band: from y=0 to y=top, full width
		bandTop.Position = UDim2.fromOffset(0, 0)
		bandTop.Size = UDim2.fromOffset(viewportSize.X, top)

		-- Bottom band: from y=top+height to viewport bottom
		bandBottom.Position = UDim2.fromOffset(0, top + height)
		bandBottom.Size = UDim2.fromOffset(viewportSize.X, viewportSize.Y - (top + height))

		-- Left band: x=0 to x=left, height of cutout
		bandLeft.Position = UDim2.fromOffset(0, top)
		bandLeft.Size = UDim2.fromOffset(left, height)

		-- Right band: x=left+width to viewport right
		bandRight.Position = UDim2.fromOffset(left + width, top)
		bandRight.Size = UDim2.fromOffset(viewportSize.X - (left + width), height)
	end

	-- ── Fade helpers ────────────────────────────────────────────────

	local function fadeBands(toTransparency)
		local info = TweenInfo.new(OVERLAY_FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, band in ipairs({ bandTop, bandBottom, bandLeft, bandRight }) do
			TweenService:Create(band, info, { BackgroundTransparency = toTransparency }):Play()
		end
		TweenService:Create(spotlightStroke, info, { Transparency = toTransparency == 1 and 1 or 0 }):Play()
	end

	-- ── Run the sequence ────────────────────────────────────────────

	local active = true
	local advanceEvent = Instance.new("BindableEvent")
	local skipped = false

	gotItButton.MouseButton1Click:Connect(function()
		advanceEvent:Fire("advance")
	end)

	skipButton.MouseButton1Click:Connect(function()
		skipped = true
		advanceEvent:Fire("skip")
	end)

	-- Allow Enter / Space to advance (keyboard accessibility)
	local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not active then
			return
		end
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.Space then
			advanceEvent:Fire("advance")
		elseif input.KeyCode == Enum.KeyCode.Escape then
			skipped = true
			advanceEvent:Fire("skip")
		end
	end)

	-- Keep cutout aligned if the viewport resizes mid-hint
	local currentHint = nil
	local cam = workspace.CurrentCamera
	local resizeConn
	if cam then
		resizeConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if currentHint and active then
				placeCutout(currentHint)
			end
		end)
	end

	local function showHint(index, hint)
		currentHint = hint
		titleLabel.Text = hint.title
		bodyLabel.Text = hint.text
		progressLabel.Text = string.format("%d / %d", index, #HINTS)
		placeCutout(hint)
		fadeBands(DIM_TRANSPARENCY)
	end

	local function clearAllFlags()
		for i = 1, #HINTS do
			safeSetAttribute("FTUE_HintsShown_" .. tostring(i), true)
		end
		safeSetAttribute("FTUE_HintsShown", true)
	end

	for index, hint in ipairs(HINTS) do
		if not active then
			break
		end

		showHint(index, hint)

		-- Wait for player to advance or skip
		local action = advanceEvent.Event:Wait()

		-- Mark this hint shown
		safeSetAttribute("FTUE_HintsShown_" .. tostring(index), true)

		if action == "skip" or skipped then
			break
		end

		-- Brief pause between hints
		if index < #HINTS then
			fadeBands(1)
			task.wait(INTER_HINT_PAUSE_SECONDS)
		end
	end

	-- ── Tear down ───────────────────────────────────────────────────

	active = false

	if skipped then
		clearAllFlags()
	else
		safeSetAttribute("FTUE_HintsShown", true)
	end
	markFTUEHintsSeen()

	if inputConn then
		inputConn:Disconnect()
	end
	if resizeConn then
		resizeConn:Disconnect()
	end

	-- Fade out and destroy
	fadeBands(1)
	task.wait(OVERLAY_FADE_SECONDS + 0.05)
	screenGui:Destroy()
	advanceEvent:Destroy()
end

-- ═══════════════════════════════════════════════════════════════════
-- Sequence
-- ═══════════════════════════════════════════════════════════════════

local isNewPlayer = (playerData.totalBlocksDug or 0) <= NEW_PLAYER_MAX_BLOCKS

if isNewPlayer then
	runObjectiveTracker()
	task.wait(0.8)
else
	task.wait(TOUR_ONLY_DELAY_SECONDS)
end

-- Re-check — another path may have set the flag while we waited.
if safeGetAttribute("FTUE_HintsShown") then
	return
end

runSpotlightTour()
