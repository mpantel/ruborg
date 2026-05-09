# frozen_string_literal: true

require "json"
require "open3"
require "tempfile"

module Ruborg
  # Persistent cache of per-archive metadata, stored as a JSON file sibling to the
  # Borg repository. Eliminates repeated `borg info` calls across runs.
  #
  # Supports local paths (File::LOCK_EX) and SSH paths (optimistic merge via scp).
  # All metadata is stored and returned with symbol keys (:path, :size, :hash, :source_dir).
  class ArchiveCache
    SSH_PATTERN = %r{\A(?:ssh://|[^\s/]+@[^\s:]+:)}

    def initialize(repo_path)
      @repo_path = repo_path
      @data = {}
      @snapshot = {}
      @loaded = false
    end

    def fetch
      return self if @loaded

      if ssh?
        load_remote
      else
        load_local
      end

      @snapshot = snapshot(@data)
      @loaded = true
      self
    end

    def [](archive_name)
      @data[archive_name]
    end

    def store(archive_name, metadata)
      @data[archive_name] = symbolize(metadata)
    end

    # Returns all cached entries as an array of hashes, each including :archive_name.
    def entries
      @data.map { |archive_name, metadata| metadata.merge(archive_name: archive_name) }
    end

    def save_if_changed
      return unless dirty?

      if ssh?
        save_remote
      else
        save_local
      end
    end

    private

    def dirty?
      @data != @snapshot
    end

    def snapshot(hash)
      hash.transform_values(&:dup)
    end

    def ssh?
      SSH_PATTERN.match?(@repo_path)
    end

    def cache_path_for(path)
      "#{path}.ruborg_cache.json"
    end

    def symbolize(metadata)
      metadata.transform_keys(&:to_sym)
    end

    def normalize_archives(raw)
      (raw || {}).transform_values { |v| symbolize(v) }
    end

    def load_local
      path = cache_path_for(@repo_path)
      return unless File.exist?(path)

      File.open(path, "r") do |f|
        f.flock(File::LOCK_SH)
        parsed = JSON.parse(f.read)
        @data = normalize_archives(parsed["archives"])
      end
    rescue JSON::ParserError
      @data = {}
    end

    def save_local
      path = cache_path_for(@repo_path)
      File.open(path, File::RDWR | File::CREAT, 0o600) do |f|
        f.flock(File::LOCK_EX)
        existing = read_existing_local(f)
        merged = existing.merge(@data)
        f.rewind
        f.write(JSON.generate({ "version" => 1, "archives" => stringify_for_storage(merged) }))
        f.truncate(f.pos)
      end
    end

    def read_existing_local(file)
      content = file.read
      return {} if content.empty?

      normalize_archives(JSON.parse(content)["archives"])
    rescue JSON::ParserError
      {}
    end

    # JSON requires string keys; convert symbol keys back before writing.
    def stringify_for_storage(data)
      data.transform_values { |v| v.transform_keys(&:to_s) }
    end

    def parse_ssh
      if @repo_path.start_with?("ssh://")
        require "uri"
        uri = URI.parse(@repo_path)
        host = uri.user ? "#{uri.user}@#{uri.host}" : uri.host
        host = "#{host}:#{uri.port}" if uri.port && uri.port != 22
        [host, uri.path]
      else
        match = @repo_path.match(%r{\A([^\s/]+@[^\s:]+):(.+)\z})
        return [nil, nil] unless match

        [match[1], match[2]]
      end
    end

    def load_remote
      host, path = parse_ssh
      return unless host

      remote = "#{host}:#{cache_path_for(path)}"
      loaded = nil
      Tempfile.create(["ruborg_cache", ".json"]) do |tmp|
        _, status = Open3.capture2e("scp", "-q", "-B", remote, tmp.path)
        next unless status.success?

        begin
          loaded = normalize_archives(JSON.parse(File.read(tmp.path))["archives"])
        rescue JSON::ParserError
          loaded = {}
        end
      end
      @data = loaded if loaded
    end

    def save_remote
      host, path = parse_ssh
      return unless host

      remote = "#{host}:#{cache_path_for(path)}"
      fresh = fetch_remote_fresh(remote)
      merged = fresh.merge(@data)

      Tempfile.create(["ruborg_cache_upload", ".json"]) do |tmp|
        tmp.write(JSON.generate({ "version" => 1, "archives" => stringify_for_storage(merged) }))
        tmp.flush
        Open3.capture2e("scp", "-q", "-B", tmp.path, remote)
      end
    end

    def fetch_remote_fresh(remote)
      result = {}
      Tempfile.create(["ruborg_cache_fresh", ".json"]) do |tmp|
        _, status = Open3.capture2e("scp", "-q", "-B", remote, tmp.path)
        next unless status.success?

        begin
          result = normalize_archives(JSON.parse(File.read(tmp.path))["archives"])
        rescue JSON::ParserError
          result = {}
        end
      end
      result
    end
  end
end
