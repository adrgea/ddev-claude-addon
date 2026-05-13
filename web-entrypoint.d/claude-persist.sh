#!/usr/bin/env bash
# Persists Claude Code auth/config across ddev restarts and reinstalls
# the native `claude` binary if it is missing from a freshly-recreated container.
#
# Runs as root from .ddev/web-entrypoint.d on every web container start.
# Strategy:
#   - /mnt/ddev-global-cache/claude/<hostname>/ holds ~/.claude and ~/.claude.json
#   - Home-directory paths are symlinked into the persistent location
#   - On fresh containers (no ~/.local/bin/claude) the native installer is re-run
#   - PATH is exported via /etc/profile.d so every login shell (interactive or not)
#     finds the binary without depending on ~/.bashrc

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

# PATH: drop into /etc/profile.d so every login shell picks it up,
# without depending on Ubuntu's ~/.bashrc which returns early in non-interactive shells.
PROFILE_D="/etc/profile.d/claude-path.sh"
if [ ! -f "$PROFILE_D" ]; then
    cat > "$PROFILE_D" <<'EOF'
# Added by ddev-claude-addon
if [ -d "$HOME/.local/bin" ] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi
EOF
    chmod 0644 "$PROFILE_D"
fi

# Install native claude if the binary is missing (fresh container)
if [ ! -x "$USER_HOME/.local/bin/claude" ]; then
    as_user "curl -fsSL https://claude.ai/install.sh | bash" \
        || echo "[claude-persist] native installer failed; will retry next start"
fi
