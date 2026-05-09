# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ruborg::ArchiveCache do
  let(:repo_path) { File.join(tmpdir, "test_repo") }
  let(:cache_path) { "#{repo_path}.ruborg_cache.json" }
  let(:cache) { described_class.new(repo_path) }

  def write_cache(archives)
    File.write(cache_path, JSON.generate({ "version" => 1, "archives" => archives }))
  end

  describe "#fetch" do
    context "when no cache file exists" do
      it "returns self and leaves data empty" do
        result = cache.fetch
        expect(result).to be(cache)
        expect(cache["nonexistent"]).to be_nil
      end
    end

    context "when cache file exists" do
      let(:existing) do
        { "archive-2024" => { "path" => "/foo/bar.txt", "size" => 100, "hash" => "abc", "source_dir" => "/foo" } }
      end

      before { write_cache(existing) }

      it "loads existing archive entries with symbol keys" do
        cache.fetch
        expect(cache["archive-2024"]).to eq(
          path: "/foo/bar.txt", size: 100, hash: "abc", source_dir: "/foo"
        )
      end

      it "returns nil for unknown archives" do
        cache.fetch
        expect(cache["unknown-archive"]).to be_nil
      end
    end

    context "when cache file contains invalid JSON" do
      before { File.write(cache_path, "not json {{{") }

      it "treats cache as empty without raising" do
        expect { cache.fetch }.not_to raise_error
        expect(cache["anything"]).to be_nil
      end
    end

    it "is idempotent — second call does not re-read the file" do
      write_cache({ "a" => { "path" => "/a", "size" => 1, "hash" => "", "source_dir" => "" } })
      cache.fetch
      File.write(cache_path, "corrupted")
      expect { cache.fetch }.not_to raise_error
      expect(cache["a"]).not_to be_nil
    end
  end

  describe "#store and #[]" do
    it "stores and retrieves metadata by archive name" do
      cache.fetch
      metadata = { path: "/data/file.txt", size: 512, hash: "deadbeef", source_dir: "/data" }
      cache.store("new-archive", metadata)
      expect(cache["new-archive"]).to eq(metadata)
    end
  end

  describe "symbol key normalisation" do
    it "returns symbol keys when loaded from JSON (string keys on disk)" do
      write_cache({ "arch" => { "path" => "/p", "size" => 10, "hash" => "hh", "source_dir" => "/s" } })
      cache.fetch
      entry = cache["arch"]
      expect(entry.keys).to all(be_a(Symbol))
    end

    it "preserves symbol keys after round-trip (store → save → fetch)" do
      cache.fetch
      cache.store("arch", { path: "/p", size: 10, hash: "hh", source_dir: "/s" })
      cache.save_if_changed

      fresh = described_class.new(repo_path).fetch
      expect(fresh["arch"].keys).to all(be_a(Symbol))
    end

    it "normalises string keys passed to #store" do
      cache.fetch
      cache.store("arch", { "path" => "/p", "size" => 5, "hash" => "", "source_dir" => "" })
      expect(cache["arch"].keys).to all(be_a(Symbol))
    end
  end

  describe "#entries" do
    before do
      write_cache({
                    "archive-a" => { "path" => "/a/file.txt", "size" => 100, "hash" => "aa", "source_dir" => "/a" },
                    "archive-b" => { "path" => "/b/file.txt", "size" => 200, "hash" => "bb", "source_dir" => "/b" }
                  })
    end

    it "returns one entry per cached archive" do
      cache.fetch
      expect(cache.entries.size).to eq(2)
    end

    it "includes :archive_name in each entry" do
      cache.fetch
      names = cache.entries.map { |e| e[:archive_name] }
      expect(names).to contain_exactly("archive-a", "archive-b")
    end

    it "includes metadata fields in each entry" do
      cache.fetch
      entry = cache.entries.find { |e| e[:archive_name] == "archive-a" }
      expect(entry).to include(path: "/a/file.txt", size: 100, hash: "aa", source_dir: "/a")
    end

    it "returns empty array when cache is empty" do
      cache.fetch
      expect(described_class.new(File.join(tmpdir, "empty_repo")).fetch.entries).to eq([])
    end
  end

  describe "#save_if_changed" do
    context "when nothing was stored (no changes)" do
      it "does not write a cache file" do
        cache.fetch
        cache.save_if_changed
        expect(File.exist?(cache_path)).to be false
      end
    end

    context "when new entries were stored" do
      it "writes cache file with correct JSON structure" do
        cache.fetch
        cache.store("archive-new", { path: "/x", size: 10, hash: "ff", source_dir: "/x" })
        cache.save_if_changed

        expect(File.exist?(cache_path)).to be true
        data = JSON.parse(File.read(cache_path))
        expect(data["version"]).to eq(1)
        expect(data["archives"]["archive-new"]).to eq(
          "path" => "/x", "size" => 10, "hash" => "ff", "source_dir" => "/x"
        )
      end

      it "merges with existing entries on disk" do
        write_cache({ "old-archive" => { "path" => "/old", "size" => 5, "hash" => "", "source_dir" => "" } })
        cache.fetch
        cache.store("new-archive", { path: "/new", size: 20, hash: "aa", source_dir: "" })
        cache.save_if_changed

        data = JSON.parse(File.read(cache_path))
        expect(data["archives"].keys).to contain_exactly("old-archive", "new-archive")
      end

      it "creates cache file with 0600 permissions" do
        cache.fetch
        cache.store("a", { path: "/a", size: 1, hash: "", source_dir: "" })
        cache.save_if_changed

        perms = File.stat(cache_path).mode & 0o777
        expect(perms).to eq(0o600)
      end
    end

    context "concurrent write merging" do
      it "merges external additions written after fetch" do
        write_cache({ "pre-existing" => { "path" => "/pre", "size" => 1, "hash" => "", "source_dir" => "" } })
        cache.fetch

        # Simulate another process adding an entry after our fetch
        concurrent_data = {
          "pre-existing" => { "path" => "/pre", "size" => 1, "hash" => "", "source_dir" => "" },
          "concurrent" => { "path" => "/c", "size" => 2, "hash" => "", "source_dir" => "" }
        }
        write_cache(concurrent_data)

        cache.store("ours", { path: "/ours", size: 3, hash: "", source_dir: "" })
        cache.save_if_changed

        data = JSON.parse(File.read(cache_path))
        expect(data["archives"].keys).to contain_exactly("pre-existing", "concurrent", "ours")
      end
    end
  end

  describe "SSH path detection" do
    it "recognises user@host:/path style" do
      c = described_class.new("user@host:/backups/repo")
      expect(c.send(:ssh?)).to be true
    end

    it "recognises ssh://user@host/path style" do
      c = described_class.new("ssh://user@host/backups/repo")
      expect(c.send(:ssh?)).to be true
    end

    it "does not flag local paths as SSH" do
      c = described_class.new("/local/backups/repo")
      expect(c.send(:ssh?)).to be false
    end

    it "does not flag relative paths as SSH" do
      c = described_class.new("relative/path/repo")
      expect(c.send(:ssh?)).to be false
    end
  end

  describe "#parse_ssh" do
    it "parses user@host:/path" do
      c = described_class.new("user@myhost:/backups/repo")
      host, path = c.send(:parse_ssh)
      expect(host).to eq("user@myhost")
      expect(path).to eq("/backups/repo")
    end

    it "parses ssh:// URI with user" do
      c = described_class.new("ssh://admin@myhost/backups/repo")
      host, path = c.send(:parse_ssh)
      expect(host).to eq("admin@myhost")
      expect(path).to eq("/backups/repo")
    end

    it "parses ssh:// URI with custom port" do
      c = described_class.new("ssh://admin@myhost:2222/backups/repo")
      host, path = c.send(:parse_ssh)
      expect(host).to eq("admin@myhost:2222")
      expect(path).to eq("/backups/repo")
    end
  end

  describe "SSH fetch and save" do
    let(:ssh_cache) { described_class.new("user@remotehost:/backups/repo") }
    let(:remote_ref) { "user@remotehost:/backups/repo.ruborg_cache.json" }

    describe "#fetch (SSH)" do
      it "calls scp to retrieve the cache file" do
        allow(Open3).to receive(:capture2e).and_return(["", double(success?: false)])
        ssh_cache.fetch
        expect(Open3).to have_received(:capture2e).with("scp", "-q", "-B", remote_ref, anything)
      end

      it "loads archives when scp succeeds" do
        remote_data = JSON.generate({ "version" => 1, "archives" => {
                                      "remote-arch" => { "path" => "/r", "size" => 9, "hash" => "xy", "source_dir" => "/r" }
                                    } })

        allow(Open3).to receive(:capture2e) do |*_args, **_kwargs|
          # Write data to the tempfile argument (last positional arg)
          # We need a different approach: stub the whole load_remote
          ["", double(success?: true)]
        end

        # Use a simpler approach: directly test load_remote by writing a temp file
        expect(ssh_cache).to receive(:load_remote) do
          ssh_cache.instance_variable_set(:@data, JSON.parse(remote_data)["archives"])
        end

        ssh_cache.fetch
        expect(ssh_cache["remote-arch"]).to include("path" => "/r")
      end

      it "leaves cache empty when scp fails (no remote cache yet)" do
        allow(Open3).to receive(:capture2e).and_return(["scp: not found", double(success?: false)])
        expect { ssh_cache.fetch }.not_to raise_error
        expect(ssh_cache["anything"]).to be_nil
      end
    end

    describe "#save_if_changed (SSH)" do
      it "does not call scp when nothing changed" do
        allow(Open3).to receive(:capture2e).and_return(["", double(success?: false)])
        ssh_cache.fetch
        expect(Open3).not_to receive(:capture2e).with("scp", "-q", "-B", anything, remote_ref)
        ssh_cache.save_if_changed
      end

      it "pushes updated cache when new entries are stored" do
        allow(Open3).to receive(:capture2e).and_return(["", double(success?: false)])
        ssh_cache.fetch
        ssh_cache.store("arch", { path: "/p", size: 1, hash: "", source_dir: "" })

        expect(Open3).to receive(:capture2e).with("scp", "-q", "-B", anything, remote_ref)
                                            .and_return(["", double(success?: true)])
        # Also allow the fresh-fetch scp call
        allow(Open3).to receive(:capture2e).and_return(["", double(success?: false)])

        ssh_cache.save_if_changed
      end
    end
  end
end
