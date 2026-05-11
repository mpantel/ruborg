# Per-File Backup Mode Guide

> **Addressing [issue #2](https://github.com/mpantel/ruborg/issues/2)** raised by Thomas Waldmann (Borg Backup maintainer): per-file mode is a special-purpose feature that must be used with care. This guide clarifies when it is appropriate and what limits apply.

## Overview

Per-file mode creates **one Borg archive per file** in each backup run. This enables independent versioning and retention per file, and per source directory (v0.8+).

**This mode is not a general-purpose backup strategy.** It is designed for a small, well-bounded set of files such as database dumps or a handful of configuration files.

## Key Differences: Per-File vs. Standard Mode

| Aspect | Standard Mode | Per-File Mode |
|--------|--------------|----------------|
| Archives created per run | 1 per repository | 1 per file |
| Archive count growth | Slow (bounded by retention) | Fast (files × runs) |
| Retention scope | Repository-wide | Per source directory |
| Best for | Full directory snapshots | Database dumps, select configs |
| Borg archive index load | Light | Medium-to-high |

## Borg Archive Limits

Borg Backup is designed to handle a **normal number of archives** — typically 10 to 10,000 per repository. Performance degrades significantly when archive counts grow into the tens or hundreds of thousands:

| Archive count | Status |
|---|---|
| < 1,000 | ✅ Negligible performance impact |
| 1,000 – 10,000 | ✅ Good performance, monitor growth |
| 10,000 – 50,000 | ⚠️ Slower `borg list`, `borg info`, and prune |
| > 100,000 | ❌ Borg will be slow; backup and prune may stall |

> **Important distinction:** Borg's deduplication handles large *data volumes* very well. The archive count limit is a separate concern — it relates to Borg's archive index, not storage. Per-file mode can create a large number of archives even when backing up small files.

## Estimating Your Archive Count

A rough formula for steady-state archive count:

```
archive_count ≈ files_per_source_dir × max(keep_daily, keep_weekly, keep_monthly)
                × number_of_source_dirs
```

**Example — database dumps (safe):**
```
- 5 database dump files in /var/backups/mysql
- Daily backups, retention: keep_daily: 30
- Archive count: 5 × 30 = 150 ✅
```

**Example — project directory (unsafe):**
```
- 2,000 source files in /home/user/projects
- Daily backups, retention: keep_daily: 30
- Archive count: 2,000 × 30 = 60,000 ⚠️ (approaching limit)
```

**Solution for the second case:** Use standard backup mode.

## When to Use Per-File Mode

✅ **Appropriate use cases:**
- Database dump files (e.g., `/var/backups/mysql/*.sql`) — typically a handful of files
- A small set of critical configuration files
- Any source directory with fewer than ~500 files and predictable growth

❌ **Inappropriate use cases:**
- User home directories or document collections
- Log file directories
- Source code repositories or large project trees
- Any source that would produce >> 10,000 total archives

## Checking Your Archive Count

Monitor the archive count in a repository regularly:

```bash
# Count all archives
borg list /path/to/repo | wc -l

# Thresholds:
#   < 1,000   — safe
#  10,000     — start monitoring
#  > 50,000   — switch to standard mode or split into multiple repos
```

## Retention Behavior Differences

### Standard Mode

```yaml
repositories:
  - name: documents
    path: /mnt/backup/documents
    retention:
      keep_daily: 14
```

One archive per backup run. Retention applies globally: at most 14 daily archives in the repository at any time.

### Per-File Mode

```yaml
repositories:
  - name: databases
    path: /mnt/backup/databases
    retention_mode: per_file
    retention:
      keep_daily: 14
    sources:
      - name: mysql
        paths:
          - /var/backups/mysql
      - name: postgres
        paths:
          - /var/backups/postgresql
```

One archive per file per run. **From v0.8+, retention is applied independently per source directory** — `/var/backups/mysql` gets its own 14-daily quota, and `/var/backups/postgresql` gets its own. See [PER_DIRECTORY_RETENTION.md](./PER_DIRECTORY_RETENTION.md) for implementation details.

### File Metadata Retention

Per-file mode also supports retention based on the file's own modification time (read from inside the archive), rather than the archive creation time:

```yaml
retention:
  keep_files_modified_within: "30d"  # Keep archives of files modified in last 30 days
```

This works even after source files are deleted.

## Safe Configuration Examples

### ✅ Good — small set of database dumps

```yaml
repositories:
  - name: databases
    description: "MySQL and PostgreSQL daily dumps"
    path: /mnt/backup/databases
    retention_mode: per_file
    auto_prune: true
    retention:
      keep_daily: 14
      keep_weekly: 4
      keep_monthly: 6
    sources:
      - name: mysql
        paths:
          - /var/backups/mysql      # ~3 dump files
      - name: postgres
        paths:
          - /var/backups/postgresql # ~2 dump files
```

Steady-state archives: ~5 files × ~24 max retention slots ≈ **~120 archives total** ✅

### ❌ Bad — large source directory

```yaml
repositories:
  - name: user-files
    path: /mnt/backup/user-files
    retention_mode: per_file       # Wrong choice for this source
    retention:
      keep_daily: 30
    sources:
      - name: documents
        paths:
          - /home/user/Documents   # 5,000 files
```

Steady-state archives: 5,000 × 30 = **150,000 archives** ❌

**Fix:** Switch to standard mode.

### ✅ Good — standard mode for large sources

```yaml
repositories:
  - name: user-files
    path: /mnt/backup/user-files
    retention:                     # No retention_mode → defaults to standard
      keep_daily: 30
      keep_weekly: 8
    sources:
      - name: documents
        paths:
          - /home/user/Documents   # 5,000 files — fine in standard mode
```

Steady-state archives: ~38 total ✅ (one per backup run, within retention window)

## Migration Between Modes

### From Standard to Per-File

1. Create a new repository with `retention_mode: per_file`
2. Keep the old repository for historical archives
3. Start new per-file backups in parallel
4. Retire the old repository when its retention expires

### From Per-File to Standard

1. Keep the existing per-file repository — do not delete it
2. Create a new repository without `retention_mode: per_file`
3. Run one full backup in standard mode
4. Switch your configuration to the new repository
5. Let the old per-file repository age out naturally

## Troubleshooting

### Slow `borg list` or `borg info`
- **Cause:** Too many archives (> 10,000)
- **Check:** `borg list /path/to/repo | wc -l`
- **Fix:** Reduce retention policy, split into multiple repositories, or switch to standard mode

### High CPU usage during pruning
- **Cause:** Pruning large numbers of archives
- **Fix:** Reduce `keep_*` values; consider `keep_files_modified_within` instead of count-based retention

### Archive count growing unexpectedly
- **Cause:** Source directory has more files than expected, or retention is too generous
- **Fix:** Count source files (`find /your/source -type f | wc -l`), then estimate the steady-state archive count; switch to standard mode if it will exceed 10,000

## FAQ

**Q: Can I mix per-file and standard backups in the same repository?**
A: No. `retention_mode` is a per-repository setting. Use separate repositories if you need both modes.

**Q: Does per-file mode use more disk space?**
A: Not necessarily. Borg deduplicates identical file content across archives, so if files don't change, the storage overhead is small. The concern is Borg's archive *index*, not storage volume.

**Q: What's the safe limit on files per source directory?**
A: Depends on your retention policy. As a guideline: `files × max_retention_count < 5,000` keeps you well within safe territory. For example, 100 files with `keep_daily: 30` = 3,000 archives — acceptable.

**Q: Can I use `skip_hash_check: true` to make per-file mode faster?**
A: Yes. See the [README](./README.md#skip-hash-check-for-faster-backups) for details. This does not affect archive count — it only speeds up duplicate detection.

## Resources

- [Borg Backup Documentation](https://borgbackup.readthedocs.io/)
- [Borg Internals — Archive format and index](https://borgbackup.readthedocs.io/en/stable/internals/data_structures.html)
- [Ruborg Per-Directory Retention](./PER_DIRECTORY_RETENTION.md)
- [GitHub issue #2 — Archive count concerns](https://github.com/mpantel/ruborg/issues/2)
