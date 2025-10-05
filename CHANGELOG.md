# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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