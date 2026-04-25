# Deep Dig — Roblox Excavation Game

## Vault Write-Intent Contract (Required Before Edits)

This file is project-specific quick start only. It does not replace the vault bootstrap contract for write-enabled work.

Before editing files, staging, or committing:

1. Read `_state.md` first for live incidents and concurrent work signals.
2. Read `_collab/START-HERE.md` and follow its write-intent bootstrap path.
3. Read `_collab/protocol/AGENT-PROTOCOL.md`.
4. Read `_collab/protocol/RULES.md`.

Guardrails:

- If bootstrap evidence is incomplete or live state is unclear, remain read-only.
- If an operational claim cannot be confirmed from live state or runtime scripts, mark it `[UNVERIFIED]` instead of guessing.
- Before staging, committing, or merging, run `bash _scripts/validation-gate.sh --staged` and stop on failure.

## Project Quick Start (After Bootstrap)

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
