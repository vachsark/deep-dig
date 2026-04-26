# Deep Dig — Feature Roadmap

## What We Have (MVP)

- [x] 6 depth tiers with era-themed loot (48 items)
- [x] Tool progression (6 tiers)
- [x] Random server events (Fossil Layer, Gold Vein, Cave System, Earthquake)
- [x] Personal museum with teleport pads
- [x] Player-to-player proximity trading
- [x] Duplicate recycling → fragments → crafting
- [x] Promo codes (DEEPDIG, DIGDEEP, FIRSTDIG)
- [x] Resurface/rebirth with auras + badges
- [x] DataStore persistence + auto-save
- [x] Full HUD

## Phase 1: Launch Week (highest impact, easiest to build)

### 1. FTUE Tuning (Day 1) — COMPLETE

- [x] Guarantee first item drop within 10 blocks (commit 36a0183)
- [x] Tune economy so first sell = enough for Tier 2 tool (commit ca1eb9e)
- [x] Add arrow guide: dig → sell → upgrade flow (commit 43def6d)
- [x] First gamepass prompt only after 4 minutes (commit 15a1d76)
- [x] First-time tutorial popup (commit bc91223)

### 2. Screen Effects for Rare Finds (Day 1-2) — IN PROGRESS

- [ ] Full-screen gold flash on Legendary+ finds
- [ ] Screen shake on events
- [x] Particle burst at finder's position (commit 8af4007 — every block break)
- [x] Sound effects scaffolding (commit 03ff2f8 — block_break + resurface_fanfare; remaining hooks: item_found, rare_reveal, sell_coins, upgrade_whoosh, event_alarm)

### 3. Daily Login Streak (Day 2-3) — COMPLETE

- [x] 7-day cycle reward ladder
- [x] Streak counter in HUD
- [ ] Streak revival for 50 Robux (Robux dev product not yet wired)

### 4. Gamepasses (Day 2-3) — COMPLETE (placeholder asset IDs — needs real Roblox passes)

- [x] 2x Loot Value gamepass effect wired
- [x] VIP gamepass effect wired
- [x] Lucky Digger gamepass effect wired
- [ ] Replace placeholder pass IDs (1, 2, 3) with real Creator Hub IDs before launch

### 5. Depth Leaderboard (Day 3-4) — COMPLETE

- [x] In-world board showing top 5 on current server (commit abcd57e)
- [x] Global leaderboard via OrderedDataStore
- [x] "New Personal Best!" notifications

### 6. Stability + UX gaps shipped 2026-04-25

- [x] Resurface (prestige) fully wired end-to-end (commit 77976db) — was a stub
- [x] Trading.executeTrade actually swaps inventory (commit 117abaf) — was a no-op
- [x] PromoCodes actually applies rewards (commit 7ea3916) — was a phantom toast
- [x] Museum.server.lua + Rebirth.server.lua parse-error fix (commit 3441a2c)
- [x] Museum + Resurface buttons in HUD (commits bc91223, 77976db)
- [x] AdminCommands chat gate (commit 5233dfe) — game owner can /maxall, /coins, /tool
- [x] 60-stud range check on dig (commit 8af4007)
- [x] PlayerAdded race fix across 4 server scripts (commit 744f2b3)

## Phase 2: First Month (retention + monetization)

### TOP PRIORITY — Enemies / Combat (added 2026-04-26, build first)

The dig site is too peaceful and the mid-game loop is grinding without tension. Add buried creatures that spawn deeper than X depth and have to be defeated to keep digging. Existing tools become weapons (higher tool tier = more damage), enemies drop coins / fragments / occasionally a tier-appropriate item. Death just respawns at the surface — keep it forgiving.

- [ ] **EnemyDatabase.lua** (ReplicatedStorage ModuleScript): 6 enemy types tagged to depth tier — Bone Crawler (Stone), Bronze Sentinel (Bronze), Rusted Construct (Iron), Iron Wraith (Iron+), Voidling (Unknown), and a tier-Unknown miniboss "Hollow King". Each has `{name, tier, hp, damage, coinDrop, fragmentDrop, itemDropChance, color, model = "BasicNPC"}`.
- [ ] **EnemySystem.server.lua**: spawns one enemy per active player every 30s if their `data.deepestBlock` is past the tier threshold. Cap of 5 alive per player. Random walk AI with a 16-stud aggro radius. Damages player if it touches them (no projectiles for v1). Listens to `BlockBrokenEvent` or a new `EnemyHitEvent` so the player's tool counts as the weapon — damage = `Config.TOOLS[data.toolTier].damage` (add a `damage` field to each tool record). On death: pay coins/fragments via `_G.DeepDig_playerData`, occasionally roll a tier-appropriate item via existing `ItemDatabase` helpers.
- [ ] **Tool damage wiring in Config**: add `damage` field per tool — Rusty Shovel 1, all the way up to top tier ~25. No client changes needed.
- [ ] **EnemyHitEvent** (RemoteEvent in `ReplicatedStorage.Remotes`): client fires on click/proximity-attack, server validates 8-stud range + cooldown.
- [ ] **EnemyHealthBar** (StarterGui LocalScript or BillboardGui): floating HP bar above each enemy. Color-shifts as HP drops.
- [ ] **Death + respawn**: if player Humanoid health hits 0, server respawns them at dig-site origin and they keep their inventory. No item loss.
- [ ] **BadgeSystem hook**: add `first_enemy_kill` and `enemy_count_100` badges.
- [ ] **QuestSystem hook**: add `kill_enemies` quest type and 1-2 daily quests around it.

### 6. Offline Passive Income

- Earn coins while logged out (rate based on tool tier)
- Cap at 8 hours (24h with gamepass)
- "Welcome back!" popup showing earnings
- Foreman's Pass gamepass — 499 R$

### 7. Quest System

- Daily quests (dig 50, find 3 rare, earn 10K)
- Weekly challenges (reach tier X, complete 5 dailies)
- Milestone achievements (permanent badges)
- Progress bars in side panel

### 8. Pet System (Egg Hatching)

- Stone Egg (1K coins), Gem Egg (10K), Void Egg (100K)
- Pets give passive multipliers (dig speed, loot value, luck)
- Server-wide announcement on Legendary pet hatch
- Lucky Egg Gamepass — 699 R$
- Feed duplicate pets to level up (ties into fragment system)

### 9. More Gamepasses

- Auto Collector — 349 R$
- Infinite Backpack — 799 R$
- Artifact Detector — 999 R$
- Rebirth Boost — 299 R$

## Phase 3: Growth (virality + community)

### 10. Seasonal Events (4/year)

- Halloween: "The Bone Age" — ghost fossils, haunted dig site
- Winter: "The Ice Age" — permafrost layer, frozen artifacts
- Spring: "Fossil Rush" — dino eggs across all tiers
- Summer: "Volcano Event" — lava layer, obsidian tools
- Exclusive items grayed in museum year-round (FOMO)

### 11. Group + Friend Referrals

- Roblox Group = +10% coins + unique name color
- Friend referral rewards (2K coins + egg for both)
- "Playing with friends" buff (+5% dig speed)

### 12. Digging Crews (Clans)

- 2-10 player crews with shared dig site
- Crew XP + level milestones
- Crew leaderboard
- Cross-member item mailbox

## Differentiators vs Competition

| Us                             | Mining Simulator / Dig It |
| ------------------------------ | ------------------------- |
| Era-themed depth (story)       | Generic gems/ores         |
| Personal museum (social flex)  | No display system         |
| Shared dig sites (cooperative) | Isolated grinding         |
| Discovery feel                 | Numbers-go-up feel        |
| Historical artifact collection | Random loot only          |

## Key Metrics to Track

- D1 retention (target: 8%+)
- Session length (target: 19+ min)
- Payer conversion rate
- Depth reached distribution
- Gamepass conversion per prompt shown

## Revenue Targets

- Median Roblox dev: $1,440/year
- Mid-tier game (1K+ DAU): $5K-20K/year
- Enable Regional Pricing on all passes immediately
