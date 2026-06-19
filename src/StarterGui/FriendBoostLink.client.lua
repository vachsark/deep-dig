-- FriendBoostLink.client.lua - local friend dig-speed boost link beam
-- Place in: StarterGui/FriendBoostLink (LocalScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if not Remotes then
	warn("[FriendBoostLink] Remotes folder missing - boost links disabled.")
	return
end

local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD", 5)
if not UpdateHUDEvent then
	warn("[FriendBoostLink] UpdateHUD remote missing - boost links disabled.")
	return
end

local INSTANCE_PREFIX = "DeepDigFriendBoost"
local LOCAL_ATTACHMENT_NAME = INSTANCE_PREFIX .. "LocalAttachment"
local FRIEND_ATTACHMENT_NAME = INSTANCE_PREFIX .. "FriendAttachment"
local BEAM_NAME = INSTANCE_PREFIX .. "Beam"
local MAX_LINK_DISTANCE = 105
local REFRESH_INTERVAL = 0.2

local boostActive = false
local activeLinks = {}
local characterConnections = {}
local refreshElapsed = 0

local function getRootPart(targetPlayer)
	local character = targetPlayer and targetPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function destroyNamedLinkInstances(root)
	if not root then
		return
	end

	for _, child in ipairs(root:GetChildren()) do
		if string.sub(child.Name, 1, #INSTANCE_PREFIX) == INSTANCE_PREFIX then
			child:Destroy()
		end
	end
end

local function cleanupLink(userId)
	local link = activeLinks[userId]
	if not link then
		return
	end

	if link.beam then
		link.beam:Destroy()
	end
	if link.localAttachment then
		link.localAttachment:Destroy()
	end
	if link.friendAttachment then
		link.friendAttachment:Destroy()
	end

	activeLinks[userId] = nil
end

local function cleanupAllLinks()
	for userId in pairs(activeLinks) do
		cleanupLink(userId)
	end
end

local function isRobloxFriend(otherPlayer)
	if not otherPlayer or otherPlayer == player then
		return false
	end

	local success, isFriend = pcall(function()
		return player:IsFriendsWith(otherPlayer.UserId)
	end)

	return success and isFriend == true
end

local function getDistance(localRoot, friendRoot)
	return (localRoot.Position - friendRoot.Position).Magnitude
end

local function createLink(otherPlayer, localRoot, friendRoot)
	cleanupLink(otherPlayer.UserId)
	destroyNamedLinkInstances(friendRoot)

	local localAttachment = Instance.new("Attachment")
	localAttachment.Name = LOCAL_ATTACHMENT_NAME .. tostring(otherPlayer.UserId)
	localAttachment.Position = Vector3.new(0, 0.2, 0)
	localAttachment.Parent = localRoot

	local friendAttachment = Instance.new("Attachment")
	friendAttachment.Name = FRIEND_ATTACHMENT_NAME .. tostring(player.UserId)
	friendAttachment.Position = Vector3.new(0, 0.2, 0)
	friendAttachment.Parent = friendRoot

	local beam = Instance.new("Beam")
	beam.Name = BEAM_NAME .. tostring(otherPlayer.UserId)
	beam.Attachment0 = localAttachment
	beam.Attachment1 = friendAttachment
	beam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(95, 235, 155)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 222, 94)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(95, 235, 155)),
	})
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.62),
		NumberSequenceKeypoint.new(0.5, 0.18),
		NumberSequenceKeypoint.new(1, 0.62),
	})
	beam.Width0 = 0.16
	beam.Width1 = 0.16
	beam.FaceCamera = true
	beam.LightEmission = 0.55
	beam.LightInfluence = 0
	beam.Segments = 8
	beam.TextureSpeed = 0.75
	beam.Parent = localRoot

	activeLinks[otherPlayer.UserId] = {
		beam = beam,
		localAttachment = localAttachment,
		friendAttachment = friendAttachment,
		localRoot = localRoot,
		friendRoot = friendRoot,
		phase = os.clock() % 1,
	}
end

local function refreshPlayerLink(otherPlayer)
	if otherPlayer == player then
		return
	end

	local userId = otherPlayer.UserId
	if not boostActive or not isRobloxFriend(otherPlayer) then
		cleanupLink(userId)
		return
	end

	local localRoot = getRootPart(player)
	local friendRoot = getRootPart(otherPlayer)
	if not localRoot or not friendRoot then
		cleanupLink(userId)
		return
	end

	if getDistance(localRoot, friendRoot) > MAX_LINK_DISTANCE then
		cleanupLink(userId)
		return
	end

	local link = activeLinks[userId]
	if not link or link.localRoot ~= localRoot or link.friendRoot ~= friendRoot then
		createLink(otherPlayer, localRoot, friendRoot)
	end
end

local function refreshLinks()
	if not boostActive then
		cleanupAllLinks()
		return
	end

	local wanted = {}
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			wanted[otherPlayer.UserId] = true
			refreshPlayerLink(otherPlayer)
		end
	end

	for userId in pairs(activeLinks) do
		if not wanted[userId] then
			cleanupLink(userId)
		end
	end
end

local function pulseLinks()
	local now = os.clock()
	for userId, link in pairs(activeLinks) do
		local beam = link.beam
		if not beam or not beam.Parent or not link.localAttachment.Parent or not link.friendAttachment.Parent then
			cleanupLink(userId)
		else
			local alpha = (math.sin((now + link.phase) * 3.4) + 1) * 0.5
			local width = 0.12 + (alpha * 0.08)
			local centerTransparency = 0.16 + ((1 - alpha) * 0.12)

			beam.Width0 = width
			beam.Width1 = width
			beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.68),
				NumberSequenceKeypoint.new(0.5, centerTransparency),
				NumberSequenceKeypoint.new(1, 0.68),
			})
		end
	end
end

local function ensureCharacterConnection(otherPlayer)
	if characterConnections[otherPlayer.UserId] then
		return
	end

	characterConnections[otherPlayer.UserId] = otherPlayer.CharacterAdded:Connect(function()
		cleanupLink(otherPlayer.UserId)
		task.delay(0.25, refreshLinks)
	end)
end

local function disconnectCharacterConnection(userId)
	local connection = characterConnections[userId]
	if connection then
		connection:Disconnect()
		characterConnections[userId] = nil
	end
end

for _, otherPlayer in ipairs(Players:GetPlayers()) do
	if otherPlayer ~= player then
		ensureCharacterConnection(otherPlayer)
	end
end

Players.PlayerAdded:Connect(function(otherPlayer)
	if otherPlayer ~= player then
		ensureCharacterConnection(otherPlayer)
		task.delay(0.25, refreshLinks)
	end
end)

Players.PlayerRemoving:Connect(function(otherPlayer)
	cleanupLink(otherPlayer.UserId)
	disconnectCharacterConnection(otherPlayer.UserId)
end)

player.CharacterAdded:Connect(function()
	cleanupAllLinks()
	task.delay(0.25, refreshLinks)
end)

UpdateHUDEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.friendBoostActive == nil then
		return
	end

	boostActive = payload.friendBoostActive == true
	if boostActive then
		refreshLinks()
	else
		cleanupAllLinks()
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	refreshElapsed = refreshElapsed + deltaTime
	if refreshElapsed >= REFRESH_INTERVAL then
		refreshElapsed = 0
		refreshLinks()
	end

	pulseLinks()
end)
