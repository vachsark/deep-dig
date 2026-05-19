# Next Task — 2026-05-19T09:33:00-07:00

## Goal
Make deeper tiers feel more distinct by tinting the player's local view as the HUD receives depth/tier updates.

## Why now
Depth progression already drives item tiers, enemy pressure, and resurface decisions, but the HUD view still feels visually flat across tiers. A lightweight client-only tone shift adds game feel without changing server economy or dig rules.

## Files to touch
- src/StarterGui/HudGui.client.lua: create/reuse a local `ColorCorrectionEffect` and tween it when `UpdateHUD` depth or tier fields change
- knowledge/vault-context.md: refresh generated project context

## Acceptance criteria
- [ ] Entering each configured tier can update the local `DeepDigDepthTone` color correction profile without adding remotes or server state.
- [ ] Repeated HUD updates in the same tier do not restart the tween.
- [ ] Initial data sync and later `UpdateHUD` payloads both apply the tone when depth or tier data is present.
- [ ] `luac -p src/StarterGui/HudGui.client.lua` passes from the Roblox project root.

## Implementation notes
- Keep the implementation local to `HudGui.client.lua`; existing `UpdateHUD` payloads already include `depth` and `tierName`.
- Use a closure or small table for depth-tone state so the large HUD script stays under stock Lua's top-level local-variable limit.
- Keep profiles subtle enough that rare-find lighting pulses and existing UI colors remain legible.
- Treat the crew bonus sound brief as a later separate task; do not mix it into this visual pass.

## Cycle budget
1
