#!/bin/bash
# Install systemd user timers for daily database backups
#
# Usage: ./systemd/install.sh [--all|--datahike|--chroma|--datalevin]
#
# Creates systemd user units in ~/.config/systemd/user/
# and enables the timers to fire daily.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SYSTEMD_DIR="$HOME/.config/systemd/user"
SELECTED="${1:---all}"

mkdir -p "$SYSTEMD_DIR"

install_unit() {
    local name="$1"
    local script="$2"
    local desc="$3"
    local pre_check="${4:-}"

    echo "Installing ${name}..."

    # Service unit
    cat > "$SYSTEMD_DIR/${name}.service" << EOF
[Unit]
Description=${desc}
After=default.target

[Service]
Type=oneshot
${pre_check}ExecStart=${script}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

    # Timer unit
    cat > "$SYSTEMD_DIR/${name}.timer" << EOF
[Unit]
Description=Run ${name} daily

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

    # Enable and start timer
    systemctl --user daemon-reload
    systemctl --user enable "${name}.timer"
    systemctl --user start "${name}.timer"

    echo "  ✓ ${name}.timer enabled and started"
}

# Datahike backup (requires nREPL)
if [[ "$SELECTED" == "--all" || "$SELECTED" == "--datahike" ]]; then
    install_unit "backup-datahike" \
        "${PROJECT_DIR}/scripts/backup-datahike.sh" \
        "Datahike KG backup via nREPL (if >8h old)"
fi

# Chroma backup (requires Docker)
if [[ "$SELECTED" == "--all" || "$SELECTED" == "--chroma" ]]; then
    DOCKER_CHECK="ExecStartPre=/bin/bash -c 'for i in {1..24}; do docker ps --format \"{{.Names}}\" | grep -q \"chroma\" && exit 0; sleep 5; done; exit 1'\n"
    install_unit "backup-chroma" \
        "${PROJECT_DIR}/scripts/backup-chroma.sh" \
        "Chroma SQLite backup from Docker (if >8h old)" \
        "$DOCKER_CHECK"
fi

# Datalevin backup (filesystem only)
if [[ "$SELECTED" == "--all" || "$SELECTED" == "--datalevin" ]]; then
    install_unit "backup-datalevin" \
        "${PROJECT_DIR}/scripts/backup-datalevin.sh" \
        "Datalevin LMDB backup (if >8h old)"
fi

echo ""
echo "=== Installed timers ==="
systemctl --user list-timers --no-pager | grep -E "backup-(datahike|chroma|datalevin)" || echo "  (none matched)"
echo ""
echo "Check status:  systemctl --user status backup-datahike.timer"
echo "View logs:     journalctl --user -u backup-datahike.service"
echo "Run manually:  systemctl --user start backup-datahike.service"
