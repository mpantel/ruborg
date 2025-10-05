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
- ✅ **Well-tested** - Comprehensive test suite with RSpec
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

Ruborg supports two configuration formats: **single repository** (legacy) and **multi-repository** (recommended for complex setups).

### Single Repository Configuration

```yaml
# Repository path
repository: /path/to/borg/repository

# Paths to backup
backup_paths:
  - /home/user/documents
  - /home/user/projects

# Exclude patterns
exclude_patterns:
  - "*.tmp"
  - "*.log"

# Compression algorithm (lz4, zstd, zlib, lzma, none)
compression: lz4

# Encryption mode (repokey, keyfile, none)
encryption: repokey

# Passbolt integration (optional)
passbolt:
  resource_id: "your-passbolt-resource-uuid"

# Auto-initialize repository (optional, default: false)
auto_init: true

# Log file path (optional, default: ~/.ruborg/logs/ruborg.log)
log_file: /var/log/ruborg.log

# Borg environment options (optional)
borg_options:
  allow_relocated_repo: true  # Allow relocated repositories (default: true)
  allow_unencrypted_repo: true  # Allow unencrypted repositories (default: true)
```

### Multi-Repository Configuration

For managing multiple repositories with different sources:

```yaml
# Global settings (applied to all repositories unless overridden)
compression: lz4
encryption: repokey
auto_init: true
passbolt:
  resource_id: "global-passbolt-id"
borg_options:
  allow_relocated_repo: false
  allow_unencrypted_repo: false

# Multiple repositories
repositories:
  - name: documents
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
    path: /mnt/backup/databases
    # Repository-specific passbolt (overrides global)
    passbolt:
      resource_id: "db-specific-passbolt-id"
    sources:
      - name: mysql
        paths:
          - /var/lib/mysql/dumps
      - name: postgres
        paths:
          - /var/lib/postgresql/dumps
```

**Multi-repo benefits:**
- Organize backups by type (documents, databases, media)
- Different encryption keys per repository
- Multiple sources per repository
- Per-source exclude patterns
- Repository-specific settings override global ones

## Usage

### Initialize a Repository

```bash
# With passphrase
ruborg init /path/to/repository --passphrase "your-passphrase"

# With Passbolt
ruborg init /path/to/repository --passbolt-id "resource-uuid"
```

### Create a Backup

**Single repository:**
```bash
# Using default configuration (ruborg.yml)
ruborg backup

# Using custom configuration file
ruborg backup --config /path/to/config.yml

# With custom archive name
ruborg backup --name "my-backup-2025-10-04"

# Remove source files after successful backup
ruborg backup --remove-source
```

**Multi-repository:**
```bash
# Backup specific repository
ruborg backup --repository documents

# Backup all repositories
ruborg backup --all

# Backup specific repository with custom name
ruborg backup --repository databases --name "db-backup-2025-10-05"
```

### List Archives

```bash
ruborg list
```

### Restore from Archive

```bash
# Restore entire archive to current directory
ruborg restore archive-name

# Restore to specific directory
ruborg restore archive-name --destination /path/to/restore

# Restore a single file from archive
ruborg restore archive-name --path /path/to/file.txt --destination /new/location
```

### View Repository Information

```bash
ruborg info
```

## Logging

Ruborg automatically logs all operations with daily rotation. Log file location priority:

1. **CLI option** (highest priority): `--log /path/to/custom.log`
2. **Config file**: `log_file: /path/to/log.log`
3. **Default**: `~/.ruborg/logs/ruborg.log`

**Examples:**

```bash
# Use CLI option (overrides config)
ruborg backup --log /var/log/ruborg.log

# Or set in config file
log_file: /var/log/ruborg.log
```

**Logs include:**
- Operation start/completion timestamps
- Paths being backed up
- Archive names created
- Success and error messages
- Source file removal actions

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

Set `auto_init: true` in your configuration file to automatically initialize the repository on first use:

```yaml
repository: /path/to/borg/repository
auto_init: true
passbolt:
  resource_id: "your-passbolt-resource-uuid"
backup_paths:
  - /path/to/backup
```

When enabled, ruborg will automatically run `borg init` if the repository doesn't exist when you run `backup`, `list`, or `info` commands. The passphrase will be retrieved from Passbolt if configured.

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
| `backup` | Create a backup using config file | `--config`, `--name`, `--remove-source`, `--repository`, `--all`, `--log` |
| `list` | List all archives in repository | `--config`, `--repository`, `--log` |
| `restore ARCHIVE` | Restore files from archive | `--config`, `--destination`, `--path`, `--repository`, `--log` |
| `info` | Show repository information | `--config`, `--repository`, `--log` |

### Global Options

- `--config`: Path to configuration file (default: `ruborg.yml`)
- `--log`: Path to log file (overrides config, default: `~/.ruborg/logs/ruborg.log`)
- `--repository` / `-r`: Repository name (required for multi-repo configs)

### Multi-Repository Options

- `--all`: Backup all repositories (multi-repo config only)
- `--repository NAME`: Target specific repository by name

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