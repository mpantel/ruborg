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

### 4. Safe YAML Loading
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

## Security Best Practices

### When Using `--remove-source`
⚠️ **Warning**: The `--remove-source` flag permanently deletes source files after backup.

**Recommendations:**
1. **Test first** without `--remove-source` to verify backups work
2. **Never use on symlinks** to critical system directories
3. **Verify backups** before using this flag in production
4. **Use absolute paths** in configuration to avoid ambiguity

### Configuration File Security
- Store configuration files with restricted permissions: `chmod 600 ruborg.yml`
- Never commit Passbolt resource IDs to public repositories
- Use environment variables for sensitive paths when possible

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

- **v0.3.1** (2025-10-05): Comprehensive security hardening
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
