# Roblox / Luau Conventions — Auto-Injected

## Luau idioms (not Lua 5.1)

- Use `task.wait(n)` not `wait(n)` (deprecated, slower)
- Use `task.spawn(fn)` not `spawn(fn)`
- Use `task.delay(n, fn)` not `delay(n, fn)`
- Children created at runtime: always `Instance:WaitForChild("Name", timeoutSeconds)` rather than `Instance.Name` — the latter races with replication
- For RemoteEvents: `Remotes:WaitForChild("EventName", 5)` on the client side
- Tables for structured data; never expose raw indices to other scripts

## Globals

- **The only allowed global** is `_G.DeepDig_playerData` — a table keyed by `Player` instances, populated by `GameManager.server.lua`. See `ARCHITECTURE.md` for the shape.
- Other server scripts wait for it via `awaitPlayerData(player)` or by listening to the `PlayerDataReady` BindableEvent on `ServerEvents`.
- **Never introduce other globals.** Use ModuleScripts in ReplicatedStorage instead.

## File / script naming

- Server scripts: `Name.server.lua` (Rojo maps `.server.lua` → server `Script`)
- Client scripts: `Name.client.lua` (Rojo maps `.client.lua` → `LocalScript`)
- ModuleScripts: `Name.lua` (no suffix, returns a table)
- Match the existing `src/` layout — Rojo's `default.project.json` is set up for it

## Validation after every edit

```bash
luac -p path/to/file.lua    # syntax check (Lua 5.1 mostly compatible with Luau)
```

If `luac` flags something Luau-specific (typed params, `continue`, `+=`), it's a false positive — verify in Studio instead. But if it flags missing `end` or unclosed string, fix immediately.

`selene` and the Luau LSP are also available (see `selene.toml` and `roblox.yml`).

## Don't introduce Studio-only dependencies

The autonomous lane can ship code, not assets. So:

- ❌ No new MeshPart asset IDs that aren't already published under `vachsark`'s account
- ❌ No new Decal/Audio/Image IDs without authorization
- ❌ No code that requires manually-placed objects in the workspace (e.g. `workspace.SpecialPart`)
- ✅ Procedurally generated parts are fine
- ✅ Reusing existing asset IDs already in the codebase is fine

If a feature needs a new asset, leave a `TODO(asset):` comment and tell Vache.

## Game patterns to match

- **PlayerAdded race fix**: never `task.wait(N)` to wait for player data. Use `awaitPlayerData(player)` or listen to `PlayerDataReady`. (Pattern from commit `744f2b3`.)
- **Range checks on remotes**: server-side validate distance for `DigRequest` (60 studs) and `EnemyHitEvent` (8 studs). Don't trust client-claimed positions.
- **Cooldowns on remotes**: every player-triggered remote must have a per-player cooldown. Pattern in `EnemySystem.server.lua`.
- **Damage source = tool tier**: enemy damage taken = `Config.TOOLS[data.toolTier].damage`. Don't hardcode damage values per script.

## When in doubt

Read the existing implementation in `src/`. Match the style. The codebase is consistent — outliers stick out and break in autonomous-lane review.
