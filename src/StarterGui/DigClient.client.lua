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
local CLIENT_ATTACK_RANGE = 8
local DEBUG_DIG_CLIENT = false

local character = player.Character or player.CharacterAdded:Wait()
local equippedExcavator = nil
local playerGui = player:WaitForChild("PlayerGui")

local targetHighlight = Instance.new("Highlight")
targetHighlight.Name = "DeepDigTargetHighlight"
targetHighlight.Enabled = false
targetHighlight.FillTransparency = 0.86
targetHighlight.OutlineTransparency = 0.12
targetHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
targetHighlight.Parent = workspace

local moveCloserCue = Instance.new("BillboardGui")
moveCloserCue.Name = "DeepDigMoveCloserCue"
moveCloserCue.Enabled = false
moveCloserCue.AlwaysOnTop = true
moveCloserCue.Size = UDim2.fromOffset(120, 32)
moveCloserCue.StudsOffset = Vector3.new(0, 3.2, 0)
moveCloserCue.MaxDistance = 120
moveCloserCue.Parent = playerGui

local moveCloserLabel = Instance.new("TextLabel")
moveCloserLabel.Name = "Label"
moveCloserLabel.BackgroundTransparency = 1
moveCloserLabel.Size = UDim2.fromScale(1, 1)
moveCloserLabel.Font = Enum.Font.GothamBold
moveCloserLabel.Text = "Move closer"
moveCloserLabel.TextColor3 = Color3.fromRGB(255, 210, 190)
moveCloserLabel.TextStrokeColor3 = Color3.fromRGB(45, 25, 20)
moveCloserLabel.TextStrokeTransparency = 0.25
moveCloserLabel.TextScaled = true
moveCloserLabel.Parent = moveCloserCue

local function debugLog(...)
	if DEBUG_DIG_CLIENT then
		print(...)
	end
end

local function clearMoveCloserCue()
	moveCloserCue.Enabled = false
	moveCloserCue.Adornee = nil
end

local function clearTargetHighlight()
	targetHighlight.Enabled = false
	targetHighlight.Adornee = nil
	clearMoveCloserCue()
end

local function getModelRoot(model)
	if not model then
		return nil
	end

	if model.PrimaryPart then
		return model.PrimaryPart
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	root = model:FindFirstChild("RootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	root = model:FindFirstChild("UpperTorso")
	if root and root:IsA("BasePart") then
		return root
	end

	root = model:FindFirstChild("Torso")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function getPlayerRoot()
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function isEnemyInClientAttackRange(enemyModel)
	local playerRoot = getPlayerRoot()
	local enemyRoot = getModelRoot(enemyModel)
	if not playerRoot or not enemyRoot then
		return true, enemyRoot
	end

	return (playerRoot.Position - enemyRoot.Position).Magnitude <= CLIENT_ATTACK_RANGE, enemyRoot
end

local function showMoveCloserCue(enemyModel)
	local enemyRoot = getModelRoot(enemyModel)
	if not enemyRoot then
		clearMoveCloserCue()
		return
	end

	moveCloserCue.Adornee = enemyRoot
	moveCloserCue.Enabled = true
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
		local isInRange = isEnemyInClientAttackRange(targetInstance)
		targetHighlight.Adornee = targetInstance
		if isInRange then
			targetHighlight.FillColor = Color3.fromRGB(255, 65, 65)
			targetHighlight.OutlineColor = Color3.fromRGB(255, 35, 35)
			targetHighlight.FillTransparency = 0.86
			targetHighlight.OutlineTransparency = 0.12
			clearMoveCloserCue()
		else
			targetHighlight.FillColor = Color3.fromRGB(120, 78, 78)
			targetHighlight.OutlineColor = Color3.fromRGB(150, 110, 110)
			targetHighlight.FillTransparency = 0.92
			targetHighlight.OutlineTransparency = 0.35
			showMoveCloserCue(targetInstance)
		end
		targetHighlight.Enabled = true
	elseif targetType == TARGET_DIG_BLOCK then
		targetHighlight.Adornee = targetInstance
		targetHighlight.FillColor = Color3.fromRGB(255, 190, 70)
		targetHighlight.OutlineColor = Color3.fromRGB(255, 170, 35)
		targetHighlight.FillTransparency = 0.86
		targetHighlight.OutlineTransparency = 0.12
		targetHighlight.Enabled = true
		clearMoveCloserCue()
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
		local isInRange = isEnemyInClientAttackRange(targetInstance)
		if not isInRange then
			debugLog("[DeepDig dig] enemy hit ignored: move closer:", targetInstance.Name)
			showMoveCloserCue(targetInstance)
			return
		end

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
