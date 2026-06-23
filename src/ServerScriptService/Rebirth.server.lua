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

local ResurfaceCelebrationEvent = Instance.new("RemoteEvent")
ResurfaceCelebrationEvent.Name = "ResurfaceCelebration"
ResurfaceCelebrationEvent.Parent = Remotes

local NotifyEvent = Remotes:WaitForChild("Notify")
local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD")

-- ═══════════════════════════════════════════════════════════════════
-- Resurface Configuration
-- ═══════════════════════════════════════════════════════════════════

local BASE_COST = 1000000 -- 1M coins total earned to first resurface
local COST_SCALE = 1.08   -- Each resurface costs 8% more
local MULTIPLIER_PER_RESURFACE = 0.5 -- +0.5x per resurface (1x → 1.5x → 2x → ...)
local REBIRTH_BOOST_MULTIPLIER_PER_RESURFACE = 1.0 -- +1.0x per resurface with Rebirth Boost
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

local function hasOwnedGamepass(data, passId, passKey)
	local ownedGamepasses = data and data.ownedGamepasses
	if not ownedGamepasses then
		return false
	end

	return ownedGamepasses[passId] == true or (passKey and ownedGamepasses[passKey] == true)
end

local function getMultiplierPerResurface(data)
	if hasOwnedGamepass(
		data,
		Config.GAMEPASS_REBIRTH_BOOST_ID,
		Config.GAMEPASS_REBIRTH_BOOST
	) then
		return REBIRTH_BOOST_MULTIPLIER_PER_RESURFACE
	end

	return MULTIPLIER_PER_RESURFACE
end

local function getMultiplier(resurfaces, data)
	return 1 + (resurfaces * getMultiplierPerResurface(data))
end

-- ═══════════════════════════════════════════════════════════════════
-- Resurface Info (client queries this to show UI)
-- ═══════════════════════════════════════════════════════════════════

ResurfaceInfoFunc.OnServerInvoke = function(player)
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

local function getData(player)
	local cache = _G.DeepDig_playerData
	if not cache then return nil end
	return cache[player.UserId]
end

-- Wait for GameManager to populate player data via the PlayerDataReady
-- BindableEvent. Replaces the old `task.wait(1)` race in onCharacterAdded.
local ServerEvents = ReplicatedStorage:WaitForChild("ServerEvents")
local PlayerDataReady = ServerEvents:WaitForChild("PlayerDataReady")

local function awaitPlayerData(player, timeoutSeconds)
	if _G.DeepDig_playerData and _G.DeepDig_playerData[player.UserId] then
		return _G.DeepDig_playerData[player.UserId]
	end
	local readyForThisPlayer = false
	local connection
	connection = PlayerDataReady.Event:Connect(function(p)
		if p == player then
			readyForThisPlayer = true
		end
	end)
	local elapsed = 0
	local step = 0.1
	local cap = timeoutSeconds or 30
	while not readyForThisPlayer and elapsed < cap and player.Parent do
		task.wait(step)
		elapsed = elapsed + step
	end
	connection:Disconnect()
	if _G.DeepDig_playerData then
		return _G.DeepDig_playerData[player.UserId]
	end
	return nil
end

-- Forward-declared so the ResurfaceEvent handler can call it; defined below
-- alongside the spawn-time aura logic.
local applyAura

ResurfaceEvent.OnServerEvent:Connect(function(player)
	local data = getData(player)
	if not data then
		NotifyEvent:FireClient(player, "Player data not loaded yet — try again in a moment.", "Common")
		return
	end

	if (data.rebirths or 0) >= MAX_RESURFACES then
		NotifyEvent:FireClient(player, "You're at the soft cap of " .. MAX_RESURFACES .. " resurfaces.", "Common")
		return
	end

	local tierEntry = Config.TIERS[MIN_DEPTH_TIER]
	local tierName = (tierEntry and tierEntry.name) or "Unknown tier"
	local minDepth = (tierEntry and tierEntry.minDepth) or 188
	if (data.deepestBlock or 0) < minDepth then
		NotifyEvent:FireClient(player,
			"Resurface locked — reach " .. tierName .. " tier first (depth " .. minDepth .. ").",
			"Common")
		return
	end

	local cost = getResurfaceCost(data.rebirths or 0)
	if (data.totalEarned or 0) < cost then
		NotifyEvent:FireClient(player,
			string.format("Resurface needs %s total earned (you have %s).", tostring(cost), tostring(math.floor(data.totalEarned or 0))),
			"Common")
		return
	end

	-- Apply prestige: reset progression, keep collections + identity.
	data.rebirths = (data.rebirths or 0) + 1
	data.coins = Config.STARTING_COINS
	data.toolTier = 1
	data.totalBlocksDug = 0
	data.deepestBlock = 0
	data.inventory = {}
	data.firstSellAffordabilityGrantUsed = false

	-- Drop any active dig chain so the post-resurface run starts clean.
	-- Without this, a x40 chain carries through to the new run's first
	-- dig at tool tier 1 — pure exploit on coin-pop economy.
	local resetCombo = _G.DeepDig_resetChainCombo
	if type(resetCombo) == "function" then
		resetCombo(player)
	end

	local multiplier = getMultiplier(data.rebirths, data)

	NotifyEvent:FireClient(player,
		string.format("⭐ Resurface #%d — permanent +%.1fx coin multiplier active.", data.rebirths, multiplier - 1),
		"Mythic")

	UpdateHUDEvent:FireClient(player, {
		coins = data.coins,
		toolTier = data.toolTier,
		toolName = Config.TOOLS[1].name,
		blocksDug = 0,
		depth = 0,
		tierName = Config.TIERS[1].name,
		inventoryCount = 0,
		rebirths = data.rebirths,
	})

	-- Refresh aura instantly (don't wait for next respawn).
	if player.Character then
		applyAura(player, data.rebirths)
	end

	-- Prestige fanfare for the whole server (everyone sees the player erupt).
	local PlaySound = Remotes:FindFirstChild("PlaySound")
	if PlaySound then PlaySound:FireAllClients("resurface_fanfare") end

	ResurfaceCelebrationEvent:FireClient(player, {
		resurfaceCount = data.rebirths,
		permanentMultiplier = multiplier,
		bonusMultiplier = multiplier - 1,
	})
end)

-- ═══════════════════════════════════════════════════════════════════
-- Aura Visual Effect (applied on character spawn)
-- ═══════════════════════════════════════════════════════════════════

applyAura = function(player, resurfaces)
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

-- Apply aura on character spawn using shared player data.
local function onCharacterAdded(player, character)
	-- Wait for GameManager via PlayerDataReady BindableEvent (cap 30s).
	local data = awaitPlayerData(player, 30)
	if not data then return end
	if (data.rebirths or 0) > 0 then
		applyAura(player, data.rebirths)
	end
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	-- Studio playtest: handle the case where character already exists at script load.
	if player.Character then
		task.spawn(function()
			onCharacterAdded(player, player.Character)
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

print("[DeepDig] Resurface system loaded")
