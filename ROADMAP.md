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

### 1. FTUE Tuning (Day 1)

- Guarantee first item drop within 10 blocks
- Tune economy so first sell = enough for Tier 2 tool
- Add arrow guide: dig → sell → upgrade flow
- First gamepass prompt only after 4 minutes

### 2. Screen Effects for Rare Finds (Day 1-2)

- Full-screen gold flash on Legendary+ finds
- Screen shake on events
- Particle burst at finder's position (visible server-wide)
- Sound effects for dig, find, sell, upgrade

### 3. Daily Login Streak (Day 2-3)

- 7-day cycle: coins → coins → coins → fragments → coins → fragments → guaranteed Rare
- Streak counter in HUD
- Streak revival for 50 Robux

### 4. Gamepasses (Day 2-3)

- 2x Loot Value — 199 R$
- VIP Pass — 349 R$ (cosmetic + 50% coins)
- Lucky Digger — 499 R$ (+25% drop chance)

### 5. Depth Leaderboard (Day 3-4)

- In-world board showing top 5 on current server
- Global leaderboard via OrderedDataStore
- "New Personal Best!" notifications

## Phase 2: First Month (retention + monetization)

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
