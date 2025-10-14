# Ruborg

> This gem is being developed with the assistance of Claude AI.

A friendly Ruby frontend for [Borg Backup](https://www.borgbackup.org/). Ruborg simplifies backup management by providing a YAML-based configuration system and seamless integration with Passbolt for encryption password management.

## Features

- 📦 **Repository Management** - Create and manage Borg backup repositories
- 💾 **Backup & Restore** - Easy backup creation and archive restoration
- 📝 **YAML Configuration** - Simple, readable configuration files
- 🔐 **Passbolt Integration** - Secure password management via Passbolt CLI
- 🎯 **Pattern Exclusions** - Flexible file exclusion patterns
- 🗜️ **Compression Options** - Support for multiple compression algorithms
- 🗂️ **Selective Restore** - Restore individual files or directories from archives
- 🧹 **Auto-cleanup** - Optionally remove source files after successful backup
- 📊 **Logging** - Comprehensive logging with daily rotation
- 🗄️ **Multi-Repository** - Manage multiple backup repositories with different sources
- 🔄 **Auto-initialization** - Automatically initialize repositories on first use
- ⏰ **Retention Policies** - Configure backup retention (hourly, daily, weekly, monthly, yearly)
- 🗑️ **Automatic Pruning** - Automatically remove old backups based on retention policies
- 📁 **Per-File Backup Mode** - NEW! Backup each file as a separate archive with metadata-based retention
- 🕒 **File Metadata Retention** - NEW! Prune based on file modification time, works even after files are deleted
- 📋 **Repository Descriptions** - Document each repository's purpose
- 📈 **Summary View** - Quick overview of all repositories and their configurations
- 🔧 **Custom Borg Path** - Support for custom Borg executable paths per repository
- 🏠 **Hostname Validation** - NEW! Restrict backups to specific hosts (global or per-repository)
- ✅ **Well-tested** - Comprehensive test suite with RSpec (297 examples, 0 failures)
- 🔒 **Security-focused** - Path validation, safe YAML loading, command injection protection

## Prerequisites

- Ruby >= 3.2.0
- [Borg Backup](https://www.borgbackup.org/) installed and available in PATH
- [Passbolt CLI](https://github.com/passbolt/go-passbolt-cli) (optional, for password management)

### Installing Borg Backup

**macOS:**
```bash
brew install borgbackup
```

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install borgbackup
```

**Verify installation:**
```bash
borg --version
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ruborg'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install ruborg
```

## Configuration

Create your configuration file from the example template:

```bash
cp ruborg.yml.example ruborg.yml
chmod 600 ruborg.yml  # Important: protect your configuration
```

Then edit `ruborg.yml` with your settings. Ruborg uses a multi-repository YAML configuration format:

```yaml
# Global settings (applied to all repositories unless overridden)
compression: lz4
encryption: repokey
auto_init: true
log_file: /var/log/ruborg.log

# Custom Borg executable path (optional)
# Use this if borg is not in PATH or you want to use a specific version
# borg_path: /usr/local/bin/borg

passbolt:
  resource_id: "global-passbolt-id"
borg_options:
  allow_relocated_repo: false
  allow_unencrypted_repo: false

# Global retention policy (can be overridden per repository)
retention:
  keep_hourly: 24    # Keep 24 hourly backups
  keep_daily: 7      # Keep 7 daily backups
  keep_weekly: 4     # Keep 4 weekly backups
  keep_monthly: 6    # Keep 6 monthly backups
  keep_yearly: 1     # Keep 1 yearly backup

# Multiple repositories
repositories:
  - name: documents
    description: "Personal and work documents backup"
    path: /mnt/backup/documents
    sources:
      - name: home-docs
        paths:
          - /home/user/documents
        exclude:
          - "*.tmp"
      - name: work-docs
        paths:
          - /home/user/work
        exclude:
          - "*.log"

  - name: databases
    description: "MySQL and PostgreSQL database dumps"
    path: /mnt/backup/databases
    hostname: dbserver.local  # Optional: repository-specific hostname override
    # Repository-specific passbolt (overrides global)
    passbolt:
      resource_id: "db-specific-passbolt-id"
    # Repository-specific retention (overrides global)
    retention:
      keep_daily: 14
      keep_weekly: 8
      keep_monthly: 12
    # Repository-specific borg executable path (optional)
    # borg_path: /opt/borg-2.0/bin/borg
    sources:
      - name: mysql
        paths:
          - /var/lib/mysql/dumps
      - name: postgres
        paths:
          - /var/lib/postgresql/dumps

  - name: media
    description: "Photos and videos archive"
    path: /mnt/backup/media
    # Override compression for large media files
    compression: lz4
    retention:
      keep_weekly: 2
      keep_monthly: 3
    sources:
      - name: photos
        paths:
          - /home/user/Pictures
```

**Configuration Features:**
- **Automatic Type Validation**: Configuration is validated on startup to catch type errors early
- **Validation Command**: Run `ruborg validate config` to check configuration files for errors
- **Descriptions**: Add `description` field to document each repository's purpose
- **Hostname Validation**: Optional `hostname` field to restrict backups to specific hosts (global or per-repository)
- **Source Deletion Safety**: `allow_remove_source` flag to explicitly enable `--remove-source` option (default: disabled)
- **Skip Hash Check**: Optional `skip_hash_check` flag to skip content hash verification for faster backups (per-file mode only)
- **Type-Safe Booleans**: Strict boolean validation prevents configuration errors (must use `true`/`false`, not strings)
- **Global Settings**: Hostname, compression, encryption, auto_init, allow_remove_source, skip_hash_check, log_file, borg_path, borg_options, and retention apply to all repositories
- **Per-Repository Overrides**: Any global setting can be overridden at the repository level (including hostname, allow_remove_source, skip_hash_check, and custom borg_path)
- **Custom Borg Path**: Specify a custom Borg executable path if borg is not in PATH or to use a specific version
- **Retention Policies**: Define how many backups to keep (hourly, daily, weekly, monthly, yearly)
- **Multiple Sources**: Each repository can have multiple backup sources with their own exclude patterns
- **Flexible Organization**: Organize backups by type (documents, databases, media) with different policies

## Configuration Validation

Ruborg automatically validates your configuration on startup. All commands check for type errors and structural issues before executing.

### Validate Configuration

Check your configuration file for errors:

```bash
ruborg validate config --config ruborg.yml
```

**Validation checks:**
- **Unknown configuration keys**: Detects typos and invalid keys at all levels (catches `auto_prun` vs `auto_prune`)
- **Boolean types**: Must be `true` or `false`, not strings like `'true'`
- **Retention policies**: Validates structure and values
  - Integer fields (keep_hourly, keep_daily, etc.) must be non-negative integers
  - Time-based fields (keep_within, keep_files_modified_within) must use format like "7d", "30d"
  - Rejects empty retention policies
  - Detects unknown retention keys
- **Passbolt configuration**: Validates resource_id is non-empty string
- **Retention mode**: Must be "standard" or "per_file"
- **Compression values**: Must be one of: lz4, zstd, zlib, lzma, none
- **Encryption modes**: Must be valid Borg encryption mode
- **Repository structure**: Required fields (name, path, sources)
- **Source structure**: Required fields (name, paths), validates exclude arrays
- **Borg options**: Validates allow_relocated_repo and allow_unencrypted_repo

**Example validation output:**

```
✓ Configuration is valid
  No type errors or warnings found
```

Or with errors:

```
❌ ERRORS FOUND (2):
  - global/auto_init: must be boolean (true or false), got String: "true"
  - test-repo/allow_remove_source: must be boolean (true or false), got Integer: 1

Configuration has errors that must be fixed.
```

## Logging

Ruborg v0.6.1 includes comprehensive logging to help you track backup operations, troubleshoot issues, and maintain audit trails. Logs are written to `~/.ruborg/logs/ruborg.log` by default, or to a custom location specified in your configuration.

### What Gets Logged

Ruborg logs operational information at various levels to help you monitor and debug backup operations:

#### Repository Operations
- Repository creation and initialization
- Repository path and encryption mode
- Per-file pruning operations (archive counts, file modification times)
- Archive deletion during pruning

#### Backup Operations
- Number of files found for backup (per-file mode)
- Individual file backup progress (per-file mode)
- Backup completion status
- Archive names (user-provided or auto-generated)

#### Restore Operations
- Archive extraction start (archive name, destination path)
- Specific paths being restored (if using `--path` option)
- Extraction completion status

#### Source File Deletion (when using `--remove-source`)
- Start of source file removal process
- Each file/directory being removed (with full resolved path)
- Warnings for non-existent or missing paths
- Errors when attempting to delete system directories (with path)
- Count of items successfully removed

#### Passbolt Integration
- Password retrieval start (includes Passbolt resource UUID)
- Password retrieval failures (includes resource UUID)

### What Is NOT Logged

To protect sensitive information, the following are **never logged**:

- ✅ **Passwords and passphrases** - Neither from command line nor from Passbolt
- ✅ **File contents** - Only file paths and metadata
- ✅ **Encryption keys** - Repository encryption passphrases are never written to logs
- ✅ **Passbolt passwords** - Only resource IDs (UUIDs) are logged, never the actual passwords retrieved

### Log Levels

- **INFO**: Normal operation events (backups, restores, deletions)
- **WARN**: Non-critical issues (missing paths, skipped operations)
- **ERROR**: Critical errors (system path deletion attempts, command failures)
- **DEBUG**: Detailed information for troubleshooting (requires DEBUG level configuration)

### Configuring Logging

```yaml
# Log to default location: ~/.ruborg/logs/ruborg.log
log_file: default

# OR custom log file path
log_file: /var/log/ruborg/backup.log

# OR disable file logging (stdout only)
log_file: stdout
```

You can also override the log file location using the `--log` command-line option:

```bash
ruborg backup --repository documents --log /tmp/debug.log
```

### Log Security Considerations

- **File Paths**: Logs contain file and directory paths being backed up. Secure your log files with appropriate permissions (recommended: `chmod 600` or `640`)
- **Passbolt Resource IDs**: UUID identifiers for Passbolt resources are logged. These are safe to log as they are unguessable and don't expose credentials, but logs should still be protected
- **Archive Names**: User-provided or auto-generated archive names are logged for audit purposes
- **System Paths**: When `--remove-source` attempts to delete system directories, the full path is logged in error messages for security auditing

### Best Practices

1. **Secure Log Files**: Set restrictive permissions on log files
   ```bash
   chmod 600 ~/.ruborg/logs/ruborg.log
   ```

2. **Log Rotation**: Configure log rotation to prevent logs from consuming excessive disk space
   ```bash
   # Example logrotate configuration
   /home/user/.ruborg/logs/ruborg.log {
       weekly
       rotate 4
       compress
       missingok
       notifempty
   }
   ```

3. **Monitoring**: Review logs regularly to detect:
   - Failed backup operations
   - Unauthorized deletion attempts
   - Passbolt password retrieval failures
   - Unexpected file paths

4. **Audit Trail**: Logs provide an audit trail for compliance purposes:
   - What was backed up and when
   - What was restored and where
   - What was deleted (with `--remove-source`)
   - Any errors or security-related events

## Usage

### Initialize a Repository

```bash
# With passphrase
ruborg init /path/to/repository --passphrase "your-passphrase"

# With Passbolt
ruborg init /path/to/repository --passbolt-id "resource-uuid"
```

### Create a Backup

```bash
# Backup specific repository
ruborg backup --repository documents

# Backup all repositories
ruborg backup --all

# Backup specific repository with custom name
ruborg backup --repository databases --name "db-backup-2025-10-05"

# Using custom configuration file
ruborg backup --config /path/to/config.yml --repository documents

# Remove source files after successful backup (requires allow_remove_source: true)
ruborg backup --repository documents --remove-source
```

**IMPORTANT: Source File Deletion Safety**

The `--remove-source` option is disabled by default for safety. To use it, you must explicitly enable it in your configuration:

```yaml
# Global setting - applies to all repositories
allow_remove_source: true

# OR per-repository setting
repositories:
  - name: temp-backups
    allow_remove_source: true  # Only for this repository
    ...
```

**⚠️ TYPE SAFETY WARNING:** The value MUST be a boolean `true`, not a string:

```yaml
# ✅ CORRECT - Boolean true
allow_remove_source: true

# ❌ WRONG - String 'true' (will be rejected)
allow_remove_source: 'true'
allow_remove_source: "true"

# ❌ WRONG - Other truthy values (will be rejected)
allow_remove_source: 1
allow_remove_source: yes
```

Ruborg uses strict type checking to prevent configuration errors. Only the boolean value `true` (unquoted) will enable source deletion. Any other value, including string `'true'` or `"true"`, will be rejected with a detailed error message showing the actual type received.

Without `allow_remove_source: true` configured, using `--remove-source` will result in an error:
```
Error: Cannot use --remove-source: 'allow_remove_source' must be true (boolean).
Current value: "true" (String). Set 'allow_remove_source: true' in configuration.
```

### List Archives

```bash
# List all archives for a specific repository
ruborg list --repository documents

# List files within a specific archive
ruborg list --repository documents --archive archive-name
```

### Restore from Archive

```bash
# Restore entire archive to current directory
ruborg restore archive-name --repository documents

# Restore to specific directory
ruborg restore archive-name --repository documents --destination /path/to/restore

# Restore a single file from archive
ruborg restore archive-name --repository documents --path /path/to/file.txt --destination /new/location
```

### View Repository Information

```bash
# Show summary of all configured repositories
ruborg info

# View detailed info for a specific repository
ruborg info --repository documents
```

The `info` command without `--repository` displays a summary showing:
- Global configuration settings
- All configured repositories with their descriptions
- Retention policies (global and per-repository overrides)
- Number of sources per repository

### Get File Metadata from Archives

```bash
# Get metadata from per-file archive (auto-detects single file)
ruborg metadata archive-name --repository documents

# Get metadata for specific file in standard archive
ruborg metadata archive-name --repository documents --file /path/to/file.txt
```

The `metadata` command displays detailed file information:
- File path
- Size (human-readable format)
- Modification time
- File permissions (mode)
- Owner and group
- File type

**Example output:**
```
═══════════════════════════════════════════════════════════════
  FILE METADATA
═══════════════════════════════════════════════════════════════

Archive: databases-backup.sql-8b4c26d05aae-2025-10-08_19-05-07
File: var/backups/database.sql
Size: 45.67 MB
Modified: 2025-10-08T19:05:07.123456
Mode: -rw-r--r--
User: postgres
Group: postgres
Type: regular file
```

### Validate Repository Compatibility

```bash
# Check specific repository compatibility with installed Borg version
ruborg validate repo --repository documents

# Check all repositories
ruborg validate repo --all

# Check with data integrity verification (slower)
ruborg validate repo --repository documents --verify-data
```

The `validate repo` command verifies:
- Installed Borg version
- Repository format version
- Compatibility between Borg and repository versions
- Optionally: Repository data integrity (with `--verify-data`)

**Example output:**
```
Borg version: 1.2.8

--- Validating repository: documents ---
  Repository version: 1
  ✓ Compatible with Borg 1.2.8

--- Validating repository: databases ---
  Repository version: 2
  ✗ INCOMPATIBLE with Borg 1.2.8
    Repository version 2 cannot be read by Borg 1.2.8
    Please upgrade Borg or migrate the repository
```

### Show Version

```bash
# Display ruborg version
ruborg version
```

## Passbolt Integration

Ruborg can retrieve encryption passphrases from Passbolt using the Passbolt CLI:

1. Install and configure [Passbolt CLI](https://github.com/passbolt/go-passbolt-cli)
2. Configure Passbolt CLI with your server credentials:
   ```bash
   passbolt configure --serverAddress https://server.address \
                      --userPrivateKeyFile /path/to/private.key \
                      --userPassword YOUR_PASSWORD
   ```
   Or set environment variables:
   ```bash
   export PASSBOLT_SERVER_ADDRESS=https://server.address
   export PASSBOLT_USER_PRIVATE_KEY_FILE=/path/to/private.key
   export PASSBOLT_USER_PASSWORD=YOUR_PASSWORD
   ```
3. Store your Borg repository passphrase in Passbolt
4. Add the resource ID to your `ruborg.yml`:

```yaml
passbolt:
  resource_id: "your-passbolt-resource-uuid"
```

Ruborg will automatically retrieve the passphrase when performing backup operations.

## Auto-initialization

Set `auto_init: true` in the global settings or per-repository to automatically initialize repositories on first use:

```yaml
auto_init: true
repositories:
  - name: documents
    path: /path/to/borg/repository
    sources:
      - name: main
        paths:
          - /path/to/backup
```

When enabled, ruborg will automatically run `borg init` if the repository doesn't exist when you run `backup`, `list`, or `info` commands. The passphrase will be retrieved from Passbolt if configured.

## Hostname Validation

Restrict backup operations to specific hosts using the optional `hostname` configuration key. This prevents accidental execution of backups on the wrong machine.

### Global Hostname

Apply hostname restriction to all repositories:

```yaml
# Global hostname - applies to all repositories
hostname: myserver.local

repositories:
  - name: documents
    path: /mnt/backup/documents
    sources:
      - name: main
        paths:
          - /home/user/documents
```

### Per-Repository Hostname

Override global hostname for specific repositories:

```yaml
# Global hostname for most repositories
hostname: mainserver.local

repositories:
  # Uses global hostname (mainserver.local)
  - name: documents
    path: /mnt/backup/documents
    sources:
      - name: main
        paths:
          - /home/user/documents

  # Override with repository-specific hostname
  - name: databases
    hostname: dbserver.local  # Only runs on dbserver.local
    path: /mnt/backup/databases
    sources:
      - name: mysql
        paths:
          - /var/lib/mysql/dumps
```

**How it works:**
- Before backup, list, restore, or check operations, Ruborg validates the system hostname
- If configured hostname doesn't match the current hostname, the operation fails with an error
- Repository-specific hostname takes precedence over global hostname
- If no hostname is configured, validation is skipped

**Example error:**
```
Error: Hostname mismatch: configuration is for 'dbserver.local' but current hostname is 'mainserver.local'
```

**Use cases:**
- **Multi-server environments**: Different servers backup to different repositories
- **Development vs Production**: Prevent production config from running on dev machines
- **Safety**: Avoid accidentally running wrong backups on shared configuration files

## Security Configuration

Ruborg provides configurable security options via `borg_options`:

```yaml
borg_options:
  # Control whether to allow access to relocated repositories
  # Set to false in production for enhanced security
  allow_relocated_repo: true  # default: true

  # Control whether to allow access to unencrypted repositories
  # Set to false to enforce encryption
  allow_unencrypted_repo: true  # default: true
```

**Security Features:**
- **Repository Path Validation**: Prevents creation in system directories (`/bin`, `/etc`, `/usr`, etc.)
- **Backup Path Validation**: Validates and normalizes all backup source paths
- **Archive Name Sanitization**: Automatically sanitizes custom archive names
- **Path Traversal Protection**: Prevents extraction to system directories
- **Symlink Protection**: Resolves and validates symlinks before deletion with `--remove-source`
- **Safe YAML Loading**: Uses `YAML.safe_load_file` to prevent code execution
- **Command Injection Protection**: Uses safe command execution methods
- **Log Path Validation**: Prevents writing logs to system directories

See [SECURITY.md](SECURITY.md) for detailed security information and best practices.

## Command Reference

| Command | Description | Options |
|---------|-------------|---------|
| `init REPOSITORY` | Initialize a new Borg repository | `--passphrase`, `--passbolt-id`, `--log` |
| `validate config` | Validate configuration file for type errors | `--config`, `--log` |
| `validate repo` | Validate repository compatibility and integrity | `--config`, `--repository`, `--all`, `--verify-data`, `--log` |
| `backup` | Create a backup using config file | `--config`, `--repository`, `--all`, `--name`, `--remove-source`, `--log` |
| `list` | List archives or files in repository | `--config`, `--repository`, `--archive`, `--log` |
| `restore ARCHIVE` | Restore files from archive | `--config`, `--repository`, `--destination`, `--path`, `--log` |
| `metadata ARCHIVE` | Get file metadata from archive | `--config`, `--repository`, `--file`, `--log` |
| `info` | Show repository information | `--config`, `--repository`, `--log` |
| `version` | Show ruborg version | None |

### Options

- `--config`: Path to configuration file (default: `ruborg.yml`)
- `--log`: Path to log file (overrides config, default: `~/.ruborg/logs/ruborg.log`)
- `--repository` / `-r`: Repository name (optional for info, required for backup/list/restore/validate repo unless --all)
- `--all`: Process all repositories (backup and validate repo commands)
- `--name`: Custom archive name (backup command only)
- `--remove-source`: Remove source files after successful backup (backup command only)
- `--destination`: Destination directory for restore (restore command only)
- `--path`: Specific file or directory to restore (restore command only)
- `--verify-data`: Run full data integrity check (validate repo command only, slower)

## Retention Policies

Retention policies define how many backups to keep. You can use **count-based rules**, **time-based rules**, or **both together** for maximum flexibility.

### Count-based Retention

Keep a specific number of backups for each time interval:

```yaml
retention:
  keep_hourly: 24    # Keep last 24 hourly backups
  keep_daily: 7      # Keep last 7 daily backups
  keep_weekly: 4     # Keep last 4 weekly backups
  keep_monthly: 6    # Keep last 6 monthly backups
  keep_yearly: 1     # Keep last 1 yearly backup
```

### Time-based Retention

Keep backups based on time periods:

```yaml
retention:
  keep_within: "7d"      # Keep ALL backups within last 7 days
  keep_last: "30d"       # Keep at least one backup from last 30 days
```

### Combining Time-based and Count-based Rules

**Yes, you can combine both types!** When you use both time-based and count-based rules together, they work **additively** - Borg keeps the **union** of all matching backups.

```yaml
retention:
  keep_within: "2d"      # Keep everything from last 2 days
  keep_daily: 7          # PLUS keep 7 daily backups (goes back ~7 days)
  keep_weekly: 4         # PLUS keep 4 weekly backups (goes back ~4 weeks)
  keep_monthly: 6        # PLUS keep 6 monthly backups (goes back ~6 months)
```

**How this works:** Borg will keep a backup if it matches **ANY** of these rules:
- Backup is within the last 2 days, OR
- Backup is one of the last 7 daily backups, OR
- Backup is one of the last 4 weekly backups, OR
- Backup is one of the last 6 monthly backups

**Practical example:**

```yaml
# Database backups - keep recent changes, long-term history
retention:
  keep_within: "1d"      # Everything from last 24 hours (frequent changes)
  keep_daily: 14         # Plus 14 days of daily backups (2 weeks)
  keep_weekly: 8         # Plus 8 weeks of weekly backups (2 months)
  keep_monthly: 12       # Plus 12 months of monthly backups (1 year)
  keep_yearly: 3         # Plus 3 years of yearly backups
```

This configuration provides:
- **Maximum detail** for recent backups (last 24 hours - every backup kept)
- **Daily granularity** for the last 2 weeks
- **Weekly granularity** for the last 2 months
- **Monthly granularity** for the last year
- **Yearly snapshots** for long-term compliance

**Time format:** Use suffixes like `d` (days), `w` (weeks), `m` (months), `y` (years). Examples: `7d`, `4w`, `6m`, `1y`

**Configuration notes:**
- Policies can be set globally and overridden per repository
- All fields are optional - use only what you need
- `keep_within`: Keeps **all** archives created within the specified time period
- `keep_last`: Ensures at least one backup from the last specified time period is kept
- **Rules are additive** - combining rules keeps MORE backups, not fewer
- Retention settings are displayed in the `ruborg info` summary

### Per-File Backup Mode with File Metadata Retention

**NEW:** Ruborg supports a per-file backup mode where each file is backed up as a separate archive. This enables intelligent retention based on **file modification time** rather than backup creation time.

**Per-Directory Retention (v0.8+):** Retention policies are now applied **independently per source directory**. Each `paths` entry gets its own retention quota, preventing one active directory from dominating retention across all sources.

**Use Case:** Keep backups of actively modified files while automatically pruning backups of files that haven't been modified recently - even after the source files are deleted.

```yaml
repositories:
  - name: project-files
    description: "Active project files with metadata-based retention"
    path: /mnt/backup/project-files
    retention_mode: per_file      # Enable per-file backup mode
    retention:
      # Prune based on file metadata (modification time) read from archives
      keep_files_modified_within: "30d"  # Keep files modified in last 30 days
      # Traditional retention also applies
      keep_daily: 7
    sources:
      - name: projects
        paths:
          - /home/user/projects
        exclude:
          - "*.tmp"
          - "*/.cache/*"
```

**How it works:**
- **Per-File Archives**: Each file is backed up as a separate Borg archive
- **Hash-Based Naming**: Archives are named `repo-filename-{hash}-{timestamp}` (hash uniquely identifies the file path)
- **Metadata Storage**: Archive comments store `path|||size|||hash` for comprehensive duplicate detection
- **Metadata Preservation**: Borg preserves all file metadata (mtime, size, permissions) in the archive
- **Paranoid Mode Duplicate Detection** (v0.7.1+): SHA256 content hashing detects file changes even when size and mtime are identical
- **Smart Skip**: Automatically skips unchanged files during backup (compares path, size, and content hash)
- **Version Suffixes**: Creates versioned archives (`-v2`, `-v3`) for archive name collisions, preventing data loss
- **Smart Pruning**: Retention reads file mtime directly from archives - works even after files are deleted

**File Metadata Retention Options:**
- `keep_files_modified_within`: Keep archives containing files modified within the specified time period
  - Reads mtime from inside the Borg archive
  - Works even if source files are deleted
  - Example: `"30d"` keeps files modified in the last 30 days

**Mixed Mode Example:**
```yaml
repositories:
  # Standard mode for full system backups
  - name: system
    path: /mnt/backup/system
    retention_mode: standard    # Default: one archive per backup run
    retention:
      keep_daily: 7
    sources:
      - name: etc
        paths:
          - /etc

  # Per-file mode for active development files
  - name: active-code
    path: /mnt/backup/code
    retention_mode: per_file    # One archive per file
    retention:
      keep_files_modified_within: "60d"
      keep_monthly: 12           # Plus monthly snapshots
    sources:
      - name: projects
        paths:
          - /home/user/dev
```

**Performance Note:** Per-file mode creates many archives (one per file). Borg handles this efficiently due to deduplication, but it's best suited for directories with hundreds to thousands of files rather than millions.

**Backup vs Retention:** The per-file `retention_mode` only affects how archives are created and pruned. Traditional backup commands still work normally - you can list, restore, and check per-file archives just like standard archives.

### Skip Hash Check for Faster Backups

**NEW:** In per-file backup mode, you can optionally skip content hash verification for faster duplicate detection:

```yaml
repositories:
  - name: project-files
    path: /mnt/backup/project-files
    retention_mode: per_file
    skip_hash_check: true    # Skip SHA256 content hash verification
    sources:
      - name: projects
        paths:
          - /home/user/projects
```

**How it works:**
- **Default (paranoid mode)**: Ruborg calculates SHA256 hash of file content to verify files haven't changed (even when size and mtime are identical)
- **With skip_hash_check: true**: Ruborg trusts file path, size, and modification time for duplicate detection (skips hash calculation)

**When to use:**
- ✅ **Large directories** with thousands of files where hash calculation is slow
- ✅ **Reliable filesystems** where modification time changes are trustworthy
- ✅ **Regular backups** where files are unlikely to be manually modified with `touch -t`

**When NOT to use:**
- ❌ **Security-critical data** where you want maximum verification
- ❌ **Untrusted sources** where files might be tampered with
- ❌ **Systems with unreliable mtime** (rare, but some network filesystems)

**Performance impact:**
```yaml
# Example: 10,000 unchanged files, average 50KB each
# With skip_hash_check: false (default) - ~30 seconds (read + hash all files)
# With skip_hash_check: true            - ~3 seconds  (read metadata only)
```

**Console output:**
```
# With skip_hash_check: true
[1/10000] Backing up: /home/user/file1.txt - Archive already exists (skipped hash check)
[2/10000] Backing up: /home/user/file2.txt - Archive already exists (skipped hash check)
...
✓ Per-file backup completed: 50 file(s) backed up, 9950 skipped (hash check skipped)

# With skip_hash_check: false (default)
[1/10000] Backing up: /home/user/file1.txt - Archive already exists (file unchanged)
[2/10000] Backing up: /home/user/file2.txt - Archive already exists (file unchanged)
...
✓ Per-file backup completed: 50 file(s) backed up, 9950 skipped (unchanged)
```

**Security note:** Even with `skip_hash_check: true`, files are still verified by path, size, and mtime. The only difference is skipping the SHA256 content hash verification, which catches rare edge cases like manual file tampering with preserved timestamps.

### Automatic Pruning

Enable **automatic pruning** to remove old backups after each backup operation:

```yaml
# Global configuration
auto_prune: true    # Enable automatic pruning for all repositories
retention:
  keep_daily: 7
  keep_weekly: 4
  keep_monthly: 6

repositories:
  - name: documents
    path: /mnt/backup/documents
    sources:
      - name: main
        paths:
          - /home/user/documents

  - name: databases
    path: /mnt/backup/databases
    auto_prune: true   # Override: enable pruning for this repository only
    retention:
      keep_daily: 14   # Override: use different retention policy
      keep_weekly: 8
      keep_monthly: 12
    sources:
      - name: mysql
        paths:
          - /var/lib/mysql/dumps
```

**How it works:**
- When `auto_prune: true` is set, Ruborg automatically runs `borg prune` after each successful backup
- Pruning removes old archives that don't match any retention rule
- If both global and repository-specific `auto_prune` are set, repository-specific takes precedence
- Requires a retention policy to be configured (otherwise pruning is skipped)
- Pruning statistics are displayed after completion

**Example output:**

```
--- Backing up repository: documents ---
✓ Backup created: documents-2025-10-06_12-30-45
  Pruning old backups...
  ✓ Pruning completed
```

**Manual pruning:**

If you prefer to prune manually or have `auto_prune: false`, run Borg's prune command directly:

```bash
# Example: Apply retention policy to a repository
BORG_PASSPHRASE="your-passphrase" borg prune \
  --keep-hourly=24 \
  --keep-daily=7 \
  --keep-weekly=4 \
  --keep-monthly=6 \
  --keep-yearly=1 \
  /path/to/repository
```

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `rake spec` to run the tests.

To install this gem onto your local machine, run:

```bash
bundle exec rake install
```

To release a new version, update the version number in `lib/ruborg/version.rb`, and then run:

```bash
bundle exec rake release
```

## Testing

Run the test suite:

```bash
# Run all tests
bundle exec rspec

# Run only unit tests (no Borg required)
bundle exec rspec --tag ~borg

# Run only integration tests (requires Borg)
bundle exec rspec --tag borg
```

The test suite includes:
- Config loading and validation
- Repository management (with actual Borg integration)
- Backup and restore operations
- Passbolt integration (mocked)
- CLI commands
- Logging functionality
- Comprehensive security tests (path validation, sanitization, etc.)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/mpantel/ruborg.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Acknowledgments

- [Borg Backup](https://www.borgbackup.org/) - The excellent backup tool this gem wraps
- [Passbolt](https://www.passbolt.com/) - Secure password management