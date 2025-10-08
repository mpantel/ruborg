# Security Policy

## Security Features

Ruborg implements several security measures to protect your backup operations:

### 1. Command Injection Prevention
- Uses `Open3.capture3` for Passbolt CLI execution (no shell interpolation)
- Array-based command construction for Borg commands
- No user input directly interpolated into shell commands

### 2. Path Traversal Protection
- Validates all destination paths during restore operations
- Prevents extraction to system directories (`/`, `/etc`, `/bin`, `/usr`, etc.)
- Normalizes paths to prevent `../` traversal attacks

### 3. Symlink Protection
- Resolves symlinks before file deletion with `--remove-source`
- Refuses to delete system directories even when targeted via symlinks
- Uses `FileUtils.rm_rf` with `secure: true` option

### 4. Immutable File Handling (Linux)
- **Automatic Detection**: Checks for Linux immutable attributes (`lsattr`) before file deletion
- **Safe Removal**: Removes immutable flag (`chattr -i`) only when necessary for deletion
- **Platform-Aware**: Feature only active on Linux systems with lsattr/chattr commands available
- **Error Handling**: Raises informative errors if immutable flag cannot be removed
- **Audit Trail**: All immutable attribute operations are logged for security auditing
- **Root Required**: Removing immutable attributes requires root privileges (use sudo with appropriate sudoers configuration)

### 5. Safe YAML Loading
- Uses `YAML.safe_load_file` to prevent arbitrary code execution
- Rejects YAML files containing Ruby objects or other dangerous constructs
- Only permits basic data types and Symbol class

### 5. Log Path Validation
- Validates log file paths to prevent writing to system directories
- Automatically creates log directories with proper permissions
- Rejects paths in `/bin`, `/etc`, `/usr`, and other sensitive locations

### 6. Passphrase Handling
- Passes passphrases via environment variables (never CLI arguments)
- Prevents passphrase leakage in process listings
- Uses Passbolt integration for secure password retrieval

### 7. Repository Path Validation
- Validates repository paths to prevent creation in system directories
- Rejects empty or nil repository paths
- Prevents accidental repository creation in `/bin`, `/etc`, `/usr`, etc.

### 8. Backup Path Validation
- Validates all backup source paths before creating archives
- Rejects empty, nil, or whitespace-only paths
- Normalizes relative paths to absolute paths for consistency

### 9. Archive Name Sanitization
- Sanitizes user-provided archive names to prevent injection attacks
- Allows only alphanumeric characters, dashes, underscores, and dots
- Rejects archive names that would become empty after sanitization

### 10. Configurable Borg Environment Options
- Allows control over relocated repository access via config
- Allows control over unencrypted repository access via config
- Defaults to safe settings while maintaining backward compatibility

### 11. Borg Executable Validation
- Validates that `borg_path` points to an actual executable file
- Verifies the executable is actually Borg by checking version output
- Prevents execution of arbitrary binaries specified in config
- Searches PATH for command-name-only specifications

### 12. Dependency Vulnerability Scanning
- Uses `bundler-audit` to check for known vulnerabilities
- Regular database updates ensure latest security advisories
- Integrated into development workflow
- Run: `bundle exec bundle-audit check`

### 13. Boolean Type Safety (Type Confusion Protection)
- **Critical safety flag validation** for `allow_remove_source` configuration
- Uses strict type checking (`is_a?(TrueClass)`) to prevent type confusion attacks
- Rejects truthy values like strings `'true'`, `"false"`, integers `1`, or `"yes"`
- Only boolean `true` enables dangerous operations like `--remove-source`
- Provides detailed error messages showing actual type received vs expected
- Prevents configuration errors that could lead to unintended data loss
- **CWE-843 Mitigation**: Protects against type confusion vulnerabilities

### 14. Logging Security (v0.6.1+)
- **Comprehensive logging** of backup operations for audit trails and troubleshooting
- **Sensitive data protection**: Passwords and passphrases are NEVER logged
- **Safe operational logging**: File paths, archive names, and operation status are logged
- **Passbolt resource IDs** (UUIDs) are logged but actual passwords are not
- **System path protection**: Failed deletion attempts are logged with full paths for security auditing
- **Log level support**: INFO, WARN, ERROR, DEBUG levels for appropriate detail

#### What Is Logged (Safe)
- Repository creation and initialization events
- Backup operation start/completion with file counts
- Individual file paths being backed up (per-file mode)
- Archive names (user-provided or auto-generated)
- Restore operations with destination paths
- Source file deletion events (when using `--remove-source`)
- Passbolt resource IDs (UUIDs) for password retrieval attempts
- System path deletion refusals with full path (security audit)
- Pruning operations with archive counts

#### What Is NEVER Logged (Protected)
- ✅ **Passwords and passphrases** - Neither from CLI nor Passbolt
- ✅ **Encryption keys** - Repository encryption keys never written to logs
- ✅ **Passbolt passwords** - Only resource UUIDs logged, not actual retrieved passwords
- ✅ **File contents** - Only paths and metadata, never file contents
- ✅ **Environment variables** with sensitive data

#### Log Security Recommendations
1. **Protect log files** with restrictive permissions:
   ```bash
   chmod 600 ~/.ruborg/logs/ruborg.log
   # Or for shared access with backup group:
   chmod 640 ~/.ruborg/logs/ruborg.log
   chown user:backup ~/.ruborg/logs/ruborg.log
   ```

2. **Configure log rotation** to prevent log files from growing indefinitely:
   ```bash
   # /etc/logrotate.d/ruborg
   /home/user/.ruborg/logs/ruborg.log {
       weekly
       rotate 4
       compress
       missingok
       notifempty
       create 0600 user user
   }
   ```

3. **Review logs regularly** for:
   - Failed backup or restore operations
   - Unauthorized `--remove-source` attempts
   - Passbolt password retrieval failures
   - System path deletion attempts (potential security issues)
   - Unexpected file paths being backed up

4. **Secure log storage locations**:
   - Use absolute paths in `log_file` configuration
   - Avoid logging to world-readable directories
   - Consider logging to `/var/log/ruborg/` with proper permissions

5. **Passbolt Resource IDs in Logs**:
   - Resource IDs (UUIDs) are logged for operational debugging
   - These are identifiers, not credentials - safe to log
   - They cannot be used to access Passbolt without proper authentication
   - Still, protect logs as they reveal which Passbolt resources are used

## Security Best Practices

### When Using `--remove-source`
⚠️ **Warning**: The `--remove-source` flag permanently deletes source files after backup.

**Recommendations:**
1. **Test first** without `--remove-source` to verify backups work
2. **Never use on symlinks** to critical system directories
3. **Verify backups** before using this flag in production
4. **Use absolute paths** in configuration to avoid ambiguity
5. **Use boolean values** for `allow_remove_source` - NEVER use quoted strings:
   ```yaml
   # ✅ CORRECT
   allow_remove_source: true

   # ❌ WRONG - Will be rejected
   allow_remove_source: 'true'
   allow_remove_source: "true"
   allow_remove_source: 1
   ```

### Configuration File Security

**CRITICAL**: Always protect your configuration file with restrictive permissions:

```bash
# Set owner-only read/write permissions
chmod 600 ruborg.yml

# Verify permissions
ls -l ruborg.yml
# Should show: -rw------- 1 user user ... ruborg.yml

# For shared environments with a backup group
chmod 640 ruborg.yml
chown user:backup ruborg.yml
```

**Additional recommendations:**
- Never commit Passbolt resource IDs to public repositories
- Use environment variables for sensitive paths when possible
- Store config files outside web-accessible directories
- Regularly audit who has access to the config file

### Repository Security
- Use encrypted repositories (default: `encryption: repokey`)
- Store passphrases in Passbolt, not in config files
- Use different encryption keys for different repository types
- Regularly rotate Passbolt passphrases
- Avoid creating repositories in system directories
- Use absolute paths for repository locations

### Multi-Repository Considerations
- Each repository can have its own Passbolt resource ID
- Validate all source paths before adding to configuration
- Review exclude patterns to ensure no sensitive files leak

### Archive Naming
- Use default timestamp-based names when possible
- If providing custom names, use only alphanumeric characters, dashes, and underscores
- Avoid special characters or path separators in archive names

### Borg Environment Options
- Consider disabling `allow_relocated_repo` for production environments
- Consider disabling `allow_unencrypted_repo` for sensitive data
- Configure in `ruborg.yml`:
```yaml
borg_options:
  allow_relocated_repo: false  # Reject relocated repositories
  allow_unencrypted_repo: false  # Reject unencrypted repositories
```

## Reporting Security Issues

If you discover a security vulnerability, please:

1. **Do NOT** open a public issue
2. Email security concerns to: mpantel@aegean.gr
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We will respond within 48 hours and work with you to address the issue.

## Security Audit History

- **v0.7.5** (2025-10-09): Immutable file handling - security review passed
  - **NEW FEATURE**: Automatic detection and removal of Linux immutable attributes (`chattr +i`) when deleting files with `--remove-source`
  - **PLATFORM-AWARE**: Feature only active on Linux systems with lsattr/chattr commands available
  - **SAFE OPERATION**: Checks files with `lsattr` before deletion, removes immutable flag with `chattr -i` only when necessary
  - **ERROR HANDLING**: Raises informative errors if immutable flag cannot be removed (operation not permitted)
  - **AUDIT TRAIL**: All immutable attribute operations logged for security monitoring
  - **ROOT REQUIRED**: Removing immutable attributes requires root privileges (documented sudoers configuration)
  - **SECURITY REVIEW**: No new security vulnerabilities introduced
  - Uses Open3.capture3 for safe command execution (no shell injection)
  - Precise flag parsing prevents false positives from filenames containing 'i'
  - Works for both single files (per-file mode) and directories (recursive, standard mode)
  - Gracefully handles systems without lsattr/chattr (macOS, BSD, etc.)
  - Test coverage: 6 comprehensive specs covering all scenarios

- **v0.7.1** (2025-10-08): Paranoid mode duplicate detection - security review passed
  - **NEW FEATURE**: SHA256 content hashing for detecting file changes even when mtime/size are identical
  - **NEW FEATURE**: Smart skip statistics showing backed-up and skipped file counts
  - **BUG FIX**: Fixed "Archive already exists" error in per-file backup mode
  - **ENHANCED**: Archive comment format now stores comprehensive metadata (`path|||size|||hash`)
  - **ENHANCED**: Version suffix generation for archive name collisions (`-v2`, `-v3`)
  - **SECURITY REVIEW**: Comprehensive security analysis found no exploitable vulnerabilities
  - SHA256 hashing is cryptographically secure (using Ruby's Digest::SHA256)
  - Archive comment parsing uses safe string splitting with `|||` delimiter (no injection risks)
  - File paths from archives only used for comparison, never for file operations
  - Array-based command execution prevents shell injection (maintained from previous versions)
  - JSON parsing uses Ruby's safe `JSON.parse()` with error handling
  - All existing security controls maintained - no security regressions
  - Backward compatibility with three metadata formats (plain path, path|||hash, path|||size|||hash)

- **v0.7.0** (2025-10-08): Archive naming and metadata features - security review passed
  - **NEW FEATURE**: List files within archives (--archive option)
  - **NEW FEATURE**: File metadata retrieval from archives
  - **NEW FEATURE**: Enhanced archive naming with filenames in per-file mode
  - **SECURITY REVIEW**: Comprehensive security analysis found no exploitable vulnerabilities
  - Archive name sanitization uses whitelist approach `[a-zA-Z0-9._-]`
  - Array-based command execution prevents shell injection
  - Safe JSON parsing without deserialization risks
  - Path normalization handles borg's format safely (strips leading slash for matching only)
  - All new features maintain existing security controls

- **v0.6.1** (2025-10-08): Enhanced logging with sensitive data protection
  - **NEW FEATURE**: Comprehensive logging for backup operations, restoration, and deletion
  - Passwords and passphrases are NEVER logged (neither CLI nor Passbolt passwords)
  - Passbolt resource IDs (UUIDs) logged for debugging - identifiers only, not credentials
  - File paths and archive names logged for audit trails
  - System path deletion attempts logged with full paths for security monitoring
  - Log levels: INFO, WARN, ERROR, DEBUG for appropriate detail
  - Documentation added for logging security best practices
  - Enhanced configuration validation with unknown key detection across all levels

- **v0.6.0** (2025-10-08): Configuration validation and type confusion protection
  - **SECURITY FIX**: Implemented strict boolean type checking for `allow_remove_source`
  - Prevents type confusion attacks (CWE-843) where string values bypass safety checks
  - Added configuration validation command (`ruborg validate`) for proactive error detection
  - Automatic schema validation on config load catches type errors early
  - Added 10 comprehensive test cases for validation and type confusion scenarios
  - Enhanced error messages to show actual type vs expected type
  - Updated documentation with type safety warnings and examples

- **v0.5.0** (2025-10-08): Hostname validation
  - Added hostname validation feature (optional global or per-repository)
  - Prevents accidental execution of backups on wrong machines

- **v0.4.0** (2025-10-06): Complete command injection elimination
  - **CRITICAL**: Fixed all remaining command injection vulnerabilities in repository.rb
  - Replaced all backtick execution with Open3.capture3/capture2e methods
  - Added Borg executable validation to prevent arbitrary binary execution
  - Integrated bundler-audit for dependency vulnerability scanning
  - Removed unused env_to_cmd_prefix method
  - Enhanced security documentation with config file permission requirements
  - Zero known vulnerabilities in dependencies

- **v0.3.1** (2025-10-05): Initial security hardening
  - Fixed command injection in Passbolt CLI execution (uses Open3.capture3)
  - Added path traversal protection for extract operations
  - Implemented symlink protection for file deletion with --remove-source
  - Switched to safe YAML loading (YAML.safe_load_file)
  - Added log path validation to prevent writing to system directories
  - Added repository path validation to prevent creation in system directories
  - Added backup path validation and normalization
  - Implemented archive name sanitization
  - Made Borg environment variables configurable
  - Enhanced test coverage for all security features
  - Created comprehensive SECURITY.md documentation

- **v0.3.0** (2025-10-05): Multi-repository and auto-initialization features
  - Added multi-repository configuration support
  - Added auto-initialization feature
  - Added configurable log file paths
  - No security-specific changes in this version

## Dependency Security

Ruborg relies on:
- **Borg Backup**: Industry-standard backup tool with strong encryption
- **Passbolt CLI**: Secure password management
- **Ruby stdlib**: No external gems for core functionality (only Thor for CLI)

Keep dependencies updated:
```bash
# Update Borg
brew upgrade borgbackup  # macOS
sudo apt update && sudo apt upgrade borgbackup  # Ubuntu

# Update Passbolt CLI
# Follow https://github.com/passbolt/go-passbolt-cli

# Update Ruby gems
bundle update
```

## Security Checklist

Before deploying ruborg in production:

- [ ] Review all paths in configuration files
- [ ] Set proper file permissions on config (600) and logs (640)
- [ ] Use Passbolt for all passphrases (never hardcode)
- [ ] Test restore operations before relying on backups
- [ ] Never use `--remove-source` without thorough testing
- [ ] Keep Borg and Passbolt CLI up to date
- [ ] Review exclude patterns for sensitive data
- [ ] Use absolute paths in configuration
- [ ] Enable auto_init only for trusted repository locations
- [ ] Regularly audit backup logs for anomalies
- [ ] Validate repository paths are not in system directories
- [ ] Configure borg_options for your security requirements
- [ ] Use default archive names or sanitized custom names only
- [ ] Ensure backup paths don't contain empty or nil values
- [ ] Use boolean `true` (not strings) for `allow_remove_source` configuration
- [ ] Configure hostname validation for multi-server environments
