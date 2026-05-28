-- AdminCommands.server.lua — slash commands for the game owner to test every system fast.
-- Place in: ServerScriptService/AdminCommands (Script)
--
-- Gating: only the game's CreatorId (or UserIds in Config.ADMIN_USERIDS) can run these.
-- For group games, change the gate to GroupService rank checks.
--
-- Commands (chat them in-game):
--   /help                     list commands
--   /coins <n>                grant coins
--   /tool <tier>              set tool tier (1-6)
--   /maxtool                  set tool to top tier
--   /depth <n>                set deepestBlock to n (and refresh HUD)
--   /give <rarity> [tier]     drop a random item of given rarity into inventory
--   /event <effect>           trigger event effect: 2x_rare | bonus_loot | gold_rush
--   /resetfresh               wipe player data to defaults (for testing FTUE)
--   /maxall                   coins=10M, tool=top, depth=200, all collections, 5 rebirths
--   /tp museum                teleport to your museum
--   /tp dig                   teleport back to dig site

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local ItemDatabase = require(ReplicatedStorage:WaitForChild("ItemDatabase"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ServerEvents = ReplicatedStorage:WaitForChild("ServerEvents")
local NotifyEvent = Remotes:WaitForChild("Notify")
local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD")
local ItemFoundEvent = Remotes:WaitForChild("ItemFound")
local TriggerWorldEvent = ServerEvents:WaitForChild("TriggerWorldEvent")

-- ═══════════════════════════════════════════════════════════════════
-- Authorization
-- ═══════════════════════════════════════════════════════════════════

local ADMIN_USERIDS = Config.ADMIN_USERIDS or {}
local creatorId = game.CreatorId

local function isAdmin(player)
	if player.UserId == creatorId then return true end
	for _, id in ipairs(ADMIN_USERIDS) do
		if player.UserId == id then return true end
	end
	return false
end

-- ═══════════════════════════════════════════════════════════════════
-- Helpers
-- ═══════════════════════════════════════════════════════════════════

local function getData(player)
	local cache = _G.DeepDig_playerData
	if not cache then return nil end
	return cache[player.UserId]
end

local function refreshHUD(player, data)
	local tool = Config.TOOLS[data.toolTier]
	local getInventoryCapacityLabel = _G.DeepDig_getInventoryCapacityLabel
	UpdateHUDEvent:FireClient(player, {
		coins = data.coins,
		depth = data.deepestBlock,
		toolName = tool and tool.name or "Rusty Shovel",
		toolTier = data.toolTier,
		blocksDug = data.totalBlocksDug,
		inventoryCount = #data.inventory,
		inventoryCapacity = getInventoryCapacityLabel and getInventoryCapacityLabel(data) or Config.DEFAULT_BACKPACK_CAPACITY,
		fragments = data.fragments,
	})
end

local function notify(player, msg, rarity)
	NotifyEvent:FireClient(player, "[admin] " .. msg, rarity or "Uncommon")
end

-- ═══════════════════════════════════════════════════════════════════
-- Commands
-- ═══════════════════════════════════════════════════════════════════

local commands = {}

commands.help = function(player)
	notify(player, "Commands: /coins N · /tool T · /maxtool · /depth N · /give RARITY [TIER] · /event NAME · /resetfresh · /maxall · /tp museum|dig", "Rare")
end

commands.coins = function(player, args)
	local n = tonumber(args[1])
	if not n then return notify(player, "usage: /coins <number>") end
	local data = getData(player); if not data then return end
	data.coins = math.max(0, n)
	notify(player, "coins set to " .. data.coins)
	refreshHUD(player, data)
end

commands.tool = function(player, args)
	local n = tonumber(args[1])
	if not n or not Config.TOOLS[n] then
		return notify(player, "usage: /tool <1-" .. #Config.TOOLS .. ">")
	end
	local data = getData(player); if not data then return end
	data.toolTier = n
	notify(player, "tool set to " .. Config.TOOLS[n].name, "Rare")
	refreshHUD(player, data)
end

commands.maxtool = function(player)
	local data = getData(player); if not data then return end
	data.toolTier = #Config.TOOLS
	notify(player, "tool maxed → " .. Config.TOOLS[#Config.TOOLS].name, "Legendary")
	refreshHUD(player, data)
end

commands.depth = function(player, args)
	local n = tonumber(args[1])
	if not n then return notify(player, "usage: /depth <blocks>") end
	local data = getData(player); if not data then return end
	data.deepestBlock = math.max(0, math.min(Config.GRID_DEPTH_BLOCKS, math.floor(n)))
	notify(player, "deepestBlock = " .. data.deepestBlock)
	refreshHUD(player, data)
end

commands.give = function(player, args)
	local rarity = args[1]
	local tierName = args[2]
	if not rarity then
		return notify(player, "usage: /give <Common|Uncommon|Rare|Epic|Legendary|Mythic> [tierName]")
	end
	local data = getData(player); if not data then return end
	if not tierName then
		tierName = ItemDatabase.getTierForDepth(data.deepestBlock)
	end
	local tierItems = ItemDatabase.ITEMS[tierName]
	if not tierItems then
		return notify(player, "unknown tier: " .. tostring(tierName))
	end
	local pool = {}
	for _, it in ipairs(tierItems) do
		if it.rarity == rarity then table.insert(pool, it) end
	end
	if #pool == 0 then
		return notify(player, "no " .. rarity .. " items in " .. tierName)
	end
	local item = pool[math.random(#pool)]
	local rarityData = ItemDatabase.RARITY[item.rarity]
	local sellValue = item.baseValue * (rarityData and rarityData.multiplier or 1)
	local grantedItem = { name = item.name, rarity = item.rarity, sellValue = sellValue }
	local tryAddInventoryItem = _G.DeepDig_tryAddInventoryItem
	if tryAddInventoryItem then
		if not tryAddInventoryItem(player, grantedItem) then
			refreshHUD(player, data)
			return
		end
	else
		table.insert(data.inventory, grantedItem)
	end
	data.collections[item.name] = true
	ItemFoundEvent:FireClient(player, { name = item.name, rarity = item.rarity, sellValue = sellValue, color = rarityData and rarityData.color })
	refreshHUD(player, data)
end

commands.event = function(player, args)
	local effect = args[1]
	if not effect then return notify(player, "usage: /event <2x_rare|bonus_loot|gold_rush>") end
	local match
	for _, e in ipairs(Config.EVENTS) do
		if e.effect == effect then match = e; break end
	end
	if not match then return notify(player, "unknown effect: " .. effect) end
	TriggerWorldEvent:Fire(match)
	notify(player, "fired " .. match.name, "Epic")
end

commands.resetfresh = function(player)
	local data = getData(player); if not data then return end
	for k, _ in pairs(data) do data[k] = nil end
	data.coins = Config.STARTING_COINS
	data.toolTier = 1
	data.totalBlocksDug = 0
	data.deepestBlock = 0
	data.inventory = {}
	data.collections = {}
	data.fragments = 0
	data.rebirths = 0
	data.totalEarned = 0
	data.lastLoginDate = ""
	data.loginStreak = 0
	data.ownedGamepasses = {}
	data.firstSellAffordabilityGrantUsed = false
	notify(player, "data reset — fresh profile", "Rare")
	refreshHUD(player, data)
end

commands.maxall = function(player)
	local data = getData(player); if not data then return end
	data.coins = 10000000
	data.totalEarned = 10000000
	data.toolTier = #Config.TOOLS
	data.deepestBlock = Config.GRID_DEPTH_BLOCKS
	data.totalBlocksDug = math.max(data.totalBlocksDug, 1000)
	data.rebirths = 5
	data.fragments = 1000
	for _, tier in ipairs(Config.TIERS) do
		local items = ItemDatabase.ITEMS[tier.name]
		if items then
			for _, it in ipairs(items) do data.collections[it.name] = true end
		end
	end
	notify(player, "GOD MODE — coins, top tool, deepest, all collections, 5 resurfaces", "Mythic")
	refreshHUD(player, data)
end

commands.tp = function(player, args)
	local where = args[1]
	if not player.Character then return end
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if where == "dig" then
		hrp.CFrame = CFrame.new(0, 8, 0)
		notify(player, "→ dig site")
	elseif where == "museum" then
		local pad = workspace:FindFirstChild("Museums")
		local mine = pad and pad:FindFirstChild(player.Name .. "_MuseumPad")
		if mine then
			hrp.CFrame = CFrame.new(mine.Position + Vector3.new(0, 4, 0))
			notify(player, "→ your museum")
		else
			notify(player, "museum not built yet — wait a moment after spawning")
		end
	else
		notify(player, "usage: /tp <museum|dig>")
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Chat handler
-- ═══════════════════════════════════════════════════════════════════

local function onChatted(player, message)
	if not isAdmin(player) then return end
	if message:sub(1, 1) ~= "/" then return end

	local parts = {}
	for word in message:gmatch("%S+") do table.insert(parts, word) end
	local cmd = parts[1] and parts[1]:sub(2):lower() or ""
	local args = {}
	for i = 2, #parts do table.insert(args, parts[i]) end

	local handler = commands[cmd]
	if handler then
		-- Server-side audit log: in-memory ring buffer (last 200) + Studio output
		_G.DeepDig_admin_audit = _G.DeepDig_admin_audit or {}
		table.insert(_G.DeepDig_admin_audit, {
			t = os.time(),
			userId = player.UserId,
			name = player.Name,
			cmd = cmd,
			args = table.concat(args, " "),
		})
		while #_G.DeepDig_admin_audit > 200 do
			table.remove(_G.DeepDig_admin_audit, 1)
		end
		print("[DeepDig][admin]", player.UserId, player.Name, cmd, table.concat(args, " "))

		local ok, err = pcall(handler, player, args)
		if not ok then
			notify(player, "error: " .. tostring(err), "Common")
		end
	end
end

local function bind(player)
	player.Chatted:Connect(function(message)
		onChatted(player, message)
	end)
	if isAdmin(player) then
		task.delay(2, function()
			notify(player, "admin commands enabled — type /help", "Legendary")
		end)
	end
end

Players.PlayerAdded:Connect(bind)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(function() bind(p) end)
end

print("[DeepDig] AdminCommands loaded (gated to creator + Config.ADMIN_USERIDS)")
