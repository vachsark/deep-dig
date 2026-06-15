-- DigSystem.server.lua — Block generation, breaking, and terrain
-- Place in: ServerScriptService/DigSystem (Script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local PetDatabase = require(ReplicatedStorage:WaitForChild("PetDatabase"))

local EXCAVATOR_TOOL_NAME = "Excavator"
local REFRESH_EXCAVATOR_VISUAL_EVENT_NAME = "RefreshExcavatorVisual"

local function getData(player)
	return _G.DeepDig_playerData and _G.DeepDig_playerData[player.UserId]
end

local function getEquippedPetDigSpeed(data)
	if not data or not data.equippedPet or not data.pets then
		return 1
	end

	for _, record in ipairs(data.pets) do
		if type(record) == "table" and record.id == data.equippedPet then
			local multipliers = type(record.multipliers) == "table" and record.multipliers
			if not multipliers then
				local petDef = PetDatabase.getPet(record.name)
				multipliers = petDef and petDef.multipliers
			end

			local digSpeed = multipliers and multipliers.dig_speed
			if type(digSpeed) ~= "number" then
				return 1
			end

			return math.min(digSpeed, 5)
		end
	end

	return 1
end

local function getFriendDigSpeed(player)
	local getMultiplier = _G.DeepDig_getFriendDigSpeedMultiplier
	if type(getMultiplier) ~= "function" then
		return 1
	end

	local success, multiplier = pcall(getMultiplier, player)
	if not success or type(multiplier) ~= "number" then
		return 1
	end

	return math.clamp(multiplier, 1, 2)
end

local function getDigInterval(player)
	local data = getData(player)
	local tool = data and Config.TOOLS[data.toolTier]
	local baseInterval = (tool and tool.speed) or 1
	local petDigSpeed = getEquippedPetDigSpeed(data)
	local friendDigSpeed = getFriendDigSpeed(player)

	return baseInterval / (petDigSpeed * friendDigSpeed)
end

local function isWorldEventEffectActive(effectName)
	local isActive = _G.DeepDig_isWorldEventEffectActive
	if type(isActive) ~= "function" then
		return false
	end

	local success, active = pcall(isActive, effectName)
	return success and active == true
end

-- ═══════════════════════════════════════════════════════════════════
-- Dig Site Generation
-- ═══════════════════════════════════════════════════════════════════

local digSiteFolder = Instance.new("Folder")
digSiteFolder.Name = "DigSite"
digSiteFolder.Parent = workspace

local blockGrid = {} -- [x][z][y] = Part
local digCooldownByUserId = {}
local enemyBlockedNotifyByUserId = {}
local BLOCKED_DIG_ENEMY_RANGE_STUDS = 16
local BLOCKED_DIG_NOTIFY_COOLDOWN = 2.5

local function getTierForDepth(depthBlocks)
	for _, tier in ipairs(Config.TIERS) do
		if depthBlocks >= tier.minDepth and depthBlocks <= tier.maxDepth then
			return tier
		end
	end
	return Config.TIERS[#Config.TIERS]
end

local function createBlock(gridX, gridZ, depthBlock)
	local tier = getTierForDepth(depthBlock)
	local size = Config.BLOCK_SIZE

	local block = Instance.new("Part")
	block.Name = "Block_" .. gridX .. "_" .. gridZ .. "_" .. depthBlock
	block.Size = Vector3.new(size, size, size)
	block.Position = Vector3.new(
		gridX * size - (Config.GRID_WIDTH * size / 2),
		-depthBlock * size,
		gridZ * size - (Config.GRID_WIDTH * size / 2)
	)
	block.Anchored = true
	block.Material = Enum.Material.Ground
	block.Color = tier.color

	-- Slight color variation for visual interest
	local r = (math.random() - 0.5) * 0.05
	block.Color = Color3.new(
		math.clamp(tier.color.R + r, 0, 1),
		math.clamp(tier.color.G + r, 0, 1),
		math.clamp(tier.color.B + r, 0, 1)
	)

	-- Store grid position as attributes for click detection
	block:SetAttribute("GridX", gridX)
	block:SetAttribute("GridZ", gridZ)
	block:SetAttribute("Depth", depthBlock)
	block:SetAttribute("Health", 1)

	block.Parent = digSiteFolder

	-- Store reference
	if not blockGrid[gridX] then blockGrid[gridX] = {} end
	if not blockGrid[gridX][gridZ] then blockGrid[gridX][gridZ] = {} end
	blockGrid[gridX][gridZ][depthBlock] = block

	return block
end

-- Generate initial surface layer + a few layers deep
local function generateInitialTerrain()
	print("[DeepDig] Generating dig site...")
	local generated = 0
	local width = Config.GRID_WIDTH

	-- Generate top 5 layers to start
	for depthBlock = 0, 4 do
		for x = 0, width - 1 do
			for z = 0, width - 1 do
				createBlock(x, z, depthBlock)
				generated = generated + 1
			end
		end
	end

	-- Create border walls
	local wallHeight = 20
	local wallThickness = 2
	local siteSize = width * Config.BLOCK_SIZE
	local center = siteSize / 2

	for _, wallDef in ipairs({
		{ pos = Vector3.new(-center - wallThickness/2, -wallHeight/2, 0), size = Vector3.new(wallThickness, wallHeight * 2, siteSize + wallThickness * 2) },
		{ pos = Vector3.new(siteSize - center + wallThickness/2, -wallHeight/2, 0), size = Vector3.new(wallThickness, wallHeight * 2, siteSize + wallThickness * 2) },
		{ pos = Vector3.new(0, -wallHeight/2, -center - wallThickness/2), size = Vector3.new(siteSize + wallThickness * 2, wallHeight * 2, wallThickness) },
		{ pos = Vector3.new(0, -wallHeight/2, siteSize - center + wallThickness/2), size = Vector3.new(siteSize + wallThickness * 2, wallHeight * 2, wallThickness) },
	}) do
		local wall = Instance.new("Part")
		wall.Name = "Wall"
		wall.Size = wallDef.size
		wall.Position = wallDef.pos
		wall.Anchored = true
		wall.Material = Enum.Material.Rock
		wall.Color = Color3.fromRGB(60, 55, 50)
		wall.Transparency = 0.3
		wall.Parent = digSiteFolder
	end

	-- Spawn platform — small pad at center; sized so the dig site stays clickable.
	local platform = Instance.new("Part")
	platform.Name = "SpawnPlatform"
	platform.Size = Vector3.new(12, 2, 12)
	platform.Position = Vector3.new(0, 5, 0)
	platform.Anchored = true
	platform.Material = Enum.Material.SmoothPlastic
	platform.Color = Color3.fromRGB(80, 80, 80)
	platform.Parent = digSiteFolder

	-- Spawn location
	local spawn = Instance.new("SpawnLocation")
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = Vector3.new(0, 7, 0)
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Parent = digSiteFolder

	print("[DeepDig] Generated " .. generated .. " blocks, " .. width .. "x" .. width .. " grid")
end

-- ═══════════════════════════════════════════════════════════════════
-- Block Breaking
-- ═══════════════════════════════════════════════════════════════════

-- Reveal blocks below when a block is broken
local function revealBelow(gridX, gridZ, depthBlock)
	local nextDepth = depthBlock + 1
	if nextDepth > Config.GRID_DEPTH_BLOCKS then return end

	-- Only create if not already exists
	if blockGrid[gridX] and blockGrid[gridX][gridZ] and blockGrid[gridX][gridZ][nextDepth] then
		return
	end

	createBlock(gridX, gridZ, nextDepth)
end

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local COMBO_BREAK_ACCENT_COLOR = Color3.fromRGB(255, 174, 48)
local COMBO_BREAK_TOP_MULTIPLIER = 4.0

local function getComboBreakStrength(comboMultiplier)
	if type(comboMultiplier) ~= "number" or comboMultiplier <= 1 then
		return 0
	end

	return math.clamp((math.min(comboMultiplier, COMBO_BREAK_TOP_MULTIPLIER) - 1) / (COMBO_BREAK_TOP_MULTIPLIER - 1), 0, 1)
end

-- Spawn a satisfying poof: bright flash + a few falling shards that fade.
local function spawnBreakVFX(blockPos, blockColor, comboMultiplier)
	local comboStrength = getComboBreakStrength(comboMultiplier)
	local flashColor = blockColor
	local flashSizeMultiplier = 1.6
	local shardCount = 5
	local shardSpeedMultiplier = 1
	local shardSizeMultiplier = 1

	if comboStrength > 0 then
		flashColor = blockColor:Lerp(COMBO_BREAK_ACCENT_COLOR, math.clamp(0.28 + comboStrength * 0.42, 0, 0.75))
		flashSizeMultiplier = 1.6 + comboStrength * 0.9
		shardCount = 5 + math.floor(comboStrength * 7 + 0.5)
		shardSpeedMultiplier = 1 + comboStrength * 0.35
		shardSizeMultiplier = 1 + comboStrength * 0.25
	end

	-- Central flash: scales up briefly then fades.
	local flash = Instance.new("Part")
	flash.Size = Vector3.new(0.5, 0.5, 0.5)
	flash.CFrame = CFrame.new(blockPos)
	flash.Anchored = true
	flash.CanCollide = false
	flash.Material = Enum.Material.Neon
	flash.Color = flashColor
	flash.Transparency = 0.2
	flash.Parent = workspace

	TweenService:Create(flash, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(Config.BLOCK_SIZE * flashSizeMultiplier, Config.BLOCK_SIZE * flashSizeMultiplier, Config.BLOCK_SIZE * flashSizeMultiplier),
		Transparency = 1,
	}):Play()
	Debris:AddItem(flash, 0.25)

	-- Shards: 5 small bits flying outward + falling under gravity.
	for i = 1, shardCount do
		local shard = Instance.new("Part")
		local s = (0.5 + math.random() * 0.5) * shardSizeMultiplier
		local shardColor = blockColor
		if comboStrength > 0 then
			shardColor = blockColor:Lerp(COMBO_BREAK_ACCENT_COLOR, math.clamp(0.18 + comboStrength * 0.42 + math.random() * 0.12, 0, 0.75))
		end

		shard.Size = Vector3.new(s, s, s)
		shard.CFrame = CFrame.new(blockPos)
		shard.Anchored = false
		shard.CanCollide = false
		shard.Material = Enum.Material.Slate
		shard.Color = shardColor
		shard.Velocity = Vector3.new(
			(math.random() - 0.5) * 30 * shardSpeedMultiplier,
			15 + math.random() * 10 + comboStrength * 8,
			(math.random() - 0.5) * 30 * shardSpeedMultiplier
		)
		shard.RotVelocity = Vector3.new(math.random() * 12, math.random() * 12, math.random() * 12)
		shard.Parent = workspace

		TweenService:Create(shard, TweenInfo.new(0.55, Enum.EasingStyle.Linear), {
			Transparency = 1,
		}):Play()
		Debris:AddItem(shard, 0.6)
	end
end

local function spawnVolcanoVentBreakVFX(blockPos)
	local emitterPart = Instance.new("Part")
	emitterPart.Name = "VolcanoVentBreakVFX"
	emitterPart.Size = Vector3.new(0.2, 0.2, 0.2)
	emitterPart.CFrame = CFrame.new(blockPos)
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.CanTouch = false
	emitterPart.Transparency = 1
	emitterPart.Parent = workspace

	local embers = Instance.new("ParticleEmitter")
	embers.Name = "EmberBurst"
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 215, 70)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 88, 24)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 18, 0)),
	})
	embers.LightEmission = 0.9
	embers.Lifetime = NumberRange.new(0.32, 0.7)
	embers.Rate = 0
	embers.Speed = NumberRange.new(12, 28)
	embers.SpreadAngle = Vector2.new(180, 180)
	embers.Rotation = NumberRange.new(0, 360)
	embers.RotSpeed = NumberRange.new(-160, 160)
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(0.5, 0.22),
		NumberSequenceKeypoint.new(1, 0),
	})
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Acceleration = Vector3.new(0, 18, 0)
	embers.Drag = 5
	embers.Parent = emitterPart
	embers:Emit(24)

	for i = 1, 4 do
		local crack = Instance.new("Part")
		crack.Name = "VolcanoVentLavaCrack"
		crack.Size = Vector3.new(Config.BLOCK_SIZE * (0.45 + math.random() * 0.3), 0.08, 0.16)
		crack.CFrame = CFrame.new(blockPos + Vector3.new(0, 0.12, 0))
			* CFrame.Angles(0, math.rad((i - 1) * 45 + math.random(-12, 12)), 0)
		crack.Anchored = true
		crack.CanCollide = false
		crack.CanQuery = false
		crack.CanTouch = false
		crack.Material = Enum.Material.Neon
		crack.Color = Color3.fromRGB(255, math.random(45, 95), 8)
		crack.Transparency = 0.1
		crack.Parent = workspace

		TweenService:Create(crack, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(crack.Size.X * 1.2, 0.04, 0.05),
		}):Play()
		Debris:AddItem(crack, 0.45)
	end

	Debris:AddItem(emitterPart, 1)
end

local DIG_RANGE_STUDS = 60 -- conservative; tune later

local function isOwnedActiveLivingEnemy(player, model)
	if not model or not model:IsA("Model") then
		return false
	end
	if model:GetAttribute("OwnerUserId") ~= player.UserId then
		return false
	end
	if model:GetAttribute("IsEmerging") == true then
		return false
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	return true, root
end

local function hasBlockingEnemyNearDig(player, playerRoot, block)
	local enemiesFolder = workspace:FindFirstChild("Enemies")
	if not enemiesFolder then
		return false, nil
	end

	for _, enemyModel in ipairs(enemiesFolder:GetChildren()) do
		local isBlockingCandidate, enemyRoot = isOwnedActiveLivingEnemy(player, enemyModel)
		if isBlockingCandidate then
			local enemyPosition = enemyRoot.Position
			local nearPlayer = playerRoot and (enemyPosition - playerRoot.Position).Magnitude <= BLOCKED_DIG_ENEMY_RANGE_STUDS
			local nearBlock = (enemyPosition - block.Position).Magnitude <= BLOCKED_DIG_ENEMY_RANGE_STUDS
			if nearPlayer or nearBlock then
				return true, enemyModel
			end
		end
	end

	return false, nil
end

local function notifyDigBlockedByEnemy(player, blockingEnemyModel)
	local userId = player.UserId
	local now = os.clock()
	local nextNotifyAt = enemyBlockedNotifyByUserId[userId] or 0
	if now < nextNotifyAt then
		return
	end

	enemyBlockedNotifyByUserId[userId] = now + BLOCKED_DIG_NOTIFY_COOLDOWN

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local Notify = Remotes:FindFirstChild("Notify")
	if Notify then
		Notify:FireClient(player, "Defeat this enemy first before digging.", "Rare")
	end

	local EnemyCombatFeedback = Remotes:FindFirstChild("EnemyCombatFeedback")
	if EnemyCombatFeedback and blockingEnemyModel and blockingEnemyModel.Parent then
		EnemyCombatFeedback:FireClient(player, {
			type = "aggro",
			model = blockingEnemyModel,
		})
	else
		local PlaySound = Remotes:FindFirstChild("PlaySound")
		if PlaySound then
			PlaySound:FireClient(player, "enemy_aggro")
		end
	end
end

local function getChainComboMultiplier(player)
	local getMultiplier = _G.DeepDig_getChainComboMultiplier
	if type(getMultiplier) ~= "function" then
		return 1.0
	end

	local success, multiplier = pcall(getMultiplier, player)
	if not success or type(multiplier) ~= "number" then
		return 1.0
	end

	return math.clamp(multiplier, 1.0, COMBO_BREAK_TOP_MULTIPLIER)
end

local function breakBlock(player, block)
	if not block then return false end
	if not block:GetAttribute("Depth") then return false end
	if not block:IsDescendantOf(digSiteFolder) then return false end

	-- Range check: prevent click-anywhere exploits.
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and (hrp.Position - block.Position).Magnitude > DIG_RANGE_STUDS then
		return false
	end

	local hasBlockingEnemy, blockingEnemyModel = hasBlockingEnemyNearDig(player, hrp, block)
	if hasBlockingEnemy then
		notifyDigBlockedByEnemy(player, blockingEnemyModel)
		return false
	end

	local gridX = block:GetAttribute("GridX")
	local gridZ = block:GetAttribute("GridZ")
	local depthBlock = block:GetAttribute("Depth")
	local comboMultiplier = getChainComboMultiplier(player)

	spawnBreakVFX(block.Position, block.Color, comboMultiplier)
	if isWorldEventEffectActive("volcano_vent") then
		spawnVolcanoVentBreakVFX(block.Position)
	end

	-- Audio: AudioRouter creates the PlaySound RemoteEvent at game start.
	local PlaySound = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("PlaySound")
	if PlaySound then PlaySound:FireClient(player, "block_break") end

	-- Remove block from grid
	if blockGrid[gridX] and blockGrid[gridX][gridZ] then
		blockGrid[gridX][gridZ][depthBlock] = nil
	end

	block:Destroy()

	-- Reveal the block below
	revealBelow(gridX, gridZ, depthBlock)

	-- Fire DigBlock to GameManager for loot processing (server→server via BindableEvent)
	local ServerEvents = ReplicatedStorage:WaitForChild("ServerEvents")
	ServerEvents.BlockBroken:Fire(player, Vector3.new(gridX, -depthBlock * Config.BLOCK_SIZE, gridZ))

	return true
end

-- ═══════════════════════════════════════════════════════════════════
-- Tool System — Click to Dig
-- ═══════════════════════════════════════════════════════════════════

local function getPlayerToolConfig(player)
	local data = getData(player)
	local toolTier = data and data.toolTier or 1
	local toolConfig = Config.TOOLS[toolTier] or Config.TOOLS[1]

	return toolConfig, toolConfig.tier or toolTier
end

local function applyExcavatorVisual(tool, toolConfig)
	local fallbackVisual = Config.TOOLS[1] and Config.TOOLS[1].visual or {}
	local visual = (toolConfig and toolConfig.visual) or fallbackVisual
	local handle = tool:FindFirstChild("Handle")

	if not handle or not handle:IsA("BasePart") then
		if handle then
			handle:Destroy()
		end

		handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Parent = tool
	end

	tool.Name = EXCAVATOR_TOOL_NAME
	tool.ToolTip = toolConfig and toolConfig.name or "Rusty Shovel"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("ToolTier", toolConfig and toolConfig.tier or 1)
	tool:SetAttribute("ToolName", toolConfig and toolConfig.name or "Rusty Shovel")

	handle.Size = visual.handleSize or Vector3.new(1, 1, 4)
	handle.Color = visual.handleColor or Color3.fromRGB(139, 90, 43)
	handle.Material = visual.handleMaterial or Enum.Material.Wood
	handle.CanCollide = false
	handle.Massless = true
	handle:SetAttribute("ToolTier", toolConfig and toolConfig.tier or 1)
end

local function refreshExistingExcavators(player)
	local toolConfig = getPlayerToolConfig(player)
	local refreshedAny = false
	local containers = {}

	if player.Backpack then
		table.insert(containers, player.Backpack)
	end
	if player.Character then
		table.insert(containers, player.Character)
	end

	for _, container in ipairs(containers) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child.Name == EXCAVATOR_TOOL_NAME then
				applyExcavatorVisual(child, toolConfig)
				refreshedAny = true
			end
		end
	end

	return refreshedAny
end

local function createExcavator(player)
	local toolConfig = getPlayerToolConfig(player)
	local tool = Instance.new("Tool")

	applyExcavatorVisual(tool, toolConfig)

	return tool
end

local function waitForPlayerData(player, timeoutSeconds)
	local startedAt = os.clock()

	while player.Parent == Players and not getData(player) and os.clock() - startedAt < timeoutSeconds do
		task.wait(0.1)
	end
end

-- Give each player a dig tool on join
local function giveTool(player)
	local character = player.Character or player.CharacterAdded:Wait()
	if not character then return end
	waitForPlayerData(player, 5)

	if refreshExistingExcavators(player) then
		return
	end

	local tool = createExcavator(player)
	tool.Parent = player:WaitForChild("Backpack")
end

local function setupExcavatorRefreshEvents()
	task.spawn(function()
		local ServerEvents = ReplicatedStorage:WaitForChild("ServerEvents")
		local refreshEvent = ServerEvents:FindFirstChild(REFRESH_EXCAVATOR_VISUAL_EVENT_NAME)

		if not refreshEvent then
			refreshEvent = Instance.new("BindableEvent")
			refreshEvent.Name = REFRESH_EXCAVATOR_VISUAL_EVENT_NAME
			refreshEvent.Parent = ServerEvents
		end

		refreshEvent.Event:Connect(function(player)
			if player and player.Parent == Players then
				refreshExistingExcavators(player)
			end
		end)

		local playerDataReady = ServerEvents:WaitForChild("PlayerDataReady")
		playerDataReady.Event:Connect(function(player)
			if player and player.Parent == Players then
				refreshExistingExcavators(player)
			end
		end)
	end)
end

-- Listen for dig requests from client
local function setupDigRemote()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")

	-- Create the DigRequest remote for client→server block targeting
	local digRequest = Instance.new("RemoteEvent")
	digRequest.Name = "DigRequest"
	digRequest.Parent = Remotes

	digRequest.OnServerEvent:Connect(function(player, block)
		-- Validate the block is a real dig site block
		if not block or not block:IsA("BasePart") then
			return
		end
		if not block:GetAttribute("Depth") then
			return
		end
		if not block:IsDescendantOf(digSiteFolder) then
			return
		end

		local userId = player.UserId
		local now = os.clock()
		local nextAllowedDigAt = digCooldownByUserId[userId] or 0
		if now < nextAllowedDigAt then
			return
		end

		if breakBlock(player, block) then
			digCooldownByUserId[userId] = now + getDigInterval(player)
		end
	end)
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function()
		task.wait(1) -- Wait for character to fully load
		giveTool(player)
	end)
	-- Handle players already in-game when script loads (Studio playtest):
	-- if the character already exists, give the tool immediately.
	if player.Character then
		task.spawn(function()
			task.wait(1)
			giveTool(player)
		end)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	digCooldownByUserId[player.UserId] = nil
	enemyBlockedNotifyByUserId[player.UserId] = nil
end)

-- Handle players already in the game when the script loads (Studio playtest)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		onPlayerAdded(player)
	end)
end

-- ═══════════════════════════════════════════════════════════════════
-- Initialize
-- ═══════════════════════════════════════════════════════════════════

generateInitialTerrain()
setupExcavatorRefreshEvents()
setupDigRemote()
print("[DeepDig] DigSystem loaded")
