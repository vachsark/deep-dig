-- DigClient.client.lua — Client-side dig detection
-- Place in: StarterGui/DigClient (LocalScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DigRequest = Remotes:WaitForChild("DigRequest")
local EnemyHitEvent = Remotes:WaitForChild("EnemyHitEvent")

-- When the Excavator tool is activated (clicked), check what we're pointing at
local function onToolActivated()
	local target = mouse.Target
	if not target then
		print("[DeepDig dig] click ignored: no mouse target (clicked sky/void?)")
		return
	end

	local enemiesFolder = workspace:FindFirstChild("Enemies")
	local enemyModel = target:FindFirstAncestorOfClass("Model")
	if enemiesFolder and enemyModel and enemyModel:IsDescendantOf(enemiesFolder) then
		print("[DeepDig dig] enemy hit:", enemyModel.Name)
		EnemyHitEvent:FireServer(enemyModel)
		return
	end

	-- Must be a dig site block (has Depth attribute)
	if not target:GetAttribute("Depth") then
		print(("[DeepDig dig] click ignored: target %q has no Depth attribute (probably the spawn pad, a wall, or terrain)"):format(target:GetFullName()))
		return
	end

	local digSite = workspace:FindFirstChild("DigSite")
	if not digSite then
		print("[DeepDig dig] click ignored: workspace.DigSite folder missing (server-side DigSystem may not have run yet)")
		return
	end
	if not target:IsDescendantOf(digSite) then
		print("[DeepDig dig] click ignored: target is not in DigSite folder:", target:GetFullName())
		return
	end

	-- Send the block reference to the server
	print(("[DeepDig dig] firing DigRequest for %s (depth=%s)"):format(target.Name, tostring(target:GetAttribute("Depth"))))
	DigRequest:FireServer(target)
end

-- Watch for the Excavator tool being equipped
local hookedExcavators = {}
local function watchTool(tool)
	if tool:IsA("Tool") and tool.Name == "Excavator" and not hookedExcavators[tool] then
		hookedExcavators[tool] = true
		tool.Activated:Connect(onToolActivated)
		print("[DeepDig dig] Excavator detected and Activated bound:", tool:GetFullName())
	end
end

local character = player.Character or player.CharacterAdded:Wait()

-- Watch current and future tools
for _, child in ipairs(player.Backpack:GetChildren()) do
	watchTool(child)
end
player.Backpack.ChildAdded:Connect(watchTool)

-- Also watch character (tool moves there when equipped)
character.ChildAdded:Connect(watchTool)
for _, child in ipairs(character:GetChildren()) do
	watchTool(child)
end

-- Handle respawn
player.CharacterAdded:Connect(function(newChar)
	character = newChar
	newChar.ChildAdded:Connect(watchTool)
end)

print("[DeepDig] DigClient loaded")
