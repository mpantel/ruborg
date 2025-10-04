# frozen_string_literal: true

require_relative "lib/ruborg/version"

Gem::Specification.new do |spec|
  spec.name = "ruborg"
  spec.version = Ruborg::VERSION
  spec.authors = ["Michail Pantelelis"]
  spec.email = ["mpantel@aegean.gr"]

  spec.summary = "A friendly Ruby frontend for Borg backup"
  spec.description = "Ruborg is a Ruby gem that provides a user-friendly interface to Borg backup. It reads YAML configuration files and orchestrates backup operations, supporting repository creation, backup management, and integration with Passbolt for encryption password management."
  spec.homepage = "https://github.com/mpantel/ruborg"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "psych", "~> 5.0"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
end