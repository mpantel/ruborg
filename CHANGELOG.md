# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.8.1] - 2025-10-09

### Added
- **Per-Directory Retention**: Retention policies now apply independently to each source directory in per-file backup mode
  - Each `paths` entry in repository sources gets its own retention quota
  - Prevents one active directory from dominating retention across all sources
  - Example: `keep_daily: 14` keeps 14 archives per source directory, not 14 total
  - Works with both `keep_files_modified_within` and standard retention policies (`keep_daily`, `keep_weekly`, etc.)
  - Legacy archives (without source_dir metadata) grouped separately for backward compatibility
- **Enhanced Archive Metadata**: Archive comments now include source directory
  - New format: `path|||size|||hash|||source_dir` (4-field format)
  - Backward compatible with all previous formats (3-field, 2-field, plain path)
  - Enables accurate per-directory grouping and retention
- **Comprehensive Test Suite**: Added 6 new per-directory retention tests (27 total examples, 0 failures)
  - Independent retention per source directory
  - Separate retention quotas with `keep_daily`
  - Archive metadata validation
  - Legacy archive grouping
  - Mixed format pruning
  - Per-directory `keep_files_modified_within`

### Changed
- **File Collection Tracking**: Files now tracked with both path and originating source directory
  - Modified `collect_files_from_paths` to return `{path:, source_dir:}` hash format
  - Source directory captured from expanded backup paths
  - Used for per-directory retention grouping during pruning
- **Archive Grouping**: Per-file archives grouped by source directory during pruning
  - New method: `get_archives_grouped_by_source_dir` (lib/ruborg/repository.rb:281-336)
  - Queries archive metadata to extract source directory
  - Returns hash: `{"/path/to/source" => [archives]}`
  - Handles legacy archives gracefully (empty source_dir)
- **Pruning Logic**: Per-file pruning now processes each directory independently
  - Method: `prune_per_file_archives` (lib/ruborg/repository.rb:163-223)
  - Applies retention policy separately to each source directory group
  - Logs per-directory pruning statistics
  - Falls back to standard pruning when `keep_files_modified_within` not specified

### Technical Details
- Per-directory retention queries archive metadata once per pruning operation
- One `borg info` call per archive to read metadata (noted in documentation as potential optimization)
- Backward compatibility: Archives without `source_dir` default to empty string and group as "legacy"
- No migration required: Old archives naturally age out, new archives have proper metadata
- Implementation documented in `PER_DIRECTORY_RETENTION.md`

### Security
- **Security Audit: PASS** ✓
  - No HIGH or MEDIUM severity issues identified
  - 1 LOW severity information disclosure (minor log message, acceptable)
  - All command execution uses safe array syntax (`Open3.capture3`)
  - Path validation maintained for all operations
  - Safe JSON parsing with error handling
  - No code evaluation or unsafe deserialization
  - Backward-compatible metadata parsing with safe defaults
  - Sensitive data (passphrases) kept in environment variables only

## [0.8.0] - 2025-10-09

### Removed
- **chattr/lsattr Functionality**: Completely removed Linux immutable attribute handling
  - The feature caused issues with network filesystems (CIFS/SMB, NFS) that don't support chattr
  - Users with truly immutable files should remove the attribute manually before using `--remove-source`
  - Simplifies code and eliminates filesystem compatibility issues
  - `--remove-source` now relies on standard file permissions only

### Changed
- File deletion now uses standard Ruby FileUtils methods without chattr checks
- Improved compatibility with all filesystem types (local, network, cloud)

## [0.7.6] - 2025-10-09

### Fixed
- **Filesystem Compatibility**: Gracefully handle filesystems that don't support chattr operations
  - Network filesystems (NFS, CIFS/SMB) and non-Linux filesystems (NTFS, FAT, exFAT) often don't support Linux file attributes
  - When chattr fails with "Operation not supported", log warning and continue with deletion
  - Allows `--remove-source` to work on network shares and external drives
  - Fixes error: "Cannot remove immutable file: ... Error: chattr: Operation not supported"

### Technical Details
- Detects "Operation not supported" error from chattr command (lib/ruborg/backup.rb:394)
- Logs informative warning about filesystem limitations
- Continues with file deletion (no longer raises error)
- Test coverage: Added comprehensive test for unsupported filesystem scenario

## [0.7.5] - 2025-10-09

### Added
- **Automatic Immutable Attribute Removal**: Ruborg now automatically detects and removes Linux immutable flags (`chattr +i`) when deleting files with `--remove-source`
  - Checks files with `lsattr` before deletion
  - Removes immutable flag with `chattr -i` if present
  - Works for both single files (per-file mode) and directories (standard mode)
  - Gracefully handles systems without lsattr/chattr (macOS, etc.)
  - Logs all immutable attribute operations for audit trail

### Technical Details
- Per-file mode: Checks each file individually before deletion (lib/ruborg/backup.rb:365)
- Standard mode: Recursively removes immutable from all files in directory (lib/ruborg/backup.rb:400-414)
- Linux-only feature - silently skips on other platforms
- Raises error if chattr command fails with proper error context
- Immutable flag detection uses precise parsing of lsattr flags field (lib/ruborg/backup.rb:386-387)
- Test coverage: 6 comprehensive specs covering all immutable file scenarios

## [0.7.4] - 2025-10-09

### Fixed
- **Passbolt Error Reporting**: Enhanced error handling for Passbolt CLI failures
  - Now captures and logs stderr from Passbolt CLI commands
  - Error messages include actual Passbolt CLI output for easier debugging
  - Improved error logging with detailed failure context

### Changed
- **Passbolt Environment Variables**: Passbolt env vars now explicitly passed to subprocess
  - Preserves `PASSBOLT_SERVER_ADDRESS`, `PASSBOLT_USER_PRIVATE_KEY_FILE`, `PASSBOLT_USER_PASSWORD`
  - Also preserves `PASSBOLT_GPG_HOME` and `PASSBOLT_CONFIG`
  - Ensures Passbolt CLI has access to required configuration when run by Ruborg

## [0.7.3] - 2025-10-09

### Changed
- **Smart Remove-Source for Skipped Files**: Skipped files (unchanged, already backed up) are now deleted when `--remove-source` is used
  - Previously: Only newly backed-up files were deleted, skipped files remained
  - Now: Both backed-up AND skipped files are deleted (they're all safely backed up)
  - Rationale: If a file is skipped because it's already in an archive (verified by hash), it's safe to delete
  - Makes `--remove-source` behavior consistent: "delete everything that's safely backed up"

### Technical Details
- Per-file mode verifies files are safely backed up before skipping (path + size + SHA256 hash match)
- Skipped files are deleted immediately after verification (lib/ruborg/backup.rb:102)
- Test updated to verify skipped files are deleted (spec/ruborg/per_file_backup_spec.rb:518)

## [0.7.2] - 2025-10-09

### Fixed
- **Per-File Remove Source Behavior**: Files are now deleted immediately after each successful backup in per-file mode
  - Previously deleted entire source paths at the end (dangerous - could delete unchanged files)
  - Now deletes only successfully backed-up files, one at a time
  - Skipped files (unchanged) are never deleted
  - Matches the per-file philosophy: individual file handling throughout the backup process

### Added
- **Test Coverage**: Added 2 new RSpec tests verifying per-file remove-source behavior
  - Tests immediate file deletion after backup
  - Tests that skipped files are not deleted

## [0.7.1] - 2025-10-08

### Added
- **Paranoid Mode Duplicate Detection**: Per-file backup mode now uses SHA256 content hashing to detect duplicate files
  - Skips unchanged files automatically (same path, size, and content hash)
  - Creates versioned archives (-v2, -v3) when content changes but modification time stays the same
  - Protects against edge cases where files are modified with manual `touch -t` operations
  - Archive metadata stores: `path|||size|||hash` for comprehensive verification
  - Backward compatible with old archive formats (plain path, path|||hash)
- **Smart Skip Statistics**: Backup completion messages show both backed-up and skipped file counts
  - Example: "✓ Per-file backup completed: 50000 file(s) backed up, 26456 skipped (unchanged)"
  - Provides visibility into deduplication efficiency

### Fixed
- **Per-File Backup Archive Collision**: Fixed "Archive already exists" error in per-file backup mode
  - Archives are now verified by path, size, and content hash before skipping
  - Different files with same archive name get automatic version suffixes
  - File size changes detected even when modification time is manually reset
  - Logs warning messages for collision scenarios with detailed context

### Changed
- **Archive Comment Format**: Per-file archives now store comprehensive metadata
  - New format: `path|||size|||hash` (three-part delimiter-based format)
  - Enables instant duplicate detection without re-hashing files
  - Backward compatible parsing handles old formats gracefully
- **Enhanced Collision Handling**: Intelligent version suffix generation
  - Appends `-v2`, `-v3`, etc. for archive name collisions
  - Prevents data loss from conflicting archive names
  - Logs warnings for all collision scenarios

### Security
- **No Security Impact**: Security review found no exploitable vulnerabilities in new features
  - Content hashing uses SHA256 (cryptographically secure)
  - Archive comment parsing uses safe string splitting (no injection risks)
  - File paths from archives only used for comparison, not file operations
  - Array-based command execution prevents shell injection
  - JSON parsing uses Ruby's safe `JSON.parse()` with error handling
  - All existing security controls maintained

## [0.7.0] - 2025-10-08

### Added
- **List Files in Archives**: New `--archive` option for list command to view files within a specific archive
  - `ruborg list --repository documents --archive archive-name`
  - Lists all files and directories contained in the specified archive
  - Useful for finding specific files before restore operations
- **File Metadata Retrieval**: New `metadata` command to retrieve detailed file information from archives
  - `ruborg metadata ARCHIVE --repository documents --file /path/to/file`
  - Auto-detects per-file archives and retrieves metadata without --file option
  - Displays file size (human-readable), modification time, permissions, owner, group, and type
  - Supports both standard and per-file archive modes
- **Version Command**: New `ruborg version` command to display current ruborg version
- **Enhanced Archive Naming**: Per-file archives now include actual filename in archive name
  - Changed from `repo-hash-timestamp` to `repo-filename-hash-timestamp`
  - Makes archive names human-readable and easier to identify
  - Automatic filename sanitization (alphanumeric, dash, underscore, dot only)
- **Smart Filename Truncation**: Archive names limited to 255 characters (filesystem limit)
  - Intelligent truncation preserves file extensions when possible
  - Handles very long filenames and repository names gracefully
  - Example: `very-long-name...truncated.sql` becomes `very-lon.sql` with hash and timestamp
- **File Modification Time in Archives**: Per-file mode uses file mtime instead of backup time
  - Archive timestamps reflect when files were last modified, not when backup ran
  - More accurate for tracking file changes over time
  - Enables better retention based on actual file activity

### Changed
- **Separated Console Output from Logs**: Console now shows progress, logs show results
  - Console displays repository headers, progress indicators, and completion messages
  - Logs contain structured operational data with timestamps
  - Repository name appears in both console headers and log entries (format: `[repo_name]`)
  - Cleaner separation between user feedback and audit trails
- **Enhanced Logging**: More detailed logging for backup operations
  - Standard mode: Logs archive name with source count
  - Per-file mode: Logs each file with its archive name
  - Repository name prefix in all log entries for multi-repo clarity

### Security
- **Archive Name Validation**: Enhanced sanitization for archive names containing filenames
  - Whitelist approach allows only safe characters: `[a-zA-Z0-9._-]`
  - Replaces unsafe characters with underscores
  - Prevents injection attacks via malicious filenames
  - Archive names still passed as array elements to prevent shell injection
- **Path Normalization**: Improved file path handling in metadata retrieval
  - Correctly handles borg's path format (strips leading slash)
  - Safe matching within JSON data from borg
  - No path traversal vulnerabilities introduced

## [0.6.2] - 2025-10-08

### Fixed
- **Passbolt Integration**: Fixed Passbolt CLI command to include required `--id` flag
  - Changed command from `passbolt get resource <id> --json` to `passbolt get resource --id <id> --json`
  - Resolves "Error: required flag(s) 'id' not set" when retrieving passwords
  - Updated security tests to verify correct command format

## [0.6.1] - 2025-10-08

### Added
- **Enhanced Configuration Validation**: Comprehensive validation system to catch configuration errors early
  - **Unknown Key Detection**: Detects typos and invalid configuration keys at all levels (global, repository, sources, retention, passbolt, borg_options)
  - **Retention Policy Validation**: Validates retention policy structure and values
    - Integer fields (keep_hourly, keep_daily, etc.) must be non-negative integers
    - Time-based fields (keep_within, keep_files_modified_within) must use correct format (e.g., "7d", "30d")
    - Validates time format with h/d/w/m/y suffixes
    - Rejects empty retention policies
    - Detects unknown retention keys
  - **Passbolt Configuration Validation**: Validates passbolt config structure
    - Requires non-empty `resource_id` string
    - Type validation for resource_id field
    - Detects unknown passbolt keys
  - **Retention Mode Validation**: Validates `retention_mode` values (must be "standard" or "per_file")
  - **Source Validation**: Validates source structure (name, paths, exclude fields)
- **Comprehensive Logging**: Added logging throughout backup, restore, and deletion operations
  - Repository operations (initialization, pruning, archive management)
  - Backup operations (file counts, progress in per-file mode)
  - Restore operations (extraction start/completion)
  - Source file deletion tracking (with `--remove-source`)
  - Passbolt integration events (resource ID logged, never passwords)
  - All sensitive data (passwords, encryption keys) protected from logs
- **Enhanced Test Suite**: Expanded test coverage to 220 examples (67 new tests added)
  - 23 new configuration validation tests
  - 28 new logging integration tests
  - 10 new CLI validation tests
  - 6 new type checking tests for boolean configurations
  - All tests passing with 0 failures

### Changed
- `global_settings` now includes `borg_path` (previously was in whitelist but not propagated)
- Validation errors are collected and reported together for better user experience
- All validation runs automatically on configuration load

### Fixed
- **Configuration Consistency**: Fixed inconsistency where `borg_path` was allowed in VALID_GLOBAL_KEYS but not returned by `global_settings` method

## [0.6.0] - 2025-10-08

### Added
- **Configuration Validation Command**: New `ruborg validate` command to check configuration files for type errors
- **Automatic Schema Validation**: All commands now validate configuration on startup to catch errors early
- **Strict Boolean Type Checking**: All boolean config values (auto_init, auto_prune, allow_remove_source, etc.) now require actual boolean types
  - Prevents type confusion attacks where strings like `'true'` or `"false"` bypass security checks
  - Clear error messages show actual type vs expected type
  - Validation runs automatically on config load
- Comprehensive validation test suite (10 new test cases)
- Documentation for configuration validation in README

### Changed
- Boolean configuration values now use strict type checking throughout the codebase
  - `auto_init`: only boolean `true` enables, everything else disables
  - `auto_prune`: only boolean `true` enables, everything else disables
  - `allow_remove_source`: strict checking - only `TrueClass` enables (security-critical)
  - `allow_relocated_repo`: permissive normalization - only `false` disables (backward compatible)
  - `allow_unencrypted_repo`: permissive normalization - only `false` disables (backward compatible)
- Config class now validates schema by default (can be disabled with `validate_types: false`)

### Security
- **Type Confusion Protection (CWE-843)**: Strict boolean type checking prevents configuration bypass attacks
  - Before: `allow_remove_source: 'false'` (string) would be truthy and enable deletion
  - After: Only `allow_remove_source: true` (boolean) enables the dangerous operation
- Enhanced error messages guide users to fix type errors correctly
- SECURITY.md updated with type confusion findings and mitigations

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