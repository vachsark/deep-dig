-- PetGui.client.lua — Pet inventory + hatchery UI
-- Place in: StarterGui/PetGui (LocalScript)
--
-- Bottom-left "🐾 Pets" toggle opens a panel with two stacked sections:
--   1. Inventory grid — owned pets, equipped pet highlighted, click to equip/unequip
--   2. Hatchery — three egg tier buttons that fire HatchEgg
--
-- Inventory data sourcing — see "API note" below: PetSystem doesn't expose a
-- GetPetInventory remote, and GameManager's GetPlayerData payload doesn't
-- include `pets` / `equippedPet` either (verified in commit be2a9d4 backend).
-- We therefore shadow-track inventory client-side from the events the server
-- already fires (NotifyEvent on hatch, UpdateHUDEvent on equip), reconciling
-- against `petCount` from UpdateHUD so the user knows when the visible list
-- under-represents the real server state (e.g. after a rejoin). When
-- shadow-tracked entries are missing, we show "Pet #id" placeholders so users
-- can still equip a known id and see it light up afterward.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════════════
-- Remotes (graceful exit if PetSystem isn't loaded)
-- ═══════════════════════════════════════════════════════════════════

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if not Remotes then
	warn("[PetGui] Remotes folder not found — PetSystem not loaded?")
	return
end

local HatchEggEvent = Remotes:WaitForChild("HatchEgg", 5)
local EquipPetEvent = Remotes:WaitForChild("EquipPet", 5)
local NotifyEvent = Remotes:WaitForChild("Notify", 5)
local UpdateHUDEvent = Remotes:WaitForChild("UpdateHUD", 5)

if not (HatchEggEvent and EquipPetEvent and NotifyEvent and UpdateHUDEvent) then
	warn("[PetGui] Required pet remotes missing — exiting cleanly.")
	return
end

-- PetDatabase lives in ReplicatedStorage and is safe to require from the
-- client. We use it for rarity colors, multiplier lookups, and egg metadata.
local petDatabaseModule = ReplicatedStorage:WaitForChild("PetDatabase", 5)
if not petDatabaseModule then
	warn("[PetGui] PetDatabase module missing — exiting cleanly.")
	return
end
local PetDatabase = require(petDatabaseModule)

-- ═══════════════════════════════════════════════════════════════════
-- Style constants — match HudGui.client.lua visual language
-- ═══════════════════════════════════════════════════════════════════

local RarityColors = {
	Common    = Color3.fromRGB(180, 180, 180),
	Uncommon  = Color3.fromRGB(30, 200, 30),
	Rare      = Color3.fromRGB(30, 100, 255),
	Epic      = Color3.fromRGB(160, 50, 255),
	Legendary = Color3.fromRGB(255, 170, 0),
	Mythic    = Color3.fromRGB(255, 50, 50),
}

local PANEL_BG = Color3.fromRGB(20, 20, 25)
local PANEL_BG_TRANSPARENCY = 0.15
local SECTION_BG = Color3.fromRGB(28, 28, 34)
local CARD_BG = Color3.fromRGB(34, 34, 40)
local TEXT_PRIMARY = Color3.fromRGB(235, 235, 235)
local TEXT_MUTED = Color3.fromRGB(160, 160, 160)
local ACCENT_GOLD = Color3.fromRGB(255, 200, 50)

-- ═══════════════════════════════════════════════════════════════════
-- Screen GUI scaffolding
-- ═══════════════════════════════════════════════════════════════════

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeepDigPetGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- ─── Toggle button (bottom-left) ─────────────────────────────────────────────
-- Positioned bottom-left so it doesn't collide with QuestGui (bottom-right)
-- or the Shop button HudGui places elsewhere.

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "PetToggle"
toggleButton.Size = UDim2.new(0, 120, 0, 40)
toggleButton.AnchorPoint = Vector2.new(0, 1)
toggleButton.Position = UDim2.new(0, 20, 1, -20)
toggleButton.BackgroundColor3 = PANEL_BG
toggleButton.BackgroundTransparency = 0.15
toggleButton.BorderSizePixel = 0
toggleButton.Text = "🐾 Pets"
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

-- Small badge that shows pet count on the toggle button
local toggleBadge = Instance.new("TextLabel")
toggleBadge.Name = "Count"
toggleBadge.Size = UDim2.new(0, 22, 0, 22)
toggleBadge.AnchorPoint = Vector2.new(1, 0)
toggleBadge.Position = UDim2.new(1, -4, 0, 4)
toggleBadge.BackgroundColor3 = ACCENT_GOLD
toggleBadge.BackgroundTransparency = 0
toggleBadge.BorderSizePixel = 0
toggleBadge.Text = "0"
toggleBadge.TextColor3 = Color3.fromRGB(20, 20, 25)
toggleBadge.TextSize = 12
toggleBadge.Font = Enum.Font.GothamBlack
toggleBadge.Visible = false
toggleBadge.Parent = toggleButton

local toggleBadgeCorner = Instance.new("UICorner")
toggleBadgeCorner.CornerRadius = UDim.new(1, 0)
toggleBadgeCorner.Parent = toggleBadge

-- ─── Main panel ──────────────────────────────────────────────────────────────

local panel = Instance.new("Frame")
panel.Name = "PetPanel"
panel.Size = UDim2.new(0, 460, 0, 520)
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 20, 1, -76)
panel.BackgroundColor3 = PANEL_BG
panel.BackgroundTransparency = PANEL_BG_TRANSPARENCY
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(60, 60, 75)
panelStroke.Thickness = 1
panelStroke.Parent = panel

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundTransparency = 1
titleBar.Parent = panel

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -60, 1, 0)
titleLabel.Position = UDim2.new(0, 15, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "🐾 Pet Collection"
titleLabel.TextColor3 = TEXT_PRIMARY
titleLabel.TextSize = 20
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 32, 0, 32)
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

-- ─── Inventory section (scrollable grid) ─────────────────────────────────────

local inventorySection = Instance.new("Frame")
inventorySection.Name = "Inventory"
inventorySection.Size = UDim2.new(1, -20, 0, 280)
inventorySection.Position = UDim2.new(0, 10, 0, 50)
inventorySection.BackgroundColor3 = SECTION_BG
inventorySection.BackgroundTransparency = 0.2
inventorySection.BorderSizePixel = 0
inventorySection.Parent = panel

local inventoryCorner = Instance.new("UICorner")
inventoryCorner.CornerRadius = UDim.new(0, 8)
inventoryCorner.Parent = inventorySection

local inventoryHeader = Instance.new("TextLabel")
inventoryHeader.Size = UDim2.new(1, -20, 0, 24)
inventoryHeader.Position = UDim2.new(0, 10, 0, 6)
inventoryHeader.BackgroundTransparency = 1
inventoryHeader.Text = "Your Pets"
inventoryHeader.TextColor3 = TEXT_MUTED
inventoryHeader.TextSize = 13
inventoryHeader.Font = Enum.Font.GothamBold
inventoryHeader.TextXAlignment = Enum.TextXAlignment.Left
inventoryHeader.Parent = inventorySection

local inventoryScroll = Instance.new("ScrollingFrame")
inventoryScroll.Name = "Scroll"
inventoryScroll.Size = UDim2.new(1, -16, 1, -38)
inventoryScroll.Position = UDim2.new(0, 8, 0, 32)
inventoryScroll.BackgroundTransparency = 1
inventoryScroll.BorderSizePixel = 0
inventoryScroll.ScrollBarThickness = 6
inventoryScroll.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 140)
inventoryScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
inventoryScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
inventoryScroll.Parent = inventorySection

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 134, 0, 110)
gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = inventoryScroll

local gridPadding = Instance.new("UIPadding")
gridPadding.PaddingTop = UDim.new(0, 4)
gridPadding.PaddingLeft = UDim.new(0, 4)
gridPadding.PaddingRight = UDim.new(0, 4)
gridPadding.PaddingBottom = UDim.new(0, 4)
gridPadding.Parent = inventoryScroll

local emptyPlaceholder = Instance.new("TextLabel")
emptyPlaceholder.Name = "Empty"
emptyPlaceholder.Size = UDim2.new(1, -20, 0, 60)
emptyPlaceholder.Position = UDim2.new(0, 10, 0.5, -30)
emptyPlaceholder.BackgroundTransparency = 1
emptyPlaceholder.Text = "Hatch your first egg below!"
emptyPlaceholder.TextColor3 = TEXT_MUTED
emptyPlaceholder.TextSize = 16
emptyPlaceholder.Font = Enum.Font.GothamMedium
emptyPlaceholder.TextWrapped = true
emptyPlaceholder.Visible = false
emptyPlaceholder.Parent = inventorySection

-- ─── Hatchery section ────────────────────────────────────────────────────────

local hatcherySection = Instance.new("Frame")
hatcherySection.Name = "Hatchery"
hatcherySection.Size = UDim2.new(1, -20, 0, 168)
hatcherySection.Position = UDim2.new(0, 10, 0, 340)
hatcherySection.BackgroundColor3 = SECTION_BG
hatcherySection.BackgroundTransparency = 0.2
hatcherySection.BorderSizePixel = 0
hatcherySection.Parent = panel

local hatcheryCorner = Instance.new("UICorner")
hatcheryCorner.CornerRadius = UDim.new(0, 8)
hatcheryCorner.Parent = hatcherySection

local hatcheryHeader = Instance.new("TextLabel")
hatcheryHeader.Size = UDim2.new(1, -20, 0, 24)
hatcheryHeader.Position = UDim2.new(0, 10, 0, 6)
hatcheryHeader.BackgroundTransparency = 1
hatcheryHeader.Text = "Hatchery"
hatcheryHeader.TextColor3 = TEXT_MUTED
hatcheryHeader.TextSize = 13
hatcheryHeader.Font = Enum.Font.GothamBold
hatcheryHeader.TextXAlignment = Enum.TextXAlignment.Left
hatcheryHeader.Parent = hatcherySection

local hatcheryStatus = Instance.new("TextLabel")
hatcheryStatus.Name = "Status"
hatcheryStatus.Size = UDim2.new(1, -20, 0, 18)
hatcheryStatus.Position = UDim2.new(0, 10, 1, -22)
hatcheryStatus.BackgroundTransparency = 1
hatcheryStatus.Text = ""
hatcheryStatus.TextColor3 = TEXT_MUTED
hatcheryStatus.TextSize = 12
hatcheryStatus.Font = Enum.Font.Gotham
hatcheryStatus.TextXAlignment = Enum.TextXAlignment.Left
hatcheryStatus.Parent = hatcherySection

-- Three egg tier buttons (Stone / Gem / Void)
local EGG_ORDER = { "Stone", "Gem", "Void" }
local eggButtons = {}

for index, eggType in ipairs(EGG_ORDER) do
	local egg = PetDatabase.EGGS[eggType]
	if egg then
		local button = Instance.new("TextButton")
		button.Name = eggType .. "EggButton"
		button.Size = UDim2.new(0, 132, 0, 92)
		-- Cells laid out left-to-right with 10px gap, 12px left padding
		button.Position = UDim2.new(0, 12 + (index - 1) * 142, 0, 36)
		button.BackgroundColor3 = egg.color
		button.BackgroundTransparency = 0.05
		button.BorderSizePixel = 0
		button.Text = ""
		button.AutoButtonColor = true
		button.Parent = hatcherySection

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 8)
		buttonCorner.Parent = button

		local buttonStroke = Instance.new("UIStroke")
		buttonStroke.Color = Color3.fromRGB(0, 0, 0)
		buttonStroke.Thickness = 1
		buttonStroke.Transparency = 0.5
		buttonStroke.Parent = button

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -10, 0, 26)
		nameLabel.Position = UDim2.new(0, 5, 0, 8)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = egg.name
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextSize = 15
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextStrokeTransparency = 0.5
		nameLabel.Parent = button

		local costLabel = Instance.new("TextLabel")
		costLabel.Size = UDim2.new(1, -10, 0, 22)
		costLabel.Position = UDim2.new(0, 5, 0, 36)
		costLabel.BackgroundTransparency = 1
		costLabel.Text = "🪙 " .. egg.cost
		costLabel.TextColor3 = Color3.fromRGB(255, 230, 110)
		costLabel.TextSize = 14
		costLabel.Font = Enum.Font.GothamBold
		costLabel.TextStrokeTransparency = 0.5
		costLabel.Parent = button

		local hatchLabel = Instance.new("TextLabel")
		hatchLabel.Size = UDim2.new(1, -10, 0, 18)
		hatchLabel.Position = UDim2.new(0, 5, 0, 64)
		hatchLabel.BackgroundTransparency = 1
		hatchLabel.Text = "Tap to hatch"
		hatchLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
		hatchLabel.TextSize = 11
		hatchLabel.Font = Enum.Font.Gotham
		hatchLabel.TextStrokeTransparency = 0.6
		hatchLabel.Parent = button

		eggButtons[eggType] = button

		button.Activated:Connect(function()
			HatchEggEvent:FireServer(eggType)
			hatcheryStatus.Text = "Hatching " .. egg.name .. "..."
			hatcheryStatus.TextColor3 = ACCENT_GOLD

			-- Brief visual squeeze on the button to acknowledge the press
			local origSize = button.Size
			local pressTween = TweenService:Create(
				button,
				TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = UDim2.new(0, origSize.X.Offset - 6, 0, origSize.Y.Offset - 4) }
			)
			pressTween:Play()
			pressTween.Completed:Connect(function()
				local releaseTween = TweenService:Create(
					button,
					TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Size = origSize }
				)
				releaseTween:Play()
			end)
		end)
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Inventory state (shadow-tracked from server events)
-- ═══════════════════════════════════════════════════════════════════
--
-- See "API note" at the top of the file. We track what we can deduce from:
--   - NotifyEvent on hatch ("You hatched a [Rarity] [Name]!") → inferred new pet record
--   - UpdateHUDEvent on equip (full equippedPet payload) → confirmed pet record
--   - UpdateHUDEvent.petCount → reconciliation hint for placeholder cards

local knownPets = {} -- ordered list, each entry: { id, name, rarity, multipliers? }
local knownPetById = {} -- id → entry
local equippedPetId = nil
local serverPetCount = 0
local hatchSequenceCounter = 0 -- monotonic id for inferred records

local function petMultipliersFromName(name)
	local def = PetDatabase.getPet(name)
	if def and def.multipliers then
		return def.multipliers
	end
	return { dig_speed = 1.0, loot_value = 1.0, luck = 1.0 }
end

-- Track or update a pet record by id. Used both for hatch-inferred records
-- (where the id is a guess) and for equip-confirmed records (server-provided id).
local function upsertPet(id, name, rarity)
	local existing = knownPetById[id]
	if existing then
		if name then
			existing.name = name
			existing.multipliers = petMultipliersFromName(name)
		end
		if rarity then
			existing.rarity = rarity
		end
		existing.placeholder = false
		return existing
	end

	local entry = {
		id = id,
		name = name or ("Pet #" .. tostring(id)),
		rarity = rarity or "Common",
		multipliers = name and petMultipliersFromName(name) or { dig_speed = 1.0, loot_value = 1.0, luck = 1.0 },
		placeholder = (name == nil),
	}
	knownPetById[id] = entry
	table.insert(knownPets, entry)
	return entry
end

-- ═══════════════════════════════════════════════════════════════════
-- Inventory rendering
-- ═══════════════════════════════════════════════════════════════════

local function formatMultiplierPreview(multipliers)
	-- Pick the strongest non-1.0 stat for the preview so the card stays compact.
	local stats = {
		{ key = "luck", label = "luck" },
		{ key = "loot_value", label = "loot" },
		{ key = "dig_speed", label = "speed" },
	}
	local bestLine = nil
	local bestDelta = 0
	for _, stat in ipairs(stats) do
		local v = multipliers and multipliers[stat.key] or 1
		local delta = v - 1
		if delta > bestDelta then
			bestDelta = delta
			bestLine = string.format("+%d%% %s", math.floor(delta * 100 + 0.5), stat.label)
		end
	end
	return bestLine or "no buffs"
end

local function buildPetCard(entry)
	local card = Instance.new("Frame")
	card.Name = "Pet_" .. tostring(entry.id)
	card.BackgroundColor3 = CARD_BG
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel = 0
	card.LayoutOrder = entry.id

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 6)
	cardCorner.Parent = card

	local rarityColor = RarityColors[entry.rarity] or RarityColors.Common
	local isEquipped = (equippedPetId == entry.id)

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = isEquipped and ACCENT_GOLD or rarityColor
	cardStroke.Thickness = isEquipped and 3 or 2
	cardStroke.Parent = card

	-- Rarity tint bar across the top
	local tintBar = Instance.new("Frame")
	tintBar.Size = UDim2.new(1, 0, 0, 6)
	tintBar.Position = UDim2.new(0, 0, 0, 0)
	tintBar.BackgroundColor3 = rarityColor
	tintBar.BackgroundTransparency = 0.1
	tintBar.BorderSizePixel = 0
	tintBar.Parent = card

	local tintCorner = Instance.new("UICorner")
	tintCorner.CornerRadius = UDim.new(0, 4)
	tintCorner.Parent = tintBar

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -10, 0, 18)
	nameLabel.Position = UDim2.new(0, 5, 0, 10)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = entry.name
	nameLabel.TextColor3 = TEXT_PRIMARY
	nameLabel.TextSize = 13
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Size = UDim2.new(1, -10, 0, 14)
	rarityLabel.Position = UDim2.new(0, 5, 0, 28)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Text = entry.rarity
	rarityLabel.TextColor3 = rarityColor
	rarityLabel.TextSize = 11
	rarityLabel.Font = Enum.Font.GothamMedium
	rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
	rarityLabel.Parent = card

	local mulLabel = Instance.new("TextLabel")
	mulLabel.Size = UDim2.new(1, -10, 0, 14)
	mulLabel.Position = UDim2.new(0, 5, 0, 44)
	mulLabel.BackgroundTransparency = 1
	mulLabel.Text = entry.placeholder and "(unknown)" or formatMultiplierPreview(entry.multipliers)
	mulLabel.TextColor3 = TEXT_MUTED
	mulLabel.TextSize = 11
	mulLabel.Font = Enum.Font.Gotham
	mulLabel.TextXAlignment = Enum.TextXAlignment.Left
	mulLabel.Parent = card

	local equipButton = Instance.new("TextButton")
	equipButton.Size = UDim2.new(1, -10, 0, 26)
	equipButton.Position = UDim2.new(0, 5, 1, -32)
	equipButton.BackgroundColor3 = isEquipped and ACCENT_GOLD or rarityColor
	equipButton.BackgroundTransparency = 0.1
	equipButton.BorderSizePixel = 0
	equipButton.Text = isEquipped and "EQUIPPED" or "Equip"
	equipButton.TextColor3 = isEquipped and Color3.fromRGB(20, 20, 25) or Color3.fromRGB(20, 20, 25)
	equipButton.TextSize = 12
	equipButton.Font = Enum.Font.GothamBold
	equipButton.AutoButtonColor = true
	equipButton.Parent = card

	local equipCorner = Instance.new("UICorner")
	equipCorner.CornerRadius = UDim.new(0, 4)
	equipCorner.Parent = equipButton

	equipButton.Activated:Connect(function()
		if equippedPetId == entry.id then
			-- Toggle off (unequip)
			EquipPetEvent:FireServer(nil)
		else
			EquipPetEvent:FireServer(entry.id)
		end
	end)

	return card
end

local function renderInventory()
	-- Clear existing cards (keep UIGridLayout / UIPadding)
	for _, child in ipairs(inventoryScroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Reconcile placeholder count with serverPetCount
	local known = #knownPets
	if serverPetCount > known then
		-- Insert placeholder entries with synthetic high ids to avoid colliding
		-- with real ids (real ids start at 1). We don't actually know which ids
		-- are missing — these are "ghost" cards that say "rejoined session".
		local missing = serverPetCount - known
		for _ = 1, missing do
			hatchSequenceCounter = hatchSequenceCounter + 1
			-- Synthetic ids in a high range so they won't collide if we later
			-- learn the real id via an equip event.
			local syntheticId = -hatchSequenceCounter
			upsertPet(syntheticId, nil, nil)
		end
	end

	if #knownPets == 0 then
		emptyPlaceholder.Visible = true
		inventoryScroll.Visible = false
		toggleBadge.Visible = false
		return
	end

	emptyPlaceholder.Visible = false
	inventoryScroll.Visible = true

	-- Sort: equipped first, then by rarity strength, then by id
	local rarityRank = {
		Mythic = 6, Legendary = 5, Epic = 4, Rare = 3, Uncommon = 2, Common = 1,
	}
	table.sort(knownPets, function(a, b)
		if (a.id == equippedPetId) ~= (b.id == equippedPetId) then
			return a.id == equippedPetId
		end
		local ra = rarityRank[a.rarity] or 0
		local rb = rarityRank[b.rarity] or 0
		if ra ~= rb then return ra > rb end
		return a.id < b.id
	end)

	for index, entry in ipairs(knownPets) do
		entry._sortIndex = index
		local card = buildPetCard(entry)
		card.LayoutOrder = index
		card.Parent = inventoryScroll
	end

	-- Update toggle badge with the better-of-known-vs-server count
	local displayCount = math.max(#knownPets, serverPetCount)
	toggleBadge.Text = tostring(displayCount)
	toggleBadge.Visible = displayCount > 0
end

-- ═══════════════════════════════════════════════════════════════════
-- Server event handling — shadow-track inventory state
-- ═══════════════════════════════════════════════════════════════════

-- Match: "You hatched a [Rarity] [Pet Name]!"
local HATCH_PATTERN = "^You hatched a (%a+) (.-)!$"

NotifyEvent.OnClientEvent:Connect(function(text, _rarity)
	if type(text) ~= "string" then return end

	local rarity, name = string.match(text, HATCH_PATTERN)
	if not (rarity and name) then return end

	-- Server doesn't tell us the new pet's id directly — it's #data.pets after
	-- insert. We approximate by appending after our known max real id. When
	-- the player eventually equips it, the equip event's id will be the
	-- authoritative one and we'll reconcile.
	local nextId = 0
	for _, entry in ipairs(knownPets) do
		if entry.id > 0 and entry.id > nextId then
			nextId = entry.id
		end
	end
	-- Bump to at least serverPetCount so we don't double-place.
	nextId = math.max(nextId, serverPetCount) + 1

	upsertPet(nextId, name, rarity)
	-- Bump serverPetCount optimistically; UpdateHUD will confirm.
	serverPetCount = math.max(serverPetCount, nextId)

	hatcheryStatus.Text = string.format("Hatched: %s %s!", rarity, name)
	hatcheryStatus.TextColor3 = RarityColors[rarity] or ACCENT_GOLD

	if panel.Visible then
		renderInventory()
	else
		-- Still update badge even if panel closed
		toggleBadge.Text = tostring(math.max(#knownPets, serverPetCount))
		toggleBadge.Visible = true
	end
end)

UpdateHUDEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end

	local changed = false

	if payload.petCount ~= nil and type(payload.petCount) == "number" then
		serverPetCount = payload.petCount
		changed = true
	end

	if payload.equippedPet ~= nil then
		if payload.equippedPet == false or payload.equippedPet == 0 then
			if equippedPetId ~= nil then
				equippedPetId = nil
				changed = true
			end
		elseif type(payload.equippedPet) == "number" then
			-- Authoritative id from server. If we have a placeholder (negative
			-- synthetic id) and the server gives us a real id, reuse the
			-- placeholder slot so the count stays consistent.
			if not knownPetById[payload.equippedPet] then
				-- Try to absorb a placeholder
				local absorbed = false
				for i, entry in ipairs(knownPets) do
					if entry.placeholder and entry.id < 0 then
						knownPetById[entry.id] = nil
						entry.id = payload.equippedPet
						entry.name = payload.petName or entry.name
						entry.rarity = payload.petRarity or entry.rarity
						entry.multipliers = payload.petMultipliers
							or (payload.petName and petMultipliersFromName(payload.petName))
							or entry.multipliers
						entry.placeholder = (payload.petName == nil)
						knownPetById[entry.id] = entry
						knownPets[i] = entry
						absorbed = true
						break
					end
				end
				if not absorbed then
					upsertPet(payload.equippedPet, payload.petName, payload.petRarity)
				end
			else
				-- Refresh the entry with any new info
				upsertPet(payload.equippedPet, payload.petName, payload.petRarity)
			end
			-- Ensure multipliers from payload override database lookup if present
			local entry = knownPetById[payload.equippedPet]
			if entry and payload.petMultipliers then
				entry.multipliers = payload.petMultipliers
			end
			equippedPetId = payload.equippedPet
			changed = true
		end
	end

	if changed and panel.Visible then
		renderInventory()
	elseif changed then
		-- Update badge even while closed
		toggleBadge.Text = tostring(math.max(#knownPets, serverPetCount))
		toggleBadge.Visible = math.max(#knownPets, serverPetCount) > 0
	end
end)

-- ═══════════════════════════════════════════════════════════════════
-- Panel toggle + persistence + auto-refresh
-- ═══════════════════════════════════════════════════════════════════

local function setPanelVisible(visible)
	panel.Visible = visible
	player:SetAttribute("PetPanelOpen", visible)
	if visible then
		renderInventory()
	end
end

toggleButton.Activated:Connect(function()
	setPanelVisible(not panel.Visible)
end)

closeButton.Activated:Connect(function()
	setPanelVisible(false)
end)

-- Restore from attribute on script load (preserves across CharacterAdded
-- because ResetOnSpawn = false on the ScreenGui).
local savedOpen = player:GetAttribute("PetPanelOpen")
if savedOpen == true then
	setPanelVisible(true)
end

-- Auto-refresh inventory every 5 seconds while open. This keeps the
-- equipped-pet badge fresh in case multiple events landed in quick succession.
task.spawn(function()
	while true do
		task.wait(5)
		if panel.Visible then
			renderInventory()
		end
	end
end)
