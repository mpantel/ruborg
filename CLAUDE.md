# Ruborg Project

## Overview
Ruborg is a Ruby gem to perform backups using Borg. It reads a configuration file in YAML and instructs Borg about what to do. It is a friendly frontend of Borg in Ruby. It can create and access backup repositories. It can take and recall backup files or directories. It can interact with Passbolt through CLI to access encryption passwords.

## Development Practices

### Code Quality
- **RuboCop**: Static code analyzer and formatter configured in `.rubocop.yml`
  - Run: `bundle exec rubocop`
  - Auto-fix: `bundle exec rubocop -a`
  - Target: 0 offenses (currently achieved)

- **RuboCop RSpec**: RSpec-specific linting rules
  - Integrated with main RuboCop configuration
  - Enforces consistent test patterns

### Security
- **bundler-audit**: Checks for known vulnerabilities in dependencies
  - Update database: `bundle exec bundle-audit update`
  - Check vulnerabilities: `bundle exec bundle-audit check`
  - Run regularly as part of CI/CD and before releases

- **Security Best Practices**:
  - Use `YAML.safe_load_file` for configuration parsing
  - Use `Open3.capture*` methods instead of backticks for command execution
  - Validate and sanitize all user inputs (archive names, paths)
  - Prevent path traversal with system directory blacklists
  - Use array syntax for system calls to prevent shell injection

### Testing
- **RSpec**: Test framework for unit and integration tests
  - Run all tests: `bundle exec rspec`
  - Run with documentation: `bundle exec rspec --format documentation`
  - Target: All tests passing (currently 124 examples, 0 failures)

- **Test Coverage**:
  - Unit tests for core classes (Repository, Backup, Config)
  - Integration tests for end-to-end workflows
  - Security tests for input validation and path handling

### Development Workflow
1. Make code changes
2. Run tests: `bundle exec rspec`
3. Run linter: `bundle exec rubocop`
4. Check security: `bundle exec bundle-audit check`
5. Commit changes with descriptive messages
6. Open pull request for review

### Project Structure
- `lib/ruborg/` - Main source code
  - `cli.rb` - Command-line interface (Thor)
  - `repository.rb` - Borg repository management
  - `backup.rb` - Backup operations
  - `config.rb` - YAML configuration handling
  - `passbolt.rb` - Passbolt integration
  - `logger.rb` - Logging functionality
- `spec/` - RSpec tests
- `exe/` - Executable scripts

### Key Features
- **Multi-repository support**: Manage multiple backup repositories from a single config
- **Per-file backup mode**: Back up each file as a separate archive with metadata-based retention
- **Passbolt integration**: Retrieve encryption passphrases from Passbolt
- **Auto-initialization**: Automatically create repositories if they don't exist
- **Auto-pruning**: Automatically prune old backups based on retention policies
- **Logging**: Comprehensive logging to file or stdout