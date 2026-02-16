#!/bin/bash
# Periodic Datalevin (LMDB) backup
# Copies the LMDB directory as tar.gz, retains last N days
# Skips if latest backup is less than MIN_AGE_HOURS old
#
# LMDB note: LMDB is crash-consistent and safe to copy while running,
# but scheduling at off-hours (e.g., 3am) is still recommended.
#
# Requirements:
#   - Datalevin data directory accessible on filesystem
#
# Environment variables:
#   DATALEVIN_DIR       — path to datalevin data (default: auto-detect from project)
#   BACKUP_DIR          — backup directory (default: ~/backups/datalevin)
#   RETENTION_DAYS      — how many days to keep (default: 7)
#   MIN_AGE_HOURS       — skip if latest backup younger than this (default: 8)

set -e

# Auto-detect datalevin dir from project structure if not set
if [[ -z "$DATALEVIN_DIR" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
    # Check common locations
    for candidate in "$PROJECT_DIR/data/kg/datalevin" "$PROJECT_DIR/data/datalevin"; do
        if [[ -d "$candidate" ]]; then
            DATALEVIN_DIR="$candidate"
            break
        fi
    done
fi

if [[ -z "$DATALEVIN_DIR" ]]; then
    echo "Error: DATALEVIN_DIR not set and not found in project structure" >&2
    echo "  Set DATALEVIN_DIR=/path/to/datalevin/data" >&2
    exit 1
fi

BACKUP_DIR="${BACKUP_DIR:-$HOME/backups/datalevin}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
MIN_AGE_HOURS="${MIN_AGE_HOURS:-8}"

# Create backup directory if needed
mkdir -p "$BACKUP_DIR"

# Check if source directory exists and is non-empty
if [[ ! -d "$DATALEVIN_DIR" ]]; then
    echo "Error: Datalevin directory not found: $DATALEVIN_DIR" >&2
    exit 1
fi

if [[ -z "$(ls -A "$DATALEVIN_DIR" 2>/dev/null)" ]]; then
    echo "Warning: Datalevin directory is empty: $DATALEVIN_DIR"
    exit 0
fi

# Check if recent backup exists (skip if less than MIN_AGE_HOURS old)
LATEST_BACKUP=$(find "$BACKUP_DIR" -name "datalevin-*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
if [[ -n "$LATEST_BACKUP" ]]; then
    BACKUP_AGE_SECONDS=$(( $(date +%s) - $(stat -c %Y "$LATEST_BACKUP") ))
    MIN_AGE_SECONDS=$(( MIN_AGE_HOURS * 3600 ))
    if [[ $BACKUP_AGE_SECONDS -lt $MIN_AGE_SECONDS ]]; then
        HOURS_OLD=$(( BACKUP_AGE_SECONDS / 3600 ))
        echo "Skipping: Latest backup is ${HOURS_OLD}h old (< ${MIN_AGE_HOURS}h threshold)"
        echo "  $LATEST_BACKUP"
        exit 0
    fi
fi

# Create timestamped backup
BACKUP_FILE="$BACKUP_DIR/datalevin-$(date +%Y%m%d-%H%M).tar.gz"
tar czf "$BACKUP_FILE" -C "$(dirname "$DATALEVIN_DIR")" "$(basename "$DATALEVIN_DIR")"

# Prune backups older than retention period
find "$BACKUP_DIR" -name "datalevin-*.tar.gz" -mtime +${RETENTION_DAYS} -delete

echo "Backup complete: $BACKUP_FILE"
ls -lh "$BACKUP_FILE"
