# frozen_string_literal: true

module Ruborg
  # Read-only view over the ArchiveCache for searching and reporting.
  # Never writes back to the cache.
  class Catalog
    def initialize(repo_path)
      @cache = ArchiveCache.new(repo_path).fetch
    end

    # Returns all cached entries sorted by file path.
    def list
      @cache.entries.sort_by { |e| e[:path].to_s }
    end

    # Returns entries whose :path matches +pattern+ (a Regexp or regex string).
    # Raises CatalogError on invalid regex.
    def search(pattern)
      regex = pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern)
      list.select { |e| regex.match?(e[:path].to_s) }
    rescue RegexpError => e
      raise CatalogError, "Invalid regex pattern: #{e.message}"
    end

    # Returns a summary hash with aggregate statistics.
    def stats
      all = list
      {
        total_archives: all.size,
        unique_paths: all.map { |e| e[:path] }.uniq.size,
        total_size: all.sum { |e| e[:size].to_i },
        source_dirs: all.map { |e| e[:source_dir] }.uniq.reject(&:empty?).size
      }
    end
  end
end
