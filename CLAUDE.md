# Deep Dig — Roblox Excavation Game

## Multi-Machine Coordination (READ FIRST)

This repo has **multiple concurrent writers**:

- An autonomous lane runs on Vache's Linux box (TestVault `_scripts/heartbeat-collectors/roblox-worker.sh`), driven by `roblox-architect` (Codex gpt-5.3-codex, every 4h) and `roblox-worker` (Codex gpt-5.4-mini, every 1h). It auto-commits + auto-pushes gameplay-meaningful changes to `origin/master`.
- Vache (or another Claude session) may edit from a Windows clone for Studio playtests.

**Protocol — every Claude in this repo MUST follow:**

1. **Before any work** (even just reading code to advise): `git pull --rebase origin master`. Skipping this means you're working on stale state and will collide with the lane.
2. **After committing**: push immediately — `git push origin master`. Do not sit on local commits; the lane will rebase and push around you, leaving your work behind.
3. **If push is rejected**: `git pull --rebase origin master`, resolve conflicts, push again. Never `git push --force` to master — you will overwrite the lane's commits.
4. **If you hit a real conflict you can't resolve**: stop and surface it to Vache. Don't guess.
5. **Before starting anything substantial**: `git log --oneline -3` — if the most recent commit is from the last ~5 minutes and authored by `Codex gpt-5.4-mini` or `Codex gpt-5.3-codex`, the lane is mid-cycle. Wait a minute, pull again, then start.
6. **Default branch is `master`**, not `main`.

The lane has the same protocol baked in (`pull --rebase` on push rejection). As long as both writers follow it, they coexist cleanly.

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
