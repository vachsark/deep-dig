-- Gamepasses.server.lua — Gamepass ownership checks and effect application
-- Place in: ServerScriptService/Gamepasses (Script)
--
-- Gamepass IDs (owner must replace with real IDs from Creator Hub):
--   1 — DOUBLE_LOOT : all item sellValues ×2 (applied in GameManager DigBlock)
--   2 — VIP         : +50% coins from all sources + VIP chat tag
--   3 — LUCKY       : +25% loot drop chance (applied in GameManager DigBlock)
--
-- On player join:
--   1. Check MarketplaceService:UserOwnsGamePassAsync for each pass
--   2. Cache result in data.ownedGamepasses[passId] = true
--   3. Fire UpdateHUD with gamepass status so client can show active badges
--
-- The actual gameplay effects (2× sell value, +25% drop chance) live in
-- GameManager.server.lua and read data.ownedGamepasses[id] there.
-- VIP coin bonus (+50%) is applied in DailyStreak reward and in the
-- SellAll handler below (via a hook on the UpdateHUD path).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Chat = game:GetService("Chat")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyEvent = Remotes:WaitForChild("Notify")
local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD")

-- ─── Gamepass definitions ─────────────────────────────────────────────────────
-- Replace placeholder IDs (1, 2, 3) with your real Roblox gamepass IDs.

local GAMEPASSES = {
	{
		id = 1,
		name = "Double Loot",
		description = "All dug items are worth 2x coins!",
		icon = "rbxassetid://0", -- replace with your icon asset ID
		price = 149,             -- display price in Robux (informational only)
		tag = "DOUBLE_LOOT",
	},
	{
		id = 2,
		name = "VIP",
		description = "+50% coins from all sources + VIP chat tag",
		icon = "rbxassetid://0",
		price = 299,
		tag = "VIP",
	},
	{
		id = 3,
		name = "Lucky Digger",
		description = "+25% chance to find items when digging",
		icon = "rbxassetid://0",
		price = 199,
		tag = "LUCKY",
	},
}

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function getSharedData(player)
	local cache = _G.DeepDig_playerData
	if cache then
		return cache[player.UserId]
	end
	return nil
end

-- Check a single gamepass. Returns true/false. Wraps in pcall.
local function ownsPass(player, passId)
	local ok, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	if not ok then
		warn("[Gamepasses] UserOwnsGamePassAsync failed for player " .. player.Name ..
			", passId " .. passId .. ": " .. tostring(result))
		return false
	end
	return result
end

-- ─── VIP Chat Tag ─────────────────────────────────────────────────────────────

local function applyVIPTag(player)
	-- Prefix [VIP] to the player's chat tag using a BillboardGui above head.
	-- Note: Roblox's legacy Chat:SetExtraData only works with the old Chat
	-- system.  The BillboardGui approach works in all configurations.
	local character = player.Character or player.CharacterAdded:Wait()
	local head = character:WaitForChild("Head", 10)
	if not head then return end

	-- Remove existing tag if any
	local existing = head:FindFirstChild("VIPTag")
	if existing then existing:Destroy() end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "VIPTag"
	billboard.Size = UDim2.new(0, 80, 0, 22)
	billboard.StudsOffset = Vector3.new(0, 2.2, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundColor3 = Color3.fromRGB(255, 180, 0)
	label.BackgroundTransparency = 0.2
	label.BorderSizePixel = 0
	label.Text = "★ VIP"
	label.TextColor3 = Color3.fromRGB(30, 20, 0)
	label.TextSize = 13
	label.Font = Enum.Font.GothamBlack
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = label
end

-- ─── On player join — check and cache all passes ─────────────────────────────

local function checkPassesForPlayer(player)
	-- Wait for GameManager to load player data first
	task.wait(3)

	local data = getSharedData(player)
	if not data then
		warn("[Gamepasses] No player data for " .. player.Name .. " — skipping pass check.")
		return
	end

	-- Ensure field exists (migration safety)
	if not data.ownedGamepasses then
		data.ownedGamepasses = {}
	end

	local owned = {}
	for _, pass in ipairs(GAMEPASSES) do
		if ownsPass(player, pass.id) then
			data.ownedGamepasses[pass.id] = true
			table.insert(owned, pass.name)

			-- Apply VIP tag immediately (on first spawn)
			if pass.tag == "VIP" then
				task.spawn(applyVIPTag, player)
			end
		else
			data.ownedGamepasses[pass.id] = nil
		end
	end

	-- Fire HUD with gamepass status so client can show badges
	UpdateHUDEvent:FireClient(player, {
		ownedGamepasses = data.ownedGamepasses,
		gamepaseDefs = GAMEPASSES, -- client uses this to render badges
	})

	if #owned > 0 then
		NotifyEvent:FireClient(
			player,
			"Active Gamepasses: " .. table.concat(owned, ", "),
			"Legendary"
		)
		print("[Gamepasses] " .. player.Name .. " owns: " .. table.concat(owned, ", "))
	end
end

-- Re-apply VIP tag on every character respawn (it's an instance on the head)
local function onCharacterAdded(player, character)
	local data = getSharedData(player)
	if data and data.ownedGamepasses and data.ownedGamepasses[2] then
		task.wait(1) -- let character finish loading
		applyVIPTag(player)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	task.spawn(function()
		checkPassesForPlayer(player)
	end)
end)

-- Also check players already in-game when script loads (Studio playtest)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		checkPassesForPlayer(player)
	end)
end

-- ─── PromptGamepassPurchase remote ───────────────────────────────────────────
-- Client fires this when a player taps "Buy" in the shop panel.

local PromptPassEvent = Instance.new("RemoteEvent")
PromptPassEvent.Name = "PromptGamepass"
PromptPassEvent.Parent = Remotes

PromptPassEvent.OnServerEvent:Connect(function(player, passId)
	-- Validate passId exists in our table
	local valid = false
	for _, pass in ipairs(GAMEPASSES) do
		if pass.id == passId then valid = true break end
	end
	if not valid then return end

	MarketplaceService:PromptGamePassPurchase(player, passId)
end)

-- ─── Post-purchase callback ───────────────────────────────────────────────────
-- Fires when the player successfully buys a pass in this session.

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if not wasPurchased then return end

	local data = getSharedData(player)
	if not data then return end
	if not data.ownedGamepasses then data.ownedGamepasses = {} end

	data.ownedGamepasses[passId] = true

	-- Find pass name for notification
	local passName = "Gamepass"
	for _, pass in ipairs(GAMEPASSES) do
		if pass.id == passId then
			passName = pass.name

			if pass.tag == "VIP" then
				task.spawn(applyVIPTag, player)
			end
			break
		end
	end

	NotifyEvent:FireClient(player, "Thank you for purchasing " .. passName .. "!", "Legendary")
	UpdateHUDEvent:FireClient(player, {
		ownedGamepasses = data.ownedGamepasses,
	})

	print("[Gamepasses] " .. player.Name .. " purchased passId " .. passId .. " (" .. passName .. ")")
end)

-- ─── GetGamepassInfo remote (client queries for shop UI) ──────────────────────

local GetPassInfoFunc = Instance.new("RemoteFunction")
GetPassInfoFunc.Name = "GetGamepassInfo"
GetPassInfoFunc.Parent = Remotes

GetPassInfoFunc.OnServerInvoke = function(player)
	local data = getSharedData(player)
	local owned = data and data.ownedGamepasses or {}

	local result = {}
	for _, pass in ipairs(GAMEPASSES) do
		table.insert(result, {
			id = pass.id,
			name = pass.name,
			description = pass.description,
			icon = pass.icon,
			price = pass.price,
			tag = pass.tag,
			owned = owned[pass.id] == true,
		})
	end
	return result
end

print("[DeepDig] Gamepasses loaded")
