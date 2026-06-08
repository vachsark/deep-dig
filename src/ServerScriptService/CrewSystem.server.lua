-- CrewSystem.server.lua - in-server digging crews and co-op dig bonus helper
-- Place in: ServerScriptService/CrewSystem (Script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyEvent = Remotes:WaitForChild("Notify")
local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD")

local function getOrCreateRemote(name, className)
	local existing = Remotes:FindFirstChild(name)
	if existing then
		return existing
	end

	local remote = Instance.new(className or "RemoteEvent")
	remote.Name = name
	remote.Parent = Remotes
	return remote
end

local CrewCreateEvent = getOrCreateRemote("CrewCreate")
local CrewInviteEvent = getOrCreateRemote("CrewInvite")
local CrewRespondInviteEvent = getOrCreateRemote("CrewRespondInvite")
local CrewLeaveEvent = getOrCreateRemote("CrewLeave")
local CrewUpdateEvent = getOrCreateRemote("CrewUpdate")
local CrewMailboxSendEvent = getOrCreateRemote("CrewMailboxSend")
local CrewMailboxClaimEvent = getOrCreateRemote("CrewMailboxClaim")
local GetCrewStateFunc = getOrCreateRemote("GetCrewState", "RemoteFunction")

local crews = {}
local playerCrewId = {}
local pendingInvites = {}
local mailboxByUserId = {}
local nextCrewId = 0
local nextMailboxId = 0

local INVITE_TIMEOUT_SECONDS = 30
local CREW_LEADERBOARD_LIMIT = 5

local function getData(player)
	local cache = _G.DeepDig_playerData
	if not cache then
		return nil
	end

	return cache[player.UserId]
end

local function getBackpackCapacity(data)
	local helper = _G.DeepDig_getBackpackCapacity
	return helper and helper(data) or Config.DEFAULT_BACKPACK_CAPACITY
end

local function getInventoryCapacityLabel(data)
	local helper = _G.DeepDig_getInventoryCapacityLabel
	return helper and helper(data) or Config.DEFAULT_BACKPACK_CAPACITY
end

local function hasInventorySpace(data)
	if not data or not data.inventory then
		return false
	end

	local capacity = getBackpackCapacity(data)
	return not capacity or #data.inventory < capacity
end

local function fireInventoryHud(player, data)
	if player and data and UpdateHUDEvent then
		UpdateHUDEvent:FireClient(player, {
			inventoryCount = data.inventory and #data.inventory or 0,
			inventoryCapacity = getInventoryCapacityLabel(data),
		})
	end
end

local function cloneItem(item)
	if type(item) ~= "table" then
		return nil
	end
	if type(item.name) ~= "string" or item.name == "" then
		return nil
	end

	return {
		name = item.name,
		rarity = item.rarity or "Common",
		sellValue = item.sellValue or 0,
	}
end

local function cloneMailboxEntry(entry)
	if type(entry) ~= "table" then
		return nil
	end

	local id = math.floor(tonumber(entry.id) or 0)
	local item = cloneItem(entry.item)
	if id <= 0 or not item then
		return nil
	end

	return {
		id = id,
		fromUserId = math.floor(tonumber(entry.fromUserId) or 0),
		fromName = type(entry.fromName) == "string" and entry.fromName or "Crewmate",
		fromDisplayName = type(entry.fromDisplayName) == "string" and entry.fromDisplayName or "Crewmate",
		sentAt = math.floor(tonumber(entry.sentAt) or 0),
		item = item,
	}
end

local function bumpNextMailboxId(queue)
	if type(queue) ~= "table" then
		return
	end

	for _, entry in ipairs(queue) do
		local id = math.floor(tonumber(entry.id) or 0)
		if id > nextMailboxId then
			nextMailboxId = id
		end
	end
end

local function normalizeMailboxQueue(data)
	local normalized = {}
	if data and type(data.crewMailbox) == "table" then
		for _, entry in ipairs(data.crewMailbox) do
			local clone = cloneMailboxEntry(entry)
			if clone then
				table.insert(normalized, clone)
			end
		end
	end

	if data then
		data.crewMailbox = normalized
	end
	bumpNextMailboxId(normalized)
	return normalized
end

local function getFallbackMailboxQueue(userId)
	local queue = mailboxByUserId[userId]
	if not queue then
		queue = {}
		mailboxByUserId[userId] = queue
	end

	return queue
end

local function getMailboxQueue(player)
	local data = getData(player)
	if data then
		local queue = normalizeMailboxQueue(data)
		local fallback = mailboxByUserId[player.UserId]
		if fallback and #fallback > 0 then
			for _, entry in ipairs(fallback) do
				local clone = cloneMailboxEntry(entry)
				if clone then
					table.insert(queue, clone)
				end
			end
			mailboxByUserId[player.UserId] = nil
			bumpNextMailboxId(queue)
		end
		return queue, data
	end

	local queue = getFallbackMailboxQueue(player.UserId)
	bumpNextMailboxId(queue)
	return queue, nil
end

local function getMailboxPayload(player)
	local payload = {}
	if not player then
		return payload
	end

	local queue = getMailboxQueue(player)
	for _, entry in ipairs(queue) do
		local clone = cloneMailboxEntry(entry)
		if clone then
			table.insert(payload, clone)
		end
	end

	return payload
end

local function getCrewLevelForXP(xp)
	local level = 1
	local thresholds = Config.CREW_LEVEL_THRESHOLDS or {}
	for _, threshold in ipairs(thresholds) do
		if xp >= threshold then
			level = level + 1
		else
			break
		end
	end

	return level
end

local function getCrewFragmentBonus(level)
	local bonuses = Config.CREW_LEVEL_FRAGMENT_BONUSES
	if type(bonuses) == "table" then
		return bonuses[level] or bonuses[#bonuses] or Config.CREW_FRAGMENT_BONUS or 0
	end

	return Config.CREW_FRAGMENT_BONUS or 0
end

local function getCrewProgress(crew)
	local xp = crew and (crew.xp or 0) or 0
	local level = getCrewLevelForXP(xp)
	local thresholds = Config.CREW_LEVEL_THRESHOLDS or {}
	local previousThreshold = thresholds[level - 1] or 0
	local nextThreshold = thresholds[level]
	local xpInLevel = xp - previousThreshold
	local xpForNextLevel = nextThreshold and (nextThreshold - previousThreshold) or 0
	local xpToNextLevel = nextThreshold and math.max(nextThreshold - xp, 0) or 0

	return {
		xp = xp,
		level = level,
		xpInLevel = xpInLevel,
		xpForNextLevel = xpForNextLevel,
		xpToNextLevel = xpToNextLevel,
		nextLevelXP = nextThreshold,
		fragmentBonus = getCrewFragmentBonus(level),
	}
end

local function notify(player, message, rarity)
	if player and NotifyEvent then
		NotifyEvent:FireClient(player, message, rarity or "Common")
	end
end

local function getRoot(player)
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function getDistance(playerA, playerB)
	local rootA = getRoot(playerA)
	local rootB = getRoot(playerB)
	if not (rootA and rootB) then
		return nil
	end

	return (rootA.Position - rootB.Position).Magnitude
end

local function countMembers(crew)
	local count = 0
	for _ in pairs(crew.members) do
		count = count + 1
	end
	return count
end

local function getCrew(player)
	local crewId = player and playerCrewId[player.UserId]
	return crewId and crews[crewId] or nil
end

local function isPendingInviteValid(invite)
	if not invite then
		return false
	end

	if invite.expiresAt and os.clock() > invite.expiresAt then
		return false
	end

	return crews[invite.crewId] ~= nil
end

local function clearPendingInviteFor(player)
	if player then
		pendingInvites[player.UserId] = nil
	end
end

local function getSortedMembers(crew)
	local members = {}
	for userId in pairs(crew.members) do
		local member = Players:GetPlayerByUserId(userId)
		if member then
			table.insert(members, {
				userId = member.UserId,
				name = member.Name,
				displayName = member.DisplayName,
				isOwner = userId == crew.ownerUserId,
			})
		end
	end

	table.sort(members, function(a, b)
		return string.lower(a.displayName) < string.lower(b.displayName)
	end)

	return members
end

local function getTopCrews(viewerCrewId)
	local topCrews = {}
	for _, crew in pairs(crews) do
		local memberCount = countMembers(crew)
		if memberCount > 0 then
			local progress = getCrewProgress(crew)
			crew.level = progress.level

			local leader = Players:GetPlayerByUserId(crew.ownerUserId)
			table.insert(topCrews, {
				crewId = crew.id,
				leaderUserId = crew.ownerUserId,
				leaderName = leader and leader.Name or "Crew Leader",
				leaderDisplayName = leader and leader.DisplayName or "Crew Leader",
				level = progress.level,
				xp = progress.xp,
				memberCount = memberCount,
				maxSize = Config.CREW_MAX_SIZE,
				isPlayerCrew = crew.id == viewerCrewId,
			})
		end
	end

	table.sort(topCrews, function(a, b)
		if a.level == b.level then
			if a.xp == b.xp then
				if a.memberCount == b.memberCount then
					return a.leaderUserId < b.leaderUserId
				end
				return a.memberCount > b.memberCount
			end
			return a.xp > b.xp
		end
		return a.level > b.level
	end)

	local limited = {}
	for index, entry in ipairs(topCrews) do
		entry.rank = index
		if index <= CREW_LEADERBOARD_LIMIT then
			table.insert(limited, entry)
		end
	end

	return limited
end

local function getNearbyCandidates(player)
	local candidates = {}
	local playerRoot = getRoot(player)
	if not playerRoot then
		return candidates
	end

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and not playerCrewId[otherPlayer.UserId] then
			local otherRoot = getRoot(otherPlayer)
			if otherRoot then
				local distance = (playerRoot.Position - otherRoot.Position).Magnitude
				if distance <= Config.CREW_INVITE_RANGE then
					table.insert(candidates, {
						userId = otherPlayer.UserId,
						name = otherPlayer.Name,
						displayName = otherPlayer.DisplayName,
						distance = math.floor(distance + 0.5),
					})
				end
			end
		end
	end

	table.sort(candidates, function(a, b)
		if a.distance == b.distance then
			return string.lower(a.displayName) < string.lower(b.displayName)
		end
		return a.distance < b.distance
	end)

	return candidates
end

local function getPendingInvitePayload(player)
	local invite = pendingInvites[player.UserId]
	if not isPendingInviteValid(invite) then
		pendingInvites[player.UserId] = nil
		return nil
	end

	local inviter = Players:GetPlayerByUserId(invite.inviterUserId)
	if not inviter then
		pendingInvites[player.UserId] = nil
		return nil
	end

	return {
		crewId = invite.crewId,
		fromUserId = inviter.UserId,
		fromName = inviter.Name,
		fromDisplayName = inviter.DisplayName,
		expiresAt = invite.expiresAt,
	}
end

local function getCrewState(player, transient)
	local viewerCrewId = player and playerCrewId[player.UserId]
	local crew = viewerCrewId and crews[viewerCrewId] or nil
	local progress = getCrewProgress(crew)
	if crew then
		crew.level = progress.level
	end

	local payload = {
		inCrew = crew ~= nil,
		crewId = crew and crew.id or nil,
		maxSize = Config.CREW_MAX_SIZE,
		inviteRange = Config.CREW_INVITE_RANGE,
		coopRadius = Config.CREW_COOP_RADIUS,
		fragmentBonus = progress.fragmentBonus,
		crewLevel = progress.level,
		crewXP = progress.xp,
		crewXPInLevel = progress.xpInLevel,
		crewXPForNextLevel = progress.xpForNextLevel,
		crewXPToNextLevel = progress.xpToNextLevel,
		crewNextLevelXP = progress.nextLevelXP,
		topCrews = getTopCrews(viewerCrewId),
		members = crew and getSortedMembers(crew) or {},
		nearbyPlayers = getNearbyCandidates(player),
		pendingInvite = getPendingInvitePayload(player),
		mailboxItems = getMailboxPayload(player),
	}

	if type(transient) == "table" then
		for key, value in pairs(transient) do
			payload[key] = value
		end
	end

	payload.memberCount = #payload.members
	payload.mailboxCount = #payload.mailboxItems
	return payload
end

local function sendState(player, transient)
	if player and player.Parent == Players then
		CrewUpdateEvent:FireClient(player, getCrewState(player, transient))
	end
end

local function broadcastCrewState(crew, transient)
	if not crew then
		return
	end

	for userId in pairs(crew.members) do
		local member = Players:GetPlayerByUserId(userId)
		if member then
			sendState(member, transient)
		end
	end
end

local function refreshEveryone()
	for _, player in ipairs(Players:GetPlayers()) do
		sendState(player)
	end
end

local function createCrew(player)
	if playerCrewId[player.UserId] then
		notify(player, "You are already in a crew.", "Common")
		sendState(player)
		return nil
	end

	nextCrewId = nextCrewId + 1
	local crewId = "crew_" .. tostring(nextCrewId)
	local crew = {
		id = crewId,
		ownerUserId = player.UserId,
		xp = 0,
		level = 1,
		members = {
			[player.UserId] = true,
		},
	}

	crews[crewId] = crew
	playerCrewId[player.UserId] = crewId
	clearPendingInviteFor(player)
	notify(player, "Crew created. Invite a nearby player to start digging together.", "Uncommon")
	refreshEveryone()
	return crew
end

local function removePlayerFromCrew(player)
	local crew = getCrew(player)
	if not crew then
		sendState(player)
		return
	end

	crew.members[player.UserId] = nil
	playerCrewId[player.UserId] = nil
	local remaining = countMembers(crew)

	if remaining == 0 then
		crews[crew.id] = nil
	elseif crew.ownerUserId == player.UserId then
		for userId in pairs(crew.members) do
			crew.ownerUserId = userId
			break
		end
	end

	for targetUserId, invite in pairs(pendingInvites) do
		if invite.crewId == crew.id or invite.inviterUserId == player.UserId then
			pendingInvites[targetUserId] = nil
		end
	end

	notify(player, "You left the crew.", "Common")
	if remaining > 0 then
		broadcastCrewState(crew)
	end
	refreshEveryone()
end

local function validateCrewInvite(inviter, target)
	if not target then
		return false, "Player not found."
	end
	if target == inviter then
		return false, "You cannot invite yourself."
	end
	if playerCrewId[target.UserId] then
		return false, target.DisplayName .. " is already in a crew."
	end

	local crew = getCrew(inviter)
	if not crew then
		return false, "Create a crew before inviting players."
	end
	if countMembers(crew) >= Config.CREW_MAX_SIZE then
		return false, "Your crew is full."
	end

	local distance = getDistance(inviter, target)
	if not distance then
		return false, "Both players must be spawned to invite."
	end
	if distance > Config.CREW_INVITE_RANGE then
		return false, "Too far away. Move within " .. Config.CREW_INVITE_RANGE .. " studs."
	end

	return true, nil, crew
end

CrewCreateEvent.OnServerEvent:Connect(function(player)
	createCrew(player)
end)

CrewInviteEvent.OnServerEvent:Connect(function(player, targetUserId)
	local target = Players:GetPlayerByUserId(tonumber(targetUserId) or 0)
	local ok, reason, crew = validateCrewInvite(player, target)
	if not ok then
		notify(player, reason, "Common")
		sendState(player)
		return
	end

	pendingInvites[target.UserId] = {
		crewId = crew.id,
		inviterUserId = player.UserId,
		expiresAt = os.clock() + INVITE_TIMEOUT_SECONDS,
	}

	notify(player, "Crew invite sent to " .. target.DisplayName .. ".", "Uncommon")
	notify(target, player.DisplayName .. " invited you to a digging crew.", "Uncommon")
	sendState(player)
	sendState(target)
end)

CrewRespondInviteEvent.OnServerEvent:Connect(function(player, accepted)
	local invite = pendingInvites[player.UserId]
	if not isPendingInviteValid(invite) then
		pendingInvites[player.UserId] = nil
		notify(player, "Crew invite expired.", "Common")
		sendState(player)
		return
	end

	local crew = crews[invite.crewId]
	local inviter = Players:GetPlayerByUserId(invite.inviterUserId)
	pendingInvites[player.UserId] = nil

	if not accepted then
		if inviter then
			notify(inviter, player.DisplayName .. " declined the crew invite.", "Common")
			sendState(inviter)
		end
		sendState(player)
		return
	end

	if playerCrewId[player.UserId] then
		notify(player, "You are already in a crew.", "Common")
		sendState(player)
		return
	end
	if not inviter then
		notify(player, "Crew invite expired.", "Common")
		sendState(player)
		return
	end
	if countMembers(crew) >= Config.CREW_MAX_SIZE then
		notify(player, "That crew is full.", "Common")
		sendState(player)
		return
	end

	local distance = getDistance(inviter, player)
	if not distance or distance > Config.CREW_INVITE_RANGE then
		notify(player, "Move closer to accept the crew invite.", "Common")
		sendState(player)
		sendState(inviter)
		return
	end

	crew.members[player.UserId] = true
	playerCrewId[player.UserId] = crew.id
	notify(player, "Joined " .. inviter.DisplayName .. "'s crew.", "Rare")
	notify(inviter, player.DisplayName .. " joined your crew.", "Rare")
	refreshEveryone()
end)

CrewLeaveEvent.OnServerEvent:Connect(function(player)
	removePlayerFromCrew(player)
end)

CrewMailboxSendEvent.OnServerEvent:Connect(function(player, recipientUserId, itemIndex)
	local crew = getCrew(player)
	if not crew then
		notify(player, "Join a crew before sending mailbox items.", "Common")
		sendState(player)
		return
	end

	recipientUserId = math.floor(tonumber(recipientUserId) or 0)
	itemIndex = math.floor(tonumber(itemIndex) or 0)
	local recipient = Players:GetPlayerByUserId(recipientUserId)
	if not recipient or recipient == player then
		notify(player, "Pick an online crewmate to receive the item.", "Common")
		sendState(player)
		return
	end

	if playerCrewId[recipient.UserId] ~= crew.id or not crew.members[recipient.UserId] then
		notify(player, recipient.DisplayName .. " is not in your crew anymore.", "Common")
		sendState(player)
		return
	end

	local data = getData(player)
	local inventory = data and data.inventory
	if type(inventory) ~= "table" then
		notify(player, "Inventory is still loading. Try again in a moment.", "Common")
		sendState(player)
		return
	end

	local recipientQueue, recipientData = getMailboxQueue(recipient)
	if not recipientData then
		notify(player, recipient.DisplayName .. "'s mailbox is still loading. Try again in a moment.", "Common")
		sendState(player)
		return
	end

	local item = inventory[itemIndex]
	local clone = cloneItem(item)
	if not clone then
		notify(player, "That item is no longer in your backpack.", "Common")
		sendState(player)
		return
	end

	table.remove(inventory, itemIndex)
	nextMailboxId = nextMailboxId + 1
	local mailboxId = nextMailboxId
	table.insert(recipientQueue, {
		id = mailboxId,
		fromUserId = player.UserId,
		fromName = player.Name,
		fromDisplayName = player.DisplayName,
		sentAt = os.time(),
		item = clone,
	})

	fireInventoryHud(player, data)
	notify(player, "Sent " .. clone.name .. " to " .. recipient.DisplayName .. ".", clone.rarity)
	notify(recipient, player.DisplayName .. " sent you " .. clone.name .. ".", clone.rarity)
	sendState(player, {
		mailboxSent = {
			id = mailboxId,
			itemName = clone.name,
			rarity = clone.rarity,
			toUserId = recipient.UserId,
			toName = recipient.Name,
			toDisplayName = recipient.DisplayName,
		},
	})
	sendState(recipient, {
		mailboxReceived = {
			id = mailboxId,
			itemName = clone.name,
			rarity = clone.rarity,
			fromUserId = player.UserId,
			fromName = player.Name,
			fromDisplayName = player.DisplayName,
		},
	})
end)

CrewMailboxClaimEvent.OnServerEvent:Connect(function(player, mailboxId)
	mailboxId = math.floor(tonumber(mailboxId) or 0)
	local queue = getMailboxQueue(player)
	if #queue == 0 then
		notify(player, "Your crew mailbox is empty.", "Common")
		sendState(player)
		return
	end

	local entryIndex = nil
	local entry = nil
	for index, queued in ipairs(queue) do
		if queued.id == mailboxId then
			entryIndex = index
			entry = queued
			break
		end
	end

	if not entry then
		notify(player, "That mailbox item was already claimed.", "Common")
		sendState(player)
		return
	end

	local data = getData(player)
	if not data or type(data.inventory) ~= "table" then
		notify(player, "Inventory is still loading. Try again in a moment.", "Common")
		sendState(player)
		return
	end

	if not hasInventorySpace(data) then
		notify(player, "Backpack full - sell items before claiming mailbox items.", "Common")
		sendState(player)
		return
	end

	local clone = cloneItem(entry.item)
	if not clone then
		table.remove(queue, entryIndex)
		notify(player, "That mailbox item could not be claimed.", "Common")
		sendState(player)
		return
	end

	table.remove(queue, entryIndex)
	data.collections = data.collections or {}
	table.insert(data.inventory, clone)
	data.collections[clone.name] = true

	fireInventoryHud(player, data)
	notify(player, "Claimed " .. clone.name .. " from your crew mailbox.", clone.rarity)
	sendState(player, {
		mailboxClaimed = {
			id = entry.id,
			itemName = clone.name,
			rarity = clone.rarity,
			fromUserId = entry.fromUserId,
			fromName = entry.fromName,
			fromDisplayName = entry.fromDisplayName,
		},
	})
end)

GetCrewStateFunc.OnServerInvoke = function(player)
	return getCrewState(player)
end

Players.PlayerRemoving:Connect(function(player)
	clearPendingInviteFor(player)
	removePlayerFromCrew(player)
	mailboxByUserId[player.UserId] = nil
	for targetUserId, invite in pairs(pendingInvites) do
		if invite.inviterUserId == player.UserId then
			pendingInvites[targetUserId] = nil
		end
	end
end)

_G.DeepDig_hasNearbyCrewmate = function(player, radius)
	local crew = getCrew(player)
	if not crew then
		return false
	end

	local root = getRoot(player)
	if not root then
		return false
	end

	local maxDistance = radius or Config.CREW_COOP_RADIUS
	for userId in pairs(crew.members) do
		if userId ~= player.UserId then
			local member = Players:GetPlayerByUserId(userId)
			local memberRoot = getRoot(member)
			if memberRoot and (root.Position - memberRoot.Position).Magnitude <= maxDistance then
				return true, member
			end
		end
	end

	return false
end

local function awardCrewCoopDigXP(player, amount)
	local crew = getCrew(player)
	if not crew then
		return Config.CREW_FRAGMENT_BONUS or 0, false, 1, 0
	end

	local xpAmount = amount or Config.CREW_XP_PER_COOP_DIG or 1
	if xpAmount <= 0 then
		local progress = getCrewProgress(crew)
		return progress.fragmentBonus, false, progress.level, progress.xp
	end

	local beforeProgress = getCrewProgress(crew)
	crew.xp = (crew.xp or 0) + xpAmount
	local afterProgress = getCrewProgress(crew)
	crew.level = afterProgress.level

	if afterProgress.level > beforeProgress.level then
		local levelUp = {
			level = afterProgress.level,
			fragmentBonus = afterProgress.fragmentBonus,
		}

		for userId in pairs(crew.members) do
			local member = Players:GetPlayerByUserId(userId)
			if member then
				notify(
					member,
					"Crew reached Level " .. tostring(afterProgress.level) .. "! Co-op bonus is now +" .. tostring(afterProgress.fragmentBonus) .. " fragments.",
					"Rare"
				)
			end
		end

		broadcastCrewState(crew, {
			levelUp = levelUp,
		})
	end

	refreshEveryone()
	return afterProgress.fragmentBonus, afterProgress.level > beforeProgress.level, afterProgress.level, afterProgress.xp
end

_G.DeepDig_awardCrewCoopDigXP = function(player, amount)
	return awardCrewCoopDigXP(player, amount)
end

print("[DeepDig] CrewSystem loaded")
