-- DigSystem.server.lua — Block generation, breaking, and terrain
-- Place in: ServerScriptService/DigSystem (Script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

-- ═══════════════════════════════════════════════════════════════════
-- Dig Site Generation
-- ═══════════════════════════════════════════════════════════════════

local digSiteFolder = Instance.new("Folder")
digSiteFolder.Name = "DigSite"
digSiteFolder.Parent = workspace

local blockGrid = {} -- [x][z][y] = Part

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

	-- Spawn platform above the dig site
	local platform = Instance.new("Part")
	platform.Name = "SpawnPlatform"
	platform.Size = Vector3.new(siteSize + 20, 2, siteSize + 20)
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

-- Spawn a satisfying poof: bright flash + a few falling shards that fade.
local function spawnBreakVFX(blockPos, blockColor)
	-- Central flash: scales up briefly then fades.
	local flash = Instance.new("Part")
	flash.Size = Vector3.new(0.5, 0.5, 0.5)
	flash.CFrame = CFrame.new(blockPos)
	flash.Anchored = true
	flash.CanCollide = false
	flash.Material = Enum.Material.Neon
	flash.Color = blockColor
	flash.Transparency = 0.2
	flash.Parent = workspace

	TweenService:Create(flash, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(Config.BLOCK_SIZE * 1.6, Config.BLOCK_SIZE * 1.6, Config.BLOCK_SIZE * 1.6),
		Transparency = 1,
	}):Play()
	Debris:AddItem(flash, 0.25)

	-- Shards: 5 small bits flying outward + falling under gravity.
	for i = 1, 5 do
		local shard = Instance.new("Part")
		local s = 0.5 + math.random() * 0.5
		shard.Size = Vector3.new(s, s, s)
		shard.CFrame = CFrame.new(blockPos)
		shard.Anchored = false
		shard.CanCollide = false
		shard.Material = Enum.Material.Slate
		shard.Color = blockColor
		shard.Velocity = Vector3.new(
			(math.random() - 0.5) * 30,
			15 + math.random() * 10,
			(math.random() - 0.5) * 30
		)
		shard.RotVelocity = Vector3.new(math.random() * 12, math.random() * 12, math.random() * 12)
		shard.Parent = workspace

		TweenService:Create(shard, TweenInfo.new(0.55, Enum.EasingStyle.Linear), {
			Transparency = 1,
		}):Play()
		Debris:AddItem(shard, 0.6)
	end
end

local DIG_RANGE_STUDS = 60 -- conservative; tune later

local function breakBlock(player, block)
	if not block then return end
	if not block:GetAttribute("Depth") then return end
	if not block:IsDescendantOf(digSiteFolder) then return end

	-- Range check: prevent click-anywhere exploits.
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and (hrp.Position - block.Position).Magnitude > DIG_RANGE_STUDS then
		return
	end

	local gridX = block:GetAttribute("GridX")
	local gridZ = block:GetAttribute("GridZ")
	local depthBlock = block:GetAttribute("Depth")

	spawnBreakVFX(block.Position, block.Color)

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
end

-- ═══════════════════════════════════════════════════════════════════
-- Tool System — Click to Dig
-- ═══════════════════════════════════════════════════════════════════

-- Give each player a dig tool on join
local function giveTool(player)
	local character = player.Character or player.CharacterAdded:Wait()

	local tool = Instance.new("Tool")
	tool.Name = "Excavator"
	tool.RequiresHandle = true
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 4)
	handle.Color = Color3.fromRGB(139, 90, 43)
	handle.Material = Enum.Material.Wood
	handle.Parent = tool

	tool.Parent = player.Backpack
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
		if not block or not block:IsA("BasePart") then return end
		if not block:GetAttribute("Depth") then return end
		if not block:IsDescendantOf(digSiteFolder) then return end

		breakBlock(player, block)
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
setupDigRemote()
print("[DeepDig] DigSystem loaded")
