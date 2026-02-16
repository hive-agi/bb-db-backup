#!/bin/bash
# Periodic Datahike knowledge graph backup via nREPL
# Exports KG edges to EDN using the running JVM (no cold start, ~1s)
# Retains last 14 days, skips if recent backup exists
#
# Requirements:
#   - Running JVM with nREPL (Datahike loaded)
#   - bb (Babashka) with bencode dependency
#   - The target namespace must have an export function
#
# Environment variables:
#   KG_BACKUP_DIR     — backup directory (default: ~/backups/datahike)
#   NREPL_PORT        — nREPL port (default: 7888)
#   NREPL_HOST        — nREPL host (default: localhost)
#   RETENTION_DAYS    — how many days to keep (default: 14)
#   MIN_AGE_HOURS     — skip if latest backup younger than this (default: 8)
#   EXPORT_FN         — fully qualified export function (default: see below)
#
# The export function must accept a file path and write EDN to it:
#   (defn export-to-file! [path] ...)

set -e

BACKUP_DIR="${KG_BACKUP_DIR:-$HOME/backups/datahike}"
NREPL_PORT="${NREPL_PORT:-7888}"
NREPL_HOST="${NREPL_HOST:-localhost}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
MIN_AGE_HOURS="${MIN_AGE_HOURS:-8}"
EXPORT_FN="${EXPORT_FN:-hive-mcp.knowledge-graph.migration/export-to-file!}"

# Resolve bb path
BB="${BB:-$(command -v bb 2>/dev/null || echo /usr/local/bin/bb)}"
if [[ ! -x "$BB" ]]; then
    echo "Error: bb (Babashka) not found. Install: https://github.com/babashka/babashka" >&2
    exit 1
fi

# Resolve project root (for bb.edn classpath)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Check if recent backup exists
LATEST_BACKUP=$(find "$BACKUP_DIR" -name "datahike-*.edn" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
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

# Check if nREPL is reachable
if ! nc -z "$NREPL_HOST" "$NREPL_PORT" 2>/dev/null; then
    echo "Error: nREPL not reachable at ${NREPL_HOST}:${NREPL_PORT}" >&2
    exit 1
fi

BACKUP_FILE="$BACKUP_DIR/datahike-$(date +%Y%m%dT%H%M%S).edn"

# Export via nREPL using requiring-resolve (no compile-time dependency)
# Single-quoted to prevent bash history expansion of '!'
NREPL_CODE='(let [export-fn (requiring-resolve (quote '"${EXPORT_FN}"'))] (export-fn "'"${BACKUP_FILE}"'") "EXPORT-OK")'

NREPL_PORT="$NREPL_PORT" NREPL_CODE="$NREPL_CODE" "$BB" -cp "$PROJECT_DIR/src" -e '
(require (quote [bencode.core :as b]))
(import (quote [java.net Socket])
        (quote [java.io PushbackInputStream]))
(defn bytes->str [x] (if (bytes? x) (String. x) (str x)))
(defn has-done? [status]
  (and (sequential? status)
       (some #(= "done" (bytes->str %)) status)))
(let [port (Integer/parseInt (System/getenv "NREPL_PORT"))
      code (System/getenv "NREPL_CODE")
      sock (doto (Socket. "localhost" port) (.setSoTimeout 120000))
      in (PushbackInputStream. (.getInputStream sock))
      out (.getOutputStream sock)]
  (b/write-bencode out {"op" "eval" "code" code})
  (loop [result nil]
    (let [msg (try (b/read-bencode in) (catch Exception _ nil))]
      (if (nil? msg)
        (do (println (or result "No response")) (.close sock))
        (let [v (get msg "value")
              e (get msg "err")
              status (get msg "status")]
          (when e (binding [*out* *err*] (print (bytes->str e))))
          (if (has-done? status)
            (do (println (bytes->str (or v result "done"))) (.close sock))
            (recur (or v result))))))))
' || {
    echo "Error: nREPL eval failed" >&2
    exit 1
}

# Verify backup was created and has content
if [[ ! -f "$BACKUP_FILE" ]] || [[ ! -s "$BACKUP_FILE" ]]; then
    echo "Error: Backup file missing or empty: $BACKUP_FILE" >&2
    exit 1
fi

# Prune old backups
find "$BACKUP_DIR" -name "datahike-*.edn" -mtime +${RETENTION_DAYS} -delete

echo "Backup complete: $BACKUP_FILE"
ls -lh "$BACKUP_FILE"
