# Autonomous Lane Context — Auto-Injected

There's a background process on Vache's Linux box that ships code to this repo while you're not looking. Knowing how it behaves prevents both surprise and collision.

## What it is

Two heartbeat-scheduled scripts in TestVault (`_scripts/heartbeat-collectors/`):

| Script                | Cadence  | Role                                                                               |
| --------------------- | -------- | ---------------------------------------------------------------------------------- |
| `roblox-architect.sh` | every 4h | Reads ROADMAP.md + recent commits, picks the next concrete task, writes a brief    |
| `roblox-worker.sh`    | every 1h | Reads the brief, implements it, runs `luac -p`, commits, pushes to `origin/master` |

Both run via Codex CLI on `gpt-5.5` (high reasoning effort). Commits are authored:

```
Co-Authored-By: Codex gpt-5.5 <noreply@openai.com>
```

So `git log --author="Codex"` shows everything the lane shipped.

## Where the brief lives

`_collab/autoresearch/roblox-next-task.md` — current scope, files to touch, acceptance criteria, cycle budget.

**Read this at the start of any session.** It tells you what the lane is about to work on, so you can pick a non-overlapping scope. If the brief targets `src/ServerScriptService/EnemySystem.server.lua` and you also want to touch enemy code, either:

- Pick a different feature, or
- Wait for the lane's next cycle to finish (check `git log -1 --format="%ai %s"` — if the last commit is fresh and matches the brief, lane is done; if not, it's mid-cycle)

## What the lane will and won't do

| Will                                                     | Won't                                                     |
| -------------------------------------------------------- | --------------------------------------------------------- |
| Add features from ROADMAP.md and the current brief       | Touch `WINDOWS-SETUP.md`, `.claude/`, `ARCHITECTURE.md`   |
| Modify `src/*.lua` files                                 | Push to a branch other than `master`                      |
| Add new files in `src/`                                  | Force-push                                                |
| Update `_collab/autoresearch/roblox-next-task.md`        | Delete files (validation gate blocks rm-without-backup)   |
| Update `knowledge/vault-context.md` with state snapshots | Introduce new asset IDs or Studio-only dependencies       |
| Mark ROADMAP.md items as shipped                         | Touch `default.project.json`, `selene.toml`, `roblox.yml` |
| `git push --rebase` if a push is rejected                | Write to GitHub from any account other than vachsark      |

## Style match

When you write code in this repo, match the lane's style so commits read consistently:

- Short conventional-commit subjects: `feat(enemies): add Hollow King miniboss spawn` / `fix(dig): resurface enemies safely on death`
- Body: 2-4 sentences max, focused on what shipped not why-the-task-mattered
- One feature per commit when possible
- Always include the Co-Authored-By trailer (use your own attribution, not Codex's)

## When the lane is wrong

The lane is autonomous, not omniscient. If you find lane-shipped code that's broken, over-engineered, or off-spec:

1. Fix it directly — don't try to "tell the lane" via the brief
2. Commit + push the fix
3. If the broken pattern will recur, add a rule to `.claude/rules/roblox-conventions.md` so the lane (which reads this on every cycle) avoids it next time

## Knowing what the lane just did

```bash
git log --author="Codex" --oneline -10
```

Or check the autoresearch state directly — `_collab/autoresearch/` shows recent briefs and what was shipped against them.
