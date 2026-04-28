# Deep Dig — Windows Dev Setup

This is the current setup. The old `SETUP.legacy.md` (paste-each-script) is obsolete — there are 30+ scripts now, and Rojo handles sync automatically.

## One-time install (~15 min)

1. **Git for Windows** — https://git-scm.com/download/win (use defaults)
2. **Node.js LTS** — https://nodejs.org/ (defaults; needed for Claude Code)
3. **Claude Code** — open PowerShell:
   ```powershell
   npm install -g @anthropic-ai/claude-code
   claude login
   ```
4. **Rojo** — pick one:
   - Easy: download `rojo-x.y.z-win64.zip` from https://github.com/rojo-rbx/rojo/releases, unzip, put `rojo.exe` somewhere on PATH (e.g. `C:\Tools\`)
   - Or via aftman: https://github.com/LPGhatguy/aftman
5. **Roblox Studio** — https://create.roblox.com → Start Creating → installs Studio
6. **Rojo Studio plugin** — in Studio: Plugins tab → Manage Plugins → search "Rojo" → install

## Clone the repo

```powershell
cd C:\Users\<you>\Documents
git clone https://github.com/vachsark/deep-dig.git
cd deep-dig
```

## Daily workflow

**Open three things:**

1. **Terminal #1 — Rojo serve** (live sync to Studio):

   ```powershell
   cd C:\Users\<you>\Documents\deep-dig
   rojo serve
   ```

   Leave running. It watches `src/` and pushes changes to Studio.

2. **Terminal #2 — Claude Code** (your dev session):

   ```powershell
   cd C:\Users\<you>\Documents\deep-dig
   claude
   ```

   Claude will auto-load `.claude/rules/*.md` and `CLAUDE.md` from this repo.

3. **Roblox Studio** — open any baseplate, click the Rojo plugin → **Connect**. The whole `src/` tree appears in ServerScriptService / ReplicatedStorage / StarterGui automatically. Press Play to test.

## Before you start each session

```powershell
git pull --rebase origin master
```

The Linux autonomous lane pushes commits roughly hourly. Always pull first or you'll fight rebases.

## After you finish each session

```powershell
git add -A
git commit -m "feat: <what you did>"
git push origin master
```

If push is rejected, the lane committed while you worked:

```powershell
git pull --rebase origin master
# resolve any conflicts (rare — lane and you should hit different files)
git push origin master
```

**Never `git push --force` to master.** It will overwrite the lane's commits.

## "It says nothing changed" troubleshooting

- **Studio shows old code?** Rojo plugin not connected. Click the plugin button → Connect. You should see `Connected to localhost:34872` in the output.
- **`git pull` shows nothing new?** Check `git log --oneline -5` — if recent commits exist locally that aren't pushed, the lane hasn't seen your work yet. Push.
- **Editing files in Studio doesn't reflect in repo?** That's expected — Rojo is one-way (filesystem → Studio). Edit the `.lua` files in your editor (or have Claude do it), and Rojo syncs them in.

## What lives where

- `src/ReplicatedStorage/*.lua` — modules + databases (ItemDatabase, EnemyDatabase, etc.)
- `src/ServerScriptService/*.server.lua` — game logic
- `src/StarterGui/*.client.lua` — client UI
- `default.project.json` — Rojo manifest (don't touch unless adding a new top-level Studio service)
- `.claude/rules/*` — auto-loaded into every Claude Code session in this repo

## What NOT to do on Windows

- Don't run the autonomous lane scripts (they're Linux-only, in TestVault)
- Don't edit `_collab/autoresearch/roblox-next-task.md` — that's the lane's brief, only the architect script writes it
- Don't commit Studio-only assets (uploaded models, audio, decals) — the lane can't ship them
