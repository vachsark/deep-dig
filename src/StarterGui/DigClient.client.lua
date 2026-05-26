-- DigClient.client.lua — Client-side dig detection
-- Place in: StarterGui/DigClient (LocalScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DigRequest = Remotes:WaitForChild("DigRequest", 10)
local EnemyHitEvent = Remotes:WaitForChild("EnemyHitEvent", 10)

local TARGET_DIG_BLOCK = "DigBlock"
local TARGET_ENEMY = "Enemy"
local DEBUG_DIG_CLIENT = false

local character = player.Character or player.CharacterAdded:Wait()
local equippedExcavator = nil

local targetHighlight = Instance.new("Highlight")
targetHighlight.Name = "DeepDigTargetHighlight"
targetHighlight.Enabled = false
targetHighlight.FillTransparency = 0.86
targetHighlight.OutlineTransparency = 0.12
targetHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
targetHighlight.Parent = workspace

local function debugLog(...)
	if DEBUG_DIG_CLIENT then
		print(...)
	end
end

local function clearTargetHighlight()
	targetHighlight.Enabled = false
	targetHighlight.Adornee = nil
end

local function classifyTarget(target)
	if not target or not DigRequest or not EnemyHitEvent then
		return nil
	end

	local enemiesFolder = workspace:FindFirstChild("Enemies")
	local enemyModel = target:FindFirstAncestorOfClass("Model")
	if enemiesFolder and enemyModel and enemyModel:IsDescendantOf(enemiesFolder) then
		return TARGET_ENEMY, enemyModel
	end

	if not target:GetAttribute("Depth") then
		return nil
	end

	local digSite = workspace:FindFirstChild("DigSite")
	if not digSite or not target:IsDescendantOf(digSite) then
		return nil
	end

	return TARGET_DIG_BLOCK, target
end

local function updateTargetHighlight()
	if not equippedExcavator or not equippedExcavator.Parent then
		clearTargetHighlight()
		return
	end

	local targetType, targetInstance = classifyTarget(mouse.Target)
	if targetType == TARGET_ENEMY then
		targetHighlight.Adornee = targetInstance
		targetHighlight.FillColor = Color3.fromRGB(255, 65, 65)
		targetHighlight.OutlineColor = Color3.fromRGB(255, 35, 35)
		targetHighlight.Enabled = true
	elseif targetType == TARGET_DIG_BLOCK then
		targetHighlight.Adornee = targetInstance
		targetHighlight.FillColor = Color3.fromRGB(255, 190, 70)
		targetHighlight.OutlineColor = Color3.fromRGB(255, 170, 35)
		targetHighlight.Enabled = true
	else
		clearTargetHighlight()
	end
end

-- When the Excavator tool is activated (clicked), check what we're pointing at
local function onToolActivated()
	local target = mouse.Target
	if not target then
		debugLog("[DeepDig dig] click ignored: no mouse target (clicked sky/void?)")
		return
	end

	local targetType, targetInstance = classifyTarget(target)
	if targetType == TARGET_ENEMY then
		debugLog("[DeepDig dig] enemy hit:", targetInstance.Name)
		EnemyHitEvent:FireServer(targetInstance)
		return
	end

	if targetType ~= TARGET_DIG_BLOCK then
		debugLog("[DeepDig dig] click ignored: invalid target:", target:GetFullName())
		return
	end

	-- Send the block reference to the server
	debugLog(("[DeepDig dig] firing DigRequest for %s (depth=%s)"):format(targetInstance.Name, tostring(targetInstance:GetAttribute("Depth"))))
	DigRequest:FireServer(targetInstance)
end

-- Watch for the Excavator tool being equipped
local hookedExcavators = {}
local function watchTool(tool)
	if tool:IsA("Tool") and tool.Name == "Excavator" and not hookedExcavators[tool] then
		hookedExcavators[tool] = true
		tool.Activated:Connect(onToolActivated)
		tool.Equipped:Connect(function()
			equippedExcavator = tool
			updateTargetHighlight()
		end)
		tool.Unequipped:Connect(function()
			if equippedExcavator == tool then
				equippedExcavator = nil
			end
			clearTargetHighlight()
		end)
		tool.AncestryChanged:Connect(function()
			if equippedExcavator == tool and not tool.Parent then
				equippedExcavator = nil
				clearTargetHighlight()
			end
		end)
		if tool.Parent == character then
			equippedExcavator = tool
			updateTargetHighlight()
		end
		debugLog("[DeepDig dig] Excavator detected and Activated bound:", tool:GetFullName())
	end
end

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
	equippedExcavator = nil
	clearTargetHighlight()
	newChar.ChildAdded:Connect(watchTool)
end)

RunService.RenderStepped:Connect(updateTargetHighlight)

if not DigRequest or not EnemyHitEvent then
	warn("[DeepDig dig] targeting disabled: DigRequest or EnemyHitEvent remote missing")
	clearTargetHighlight()
end

print("[DeepDig] DigClient loaded")
