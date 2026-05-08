-- CombatRespawn.server.lua - forgiving surface respawn after enemy knockouts
-- Place in: ServerScriptService/CombatRespawn (Script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyEvent = Remotes:WaitForChild("Notify")
local CombatRespawnFeedback = Remotes:FindFirstChild("CombatRespawnFeedback")
if not CombatRespawnFeedback then
	CombatRespawnFeedback = Instance.new("RemoteEvent")
	CombatRespawnFeedback.Name = "CombatRespawnFeedback"
	CombatRespawnFeedback.Parent = Remotes
end

local ENEMY_DAMAGE_WINDOW = 6
local RESPAWN_WINDOW = 20
local SURFACE_OFFSET = Vector3.new(0, 5, 0)
local pendingCombatRespawnAtByUserId = {}

local function getSurfaceCFrame()
	local digSite = workspace:FindFirstChild("DigSite")
	if digSite then
		local spawnLocation = digSite:FindFirstChild("SpawnLocation")
		if spawnLocation and spawnLocation:IsA("BasePart") then
			return spawnLocation.CFrame + SURFACE_OFFSET
		end

		local spawnPlatform = digSite:FindFirstChild("SpawnPlatform")
		if spawnPlatform and spawnPlatform:IsA("BasePart") then
			return spawnPlatform.CFrame + Vector3.new(0, spawnPlatform.Size.Y / 2 + 4, 0)
		end
	end

	return CFrame.new(0, 9, 0)
end

local function wasRecentlyEnemyDamaged(player)
	local lastEnemyDamageAt = player:GetAttribute("DeepDig_LastEnemyDamageAt")
	return type(lastEnemyDamageAt) == "number" and os.clock() - lastEnemyDamageAt <= ENEMY_DAMAGE_WINDOW
end

local function surfaceCharacter(player, character)
	local markedAt = pendingCombatRespawnAtByUserId[player.UserId]
	if not markedAt then
		return
	end

	if os.clock() - markedAt > RESPAWN_WINDOW then
		pendingCombatRespawnAtByUserId[player.UserId] = nil
		return
	end

	local root = character:WaitForChild("HumanoidRootPart", 5)
	if not root then
		return
	end

	pendingCombatRespawnAtByUserId[player.UserId] = nil
	character:PivotTo(getSurfaceCFrame())
	CombatRespawnFeedback:FireClient(player, {
		type = "enemy_knockout_resurface",
	})
	NotifyEvent:FireClient(player, "Knocked out - resurfaced safely.", "Common")
end

local function watchCharacter(player, character)
	task.defer(function()
		surfaceCharacter(player, character)
	end)

	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end

	humanoid.Died:Connect(function()
		if wasRecentlyEnemyDamaged(player) then
			pendingCombatRespawnAtByUserId[player.UserId] = os.clock()
		end
	end)
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)

	if player.Character then
		task.spawn(function()
			watchCharacter(player, player.Character)
		end)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		onPlayerAdded(player)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	pendingCombatRespawnAtByUserId[player.UserId] = nil
end)
