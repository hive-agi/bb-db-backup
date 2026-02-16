# bb-db-backup

Daily backup scripts for Clojure database backends, powered by [Babashka](https://babashka.org/).

Supports **Datahike**, **Datalevin**, and **Chroma** vector database — the storage backends commonly used in Clojure AI/LLM applications.

## Features

- **Hot Datahike export** — exports EDN via nREPL on a running JVM (~1s, no cold start)
- **Chroma SQLite backup** — copies SQLite from Docker container
- **Datalevin LMDB backup** — tar.gz of the LMDB directory (crash-consistent)
- **Freshness checks** — skips if latest backup is < N hours old
- **Automatic retention** — prunes backups older than N days
- **Systemd timers** — one-command install for daily scheduling
- **Reusable bb nREPL client** — standalone bencode-based nREPL eval tool

## Quick Start

```bash
# Clone
git clone https://github.com/hive-agi/bb-db-backup.git
cd bb-db-backup

# List available tasks
bb tasks

# Run a backup manually
bb backup-datahike    # Datahike via nREPL
bb backup-chroma      # Chroma from Docker
bb backup-datalevin   # Datalevin LMDB

# Install daily systemd timers
bb install-systemd

# List recent backups
bb list-backups
```

## Scripts

| Script | Backend | Method | Default Dir |
|--------|---------|--------|-------------|
| `backup-datahike.sh` | Datahike | nREPL eval → EDN file | `~/backups/datahike/` |
| `backup-chroma.sh` | Chroma | `docker cp` SQLite | `~/backups/chroma/` |
| `backup-datalevin.sh` | Datalevin | `tar.gz` of LMDB dir | `~/backups/datalevin/` |
| `restore-datalevin.sh` | Datalevin | Extract tar.gz | project data dir |

## bb nREPL Client

A standalone tool for evaluating Clojure code on a running nREPL server — useful beyond backups:

```bash
# Direct eval
bb src/bb_backup/nrepl_client.bb --port 7888 --code '(+ 1 2)'

# Via bb task
bb nrepl-eval '(System/getProperty "java.version")'

# Pipe from stdin
echo '(count (keys (ns-publics (quote clojure.core))))' | \
  bb src/bb_backup/nrepl_client.bb --port 7888
```

Uses bencode protocol for raw nREPL communication. No Clojure startup — talks directly to the running JVM.

## Configuration

All scripts are configured via environment variables:

### Datahike (`backup-datahike.sh`)

| Variable | Default | Description |
|----------|---------|-------------|
| `KG_BACKUP_DIR` | `~/backups/datahike` | Backup output directory |
| `NREPL_PORT` | `7888` | nREPL server port |
| `NREPL_HOST` | `localhost` | nREPL server host |
| `EXPORT_FN` | `hive-mcp...export-to-file!` | Fully qualified export function |
| `RETENTION_DAYS` | `14` | Days to retain backups |
| `MIN_AGE_HOURS` | `8` | Skip if latest backup younger |

The `EXPORT_FN` must accept a file path and write EDN:

```clojure
(defn export-to-file! [path]
  ;; Write your database content to path as EDN
  ...)
```

### Chroma (`backup-chroma.sh`)

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_DIR` | `~/backups/chroma` | Backup output directory |
| `CHROMA_CONTAINER` | `chroma` | Docker container name |
| `CHROMA_DB_PATH` | `/data/chroma.sqlite3` | Path inside container |
| `RETENTION_DAYS` | `7` | Days to retain backups |
| `MIN_AGE_HOURS` | `8` | Skip if latest backup younger |

### Datalevin (`backup-datalevin.sh`)

| Variable | Default | Description |
|----------|---------|-------------|
| `DATALEVIN_DIR` | auto-detect | Path to Datalevin LMDB data |
| `BACKUP_DIR` | `~/backups/datalevin` | Backup output directory |
| `RETENTION_DAYS` | `7` | Days to retain backups |
| `MIN_AGE_HOURS` | `8` | Skip if latest backup younger |

## Systemd Timers

Install daily backup timers:

```bash
# Install all
bash systemd/install.sh --all

# Install specific
bash systemd/install.sh --datahike
bash systemd/install.sh --chroma
bash systemd/install.sh --datalevin
```

Check status:

```bash
systemctl --user list-timers | grep backup
journalctl --user -u backup-datahike.service --since today
```

## Requirements

- [Babashka](https://babashka.org/) (bb) — for nREPL client and tasks
- Docker — for Chroma backup
- `nc` (netcat) — for nREPL port check
- A running nREPL server — for Datahike backup

## License

EPL-2.0 — same as Clojure.
