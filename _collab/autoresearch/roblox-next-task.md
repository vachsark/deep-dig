# Next Task — 2026-04-25T00:49:03-07:00

## Goal
Ship the Phase 2 offline passive income core so returning players receive coin earnings based on tool tier with an 8-hour cap and an immediate welcome-back reward message.

## Why now
Phase 1 launch items are already landed, and offline earnings is the first unbuilt retention feature in Phase 2 that meaningfully rewards players for returning.

## Files to touch
- src/ServerScriptService/GameManager.server.lua: add persisted offline-income timestamps/fields to player data and keep them updated on join/leave save flow.
- src/ServerScriptService/OfflineIncome.server.lua: new server script that computes capped offline duration, grants coins from a per-tool-tier rate, updates HUD, and fires a "Welcome back" notification.

## Acceptance criteria
- [ ] A returning player with prior save data gets a one-time coin payout on join based on their current tool tier and elapsed offline time, capped at 8 hours.
- [ ] After payout, the HUD coin value updates immediately and the player sees a welcome-back notification that includes earned coins and offline duration.

## Implementation notes
- Do not award offline income on true first join (no prior timestamp); only start tracking from the first recorded session end.
- Reuse the existing `_G.DeepDig_playerData` access pattern used by `DailyStreak.server.lua`, and wait briefly on join so GameManager data is loaded.
- Keep payout deterministic and integer-safe: clamp elapsed seconds to `[0, 8h]`, compute with `math.floor`, and guard against negative/invalid clock deltas.
- Persist the "last seen" timestamp immediately after processing so reconnect spam cannot claim duplicate payouts.

## Cycle budget
1
