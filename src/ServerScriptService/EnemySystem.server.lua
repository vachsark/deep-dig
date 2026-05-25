-- EnemySystem.server.lua - v1 enemy spawning, attacks, and payouts
-- Place in: ServerScriptService/EnemySystem (Script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnemyDatabase = require(ReplicatedStorage:WaitForChild("EnemyDatabase"))
local ItemDatabase = require(ReplicatedStorage:WaitForChild("ItemDatabase"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ServerEvents = ReplicatedStorage:WaitForChild("ServerEvents")
local PlayerDataReady = ServerEvents:WaitForChild("PlayerDataReady")
local ItemFoundBindable = ServerEvents:WaitForChild("ItemFoundBindable")
local NotifyEvent = Remotes:WaitForChild("Notify")
local EnemyKilledBindable = ServerEvents:FindFirstChild("EnemyKilledBindable")
if not EnemyKilledBindable then
	EnemyKilledBindable = Instance.new("BindableEvent")
	EnemyKilledBindable.Name = "EnemyKilledBindable"
	EnemyKilledBindable.Parent = ServerEvents
end

local EnemyHitEvent = Remotes:FindFirstChild("EnemyHitEvent")
if not EnemyHitEvent then
	EnemyHitEvent = Instance.new("RemoteEvent")
	EnemyHitEvent.Name = "EnemyHitEvent"
	EnemyHitEvent.Parent = Remotes
end

local EnemyCombatFeedback = Remotes:FindFirstChild("EnemyCombatFeedback")
if not EnemyCombatFeedback then
	EnemyCombatFeedback = Instance.new("RemoteEvent")
	EnemyCombatFeedback.Name = "EnemyCombatFeedback"
	EnemyCombatFeedback.Parent = Remotes
end

local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD")
local ItemFoundEvent = Remotes:FindFirstChild("ItemFound")

local enemiesFolder = workspace:FindFirstChild("Enemies")
if not enemiesFolder then
	enemiesFolder = Instance.new("Folder")
	enemiesFolder.Name = "Enemies"
	enemiesFolder.Parent = workspace
end

local SPAWN_INTERVAL = 30
local MAX_ENEMIES_PER_PLAYER = 5
local ATTACK_RANGE = 8
local ATTACK_COOLDOWN = 0.5
local STAGGER_DURATION = 0.18
local STAGGER_WALKSPEED_MULTIPLIER = 0.25
local STAGGER_KNOCKBACK_SPEED = 18
local TOUCH_DAMAGE_COOLDOWN = 1
local TOUCH_ATTACK_WINDUP = 0.35
local TOUCH_ATTACK_RANGE_TOLERANCE = 2
local WALK_RADIUS = 12
local IDLE_WANDER_INTERVAL = 3
local FIRST_ENEMY_DEPTH = 11
local SPAWN_WINDUP_DURATION = 1.2

local liveEnemies = {}
local enemiesByPlayer = {}
local nextAttackAtByUserId = {}
local sharedGlobals = getfenv()._G

local function getSharedData(player)
	local cache = sharedGlobals.DeepDig_playerData
	if cache then
		return cache[player.UserId]
	end
	return nil
end

local function awaitPlayerData(player, timeoutSeconds)
	local cache = sharedGlobals.DeepDig_playerData
	if cache and cache[player.UserId] then
		return cache[player.UserId]
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
	return getSharedData(player)
end

local QuestProgressBindable = ReplicatedStorage:FindFirstChild("QuestProgressBindable")
local function fireQuestProgress(player, eventType, eventData)
	if not QuestProgressBindable then
		QuestProgressBindable = ReplicatedStorage:FindFirstChild("QuestProgressBindable")
	end
	if QuestProgressBindable then
		QuestProgressBindable:Fire(player, eventType, eventData)
	end
end

local function getInventoryCapacityLabel(data)
	local helper = sharedGlobals.DeepDig_getInventoryCapacityLabel
	if helper then
		return helper(data)
	end
	return Config.DEFAULT_BACKPACK_CAPACITY
end

local function updateRewardHud(player, data)
	UpdateHUDEvent:FireClient(player, {
		coins = data.coins,
		fragments = data.fragments or 0,
		inventoryCount = data.inventory and #data.inventory or 0,
		inventoryCapacity = getInventoryCapacityLabel(data),
	})
end

local function addItemReward(player, data, tierName)
	local item = ItemDatabase.rollItem(tierName)
	if not item then
		return nil
	end

	local inventoryItem = {
		name = item.name,
		rarity = item.rarity,
		sellValue = item.sellValue,
	}

	local added = false
	local tryAddInventoryItem = sharedGlobals.DeepDig_tryAddInventoryItem
	if tryAddInventoryItem then
		added = tryAddInventoryItem(player, inventoryItem)
	elseif data.inventory then
		table.insert(data.inventory, inventoryItem)
		added = true
	end

	if added then
		if data.collections then
			data.collections[item.name] = true
		end
		fireQuestProgress(player, "items_found", { amount = 1 })
		fireQuestProgress(player, "rarity_found", { amount = 1, rarity = item.rarity })
		if ItemFoundEvent then
			ItemFoundEvent:FireClient(player, item)
		end
		ItemFoundBindable:Fire(player, item)
		return item
	end

	return nil
end

local function notifyEnemyReward(player, enemyName, enemy, itemReward)
	local message = "Defeated " .. enemyName
		.. ": +" .. enemy.coinDrop .. " coins"
		.. ", +" .. enemy.fragmentDrop .. " fragments"
	if itemReward then
		message = message .. ", found " .. itemReward.name
	end

	NotifyEvent:FireClient(player, message, enemy.isMiniboss and "Legendary" or "Rare")
end

local function removeEnemyRecord(record)
	local owner = record.owner
	local owned = owner and enemiesByPlayer[owner]
	if owned then
		for index = #owned, 1, -1 do
			if owned[index] == record then
				table.remove(owned, index)
			end
		end
	end

	if record.touchConnection then
		record.touchConnection:Disconnect()
	end
	if record.diedConnection then
		record.diedConnection:Disconnect()
	end

	liveEnemies[record.model] = nil
end

local function destroyEnemy(record)
	removeEnemyRecord(record)
	if record.model and record.model.Parent then
		record.model:Destroy()
	end
end

local function payEnemyReward(record)
	local player = record.lastAttacker or record.owner
	if not player or player.Parent ~= Players then
		return nil
	end

	local data = getSharedData(player)
	if not data then
		return nil
	end

	local enemy = record.enemy
	data.coins = (data.coins or 0) + enemy.coinDrop
	data.fragments = (data.fragments or 0) + enemy.fragmentDrop
	data.totalEarned = (data.totalEarned or 0) + enemy.coinDrop

	fireQuestProgress(player, "coins_earned", { amount = enemy.coinDrop })
	fireQuestProgress(player, "kill_enemies", { amount = 1 })
	EnemyKilledBindable:Fire(player, enemy)

	local itemReward = nil
	if math.random() < enemy.itemDropChance then
		itemReward = addItemReward(player, data, record.tierName)
	end

	updateRewardHud(player, data)
	notifyEnemyReward(
		player,
		record.model:GetAttribute("EnemyName") or enemy.name,
		enemy,
		itemReward
	)

	local rewardSummary = {
		coins = enemy.coinDrop,
		fragments = enemy.fragmentDrop,
		isMiniboss = enemy.isMiniboss == true,
	}
	if itemReward then
		rewardSummary.item = {
			name = itemReward.name,
			rarity = itemReward.rarity,
			color = itemReward.color,
		}
	end

	return player, rewardSummary
end

local function fireEnemyCombatFeedback(player, feedbackType, model, damage, reward)
	if player and player.Parent == Players and model and model.Parent then
		local payload = {
			type = feedbackType,
			model = model,
		}
		if damage then
			payload.damage = damage
		end
		if reward then
			payload.reward = reward
		end
		EnemyCombatFeedback:FireClient(player, payload)
	end
end

local function notifyMinibossSpawn(player, enemy, model)
	if not enemy.isMiniboss then
		return
	end

	NotifyEvent:FireClient(player, enemy.name .. " is emerging nearby!", "Legendary")
	fireEnemyCombatFeedback(player, "miniboss_spawn", model)
end

local function getEnemyMaxHealth(record)
	local attributeMaxHealth = record.model:GetAttribute("MaxHealth")
	if typeof(attributeMaxHealth) == "number" and attributeMaxHealth > 0 then
		return attributeMaxHealth
	end

	return math.max(record.humanoid.MaxHealth, 1)
end

local function checkMinibossEnrage(record, attacker, previousHealth)
	if record.enraged or record.dead or not record.enemy.isMiniboss then
		return
	end

	if not record.model or not record.model.Parent or not record.humanoid or record.humanoid.Health <= 0 then
		return
	end

	local maxHealth = getEnemyMaxHealth(record)
	local threshold = maxHealth * 0.5
	if previousHealth <= threshold or record.humanoid.Health > threshold then
		return
	end

	record.enraged = true
	record.model:SetAttribute("HasEnraged", true)
	fireEnemyCombatFeedback(record.owner, "miniboss_enrage", record.model)
	if attacker and attacker ~= record.owner then
		fireEnemyCombatFeedback(attacker, "miniboss_enrage", record.model)
	end
end

local function onEnemyDied(record)
	if record.dead then
		return
	end

	record.dead = true
	local rewardedPlayer, rewardSummary = payEnemyReward(record)
	local feedbackPlayer = rewardedPlayer or record.lastAttacker or record.owner
	fireEnemyCombatFeedback(feedbackPlayer, "defeated", record.model, nil, rewardSummary)
	if record.enemy.isMiniboss then
		fireEnemyCombatFeedback(feedbackPlayer, "miniboss_defeated", record.model)
	end
	task.delay(2, function()
		destroyEnemy(record)
	end)
end

local function getAliveCharacterParts(player)
	if not player or player.Parent ~= Players then
		return nil, nil, nil
	end

	local character = player.Character
	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil, nil, nil
	end

	return character, humanoid, root
end

local function getTouchAttackRange(record)
	local root = record.root
	local largestEnemyAxis = 0
	if root then
		largestEnemyAxis = math.max(root.Size.X, root.Size.Y, root.Size.Z)
	end

	return (largestEnemyAxis * 0.5) + TOUCH_ATTACK_RANGE_TOLERANCE
end

local function isEnemyEmerging(record)
	if not record then
		return false
	end

	return record.model and record.model:GetAttribute("IsEmerging") == true
end

local function releaseEmergingEnemy(record)
	if record.dead or not record.model or not record.model.Parent then
		return
	end
	if not record.humanoid or record.humanoid.Health <= 0 then
		return
	end
	if not record.root or not record.root.Parent then
		return
	end

	record.model:SetAttribute("IsEmerging", false)
	record.root.Anchored = false
	record.humanoid.WalkSpeed = record.enemy.walkSpeed
end

local function applyPendingTouchAttack(record, player, userId)
	record.pendingTouchAttacksByUserId[userId] = nil

	if record.dead or not record.model or not record.model.Parent then
		return
	end
	if isEnemyEmerging(record) then
		return
	end
	if not record.humanoid or record.humanoid.Health <= 0 then
		return
	end
	if not record.root or not record.root.Parent then
		return
	end

	local _, humanoid, playerRoot = getAliveCharacterParts(player)
	if not humanoid or not playerRoot then
		return
	end

	if (playerRoot.Position - record.root.Position).Magnitude > getTouchAttackRange(record) then
		return
	end

	player:SetAttribute("DeepDig_LastEnemyDamageAt", os.clock())
	humanoid:TakeDamage(record.enemy.damage)
	EnemyCombatFeedback:FireClient(player, {
		type = "player_hit",
		damage = record.enemy.damage,
		enemyName = record.model:GetAttribute("EnemyName") or record.enemy.name,
	})
end

local function handleTouched(record, hit)
	if record.dead or not hit then
		return
	end
	if isEnemyEmerging(record) then
		return
	end

	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local _, humanoid = getAliveCharacterParts(player)
	if not humanoid then
		return
	end

	local userId = player.UserId
	local now = os.clock()
	local nextDamageAt = record.nextTouchDamageAtByUserId[userId] or 0
	if now < nextDamageAt then
		return
	end
	if record.pendingTouchAttacksByUserId[userId] then
		return
	end

	record.nextTouchDamageAtByUserId[userId] = now + TOUCH_DAMAGE_COOLDOWN
	record.pendingTouchAttacksByUserId[userId] = true
	fireEnemyCombatFeedback(player, "enemy_attack_warning", record.model, record.enemy.damage)

	task.delay(TOUCH_ATTACK_WINDUP, function()
		applyPendingTouchAttack(record, player, userId)
	end)
end

local function compactOwnedEnemies(player)
	local owned = enemiesByPlayer[player]
	if not owned then
		return 0
	end

	for index = #owned, 1, -1 do
		local record = owned[index]
		if record.dead or not record.model or not record.model.Parent then
			table.remove(owned, index)
			if record.model then
				liveEnemies[record.model] = nil
			end
		end
	end

	return #owned
end

local function hasLivingEnemyById(player, enemyId)
	local owned = enemiesByPlayer[player]
	if not owned then
		return false
	end

	for _, record in ipairs(owned) do
		if not record.dead and record.enemy.id == enemyId and record.model and record.model.Parent then
			return true
		end
	end

	return false
end

local function getPlayerRoot(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function getSpawnPosition(player)
	local root = getPlayerRoot(player)
	if not root then
		return nil
	end

	local angle = math.random() * math.pi * 2
	local distance = math.random(10, 16)
	return root.Position + Vector3.new(math.cos(angle) * distance, 3, math.sin(angle) * distance)
end

local function getWanderPosition(homePosition)
	local angle = math.random() * math.pi * 2
	local distance = math.random() * WALK_RADIUS
	return homePosition + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local function scaleVector(vector, scale)
	return Vector3.new(vector.X * scale, vector.Y * scale, vector.Z * scale)
end

local function createVisualPart(model, root, enemy, visual, spawnScale, spec)
	local part = Instance.new(spec.className or "Part")
	part.Name = spec.name
	part.Size = scaleVector(spec.size, spawnScale)
	if spec.shape and part:IsA("Part") then
		part.Shape = spec.shape
	end
	part.Color = spec.useBodyColor and enemy.color or (spec.color or visual.accentColor or enemy.color)
	part.Material = spec.material or visual.accentMaterial or visual.material or Enum.Material.Slate
	part.Transparency = spec.transparency or 0
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Anchored = false

	local offset = scaleVector(spec.offset or Vector3.new(0, 0, 0), spawnScale)
	local rotation = spec.rotation or CFrame.new()
	part.CFrame = root.CFrame * CFrame.new(offset) * rotation
	part.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part

	return part
end

local function addVisualLight(root, color, brightness, range)
	local light = Instance.new("PointLight")
	light.Name = "EnemyVisualGlow"
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = root
end

local function addVisualParticles(root, color, rate, size)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "EnemyVisualParticles"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.55
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.65, 1.15)
	emitter.Speed = NumberRange.new(0.4, 1.1)
	emitter.Size = NumberSequence.new(size)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = root
end

local VISUAL_FEATURES = {
	crawler_legs = function(model, root, enemy, visual, spawnScale)
		for _, side in ipairs({ -1, 1 }) do
			for _, zOffset in ipairs({ -0.85, 0.85 }) do
				createVisualPart(model, root, enemy, visual, spawnScale, {
					name = "CrawlerLeg",
					size = Vector3.new(1.55, 0.28, 0.36),
					offset = Vector3.new(side * 2.1, -0.55, zOffset),
					rotation = CFrame.Angles(0, 0, math.rad(side * -12)),
					useBodyColor = true,
					material = visual.material,
				})
			end
		end
	end,

	back_spines = function(model, root, enemy, visual, spawnScale)
		for _, xOffset in ipairs({ -1.05, 0, 1.05 }) do
			createVisualPart(model, root, enemy, visual, spawnScale, {
				name = "BoneSpine",
				className = "WedgePart",
				size = Vector3.new(0.55, 0.95, 0.75),
				offset = Vector3.new(xOffset, 1.35, 0),
				rotation = CFrame.Angles(0, math.rad(90), 0),
			})
		end
	end,

	sentinel_shield = function(model, root, enemy, visual, spawnScale)
		createVisualPart(model, root, enemy, visual, spawnScale, {
			name = "SentinelShield",
			size = Vector3.new(2.8, 3.25, 0.35),
			offset = Vector3.new(0, -0.1, -1.75),
		})
	end,

	head_crest = function(model, root, enemy, visual, spawnScale)
		createVisualPart(model, root, enemy, visual, spawnScale, {
			name = "HeadCrest",
			size = Vector3.new(1.05, 1.25, 0.35),
			offset = Vector3.new(0, 2.95, -0.25),
		})
		createVisualPart(model, root, enemy, visual, spawnScale, {
			name = "SentinelBrow",
			size = Vector3.new(2.35, 0.35, 0.42),
			offset = Vector3.new(0, 1.9, -1.55),
		})
	end,

	construct_shoulders = function(model, root, enemy, visual, spawnScale)
		for _, side in ipairs({ -1, 1 }) do
			createVisualPart(model, root, enemy, visual, spawnScale, {
				name = "ConstructShoulder",
				size = Vector3.new(1.25, 1.65, 1.25),
				offset = Vector3.new(side * 2.35, 0.85, 0),
				useBodyColor = true,
				material = visual.material,
			})
			createVisualPart(model, root, enemy, visual, spawnScale, {
				name = "ConstructArm",
				size = Vector3.new(0.65, 2.3, 0.65),
				offset = Vector3.new(side * 2.75, -0.75, 0.25),
				useBodyColor = true,
				material = visual.material,
			})
		end
	end,

	scrap_stack = function(model, root, enemy, visual, spawnScale)
		for index, xOffset in ipairs({ -0.85, 0, 0.85 }) do
			createVisualPart(model, root, enemy, visual, spawnScale, {
				name = "ScrapStack",
				size = Vector3.new(0.55, 0.75 + index * 0.18, 0.55),
				offset = Vector3.new(xOffset, 2.15 + index * 0.08, 0.95),
			})
		end
	end,

	wraith_ribs = function(model, root, enemy, visual, spawnScale)
		for _, yOffset in ipairs({ -0.95, -0.25, 0.45, 1.15 }) do
			createVisualPart(model, root, enemy, visual, spawnScale, {
				name = "WraithRib",
				size = Vector3.new(3.05, 0.16, 0.18),
				offset = Vector3.new(0, yOffset, -0.95),
				transparency = 0.1,
			})
		end
		createVisualPart(model, root, enemy, visual, spawnScale, {
			name = "WraithTail",
			className = "WedgePart",
			size = Vector3.new(2.2, 1.55, 2.2),
			offset = Vector3.new(0, -3.05, 0),
			rotation = CFrame.Angles(math.rad(180), 0, 0),
			transparency = 0.25,
			useBodyColor = true,
			material = visual.material,
		})
	end,

	wraith_mist = function(_model, root, _enemy, visual, spawnScale)
		addVisualParticles(root, visual.accentColor, 8, 0.45 * spawnScale)
	end,

	void_orbit = function(model, root, enemy, visual, spawnScale)
		for _, spec in ipairs({
			{ offset = Vector3.new(1.85, 0.65, 0), size = Vector3.new(0.55, 0.55, 0.55) },
			{ offset = Vector3.new(-1.85, -0.1, 0), size = Vector3.new(0.42, 0.42, 0.42) },
			{ offset = Vector3.new(0, 0.25, 1.85), size = Vector3.new(0.48, 0.48, 0.48) },
			{ offset = Vector3.new(0, 1.05, -1.85), size = Vector3.new(0.36, 0.36, 0.36) },
		}) do
			createVisualPart(model, root, enemy, visual, spawnScale, {
				name = "VoidOrb",
				size = spec.size,
				offset = spec.offset,
				shape = Enum.PartType.Ball,
			})
		end
	end,

	void_light = function(_model, root, _enemy, visual, spawnScale)
		addVisualLight(root, visual.accentColor, 1.25, 10 * spawnScale)
		addVisualParticles(root, visual.accentColor, 10, 0.35 * spawnScale)
	end,

	king_crown = function(model, root, enemy, visual, spawnScale)
		for _, xOffset in ipairs({ -1.45, -0.7, 0, 0.7, 1.45 }) do
			createVisualPart(model, root, enemy, visual, spawnScale, {
				name = "KingCrownSpike",
				className = "WedgePart",
				size = Vector3.new(0.55, 1.45, 0.65),
				offset = Vector3.new(xOffset, 3.65, -0.35),
				rotation = CFrame.Angles(0, math.rad(90), 0),
			})
		end
		createVisualPart(model, root, enemy, visual, spawnScale, {
			name = "KingCrownBand",
			size = Vector3.new(3.7, 0.38, 0.55),
			offset = Vector3.new(0, 3.05, -0.35),
		})
	end,

	king_shoulders = function(model, root, enemy, visual, spawnScale)
		for _, side in ipairs({ -1, 1 }) do
			createVisualPart(model, root, enemy, visual, spawnScale, {
				name = "KingShoulder",
				size = Vector3.new(2.1, 1.15, 1.45),
				offset = Vector3.new(side * 2.95, 1.4, 0),
				useBodyColor = true,
				material = visual.material,
			})
			createVisualPart(model, root, enemy, visual, spawnScale, {
				name = "KingShoulderSpike",
				className = "WedgePart",
				size = Vector3.new(1.25, 1.45, 0.95),
				offset = Vector3.new(side * 3.7, 2.05, 0),
				rotation = CFrame.Angles(0, math.rad(side * 90), 0),
			})
		end
	end,

	king_aura = function(_model, root, _enemy, visual, spawnScale)
		addVisualLight(root, visual.accentColor, 2.1, 18 * spawnScale)
		addVisualParticles(root, visual.accentColor, 16, 0.7 * spawnScale)
	end,
}

local function applyEnemyVisualProfile(model, root, enemy, spawnScale)
	local visual = enemy.visual or {}
	root.Size = scaleVector(visual.bodySize or Vector3.new(3, 4, 3), spawnScale)
	root.Color = enemy.color
	root.Material = visual.material or Enum.Material.Slate
	root.Transparency = visual.transparency or 0

	for _, tag in ipairs(visual.featureTags or {}) do
		local builder = VISUAL_FEATURES[tag]
		if builder then
			builder(model, root, enemy, visual, spawnScale)
		end
	end
end

local function spawnEnemyForPlayer(player)
	local data = getSharedData(player)
	if not data or (data.deepestBlock or 0) < FIRST_ENEMY_DEPTH then
		return
	end

	if compactOwnedEnemies(player) >= MAX_ENEMIES_PER_PLAYER then
		return
	end

	local spawnPosition = getSpawnPosition(player)
	if not spawnPosition then
		return
	end

	local tierName = ItemDatabase.getTierForDepth(data.deepestBlock or 0)
	local blockedEnemyIds = nil
	if hasLivingEnemyById(player, "hollow_king") then
		blockedEnemyIds = {
			hollow_king = true,
		}
	end

	local enemy = EnemyDatabase.getEnemyForTier(tierName, {
		blockedEnemyIds = blockedEnemyIds,
	})
	if not enemy then
		return
	end

	local spawnScale = enemy.spawnScale or 1
	local enemyName = enemy.name
	if enemy.isMiniboss then
		enemyName = enemy.name .. " [Miniboss]"
	end
	local spawnReadyAt = os.clock() + SPAWN_WINDUP_DURATION

	local model = Instance.new("Model")
	model.Name = enemyName
	model:SetAttribute("EnemyId", enemy.id)
	model:SetAttribute("EnemyName", enemyName)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("IsMiniboss", enemy.isMiniboss == true)
	model:SetAttribute("EnemyRank", enemy.isMiniboss and "Miniboss" or "Enemy")
	model:SetAttribute("MaxHealth", enemy.hp)
	model:SetAttribute("HasEnraged", false)
	model:SetAttribute("IsEmerging", true)
	model:SetAttribute("SpawnReadyAt", spawnReadyAt)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CanCollide = true
	root.Anchored = true
	root.CFrame = CFrame.new(spawnPosition)
	root.Parent = model
	applyEnemyVisualProfile(model, root, enemy, spawnScale)

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = enemy.hp
	humanoid.Health = enemy.hp
	humanoid.WalkSpeed = 0
	humanoid.DisplayName = enemyName
	humanoid.Parent = model

	model.PrimaryPart = root
	model.Parent = enemiesFolder
	if not enemy.isMiniboss then
		fireEnemyCombatFeedback(player, "enemy_spawn", model)
	end

	local record = {
		model = model,
		root = root,
		humanoid = humanoid,
		enemy = enemy,
		owner = player,
		tierName = tierName,
		homePosition = spawnPosition,
		nextWanderAt = 0,
		lastAttacker = nil,
		dead = false,
		inAggroRange = false,
		enraged = false,
		staggerToken = 0,
		staggeredUntil = nil,
		nextTouchDamageAtByUserId = {},
		pendingTouchAttacksByUserId = {},
	}

	record.touchConnection = root.Touched:Connect(function(hit)
		handleTouched(record, hit)
	end)
	record.diedConnection = humanoid.Died:Connect(function()
		onEnemyDied(record)
	end)

	liveEnemies[model] = record
	enemiesByPlayer[player] = enemiesByPlayer[player] or {}
	table.insert(enemiesByPlayer[player], record)
	notifyMinibossSpawn(player, enemy, model)

	task.delay(SPAWN_WINDUP_DURATION, function()
		releaseEmergingEnemy(record)
	end)
end

local function startSpawnLoop(player)
	task.spawn(function()
		local data = awaitPlayerData(player, 30)
		if not data then
			return
		end

		while player.Parent == Players do
			spawnEnemyForPlayer(player)
			task.wait(SPAWN_INTERVAL)
		end
	end)
end

local function staggerEnemy(record, playerRoot, enemyRoot)
	record.staggerToken = (record.staggerToken or 0) + 1
	record.staggeredUntil = os.clock() + STAGGER_DURATION

	local token = record.staggerToken
	local walkSpeed = record.enemy.walkSpeed or 0
	record.humanoid.WalkSpeed = math.max(0, walkSpeed * STAGGER_WALKSPEED_MULTIPLIER)

	local offset = enemyRoot.Position - playerRoot.Position
	local direction = nil
	if offset.Magnitude > 0.05 then
		direction = offset.Unit
	else
		direction = playerRoot.CFrame.LookVector
	end

	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude <= 0.05 then
		direction = Vector3.new(0, 0, -1)
	else
		direction = direction.Unit
	end

	local currentVelocity = enemyRoot.AssemblyLinearVelocity
	enemyRoot.AssemblyLinearVelocity = Vector3.new(
		direction.X * STAGGER_KNOCKBACK_SPEED,
		currentVelocity.Y,
		direction.Z * STAGGER_KNOCKBACK_SPEED
	)

	task.delay(STAGGER_DURATION, function()
		if record.staggerToken ~= token then
			return
		end
		if record.dead or not record.model or not record.model.Parent then
			return
		end
		if not record.humanoid or record.humanoid.Health <= 0 then
			return
		end
		if isEnemyEmerging(record) then
			record.humanoid.WalkSpeed = 0
			return
		end

		record.staggeredUntil = nil
		record.humanoid.WalkSpeed = record.enemy.walkSpeed
	end)
end

EnemyHitEvent.OnServerEvent:Connect(function(player, enemyModel)
	if typeof(enemyModel) ~= "Instance" then
		return
	end

	local record = liveEnemies[enemyModel]
	if not record or record.dead or not record.model:IsDescendantOf(enemiesFolder) then
		return
	end

	local now = os.clock()
	local nextAttackAt = nextAttackAtByUserId[player.UserId] or 0
	if now < nextAttackAt then
		return
	end

	local playerRoot = getPlayerRoot(player)
	local enemyRoot = record.root
	if not playerRoot or not enemyRoot or not enemyRoot.Parent then
		return
	end

	if (playerRoot.Position - enemyRoot.Position).Magnitude > ATTACK_RANGE then
		return
	end

	local data = getSharedData(player)
	if not data then
		return
	end

	local tool = Config.TOOLS[data.toolTier]
	local damage = tool and tool.damage or 1
	nextAttackAtByUserId[player.UserId] = now + ATTACK_COOLDOWN
	record.lastAttacker = player
	local previousHealth = record.humanoid.Health
	record.humanoid:TakeDamage(damage)
	checkMinibossEnrage(record, player, previousHealth)
	staggerEnemy(record, playerRoot, enemyRoot)
	fireEnemyCombatFeedback(player, "hit", record.model, damage)
end)

Players.PlayerAdded:Connect(startSpawnLoop)

for _, player in ipairs(Players:GetPlayers()) do
	startSpawnLoop(player)
end

Players.PlayerRemoving:Connect(function(player)
	nextAttackAtByUserId[player.UserId] = nil

	local owned = enemiesByPlayer[player]
	if owned then
		for index = #owned, 1, -1 do
			destroyEnemy(owned[index])
		end
	end
	enemiesByPlayer[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(1)
		for _, record in pairs(liveEnemies) do
			if not record.dead and record.model.Parent and record.humanoid.Health > 0 then
				local ownerRoot = record.owner and getPlayerRoot(record.owner)
				if ownerRoot and record.root and record.root.Parent then
					if isEnemyEmerging(record) then
						record.inAggroRange = false
						record.humanoid.WalkSpeed = 0
					else
						local enemyPosition = record.root.Position
						local distanceToOwner = (ownerRoot.Position - enemyPosition).Magnitude
						local aggroRange = record.enemy.aggroRange or 16
						local targetPosition = nil
						local inAggroRange = distanceToOwner <= aggroRange

						if inAggroRange then
							if not record.inAggroRange then
								fireEnemyCombatFeedback(record.owner, "aggro", record.model)
							end
							record.inAggroRange = true
							targetPosition = ownerRoot.Position
						elseif os.clock() >= (record.nextWanderAt or 0) then
							record.inAggroRange = false
							targetPosition = getWanderPosition(record.homePosition or enemyPosition)
							record.nextWanderAt = os.clock() + IDLE_WANDER_INTERVAL
						else
							record.inAggroRange = false
						end

						if not record.staggeredUntil or os.clock() >= record.staggeredUntil then
							record.humanoid.WalkSpeed = record.enemy.walkSpeed
						end
						if targetPosition then
							record.humanoid:MoveTo(targetPosition)
						end
					end
				end
			end
		end
	end
end)
