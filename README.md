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
- ✅ **Well-tested** - Comprehensive test suite with RSpec

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

Create a `ruborg.yml` configuration file:

```yaml
# Repository path
repository: /path/to/borg/repository

# Paths to backup
backup_paths:
  - /home/user/documents
  - /home/user/projects
  - /etc

# Exclude patterns
exclude_patterns:
  - "*.tmp"
  - "*.log"
  - "*/.cache/*"
  - "*/node_modules/*"
  - "*/.git/*"

# Compression algorithm (lz4, zstd, zlib, lzma, none)
compression: lz4

# Encryption mode (repokey, keyfile, none)
encryption: repokey

# Passbolt integration (optional)
passbolt:
  resource_id: "your-passbolt-resource-uuid"
```

See `ruborg.yml.example` for a complete configuration template.

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
# Using default configuration (ruborg.yml)
ruborg backup

# Using custom configuration file
ruborg backup --config /path/to/config.yml

# With custom archive name
ruborg backup --name "my-backup-2025-10-04"

# Remove source files after successful backup
ruborg backup --remove-source
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

Ruborg automatically logs all operations to `~/.ruborg/logs/ruborg.log` with daily rotation. You can specify a custom log file:

```bash
ruborg backup --log /path/to/custom.log
```

Logs include:
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

## Command Reference

| Command | Description | Options |
|---------|-------------|---------|
| `init REPOSITORY` | Initialize a new Borg repository | `--passphrase`, `--passbolt-id`, `--log` |
| `backup` | Create a backup using config file | `--config`, `--name`, `--remove-source`, `--log` |
| `list` | List all archives in repository | `--config`, `--log` |
| `restore ARCHIVE` | Restore files from archive | `--config`, `--destination`, `--path`, `--log` |
| `info` | Show repository information | `--config`, `--log` |

### Global Options

- `--config`: Path to configuration file (default: `ruborg.yml`)
- `--log`: Path to log file (default: `~/.ruborg/logs/ruborg.log`)

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

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/mpantel/ruborg.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Acknowledgments

- [Borg Backup](https://www.borgbackup.org/) - The excellent backup tool this gem wraps
- [Passbolt](https://www.passbolt.com/) - Secure password management