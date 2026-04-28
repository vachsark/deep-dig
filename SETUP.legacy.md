# Deep Dig — Setup Guide (10 minutes)

## Step 1: Download Roblox Studio
1. Go to https://create.roblox.com
2. Sign in (or create a free account)
3. Click "Start Creating" → downloads Roblox Studio
4. Install and open it

## Step 2: Create New Place
1. File → New → Baseplate
2. Save it: File → Save to Roblox → name it "Deep Dig"

## Step 3: Create Scripts (paste each one)

### 3a. Config (ModuleScript)
1. In Explorer panel (right side), click **ReplicatedStorage**
2. Right-click → Insert Object → **ModuleScript**
3. Rename it to **Config**
4. Open `src/ReplicatedStorage/Config.module.lua` and paste ALL contents
5. Save (Ctrl+S)

### 3b. ItemDatabase (ModuleScript)
1. Right-click **ReplicatedStorage** → Insert Object → **ModuleScript**
2. Rename to **ItemDatabase**
3. Paste contents of `src/ReplicatedStorage/ItemDatabase.module.lua`

### 3c. GameManager (Script — server)
1. Click **ServerScriptService** in Explorer
2. Right-click → Insert Object → **Script**
3. Rename to **GameManager**
4. Paste contents of `src/ServerScriptService/GameManager.server.lua`

### 3d. DigSystem (Script — server)
1. Right-click **ServerScriptService** → Insert Object → **Script**
2. Rename to **DigSystem**
3. Paste contents of `src/ServerScriptService/DigSystem.server.lua`

### 3e. Museum (Script — server)
1. Right-click **ServerScriptService** → Insert Object → **Script**
2. Rename to **Museum**
3. Paste contents of `src/ServerScriptService/Museum.server.lua`

### 3f. Trading (Script — server)
1. Right-click **ServerScriptService** → Insert Object → **Script**
2. Rename to **Trading**
3. Paste contents of `src/ServerScriptService/Trading.server.lua`

### 3g. HudGui (LocalScript — client)
1. Click **StarterGui** in Explorer
2. Right-click → Insert Object → **LocalScript**
3. Rename to **HudGui**
4. Paste contents of `src/StarterGui/HudGui.client.lua`

## Step 4: Play!
1. Click the **Play** button (green triangle at top)
2. You spawn on a platform above the dig site
3. Equip the Excavator tool from your inventory (press 1)
4. Click blocks to dig
5. Find items, sell them, upgrade your tool, go deeper

## Step 5: Publish (make it multiplayer)
1. File → Publish to Roblox
2. Game Settings → set to Public
3. Share the game link with friends

## Controls
- Click block = Dig
- 1 = Equip excavator
- Sell All button = bottom right
- Upgrade button = bottom right
- Recycle Dupes = converts duplicates to fragments
- Purple pads = teleport to museums
- Green pad (in museum) = return to dig site
