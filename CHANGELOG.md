# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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