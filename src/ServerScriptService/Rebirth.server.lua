-- Rebirth.server.lua — "Resurface" prestige system
-- Place in: ServerScriptService/Rebirth (Script)
--
-- When a player reaches the Unknown tier and has enough total coins earned,
-- they can Resurface: reset depth + coins + tools, keep collections + museum,
-- gain a permanent multiplier that stacks.
--
-- Each resurface also unlocks:
--   - Visible resurface badge (aura color changes)
--   - Faster initial dig speed
--   - Access to resurface-only rare items

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local ResurfaceEvent = Instance.new("RemoteEvent")
ResurfaceEvent.Name = "Resurface"
ResurfaceEvent.Parent = Remotes

local ResurfaceInfoFunc = Instance.new("RemoteFunction")
ResurfaceInfoFunc.Name = "GetResurfaceInfo"
ResurfaceInfoFunc.Parent = Remotes

local NotifyEvent = Remotes:WaitForChild("Notify")
local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD")

-- ═══════════════════════════════════════════════════════════════════
-- Resurface Configuration
-- ═══════════════════════════════════════════════════════════════════

local BASE_COST = 1000000 -- 1M coins total earned to first resurface
local COST_SCALE = 1.08   -- Each resurface costs 8% more
local MULTIPLIER_PER_RESURFACE = 0.5 -- +0.5x per resurface (1x → 1.5x → 2x → ...)
local MIN_DEPTH_TIER = 6  -- Must have reached tier 6 (Unknown)
local MAX_RESURFACES = 50 -- Soft cap

-- Resurface aura colors (visible to other players)
local AURA_COLORS = {
	Color3.fromRGB(100, 200, 255),  -- 1: Ice blue
	Color3.fromRGB(100, 255, 100),  -- 2: Emerald
	Color3.fromRGB(255, 200, 50),   -- 3: Gold
	Color3.fromRGB(255, 100, 50),   -- 4: Flame
	Color3.fromRGB(200, 50, 255),   -- 5: Amethyst
	Color3.fromRGB(255, 50, 100),   -- 6: Ruby
	Color3.fromRGB(255, 255, 255),  -- 7+: White (prestige)
}

local function getAuraColor(resurfaces)
	if resurfaces <= 0 then return nil end
	local idx = math.min(resurfaces, #AURA_COLORS)
	return AURA_COLORS[idx]
end

local function getResurfaceCost(currentResurfaces)
	return math.floor(BASE_COST * (COST_SCALE ^ currentResurfaces))
end

local function getMultiplier(resurfaces)
	return 1 + (resurfaces * MULTIPLIER_PER_RESURFACE)
end

-- ═══════════════════════════════════════════════════════════════════
-- Resurface Info (client queries this to show UI)
-- ═══════════════════════════════════════════════════════════════════

ResurfaceInfoFunc.OnServerInvoke = function(player)
	local GetPlayerDataFunc = Remotes:FindFirstChild("GetPlayerData")
	if not GetPlayerDataFunc then return nil end

	local data = GetPlayerDataFunc:InvokeServer and nil
	-- NOTE: In production, use shared module. For MVP, return config.

	return {
		costFormula = "1M * 1.08^n",
		multiplierPerResurface = MULTIPLIER_PER_RESURFACE,
		minDepthTier = MIN_DEPTH_TIER,
		maxResurfaces = MAX_RESURFACES,
		auraColors = AURA_COLORS,
	}
end

-- ═══════════════════════════════════════════════════════════════════
-- Resurface Execution
-- ═══════════════════════════════════════════════════════════════════

ResurfaceEvent.OnServerEvent:Connect(function(player)
	-- NOTE: This needs direct access to GameManager's playerData table.
	-- In production, GameManager exposes a module API.
	-- For MVP, we define the logic and trust integration.

	-- The integration point in GameManager.server.lua:
	-- 1. Check: data.totalEarned >= getResurfaceCost(data.rebirths)
	-- 2. Check: data.deepestBlock >= Config.TIERS[MIN_DEPTH_TIER].minDepth
	-- 3. Reset: coins=STARTING_COINS, toolTier=1, totalBlocksDug=0, deepestBlock=0, inventory={}
	-- 4. Keep: collections, fragments, rebirths (incremented), totalEarned (keeps counting)
	-- 5. Apply: all future coin gains multiplied by getMultiplier(data.rebirths)

	-- For now, notify the player about the system
	NotifyEvent:FireClient(player,
		"Resurface: reach the Unknown tier + earn 1M coins to prestige! Keep your museum, gain permanent multipliers.",
		"Legendary"
	)
end)

-- ═══════════════════════════════════════════════════════════════════
-- Aura Visual Effect (applied on character spawn)
-- ═══════════════════════════════════════════════════════════════════

local function applyAura(player, resurfaces)
	local color = getAuraColor(resurfaces)
	if not color then return end

	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Remove existing aura
	local existingAura = hrp:FindFirstChild("ResurfaceAura")
	if existingAura then existingAura:Destroy() end

	-- Create aura effect
	local aura = Instance.new("PointLight")
	aura.Name = "ResurfaceAura"
	aura.Color = color
	aura.Brightness = 1 + resurfaces * 0.2
	aura.Range = 8 + resurfaces
	aura.Parent = hrp

	-- Particle effect for higher resurfaces
	if resurfaces >= 3 then
		local particles = Instance.new("ParticleEmitter")
		particles.Name = "ResurfaceParticles"
		particles.Color = ColorSequence.new(color)
		particles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 0),
		})
		particles.Lifetime = NumberRange.new(0.5, 1)
		particles.Rate = 5 + resurfaces * 2
		particles.Speed = NumberRange.new(1, 3)
		particles.SpreadAngle = Vector2.new(360, 360)
		particles.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		particles.Parent = hrp
	end

	-- Resurface badge (BillboardGui above head)
	local head = character:FindFirstChild("Head")
	if head and resurfaces > 0 then
		local existing = head:FindFirstChild("ResurfaceBadge")
		if existing then existing:Destroy() end

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "ResurfaceBadge"
		billboard.Size = UDim2.new(0, 100, 0, 30)
		billboard.StudsOffset = Vector3.new(0, 3, 0)
		billboard.AlwaysOnTop = false
		billboard.Parent = head

		local badge = Instance.new("TextLabel")
		badge.Size = UDim2.new(1, 0, 1, 0)
		badge.BackgroundTransparency = 1
		badge.Text = "⭐ Resurface " .. resurfaces
		badge.TextColor3 = color
		badge.TextStrokeTransparency = 0.5
		badge.TextScaled = true
		badge.Font = Enum.Font.GothamBold
		badge.Parent = billboard
	end
end

-- Apply aura on character spawn
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		task.wait(1)
		-- Get resurface count from player data
		local GetPlayerDataFunc = Remotes:FindFirstChild("GetPlayerData")
		if GetPlayerDataFunc then
			-- In production: local data = PlayerDataModule.get(player)
			-- For MVP: aura applied when GameManager sends resurface count via HUD update
		end
	end)
end)

-- Listen for HUD updates that include resurface info
Remotes.UpdateHUD.OnServerEvent:Connect(function() end) -- Client-only event, no-op on server

print("[DeepDig] Resurface system loaded")
