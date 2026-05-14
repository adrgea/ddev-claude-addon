#!/usr/bin/env bash
#ddev-generated: If you want to edit and own this file, remove this line.
# Persists Claude Code auth/config across ddev restarts and reinstalls
# the native `claude` binary if it is missing from a freshly-recreated container.
#
# Runs on every web container start. The parent entrypoint *sources* this script
# under `set -e`, so we must never let an error propagate or the whole container
# fails its healthcheck. We turn errexit off locally and guard everything.
#
# Strategy:
#   - /mnt/ddev-global-cache/claude/<hostname>/ holds ~/.claude and ~/.claude.json
#   - Home-directory paths are symlinked into the persistent location
#   - On fresh containers (no ~/.local/bin/claude) the native installer is re-run
#   - PATH is added via /etc/profile.d (if writable) or the user's .profile,
#     so login shells find the binary without depending on ~/.bashrc

# Isolate from parent entrypoint's set -e — never crash the container.
(
    set +e
    set -o pipefail

    USER_NAME=$(stat -c '%U' /var/www/html)
    USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
    PERSIST="/mnt/ddev-global-cache/claude/$(cat /etc/hostname)"

    as_user() {
        if [ "$(id -u)" -eq 0 ]; then
            su - "$USER_NAME" -c "$1"
        else
            bash -lc "$1"
        fi
    }

    as_user "mkdir -p '$PERSIST/dot-claude' && touch '$PERSIST/claude.json'"

    # ~/.claude → $PERSIST/dot-claude
    if [ -L "$USER_HOME/.claude" ]; then
        :
    elif [ -d "$USER_HOME/.claude" ]; then
        if [ -z "$(ls -A "$PERSIST/dot-claude" 2>/dev/null)" ]; then
            as_user "cp -a '$USER_HOME/.claude/.' '$PERSIST/dot-claude/'"
        fi
        as_user "rm -rf '$USER_HOME/.claude' && ln -s '$PERSIST/dot-claude' '$USER_HOME/.claude'"
    else
        as_user "ln -sfn '$PERSIST/dot-claude' '$USER_HOME/.claude'"
    fi

    # ~/.claude.json → $PERSIST/claude.json
    if [ -L "$USER_HOME/.claude.json" ]; then
        :
    elif [ -f "$USER_HOME/.claude.json" ]; then
        if [ ! -s "$PERSIST/claude.json" ]; then
            as_user "cp -a '$USER_HOME/.claude.json' '$PERSIST/claude.json'"
        fi
        as_user "rm -f '$USER_HOME/.claude.json' && ln -s '$PERSIST/claude.json' '$USER_HOME/.claude.json'"
    else
        as_user "ln -sfn '$PERSIST/claude.json' '$USER_HOME/.claude.json'"
    fi

    # PATH: try /etc/profile.d (needs root), fall back to user's profile.
    PROFILE_D="/etc/profile.d/claude-path.sh"
    PATH_SNIPPET='# Added by ddev-claude-addon
if [ -d "$HOME/.local/bin" ] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi'

    wrote_profile_d=0
    if [ ! -f "$PROFILE_D" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            printf '%s\n' "$PATH_SNIPPET" > "$PROFILE_D" 2>/dev/null && chmod 0644 "$PROFILE_D" && wrote_profile_d=1
        elif command -v sudo >/dev/null && sudo -n true 2>/dev/null; then
            printf '%s\n' "$PATH_SNIPPET" | sudo tee "$PROFILE_D" >/dev/null 2>&1 && sudo chmod 0644 "$PROFILE_D" && wrote_profile_d=1
        fi
    else
        wrote_profile_d=1
    fi

    if [ "$wrote_profile_d" -ne 1 ]; then
        # Fall back: append to user's login profile. Pick the first that exists,
        # or default to .profile if none do.
        for candidate in "$USER_HOME/.bash_profile" "$USER_HOME/.profile"; do
            if [ -f "$candidate" ]; then
                target="$candidate"
                break
            fi
        done
        target="${target:-$USER_HOME/.profile}"
        if ! grep -q 'ddev-claude-addon' "$target" 2>/dev/null; then
            as_user "printf '\n%s\n' '$PATH_SNIPPET' >> '$target'"
        fi
    fi

    # Install native claude if the binary is missing (fresh container).
    # Background the installer so a slow/stalled download can't fail the healthcheck.
    if [ ! -x "$USER_HOME/.local/bin/claude" ]; then
        as_user "(curl -fsSL https://claude.ai/install.sh | bash) >/tmp/claude-install.log 2>&1 &"
    fi
) || true
