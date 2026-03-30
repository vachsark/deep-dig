-- DigClient.client.lua — Client-side dig detection
-- Place in: StarterGui/DigClient (LocalScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DigRequest = Remotes:WaitForChild("DigRequest")

-- When the Excavator tool is activated (clicked), check what we're pointing at
local function onToolActivated()
	local target = mouse.Target
	if not target then return end

	-- Must be a dig site block (has Depth attribute)
	if not target:GetAttribute("Depth") then return end

	local digSite = workspace:FindFirstChild("DigSite")
	if not digSite then return end
	if not target:IsDescendantOf(digSite) then return end

	-- Send the block reference to the server
	DigRequest:FireServer(target)
end

-- Watch for the Excavator tool being equipped
local function watchTool(tool)
	if tool:IsA("Tool") and tool.Name == "Excavator" then
		tool.Activated:Connect(onToolActivated)
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
