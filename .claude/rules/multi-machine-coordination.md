# Multi-Machine Coordination — Auto-Injected

This repo has multiple writers:

1. **Vache on Windows** (interactive Studio playtest sessions, via Claude Code)
2. **Vache on Linux** (occasional, also via Claude Code)
3. **The autonomous lane on Linux** — `roblox-architect` (every 4h) and `roblox-worker` (every 1h), authored as `Codex gpt-5.5`

All three push to `origin/master`. The protocol below keeps them from clobbering each other.

## Before any work (even read-only advice)

```bash
git pull --rebase origin master
```

If you skip this, you're working on stale state — your eventual push will fail or you'll write over a feature the lane just shipped.

## After committing

Push immediately:

```bash
git push origin master
```

Don't sit on local commits. The lane will rebase and push around you, leaving your work in a detached state.

## If push is rejected

```bash
git pull --rebase origin master
# resolve conflicts (should be rare — see "Reducing conflict surface" below)
git push origin master
```

**Never `git push --force` to master.** It will overwrite whatever the lane just pushed. If you genuinely need to rewrite history, ask Vache first.

## If the lane just committed (last 5 min)

Check before starting substantial work:

```bash
git log --oneline -3
```

If the most recent commit is from `Codex gpt-5.5` and within ~5 min, the lane is mid-cycle. Wait a minute, `git pull --rebase` again, then start. Avoids you and the lane racing on the same file.

## Reducing conflict surface

The lane mostly touches:

- `src/ServerScriptService/*.server.lua` (whatever the current `_collab/autoresearch/roblox-next-task.md` brief calls out)
- `src/ReplicatedStorage/*.lua` (databases the brief touches)
- `ROADMAP.md` (occasionally, to mark items shipped)

**To avoid collisions:**

- Read `_collab/autoresearch/roblox-next-task.md` first — it tells you what the lane is currently working on. Pick a different scope for your session.
- The lane will not touch `WINDOWS-SETUP.md`, `.claude/`, `ARCHITECTURE.md`, `SETUP.legacy.md`, `default.project.json`, `selene.toml`, `roblox.yml`. These are safe for human edits anytime.
- The lane also will not delete files (validation gate blocks rm-without-backup).

## If you hit a real conflict you can't resolve

Stop. Don't guess at merges in game logic — the lane and a human can both believe their version is correct, and a wrong merge ships broken state to live players.

```bash
git rebase --abort
```

Then surface to Vache: paste the conflicting file paths and ask which side wins.

## .claude-lock convention (for outer TestVault, not deep-dig)

The outer TestVault uses a `.claude-lock` file to coordinate concurrent agents. Deep-dig doesn't need it — `git pull --rebase` is enough because the lane commits atomically and pushes immediately.

If you ever see a `.claude-lock` file appear in deep-dig: another human session opened it, or something is wrong. Stop and check `git status` and `git log` before continuing.
