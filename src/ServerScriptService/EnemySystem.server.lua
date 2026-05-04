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
local TOUCH_DAMAGE_COOLDOWN = 1
local WALK_RADIUS = 12
local IDLE_WANDER_INTERVAL = 3
local FIRST_ENEMY_DEPTH = 11

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
		return
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
	end
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
		return
	end

	local data = getSharedData(player)
	if not data then
		return
	end

	local enemy = record.enemy
	data.coins = (data.coins or 0) + enemy.coinDrop
	data.fragments = (data.fragments or 0) + enemy.fragmentDrop
	data.totalEarned = (data.totalEarned or 0) + enemy.coinDrop

	fireQuestProgress(player, "coins_earned", { amount = enemy.coinDrop })
	fireQuestProgress(player, "kill_enemies", { amount = 1 })
	EnemyKilledBindable:Fire(player, enemy)

	if math.random() < enemy.itemDropChance then
		addItemReward(player, data, record.tierName)
	end

	updateRewardHud(player, data)
end

local function fireEnemyCombatFeedback(player, feedbackType, model)
	if player and player.Parent == Players and model and model.Parent then
		EnemyCombatFeedback:FireClient(player, {
			type = feedbackType,
			model = model,
		})
	end
end

local function onEnemyDied(record)
	if record.dead then
		return
	end

	record.dead = true
	fireEnemyCombatFeedback(record.lastAttacker or record.owner, "defeated", record.model)
	payEnemyReward(record)
	task.delay(2, function()
		destroyEnemy(record)
	end)
end

local function handleTouched(record, hit)
	if record.dead or not hit then
		return
	end

	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	local nextDamageAt = record.nextTouchDamageAtByUserId[player.UserId] or 0
	if now < nextDamageAt then
		return
	end

	record.nextTouchDamageAtByUserId[player.UserId] = now + TOUCH_DAMAGE_COOLDOWN
	player:SetAttribute("DeepDig_LastEnemyDamageAt", now)
	humanoid:TakeDamage(record.enemy.damage)
	EnemyCombatFeedback:FireClient(player, {
		type = "player_hit",
		damage = record.enemy.damage,
		enemyName = record.model:GetAttribute("EnemyName") or record.enemy.name,
	})
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

	local model = Instance.new("Model")
	model.Name = enemyName
	model:SetAttribute("EnemyId", enemy.id)
	model:SetAttribute("EnemyName", enemyName)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("IsMiniboss", enemy.isMiniboss == true)
	model:SetAttribute("EnemyRank", enemy.isMiniboss and "Miniboss" or "Enemy")
	model:SetAttribute("MaxHealth", enemy.hp)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(3, 4, 3) * spawnScale
	root.Color = enemy.color
	root.Material = Enum.Material.Slate
	root.CanCollide = true
	root.CFrame = CFrame.new(spawnPosition)
	root.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = enemy.hp
	humanoid.Health = enemy.hp
	humanoid.WalkSpeed = enemy.walkSpeed
	humanoid.DisplayName = enemyName
	humanoid.Parent = model

	model.PrimaryPart = root
	model.Parent = enemiesFolder

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
		nextTouchDamageAtByUserId = {},
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
	record.humanoid:TakeDamage(damage)
	if record.humanoid.Health > 0 then
		fireEnemyCombatFeedback(player, "hit", record.model)
	end
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

					record.humanoid.WalkSpeed = record.enemy.walkSpeed
					if targetPosition then
						record.humanoid:MoveTo(targetPosition)
					end
				end
			end
		end
	end
end)
