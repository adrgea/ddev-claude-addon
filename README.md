# ddev-claude-addon

Adds Claude Code to a DDEV project's web container, with config persisted across
`ddev restart` / container rebuilds, and a `ddev claude` host command so you can
launch it without `ddev ssh`-ing first.

## Install

```bash
ddev add-on get adrgea/ddev-claude-addon
ddev restart
ddev claude
```

## What it does

- `web-entrypoint.d/claude-persist.sh` runs on every web container start. It
  symlinks `~/.claude` and `~/.claude.json` into `/mnt/ddev-global-cache/claude/`
  so authentication and settings survive rebuilds, and re-runs the official
  Claude installer if the binary is missing.
- `commands/host/claude` exposes `ddev claude [args...]` on the host, which
  `docker exec`s into the web container with the right user/UID and a fixed
  PATH so `claude` is always found.

## Uninstall

```bash
ddev add-on remove claude
ddev restart
```

Removes the two project files. Persisted config in
`/mnt/ddev-global-cache/claude/` is left alone so you can reinstall without
re-authenticating.

## Requirements

DDEV `>= v1.22.0`.
