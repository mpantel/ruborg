# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2025-10-08

### Added
- **Hostname Validation**: Optional `hostname` configuration key to restrict backup operations to specific hosts
  - Can be configured globally or per-repository
  - Repository-specific hostname overrides global setting
  - Validates system hostname before backup, list, restore, check operations
  - Prevents accidental execution of backups on wrong machines
  - Displayed in `info` command output
- Comprehensive test coverage for hostname validation (6 new test cases)
- Documentation for hostname feature in example config and README

### Changed
- `info` command now displays hostname when configured (global or per-repository)

## [0.4.0] - 2025-10-06

### Added
- Borg executable validation: verifies `borg_path` points to actual Borg binary
- bundler-audit integration for dependency vulnerability scanning
- RuboCop with rubocop-rspec for code quality enforcement
- Enhanced pruning logs showing retention mode (standard vs per-file)
- Comprehensive development workflow documentation in CLAUDE.md
- Example configuration file: `ruborg.yml.example`

### Security
- **CRITICAL**: Fixed remaining command injection vulnerabilities in repository.rb
  - Replaced backtick execution with Open3.capture3 in `list_archives_with_metadata`
  - Replaced backtick execution with Open3.capture3 in `get_file_mtime_from_archive`
  - Replaced backtick execution with Open3.capture2e in `execute_version_command`
- Added borg_path validation to prevent execution of arbitrary binaries
- Removed unused `env_to_cmd_prefix` helper method (no longer needed with Open3)
- Updated SECURITY.md with new security features and best practices
- Added config file permission requirements (chmod 600) to documentation
- Zero known vulnerabilities in dependencies (verified with bundler-audit)

### Changed
- All command execution now uses Open3 methods (no backticks anywhere)
- Pruning logs now include retention mode details
- Enhanced security documentation with detailed config file protection guidelines

## [0.3.1] - 2025-10-05

### Added
- `borg_options` configuration for controlling Borg environment variables
- Repository path validation to prevent creation in system directories
- Backup path validation and normalization
- Archive name sanitization (alphanumeric, dash, underscore, dot only)

### Changed
- Borg environment variables now configurable via `borg_options` (backward compatible)
- All backup paths are now normalized to absolute paths
- Custom archive names are automatically sanitized

### Security
- Fixed command injection vulnerability in Passbolt CLI execution (now uses Open3.capture3)
- Added path traversal protection for extract operations
- Implemented symlink resolution and system path protection for --remove-source
- Changed to YAML.safe_load_file to prevent arbitrary code execution
- Added log path validation to prevent writing to system directories
- Added repository path validation (prevents /bin, /etc, /usr, etc.)
- Added backup path validation (rejects empty/nil paths)
- Added archive name sanitization (prevents injection attacks)
- Made Borg environment options configurable for enhanced security
- Added SECURITY.md with comprehensive security guidelines and best practices
- Enhanced test coverage for all security features

## [0.3.0] - 2025-10-05

### Added
- Auto-initialization feature: Set `auto_init: true` in config to automatically initialize repositories on first use
- Multi-repository configuration support with per-repository sources
- `--repository` / `-r` option to target specific repository in multi-repo configs
- `--all` option to backup all repositories at once
- Repository-specific Passbolt integration (overrides global settings)
- Per-source exclude patterns in multi-repo configs
- BackupConfig wrapper class for multi-repo compatibility
- Automatic format detection (single vs multi-repo)
- Support for multiple backup sources per repository
- Global settings with per-repository overrides
- `log_file` configuration option to set log path in config file
- Log file priority: CLI option > config file > default

### Changed
- Config class now detects and handles both single-repo and multi-repo formats
- Backup command automatically routes to single or multi-repo implementation
- Archive naming includes repository name for multi-repo configs
- CLI now reads log_file from config if --log option not provided

## [0.2.0] - 2025-10-05

### Added
- `--remove-source` option to delete source files after successful backup
- Comprehensive logging system with daily rotation (default: `~/.ruborg/logs/ruborg.log`)
- Custom log file support via `--log` option for all commands
- `--path` option for restore command to extract single files/directories from archives
- Comprehensive RSpec test suite with mocked Passbolt and actual Borg integration tests
- Borg installation instructions for macOS and Ubuntu in README
- Support for environment variables to prevent interactive prompts (`BORG_RELOCATED_REPO_ACCESS_IS_OK`, etc.)
- Automatic destination directory creation for restore operations
- Test helpers and fixtures for easier testing

### Fixed
- Passbolt CLI command corrected from `passbolt get <id>` to `passbolt get resource <id>`
- Borg commands now properly redirect stdin to prevent interactive passphrase prompts
- Improved error handling and logging throughout the application

### Changed
- Refactored Passbolt class to use testable `execute_command` method
- Enhanced Repository and Backup classes to properly handle environment variables
- Improved CLI integration with better Passbolt mock support in tests

## [0.1.0] - 2025-10-04

### Added
- Initial gem structure
- Borg repository initialization and management
- Backup creation and restoration
- YAML configuration file support
- Passbolt CLI integration for password management
- Command-line interface with Thor
- Basic error handling