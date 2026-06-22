-- StatsGui.client.lua — player progression dashboard for Deep Dig
-- Place in: StarterGui/StatsGui (LocalScript)
--
-- Top-right toggle opens a centered stats panel with a live snapshot of:
--   • Currency
--   • Progress
--   • Collection
--   • Pets
--   • Badges
--
-- The panel fetches a full data snapshot once on open via GetPlayerData,
-- then keeps the display fresh with UpdateHUD pushes and a 3s refresh
-- loop while visible.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════════════
-- Safe module / remote lookups
-- ═══════════════════════════════════════════════════════════════════

local function waitForChildTimeout(parent, childName, timeoutSeconds)
	if not parent then return nil end
	return parent:WaitForChild(childName, timeoutSeconds or 5)
end

local Remotes = waitForChildTimeout(ReplicatedStorage, "Remotes", 5)
local ConfigModule = waitForChildTimeout(ReplicatedStorage, "Config", 5)
local ItemDatabaseModule = waitForChildTimeout(ReplicatedStorage, "ItemDatabase", 5)
local PetDatabaseModule = waitForChildTimeout(ReplicatedStorage, "PetDatabase", 5)
local EnemyDatabaseModule = waitForChildTimeout(ReplicatedStorage, "EnemyDatabase", 5)

local Config = { TIERS = {} }
local ItemDatabase = { ITEMS = {} }
local PetDatabase = {}
local EnemyDatabase = { ENEMIES = {} }

if ConfigModule then
	local ok, result = pcall(require, ConfigModule)
	if ok and type(result) == "table" then
		Config = result
	end
end

if ItemDatabaseModule then
	local ok, result = pcall(require, ItemDatabaseModule)
	if ok and type(result) == "table" then
		ItemDatabase = result
	end
end

if PetDatabaseModule then
	local ok, result = pcall(require, PetDatabaseModule)
	if ok and type(result) == "table" then
		PetDatabase = result
	end
end

if EnemyDatabaseModule then
	local ok, result = pcall(require, EnemyDatabaseModule)
	if ok and type(result) == "table" then
		EnemyDatabase = result
	end
end

local GetPlayerDataFunction = Remotes and waitForChildTimeout(Remotes, "GetPlayerData", 5)
local UpdateHUDEvent = Remotes and waitForChildTimeout(Remotes, "UpdateHUD", 5)

if not Remotes then
	warn("[StatsGui] Remotes folder missing — panel will fall back to Loading...")
end

-- ═══════════════════════════════════════════════════════════════════
-- Style constants
-- ═══════════════════════════════════════════════════════════════════

local PANEL_BG = Color3.fromRGB(20, 20, 25)
local CARD_BG = Color3.fromRGB(28, 28, 34)
local TEXT_PRIMARY = Color3.fromRGB(235, 235, 235)
local TEXT_MUTED = Color3.fromRGB(160, 160, 160)
local TEXT_SOFT = Color3.fromRGB(200, 200, 200)
local ACCENT_GOLD = Color3.fromRGB(255, 200, 50)
local ACCENT_PURPLE = Color3.fromRGB(160, 80, 200)
local ACCENT_BLUE = Color3.fromRGB(80, 160, 255)
local ACCENT_GREEN = Color3.fromRGB(80, 220, 140)
local ACCENT_RED = Color3.fromRGB(240, 90, 90)

local BADGE_TOTAL = 10 -- TODO: read BadgeSystem.BADGES count from a shared module if one is added.
local COMBAT_BADGE_GOAL = 100
local UNKNOWN_DEPTH_GOAL = 188

local BADGE_MILESTONES = {
	{
		id = "first_dig",
		name = "First Dig",
		description = "Dig your first block",
		target = 1,
		field = "totalBlocksDug",
		color = ACCENT_BLUE,
	},
	{
		id = "hundred_blocks",
		name = "Dig 100",
		description = "Dig 100 blocks",
		target = 100,
		field = "totalBlocksDug",
		color = ACCENT_BLUE,
	},
	{
		id = "thousand_blocks",
		name = "Dig 1,000",
		description = "Dig 1,000 blocks",
		target = 1000,
		field = "totalBlocksDug",
		color = ACCENT_BLUE,
	},
	{
		id = "first_rare_find",
		name = "First Rare Find",
		description = "Discover your first Rare item",
		target = 1,
		eventOnly = true,
		color = ACCENT_GOLD,
	},
	{
		id = "first_legendary",
		name = "First Legendary",
		description = "Discover your first Legendary item",
		target = 1,
		eventOnly = true,
		color = ACCENT_PURPLE,
	},
	{
		id = "depth_unknown_tier",
		name = "Unknown Depth",
		description = "Reach the Unknown depth tier",
		target = UNKNOWN_DEPTH_GOAL,
		field = "deepestBlock",
		color = ACCENT_PURPLE,
	},
	{
		id = "first_resurface",
		name = "First Resurface",
		description = "Resurface for the first time",
		target = 1,
		field = "resurfaceCount",
		color = ACCENT_GOLD,
	},
	{
		id = "first_museum_display",
		name = "First Museum Display",
		description = "Display your first item in the museum",
		target = 1,
		eventOnly = true,
		color = ACCENT_BLUE,
	},
	{
		id = "first_enemy_kill",
		name = "First Enemy Kill",
		description = "Defeat your first buried enemy",
		target = 1,
		field = "enemyKills",
		color = ACCENT_RED,
	},
	{
		id = "enemy_count_100",
		name = "100 Enemy Kills",
		description = "Defeat 100 buried enemies",
		target = 100,
		field = "enemyKills",
		color = ACCENT_RED,
	},
}

-- ═══════════════════════════════════════════════════════════════════
-- Helpers
-- ═══════════════════════════════════════════════════════════════════

local function clampNumber(value)
	value = tonumber(value)
	if not value then
		return 0
	end
	return value
end

local function formatNumber(value)
	local n = clampNumber(value)
	local negative = n < 0
	n = math.abs(n)

	local suffixes = { "", "K", "M", "B", "T" }
	local suffixIndex = 1

	while n >= 1000 and suffixIndex < #suffixes do
		n = n / 1000
		suffixIndex = suffixIndex + 1
	end

	local text
	if suffixIndex == 1 then
		text = tostring(math.floor(n))
	else
		text = string.format("%.1f", n)
		text = text:gsub("%.0$", "")
		text = text:gsub("%.$", "")
		text = text .. suffixes[suffixIndex]
	end

	if negative then
		return "-" .. text
	end

	return text
end

local function countTableEntries(value)
	if type(value) ~= "table" then
		return 0
	end

	local count = 0
	for _ in pairs(value) do
		count = count + 1
	end
	return count
end

local knownItems = {}
local totalItemsInDatabase = 0

for _, tierItems in pairs(ItemDatabase.ITEMS or {}) do
	if type(tierItems) == "table" then
		for _, item in ipairs(tierItems) do
			if type(item) == "table" and type(item.name) == "string" then
				knownItems[item.name] = true
				totalItemsInDatabase = totalItemsInDatabase + 1
			end
		end
	end
end

local function getTierNameForDepth(depth)
	local tiers = Config and Config.TIERS or {}
	depth = clampNumber(depth)

	if #tiers == 0 then
		return "Unknown"
	end

	for index, tier in ipairs(tiers) do
		local nextTier = tiers[index + 1]
		local minDepth = clampNumber(tier.minDepth)
		local nextMinDepth = nextTier and clampNumber(nextTier.minDepth) or math.huge
		if depth >= minDepth and depth < nextMinDepth then
			return tier.name or "Unknown"
		end
	end

	return tiers[#tiers].name or "Unknown"
end

local function getTierColor(tierName)
	local tiers = Config and Config.TIERS or {}
	for _, tier in ipairs(tiers) do
		if tier.name == tierName then
			return tier.color or TEXT_MUTED
		end
	end
	return TEXT_MUTED
end

local function getPetRecordById(data, petId)
	if type(data) ~= "table" or type(data.pets) ~= "table" or type(petId) ~= "string" then
		return nil
	end

	for _, record in ipairs(data.pets) do
		if type(record) == "table" and record.id == petId then
			return record
		end
	end

	return nil
end

local function getPetDefinitionFromData(data)
	if type(data) ~= "table" then
		return nil, nil
	end

	local equipped = data.equippedPet
	if type(equipped) ~= "string" or equipped == "" then
		return nil, nil
	end

	local direct = PetDatabase.getPet and PetDatabase.getPet(equipped)
	if direct then
		return direct, equipped
	end

	local record = getPetRecordById(data, equipped)
	if record and type(record.name) == "string" then
		local resolved = PetDatabase.getPet and PetDatabase.getPet(record.name)
		if resolved then
			return resolved, record.name
		end
		return nil, record.name
	end

	if type(data.pets) == "table" then
		for _, petRecord in ipairs(data.pets) do
			if type(petRecord) == "table" and petRecord.name == equipped then
				local resolved = PetDatabase.getPet and PetDatabase.getPet(petRecord.name)
				if resolved then
					return resolved, petRecord.name
				end
				return nil, petRecord.name
			end
		end
	end

	return nil, nil
end

local function countKnownInventoryItems(inventory)
	if type(inventory) ~= "table" then
		return 0
	end

	local total = 0
	for _, item in ipairs(inventory) do
		if type(item) == "table" and type(item.name) == "string" and knownItems[item.name] then
			total = total + 1
		end
	end
	return total
end

local function countKnownCollections(collections)
	if type(collections) ~= "table" then
		return 0
	end

	local total = 0
	for itemName, owned in pairs(collections) do
		if owned and type(itemName) == "string" and knownItems[itemName] then
			total = total + 1
		end
	end
	return total
end

local function countKnownPets(pets)
	if type(pets) ~= "table" then
		return 0
	end

	local total = 0
	for _, petRecord in ipairs(pets) do
		if type(petRecord) == "table" and type(petRecord.name) == "string" then
			if PetDatabase.getPet and PetDatabase.getPet(petRecord.name) then
				total = total + 1
			end
		end
	end
	return total
end

local function normalizeData(data)
	if type(data) ~= "table" then
		return nil
	end

	return data
end

local function mergeUpdate(existing, update)
	existing = existing or {}
	if type(update) ~= "table" then
		return existing
	end

	for key, value in pairs(update) do
		existing[key] = value
	end

	if type(update.rebirths) == "number" then
		existing.rebirths = update.rebirths
	end

	if type(update.depth) == "number" then
		existing.currentDepth = update.depth
		if update.depth == 0 and (update.blocksDug == 0 or update.tierName == (Config.TIERS[1] and Config.TIERS[1].name)) then
			existing.deepestBlock = 0
		else
			existing.deepestBlock = math.max(clampNumber(existing.deepestBlock), update.depth)
		end
	end

	if type(update.blocksDug) == "number" then
		existing.totalBlocksDug = update.blocksDug
	end

	if type(update.inventoryCount) == "number" then
		existing.inventoryCount = update.inventoryCount
	end

	if type(update.petCount) == "number" then
		existing.petCount = update.petCount
	end

	if type(update.fragments) == "number" then
		existing.fragments = update.fragments
	end

	if type(update.coins) == "number" then
		existing.coins = update.coins
	end

	if type(update.totalEarned) == "number" then
		existing.totalEarned = update.totalEarned
	end

	return existing
end

local function getInventoryCount(data)
	if type(data) ~= "table" then
		return 0
	end
	if type(data.inventoryCount) == "number" then
		return data.inventoryCount
	end
	return countKnownInventoryItems(data.inventory)
end

local function getPetCount(data)
	if type(data) ~= "table" then
		return 0
	end
	if type(data.petCount) == "number" then
		return data.petCount
	end
	return countKnownPets(data.pets)
end

local function getBadgeCount(data)
	if type(data) ~= "table" then
		return 0
	end
	return countTableEntries(data.badgesAwarded)
end

local function hasBadgeAwarded(data, badgeId)
	if type(data) ~= "table" or type(data.badgesAwarded) ~= "table" then
		return false
	end

	return data.badgesAwarded[badgeId] ~= nil
end

local function getMilestoneCurrent(data, milestone)
	if type(data) ~= "table" or type(milestone) ~= "table" then
		return 0
	end

	if milestone.eventOnly then
		return hasBadgeAwarded(data, milestone.id) and 1 or 0
	elseif milestone.field == "totalBlocksDug" then
		return clampNumber(data.totalBlocksDug or data.blocksDug)
	elseif milestone.field == "deepestBlock" then
		return clampNumber(data.deepestBlock or data.currentDepth)
	elseif milestone.field == "resurfaceCount" then
		return math.max(clampNumber(data.resurfaceCount), clampNumber(data.rebirths))
	elseif milestone.field == "enemyKills" then
		return clampNumber(data.enemyKills)
	end

	return 0
end

local function getCollectionCount(data)
	if type(data) ~= "table" then
		return 0
	end
	return countKnownCollections(data.collections)
end

local function getEquippedPetLabel(data)
	local petDef, fallbackName = getPetDefinitionFromData(data)
	if petDef then
		return petDef.name or fallbackName or "Unknown pet", petDef.color or TEXT_SOFT
	end

	if fallbackName and fallbackName ~= "" then
		return "Unknown pet", TEXT_MUTED
	end

	return "No pet equipped", TEXT_MUTED
end

local function makeLabel(parent, size, position, text, color, font, textSize, alignment, truncate)
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Text = text or ""
	label.TextColor3 = color or TEXT_PRIMARY
	label.TextSize = textSize or 16
	label.Font = font or Enum.Font.Gotham
	label.TextXAlignment = alignment or Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = false
	label.TextTruncate = truncate or Enum.TextTruncate.None
	label.Parent = parent
	return label
end

local function makeCard(parent, height)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, height)
	card.BackgroundColor3 = CARD_BG
	card.BackgroundTransparency = 0.05
	card.BorderSizePixel = 0
	card.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 75)
	stroke.Thickness = 1
	stroke.Parent = card

	return card, stroke
end

local function makeLine(parent, y, text, color)
	return makeLabel(
		parent,
		UDim2.new(1, -18, 0, 18),
		UDim2.fromOffset(9, y),
		text,
		color,
		Enum.Font.Gotham,
		14,
		Enum.TextXAlignment.Left,
		Enum.TextTruncate.AtEnd
	)
end

local function formatPercent(value)
	local percent = clampNumber(value) * 100
	if percent <= 0 then
		return "0%"
	end

	local text = string.format("%.1f", percent)
	text = text:gsub("%.0$", "")
	return text .. "%"
end

local function getEnemyDisplay(enemy)
	if type(enemy) == "table" and type(enemy.display) == "table" then
		return enemy.display
	end
	return {}
end

local function getEnemyUnlockDepth(enemy)
	return clampNumber(getEnemyDisplay(enemy).unlockDepth)
end

local function getEnemyUnlockText(enemy)
	local display = getEnemyDisplay(enemy)
	if type(display.unlockText) == "string" and display.unlockText ~= "" then
		return display.unlockText
	end
	return "Depth " .. formatNumber(getEnemyUnlockDepth(enemy))
end

local function getEnemyKillCount(data, enemy)
	if type(data) ~= "table" or type(enemy) ~= "table" or type(data.enemyKillCounts) ~= "table" then
		return 0
	end

	local enemyId = enemy.id
	local count = nil
	if type(enemyId) == "string" and enemyId ~= "" then
		count = data.enemyKillCounts[enemyId]
	end
	if count == nil and type(enemy.name) == "string" and enemy.name ~= "" then
		count = data.enemyKillCounts[enemy.name]
	end

	return clampNumber(count)
end

-- ═══════════════════════════════════════════════════════════════════
-- ScreenGui scaffolding
-- ═══════════════════════════════════════════════════════════════════

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeepDigStatsGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 20
screenGui.Parent = playerGui

-- Toggle button
local toggleButton = Instance.new("TextButton")
toggleButton.Name = "StatsToggle"
toggleButton.Size = UDim2.fromOffset(120, 40)
toggleButton.AnchorPoint = Vector2.new(1, 0)
toggleButton.Position = UDim2.new(1, -20, 0, 20)
toggleButton.BackgroundColor3 = PANEL_BG
toggleButton.BackgroundTransparency = 0.1
toggleButton.BorderSizePixel = 0
toggleButton.Text = "📊 Stats"
toggleButton.TextColor3 = TEXT_PRIMARY
toggleButton.TextSize = 18
toggleButton.Font = Enum.Font.GothamBold
toggleButton.AutoButtonColor = true
toggleButton.Parent = screenGui

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

local toggleStroke = Instance.new("UIStroke")
toggleStroke.Color = Color3.fromRGB(80, 80, 95)
toggleStroke.Thickness = 1
toggleStroke.Parent = toggleButton

-- Main panel
local panel = Instance.new("Frame")
panel.Name = "StatsPanel"
panel.Size = UDim2.fromOffset(440, 520)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = PANEL_BG
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel = 0
panel.Visible = false
panel.ClipsDescendants = true
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(60, 60, 75)
panelStroke.Thickness = 1
panelStroke.Parent = panel

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundTransparency = 1
titleBar.Parent = panel

local titleLabel = makeLabel(
	titleBar,
	UDim2.new(1, -64, 1, 0),
	UDim2.fromOffset(15, 0),
	"📊 Player Stats",
	TEXT_PRIMARY,
	Enum.Font.GothamBold,
	18,
	Enum.TextXAlignment.Left,
	Enum.TextTruncate.AtEnd
)

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.Size = UDim2.fromOffset(32, 32)
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, -10, 0.5, 0)
closeButton.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
closeButton.BackgroundTransparency = 0.2
closeButton.BorderSizePixel = 0
closeButton.Text = "×"
closeButton.TextColor3 = TEXT_PRIMARY
closeButton.TextSize = 22
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = titleBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = closeButton

local content = Instance.new("ScrollingFrame")
content.Name = "Content"
content.Size = UDim2.new(1, -20, 1, -54)
content.Position = UDim2.fromOffset(10, 46)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 5
content.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 95)
content.CanvasSize = UDim2.new(0, 0, 0, 0)
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.Parent = panel

local contentPadding = Instance.new("UIPadding")
contentPadding.PaddingTop = UDim.new(0, 2)
contentPadding.PaddingBottom = UDim.new(0, 6)
contentPadding.Parent = content

local contentLayout = Instance.new("UIListLayout")
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, 8)
contentLayout.Parent = content

local function addCardTitle(parent, text, color)
	return makeLabel(
	parent,
	UDim2.new(1, -18, 0, 18),
	UDim2.fromOffset(9, 8),
	text,
		color or TEXT_PRIMARY,
		Enum.Font.GothamBold,
		14,
		Enum.TextXAlignment.Left,
		Enum.TextTruncate.AtEnd
	)
end

-- Header card
local headerCard, headerStroke = makeCard(content, 74)
headerCard.LayoutOrder = 1
headerStroke.Color = Color3.fromRGB(90, 90, 105)
addCardTitle(headerCard, "Player", TEXT_MUTED)

local playerNameLabel = makeLabel(
	headerCard,
	UDim2.new(1, -120, 0, 24),
	UDim2.fromOffset(9, 28),
	"Loading...",
	TEXT_PRIMARY,
	Enum.Font.GothamBold,
	20,
	Enum.TextXAlignment.Left,
	Enum.TextTruncate.AtEnd
)

local rebirthBadge = makeLabel(
	headerCard,
	UDim2.fromOffset(98, 24),
	UDim2.new(1, -108, 0, 28),
	"",
	ACCENT_GOLD,
	Enum.Font.GothamBold,
	14,
	Enum.TextXAlignment.Center,
	Enum.TextTruncate.AtEnd
)
rebirthBadge.BackgroundColor3 = Color3.fromRGB(50, 40, 20)
rebirthBadge.BackgroundTransparency = 0.15
rebirthBadge.BorderSizePixel = 0
rebirthBadge.TextYAlignment = Enum.TextYAlignment.Center

local rebirthCorner = Instance.new("UICorner")
rebirthCorner.CornerRadius = UDim.new(0, 8)
rebirthCorner.Parent = rebirthBadge

local rebirthStroke = Instance.new("UIStroke")
rebirthStroke.Color = Color3.fromRGB(120, 90, 30)
rebirthStroke.Thickness = 1
rebirthStroke.Parent = rebirthBadge

-- Currency card
local currencyCard, currencyStroke = makeCard(content, 92)
currencyCard.LayoutOrder = 2
currencyStroke.Color = Color3.fromRGB(90, 70, 40)
addCardTitle(currencyCard, "Currency", ACCENT_GOLD)

local coinsLabel = makeLine(currencyCard, 28, "Coins: Loading...", ACCENT_GOLD)
local fragmentsLabel = makeLine(currencyCard, 48, "Fragments: Loading...", ACCENT_PURPLE)
local earnedLabel = makeLine(currencyCard, 68, "Total Earned: Loading...", ACCENT_GREEN)

-- Progress card
local progressCard, progressStroke = makeCard(content, 92)
progressCard.LayoutOrder = 3
progressStroke.Color = Color3.fromRGB(70, 80, 90)
addCardTitle(progressCard, "Progress", ACCENT_BLUE)

local depthLabel = makeLine(progressCard, 28, "Depth: Loading...", TEXT_PRIMARY)
local tierLabel = makeLine(progressCard, 48, "Tier: Loading...", TEXT_SOFT)
local dugLabel = makeLine(progressCard, 68, "Blocks Dug: Loading...", TEXT_MUTED)

-- Combat card
local combatCard, combatStroke = makeCard(content, 92)
combatCard.LayoutOrder = 4
combatStroke.Color = Color3.fromRGB(95, 60, 60)
addCardTitle(combatCard, "Combat", ACCENT_RED)

local combatKillsLabel = makeLine(combatCard, 28, "Enemies Defeated: Loading...", TEXT_PRIMARY)
local combatBadgeLabel = makeLine(combatCard, 48, "100-Kill Badge: Loading...", TEXT_SOFT)

local combatProgressTrack = Instance.new("Frame")
combatProgressTrack.Size = UDim2.new(1, -18, 0, 8)
combatProgressTrack.Position = UDim2.fromOffset(9, 72)
combatProgressTrack.BackgroundColor3 = Color3.fromRGB(45, 35, 38)
combatProgressTrack.BackgroundTransparency = 0.05
combatProgressTrack.BorderSizePixel = 0
combatProgressTrack.ClipsDescendants = true
combatProgressTrack.Parent = combatCard

local combatTrackCorner = Instance.new("UICorner")
combatTrackCorner.CornerRadius = UDim.new(0, 4)
combatTrackCorner.Parent = combatProgressTrack

local combatProgressFill = Instance.new("Frame")
combatProgressFill.Size = UDim2.fromScale(0, 1)
combatProgressFill.BackgroundColor3 = ACCENT_RED
combatProgressFill.BorderSizePixel = 0
combatProgressFill.Parent = combatProgressTrack

local combatFillCorner = Instance.new("UICorner")
combatFillCorner.CornerRadius = UDim.new(0, 4)
combatFillCorner.Parent = combatProgressFill

-- Combat bestiary card
local bestiaryCard, bestiaryStroke = makeCard(content, 386)
bestiaryCard.LayoutOrder = 5
bestiaryStroke.Color = Color3.fromRGB(80, 55, 70)
addCardTitle(bestiaryCard, "Combat Bestiary", ACCENT_RED)

local bestiaryRows = {}

local function makeBestiaryRow(parent, index, enemy)
	local y = 30 + ((index - 1) * 60)

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -18, 0, 54)
	row.Position = UDim2.fromOffset(9, y)
	row.BackgroundColor3 = Color3.fromRGB(34, 30, 34)
	row.BackgroundTransparency = 0.08
	row.BorderSizePixel = 0
	row.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row

	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.fromOffset(28, 28)
	swatch.Position = UDim2.fromOffset(8, 8)
	swatch.BackgroundColor3 = enemy.color or TEXT_MUTED
	swatch.BorderSizePixel = 0
	swatch.Parent = row

	local swatchCorner = Instance.new("UICorner")
	swatchCorner.CornerRadius = UDim.new(0, 14)
	swatchCorner.Parent = swatch

	local nameLabel = makeLabel(
		row,
		UDim2.new(0.5, -46, 0, 18),
		UDim2.fromOffset(44, 6),
		enemy.name or "Unknown Enemy",
		TEXT_PRIMARY,
		Enum.Font.GothamBold,
		13,
		Enum.TextXAlignment.Left,
		Enum.TextTruncate.AtEnd
	)

	local rewardLabel = makeLabel(
		row,
		UDim2.new(0.5, -10, 0, 18),
		UDim2.new(0.5, 0, 0, 6),
		"",
		TEXT_MUTED,
		Enum.Font.Gotham,
		12,
		Enum.TextXAlignment.Right,
		Enum.TextTruncate.AtEnd
	)

	local statLabel = makeLabel(
		row,
		UDim2.new(1, -52, 0, 16),
		UDim2.fromOffset(44, 24),
		"",
		TEXT_SOFT,
		Enum.Font.Gotham,
		12,
		Enum.TextXAlignment.Left,
		Enum.TextTruncate.AtEnd
	)

	local hintLabel = makeLabel(
		row,
		UDim2.new(1, -52, 0, 14),
		UDim2.fromOffset(44, 39),
		"",
		TEXT_MUTED,
		Enum.Font.Gotham,
		11,
		Enum.TextXAlignment.Left,
		Enum.TextTruncate.AtEnd
	)

	return {
		enemy = enemy,
		row = row,
		swatch = swatch,
		nameLabel = nameLabel,
		rewardLabel = rewardLabel,
		statLabel = statLabel,
		hintLabel = hintLabel,
	}
end

for index, enemy in ipairs(EnemyDatabase.ENEMIES or {}) do
	bestiaryRows[index] = makeBestiaryRow(bestiaryCard, index, enemy)
end

-- Collection card
local collectionCard, collectionStroke = makeCard(content, 92)
collectionCard.LayoutOrder = 6
collectionStroke.Color = Color3.fromRGB(60, 90, 90)
addCardTitle(collectionCard, "Collection", ACCENT_BLUE)

local inventoryLabel = makeLine(collectionCard, 28, "Collected: Loading...", TEXT_PRIMARY)
local uniqueLabel = makeLine(collectionCard, 48, "Unique Found: Loading...", TEXT_SOFT)
local databaseLabel = makeLine(collectionCard, 68, "Database Total: Loading...", TEXT_MUTED)

-- Pets card
local petsCard, petsStroke = makeCard(content, 92)
petsCard.LayoutOrder = 7
petsStroke.Color = Color3.fromRGB(90, 70, 90)
addCardTitle(petsCard, "Pets", ACCENT_PURPLE)

local petCountLabel = makeLine(petsCard, 28, "Pets Owned: Loading...", TEXT_PRIMARY)
local equippedLabel = makeLine(petsCard, 48, "Equipped: Loading...", TEXT_SOFT)
local petHintLabel = makeLine(petsCard, 68, "No pets yet - hatch one!", TEXT_MUTED)

-- Badges card
local badgeCard, badgeStroke = makeCard(content, 346)
badgeCard.LayoutOrder = 8
badgeStroke.Color = Color3.fromRGB(95, 85, 55)
addCardTitle(badgeCard, "Badges", ACCENT_GOLD)

local badgeCountLabel = makeLabel(
	badgeCard,
	UDim2.new(0.55, -9, 0, 18),
	UDim2.fromOffset(9, 28),
	"Unlocked: Loading...",
	TEXT_PRIMARY,
	Enum.Font.Gotham,
	14,
	Enum.TextXAlignment.Left,
	Enum.TextTruncate.AtEnd
)
local badgeTotalLabel = makeLabel(
	badgeCard,
	UDim2.new(0.45, -9, 0, 18),
	UDim2.new(0.55, 0, 0, 28),
	"Total: Loading...",
	TEXT_SOFT,
	Enum.Font.Gotham,
	14,
	Enum.TextXAlignment.Right,
	Enum.TextTruncate.AtEnd
)
local badgeMilestoneRows = {}

local function makeBadgeMilestoneRow(parent, y, milestone)
	local nameLabel = makeLabel(
		parent,
		UDim2.new(0.58, -9, 0, 16),
		UDim2.fromOffset(9, y),
		milestone.name,
		TEXT_SOFT,
		Enum.Font.Gotham,
		13,
		Enum.TextXAlignment.Left,
		Enum.TextTruncate.AtEnd
	)

	local valueLabel = makeLabel(
		parent,
		UDim2.new(0.42, -9, 0, 16),
		UDim2.new(0.58, 0, 0, y),
		"0 / " .. formatNumber(milestone.target),
		TEXT_MUTED,
		Enum.Font.Gotham,
		13,
		Enum.TextXAlignment.Right,
		Enum.TextTruncate.AtEnd
	)

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -18, 0, 6)
	track.Position = UDim2.fromOffset(9, y + 18)
	track.BackgroundColor3 = Color3.fromRGB(42, 38, 32)
	track.BackgroundTransparency = 0.05
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = parent

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 3)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = milestone.color or ACCENT_GOLD
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = fill

	return {
		milestone = milestone,
		nameLabel = nameLabel,
		valueLabel = valueLabel,
		fill = fill,
	}
end

for index, milestone in ipairs(BADGE_MILESTONES) do
	badgeMilestoneRows[index] = makeBadgeMilestoneRow(badgeCard, 52 + ((index - 1) * 28), milestone)
end

-- ═══════════════════════════════════════════════════════════════════
-- Data cache + live refresh
-- ═══════════════════════════════════════════════════════════════════

local cachedData = nil
local panelOpen = false
local refreshGeneration = 0
local fetchGeneration = 0

local function render()
	local data = normalizeData(cachedData)
	local hasData = data ~= nil

	local playerNameText = hasData and (player.DisplayName or player.Name) or "Loading..."
	playerNameLabel.Text = playerNameText
	titleLabel.Text = "📊 Player Stats"

	local rebirths = clampNumber(hasData and data.rebirths or 0)
	if rebirths > 0 then
		rebirthBadge.Visible = true
		rebirthBadge.Text = "Resurfaced ×" .. tostring(rebirths)
	else
		rebirthBadge.Visible = false
	end

	local coins = clampNumber(hasData and data.coins or 0)
	local fragments = clampNumber(hasData and data.fragments or 0)
	local totalEarned = clampNumber(hasData and data.totalEarned or 0)
	local deepestBlock = clampNumber((hasData and data.deepestBlock) or (data and data.currentDepth) or 0)
	local totalBlocksDug = clampNumber((hasData and data.totalBlocksDug) or (data and data.blocksDug) or 0)
	local tierName = getTierNameForDepth(deepestBlock)
	local tierColor = getTierColor(tierName)
	local enemyKills = clampNumber(hasData and data.enemyKills or 0)
	local enemyCombatComplete = hasBadgeAwarded(data, "enemy_count_100") or enemyKills >= COMBAT_BADGE_GOAL
	local enemyBadgeProgress = enemyCombatComplete and COMBAT_BADGE_GOAL or math.min(enemyKills, COMBAT_BADGE_GOAL)
	local enemyBadgeRatio = 0
	if hasData and COMBAT_BADGE_GOAL > 0 then
		enemyBadgeRatio = enemyBadgeProgress / COMBAT_BADGE_GOAL
	end
	local inventoryCount = getInventoryCount(data)
	local uniqueCount = getCollectionCount(data)
	local petCount = getPetCount(data)
	local equippedPetName, equippedPetColor = getEquippedPetLabel(data)
	local unlockedBadges = getBadgeCount(data)

	coinsLabel.Text = "Coins: " .. (hasData and formatNumber(coins) or "Loading...")
	fragmentsLabel.Text = "Fragments: " .. (hasData and formatNumber(fragments) or "Loading...")
	earnedLabel.Text = "Total Earned: " .. (hasData and formatNumber(totalEarned) or "Loading...")

	depthLabel.Text = "Depth: " .. (hasData and (formatNumber(deepestBlock) .. " blocks") or "Loading...")
	tierLabel.Text = "Tier: " .. (hasData and tierName or "Loading...")
	tierLabel.TextColor3 = hasData and tierColor or TEXT_SOFT
	dugLabel.Text = "Blocks Dug: " .. (hasData and formatNumber(totalBlocksDug) or "Loading...")

	combatKillsLabel.Text = "Enemies Defeated: " .. (hasData and formatNumber(enemyKills) or "Loading...")
	combatBadgeLabel.Text = "Combat Badge: " .. (hasData and (formatNumber(enemyBadgeProgress) .. " / " .. formatNumber(COMBAT_BADGE_GOAL)) or "Loading...")
	combatBadgeLabel.TextColor3 = hasData and (enemyCombatComplete and ACCENT_GREEN or TEXT_SOFT) or TEXT_SOFT
	combatProgressFill.Size = UDim2.fromScale(enemyBadgeRatio, 1)
	combatProgressFill.BackgroundColor3 = enemyCombatComplete and ACCENT_GREEN or ACCENT_RED

	for _, row in ipairs(bestiaryRows) do
		local enemy = row.enemy
		local display = getEnemyDisplay(enemy)
		local unlockDepth = getEnemyUnlockDepth(enemy)
		local unlocked = hasData and deepestBlock >= unlockDepth
		local rewardText = "+" .. formatNumber(enemy.coinDrop) .. "c +" .. formatNumber(enemy.fragmentDrop) .. "f"
		local defeatedCount = getEnemyKillCount(data, enemy)
		local mastered = defeatedCount >= 10

		if unlocked then
			row.swatch.BackgroundColor3 = enemy.color or ACCENT_RED
			row.swatch.BackgroundTransparency = 0
			row.nameLabel.Text = enemy.name or "Unknown Enemy"
			row.nameLabel.TextColor3 = TEXT_PRIMARY
			row.rewardLabel.Text = rewardText .. " | Item " .. formatPercent(enemy.itemDropChance)
			row.rewardLabel.TextColor3 = mastered and ACCENT_GREEN or ACCENT_GOLD
			row.statLabel.Text = (mastered and "Mastered | " or "") .. "Defeated " .. formatNumber(defeatedCount) .. " | HP " .. formatNumber(enemy.hp) .. " | Damage " .. formatNumber(enemy.damage)
			row.statLabel.TextColor3 = mastered and ACCENT_GREEN or TEXT_SOFT
			row.hintLabel.Text = display.hint or ""
			row.hintLabel.TextColor3 = TEXT_MUTED
		else
			row.swatch.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
			row.swatch.BackgroundTransparency = 0.1
			row.nameLabel.Text = "Locked Enemy"
			row.nameLabel.TextColor3 = TEXT_MUTED
			row.rewardLabel.Text = getEnemyUnlockText(enemy)
			row.rewardLabel.TextColor3 = TEXT_SOFT
			row.statLabel.Text = "Reach " .. getEnemyUnlockText(enemy)
			row.statLabel.TextColor3 = TEXT_MUTED
			row.hintLabel.Text = "Combat data hidden until discovered."
			row.hintLabel.TextColor3 = TEXT_MUTED
		end
	end

	inventoryLabel.Text = "Collected: " .. (hasData and (formatNumber(inventoryCount) .. " items") or "Loading...")
	if hasData and uniqueCount == 0 then
		uniqueLabel.Text = "Unique Found: 0 items"
	else
		uniqueLabel.Text = "Unique Found: " .. (hasData and (formatNumber(uniqueCount) .. " items") or "Loading...")
	end
	databaseLabel.Text = "Database Total: " .. (hasData and (formatNumber(totalItemsInDatabase) .. " items") or "Loading...")

	petCountLabel.Text = "Pets Owned: " .. (hasData and (formatNumber(petCount) .. " pets") or "Loading...")
	equippedLabel.Text = "Equipped: " .. (hasData and equippedPetName or "Loading...")
	equippedLabel.TextColor3 = hasData and equippedPetColor or TEXT_SOFT
	if hasData and petCount == 0 then
		petHintLabel.Text = "No pets yet - hatch one!"
		petHintLabel.TextColor3 = TEXT_MUTED
	elseif hasData then
		petHintLabel.Text = "Collection sync: " .. formatNumber(petCount) .. " total " .. (petCount == 1 and "pet" or "pets")
		petHintLabel.TextColor3 = TEXT_MUTED
	else
		petHintLabel.Text = "Loading..."
		petHintLabel.TextColor3 = TEXT_MUTED
	end

	badgeCountLabel.Text = "Unlocked: " .. (hasData and formatNumber(unlockedBadges) or "Loading...")
	badgeTotalLabel.Text = "Total: " .. (hasData and formatNumber(BADGE_TOTAL) or "Loading...")
	for _, row in ipairs(badgeMilestoneRows) do
		local milestone = row.milestone
		local current = hasData and getMilestoneCurrent(data, milestone) or 0
		local complete = hasBadgeAwarded(data, milestone.id) or current >= milestone.target
		local displayCurrent = complete and math.max(current, milestone.target) or current
		local ratio = 0
		if milestone.target > 0 then
			ratio = math.min(displayCurrent / milestone.target, 1)
		end

		row.valueLabel.Text = formatNumber(displayCurrent) .. " / " .. formatNumber(milestone.target)
		row.valueLabel.TextColor3 = complete and ACCENT_GREEN or TEXT_MUTED
		row.nameLabel.TextColor3 = complete and ACCENT_GREEN or TEXT_SOFT
		row.fill.Size = UDim2.fromScale(ratio, 1)
		row.fill.BackgroundColor3 = complete and ACCENT_GREEN or (milestone.color or ACCENT_GOLD)
	end

	local openTint = panelOpen and Color3.fromRGB(50, 48, 30) or PANEL_BG
	toggleButton.BackgroundColor3 = openTint
	toggleStroke.Color = panelOpen and ACCENT_GOLD or Color3.fromRGB(80, 80, 95)
end

local function fetchFullSnapshot()
	if not GetPlayerDataFunction then
		return
	end

	fetchGeneration = fetchGeneration + 1
	local generation = fetchGeneration

	task.spawn(function()
		local ok, result = pcall(function()
			return GetPlayerDataFunction:InvokeServer()
		end)

		if generation ~= fetchGeneration then
			return
		end

		if ok and type(result) == "table" then
			cachedData = result
			render()
		else
			render()
		end
	end)
end

local function startRefreshLoop()
	refreshGeneration = refreshGeneration + 1
	local generation = refreshGeneration

	task.spawn(function()
		while panelOpen and generation == refreshGeneration do
			task.wait(3)
			if not panelOpen or generation ~= refreshGeneration then
				break
			end
			fetchFullSnapshot()
		end
	end)
end

local function setPanelOpen(open)
	panelOpen = open and true or false
	panel.Visible = panelOpen

	pcall(function()
		player:SetAttribute("StatsPanelOpen", panelOpen)
	end)

	render()

	if panelOpen then
		fetchFullSnapshot()
		startRefreshLoop()
	else
		refreshGeneration = refreshGeneration + 1
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Event wiring
-- ═══════════════════════════════════════════════════════════════════

toggleButton.MouseButton1Click:Connect(function()
	setPanelOpen(not panelOpen)
end)

closeButton.MouseButton1Click:Connect(function()
	setPanelOpen(false)
end)

if UpdateHUDEvent then
	UpdateHUDEvent.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end

		cachedData = mergeUpdate(cachedData, payload)
		if panelOpen then
			render()
		end
	end)
end

local savedOpen = false
pcall(function()
	savedOpen = player:GetAttribute("StatsPanelOpen") == true
end)

render()
if savedOpen then
	setPanelOpen(true)
else
	panel.Visible = false
end
