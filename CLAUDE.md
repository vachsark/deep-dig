# Deep Dig — Roblox Excavation Game

## Setup

All scripts are Luau files ready to paste into Roblox Studio.

### Studio Structure

```
ServerScriptService/
  GameManager.server.lua        -- Core game loop, player data
  DigSystem.server.lua          -- Block breaking, loot drops
  ToolShop.server.lua           -- Tool upgrades, purchases

ReplicatedStorage/
  ItemDatabase.module.lua       -- All discoverable items
  Config.module.lua             -- Game constants

StarterPlayerScripts/
  DigClient.client.lua          -- Client-side dig effects, UI updates

StarterGui/
  InventoryGui.client.lua       -- Inventory + collection UI
  ShopGui.client.lua            -- Tool shop UI
  HudGui.client.lua             -- Depth meter, money display
```

### How to Import

1. Open Roblox Studio → New Baseplate
2. Create the folder structure above
3. For each `.lua` file, create the matching script type and paste contents
4. Add terrain: large flat terrain with a deep pit area
5. Playtest

## Game Design

- Core loop: Dig → Discover → Collect → Sell → Upgrade
- 6 depth tiers with era-themed loot
- Tool progression (6 tiers)
- Personal museum (future)
- Multiplayer shared dig sites
