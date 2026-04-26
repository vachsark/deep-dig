-- EnemyHealthBar.client.lua - floating enemy names and HP bars
-- Place in: StarterGui/EnemyHealthBar (LocalScript)

local HEALTH_BAR_NAME = "DeepDigEnemyHealthBar"
local MAX_DISTANCE = 80
local BAR_WIDTH = 120
local BAR_HEIGHT = 36

local trackedEnemies = {}

local function getHealthColor(ratio)
	if ratio > 0.5 then
		local t = (ratio - 0.5) / 0.5
		return Color3.fromRGB(245, 210, 65):Lerp(Color3.fromRGB(70, 220, 95), t)
	end

	local t = ratio / 0.5
	return Color3.fromRGB(220, 55, 45):Lerp(Color3.fromRGB(245, 210, 65), t)
end

local function findHumanoid(model, timeoutSeconds)
	local elapsed = 0
	local step = 0.1
	local timeout = timeoutSeconds or 5

	while elapsed < timeout and model.Parent do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid
		end

		task.wait(step)
		elapsed = elapsed + step
	end

	return nil
end

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		if connection then
			connection:Disconnect()
		end
	end
end

local function cleanupEnemy(model)
	local record = trackedEnemies[model]
	if not record then
		return
	end

	trackedEnemies[model] = nil
	disconnectAll(record.connections)

	if record.gui and record.gui.Parent then
		record.gui:Destroy()
	end
end

local function createHealthBar(model, root)
	local existing = root:FindFirstChild(HEALTH_BAR_NAME)
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = HEALTH_BAR_NAME
	billboard.Adornee = root
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE
	billboard.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.Parent = root

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = model:GetAttribute("EnemyName") or model.Name
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeTransparency = 0.35
	nameLabel.TextSize = 13
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.Parent = billboard

	local back = Instance.new("Frame")
	back.Name = "HealthBack"
	back.Position = UDim2.fromOffset(8, 19)
	back.Size = UDim2.new(1, -16, 0, 10)
	back.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	back.BackgroundTransparency = 0.15
	back.BorderSizePixel = 0
	back.Parent = billboard

	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 4)
	backCorner.Parent = back

	local fill = Instance.new("Frame")
	fill.Name = "HealthFill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(70, 220, 95)
	fill.BorderSizePixel = 0
	fill.Parent = back

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.6
	stroke.Thickness = 1
	stroke.Parent = back

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HealthLabel"
	hpLabel.Size = UDim2.fromScale(1, 1)
	hpLabel.BackgroundTransparency = 1
	hpLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpLabel.TextStrokeTransparency = 0.55
	hpLabel.TextSize = 8
	hpLabel.Font = Enum.Font.GothamBold
	hpLabel.TextXAlignment = Enum.TextXAlignment.Center
	hpLabel.Parent = back

	return billboard, fill, hpLabel
end

local function trackEnemy(model)
	if trackedEnemies[model] or not model:IsA("Model") then
		return
	end

	task.spawn(function()
		if trackedEnemies[model] or not model.Parent then
			return
		end

		local root = model:FindFirstChild("HumanoidRootPart") or model:WaitForChild("HumanoidRootPart", 5)
		local humanoid = findHumanoid(model, 5)
		if not root or not humanoid or not model.Parent then
			return
		end

		local gui, fill, hpLabel = createHealthBar(model, root)
		local record = {
			gui = gui,
			connections = {},
		}
		trackedEnemies[model] = record

		local function update()
			if not model.Parent or humanoid.Health <= 0 then
				cleanupEnemy(model)
				return
			end

			local maxHealth = math.max(humanoid.MaxHealth, 1)
			local ratio = math.clamp(humanoid.Health / maxHealth, 0, 1)
			fill.Size = UDim2.fromScale(ratio, 1)
			fill.BackgroundColor3 = getHealthColor(ratio)
			hpLabel.Text = string.format("%d/%d", math.ceil(humanoid.Health), math.ceil(maxHealth))
		end

		table.insert(record.connections, humanoid.HealthChanged:Connect(update))
		table.insert(record.connections, humanoid.Died:Connect(function()
			cleanupEnemy(model)
		end))
		table.insert(record.connections, model.AncestryChanged:Connect(function(_, parent)
			if not parent then
				cleanupEnemy(model)
			end
		end))

		update()
	end)
end

local enemiesFolder = workspace:WaitForChild("Enemies")

for _, child in ipairs(enemiesFolder:GetChildren()) do
	trackEnemy(child)
end

enemiesFolder.ChildAdded:Connect(trackEnemy)
enemiesFolder.ChildRemoved:Connect(cleanupEnemy)

print("[DeepDig] EnemyHealthBar loaded")
