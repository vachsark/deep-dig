# Deep Dig — Architecture Reference

Code-level reference for the running game. For setup see `WINDOWS-SETUP.md`. For lane behavior see `.claude/rules/lane-context.md`.

## Module layout

```
src/
├── ReplicatedStorage/        ← shared state, all scripts read these
│   ├── Config.lua            ← TIERS, TOOLS, DIG_SITE_CENTER, balance numbers
│   ├── ItemDatabase.lua      ← all 48 collectible items, by tier
│   ├── EnemyDatabase.lua     ← 6 enemy types + Hollow King miniboss
│   ├── PetDatabase.lua       ← egg tiers, pet stats, hatch tables
│   └── QuestDatabase.lua     ← daily/weekly quest definitions
│
├── ServerScriptService/      ← server-authoritative game logic
│   ├── GameManager.server.lua    ★ owns _G.DeepDig_playerData, fires PlayerDataReady
│   ├── DigSystem.server.lua      ← block-break + loot rolls, range-validates DigRequest
│   ├── EnemySystem.server.lua    ← enemy spawn/AI/damage, weighted miniboss selection
│   ├── CombatRespawn.server.lua  ← surface-respawn on Humanoid death, no item loss
│   ├── BadgeSystem.server.lua    ← Roblox badge awards
│   ├── QuestSystem.server.lua    ← quest progress + claim
│   ├── DailyStreak.server.lua    ← 7-day login ladder
│   ├── Gamepasses.server.lua     ← VIP, 2x loot, lucky digger, foreman, infinite, auto-collector
│   ├── PetSystem.server.lua      ← egg hatch, pet equip, multipliers
│   ├── PetFeed.server.lua        ← duplicate pet → XP
│   ├── Trading.server.lua        ← P2P proximity trading
│   ├── Museum.server.lua         ← personal museum + teleport pads
│   ├── Rebirth.server.lua        ← resurface/prestige
│   ├── Leaderboard.server.lua    ← per-server + global OrderedDataStore
│   ├── PromoCodes.server.lua     ← code redemption
│   ├── OfflineIncome.server.lua  ← passive coins while offline
│   ├── SeasonalEvents.server.lua ← scheduled in-world events
│   ├── AdminCommands.server.lua  ← chat-gated /maxall /coins /tool (game owner only)
│   └── AudioRouter.server.lua    ← server-side sound triggers
│
└── StarterGui/               ← client UI + effects
    ├── HudGui.client.lua          ← depth, money, streak, museum/resurface buttons
    ├── DigClient.client.lua       ← dig click handler + particle FX
    ├── EnemyHealthBar.client.lua  ← floating BillboardGui HP bars
    ├── QuestGui.client.lua        ← quest panel
    ├── PetGui.client.lua          ← pet inventory + equip
    ├── EggOpenAnimation.client.lua
    ├── LeaderboardGui.client.lua
    ├── TradeGui.client.lua
    ├── StatsGui.client.lua
    ├── NotifyManager.client.lua   ← toast notifications
    ├── EarthquakeFX.client.lua    ← screen shake
    ├── FTUEHints.client.lua       ← first-time tutorial arrows
    └── AudioPlayer.client.lua     ← client-side sound playback
```

## The shared player-data global

`_G.DeepDig_playerData` is a table keyed by `Player` instance, populated by `GameManager.server.lua` on `PlayerAdded`. Every other server script reads from it.

Approximate shape (verify in `GameManager.server.lua` for current fields):

```lua
_G.DeepDig_playerData[player] = {
    coins        = number,
    fragments    = number,           -- from recycling duplicates
    deepestBlock = number,           -- depth tier progression gate
    toolTier     = number,           -- 1..6, indexes Config.TOOLS
    inventory    = { [itemId] = count },
    collection   = { [itemId] = true },
    petInventory = { ... },
    equippedPet  = petId or nil,
    streakDay    = number,
    questProgress = { ... },
    badges       = { [badgeId] = true },
    gamepasses   = { vip = bool, loot2x = bool, ... },
    rebirths     = number,
    -- ...
}
```

**Never** read player data via `task.wait(N)` and hope it's populated. Use one of:

```lua
-- Pattern A: blocking helper
local data = awaitPlayerData(player)  -- defined in GameManager

-- Pattern B: event listener
local PlayerDataReady = ServerScriptService.ServerEvents.PlayerDataReady
PlayerDataReady.Event:Connect(function(player) ... end)
```

This is the fix from commit `744f2b3` — race-condition bugs across 4 scripts.

## Remotes (in `ReplicatedStorage.Remotes`)

All RemoteEvents/RemoteFunctions are created by `GameManager.server.lua` on startup (or by their owning system) and parented to a `Remotes` Folder.

| Remote                                                                                                                                 | Type           | Direction       | Purpose                                     | Validation                        |
| -------------------------------------------------------------------------------------------------------------------------------------- | -------------- | --------------- | ------------------------------------------- | --------------------------------- |
| `DigRequest`                                                                                                                           | RemoteEvent    | client → server | Player clicked a block                      | 60-stud range, tool-cooldown      |
| `EnemyHitEvent`                                                                                                                        | RemoteEvent    | client → server | Player swung tool at an enemy               | 8-stud range, per-player cooldown |
| `ItemFound`                                                                                                                            | RemoteEvent    | server → client | Show item discovery toast                   | —                                 |
| `UpdateHUD`                                                                                                                            | RemoteEvent    | server → client | Refresh coins/depth/inventory in HUD        | —                                 |
| `Notify`                                                                                                                               | RemoteEvent    | server → client | Generic toast notification                  | —                                 |
| `PlaySound`                                                                                                                            | RemoteEvent    | server → client | Trigger named sound on client               | —                                 |
| `EventTriggered`                                                                                                                       | RemoteEvent    | server → client | Server event broadcast (Earthquake, etc.)   | —                                 |
| `GetPlayerData`                                                                                                                        | RemoteFunction | client → server | Initial state pull on join                  | —                                 |
| `GetTopDepths`                                                                                                                         | RemoteFunction | client → server | Leaderboard fetch                           | —                                 |
| `HatchEgg` / `EquipPet` / `FeedPet` / `GetPetInventory`                                                                                | mixed          | both            | Pet system                                  | per-event cooldown                |
| `RequestStreakRevive`                                                                                                                  | RemoteEvent    | client → server | Daily streak revive (Robux dev product TBD) | —                                 |
| Trade events (`RequestTradeEvent`, `RespondTradeEvent`, `SetTradeOfferEvent`, `ConfirmTradeEvent`, `CancelTradeEvent`, `TradeUIEvent`) | RemoteEvent    | both            | P2P trading                                 | proximity check                   |
| `RedeemCodeEvent` / `CodeResultEvent`                                                                                                  | RemoteEvent    | both            | Promo codes                                 | server-side code validation       |

**Rule for new remotes:**

1. Create + parent in the system that owns the feature, not in `GameManager`
2. Server-side validate distance + add per-player cooldown
3. Don't trust the client for any value that can be derived server-side (positions, damage, IDs)

## Where do I add X?

| If you want to add...        | Touch these files                                                                       |
| ---------------------------- | --------------------------------------------------------------------------------------- |
| New collectible item         | `ReplicatedStorage/ItemDatabase.lua` (data only, dig system picks it up automatically)  |
| New enemy                    | `ReplicatedStorage/EnemyDatabase.lua` + verify spawn weight / aggro radius              |
| New miniboss                 | EnemyDatabase entry + `ServerScriptService/EnemySystem.server.lua` (cap, weighted roll) |
| New tool tier                | `ReplicatedStorage/Config.lua` (`TOOLS` table, `damage` field included)                 |
| New depth tier               | `ReplicatedStorage/Config.lua` (`TIERS` table) — keep depths monotonic                  |
| New gamepass                 | `ServerScriptService/Gamepasses.server.lua` + ID in the passes table                    |
| New egg / pet                | `ReplicatedStorage/PetDatabase.lua`                                                     |
| New daily/weekly quest       | `ReplicatedStorage/QuestDatabase.lua`                                                   |
| New badge                    | `ServerScriptService/BadgeSystem.server.lua` + Roblox badge ID                          |
| New seasonal event           | `ServerScriptService/SeasonalEvents.server.lua`                                         |
| New HUD element              | `StarterGui/HudGui.client.lua`                                                          |
| New particle / screen effect | New `*.client.lua` in `StarterGui/`, listen to a server-fired RemoteEvent               |

## Player data persistence

DataStore-backed. Auto-saves on a timer + on `PlayerRemoving`. If you add a new field to `_G.DeepDig_playerData`, also:

1. Add a default value in `GameManager.server.lua` (so existing players don't get `nil`)
2. Verify it's included in the save serialization
3. Verify it's loaded back on `PlayerAdded`

Forgetting any of these silently loses data.

## Things that already burned us (don't repeat)

- **PlayerAdded race**: do not `task.wait(2)` to wait for player data. (commit `744f2b3`)
- **Stub functions**: don't ship a feature whose key function is a no-op. Resurface, Trading.executeTrade, PromoCodes were all stubs that shipped feeling broken to players. (commits `77976db`, `117abaf`, `7ea3916`)
- **Range checks**: server must validate every player-claimed position. The lane added 60-stud check on dig (commit `8af4007`); same pattern for enemy hits at 8 studs.
- **Parse errors in fresh files**: run `luac -p` on every Lua file you create or edit. (Museum.server.lua and Rebirth.server.lua had parse errors that shipped before this rule.)
- **Per-block FX**: particle bursts on every block break is fine; full-screen flashes should be Legendary+ only or it gets noisy fast.
