# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ruborg::Catalog do
  subject(:catalog) { described_class.new(repo_path) }

  let(:repo_path) { File.join(tmpdir, "test_repo") }
  let(:sample_archives) do
    {
      "2024-01-10_docs_report" => { "path" => "/docs/report.pdf", "size" => 204_800, "hash" => "aabb", "source_dir" => "/docs" },
      "2024-02-15_docs_notes" => { "path" => "/docs/notes.txt", "size" => 1024, "hash" => "ccdd", "source_dir" => "/docs" },
      "2024-03-01_photos_img1" => { "path" => "/photos/IMG_001.jpg", "size" => 3_145_728, "hash" => "eeff", "source_dir" => "/photos" },
      "2024-03-02_photos_img2" => { "path" => "/photos/IMG_002.jpg", "size" => 2_097_152, "hash" => "1122", "source_dir" => "/photos" },
      "2024-04-01_docs_report" => { "path" => "/docs/report.pdf", "size" => 212_992, "hash" => "3344", "source_dir" => "/docs" }
    }
  end
  let(:cache_path) { "#{repo_path}.ruborg_cache.json" }

  def write_cache(archives)
    File.write(cache_path, JSON.generate({ "version" => 1, "archives" => archives }))
  end

  before { write_cache(sample_archives) }

  describe "#list" do
    it "returns all entries" do
      expect(catalog.list.size).to eq(5)
    end

    it "returns entries sorted by file path" do
      paths = catalog.list.map { |e| e[:path] }
      expect(paths).to eq(paths.sort)
    end

    it "includes :archive_name in each entry" do
      expect(catalog.list).to all(have_key(:archive_name))
    end

    it "includes :path, :size, :hash, :source_dir with symbol keys" do
      entry = catalog.list.first
      expect(entry).to include(:path, :size, :hash, :source_dir)
    end

    context "when cache is empty" do
      before { write_cache({}) }

      it "returns an empty array" do
        expect(catalog.list).to eq([])
      end
    end

    context "when no cache file exists" do
      before { FileUtils.rm_f(cache_path) }

      it "returns an empty array" do
        expect(catalog.list).to eq([])
      end
    end
  end

  describe "#search" do
    it "returns entries matching the regex pattern" do
      results = catalog.search(%r{/photos/})
      expect(results.size).to eq(2)
      expect(results.map { |e| e[:path] }).to all(match(%r{/photos/}))
    end

    it "accepts a regex string" do
      results = catalog.search("/docs/")
      expect(results.size).to eq(3)
    end

    it "accepts a Regexp object" do
      results = catalog.search(/\.pdf$/)
      expect(results.size).to eq(2)
      expect(results.map { |e| e[:path] }).to all(end_with(".pdf"))
    end

    it "returns empty array when no entries match" do
      expect(catalog.search("/nonexistent/")).to eq([])
    end

    it "supports anchored patterns" do
      results = catalog.search(%r{\A/docs/notes})
      expect(results.size).to eq(1)
      expect(results.first[:path]).to eq("/docs/notes.txt")
    end

    it "finds all versions of the same file path" do
      results = catalog.search(/report\.pdf$/)
      expect(results.size).to eq(2)
      archive_names = results.map { |e| e[:archive_name] }
      expect(archive_names).to contain_exactly("2024-01-10_docs_report", "2024-04-01_docs_report")
    end

    it "raises CatalogError on invalid regex" do
      expect { catalog.search("[invalid") }.to raise_error(Ruborg::CatalogError, /Invalid regex/)
    end
  end

  describe "#stats" do
    it "returns total_archives count" do
      expect(catalog.stats[:total_archives]).to eq(5)
    end

    it "counts unique file paths" do
      # /docs/report.pdf appears twice (two archive versions)
      expect(catalog.stats[:unique_paths]).to eq(4)
    end

    it "sums total size across all archives" do
      expected = 204_800 + 1024 + 3_145_728 + 2_097_152 + 212_992
      expect(catalog.stats[:total_size]).to eq(expected)
    end

    it "counts distinct non-empty source directories" do
      expect(catalog.stats[:source_dirs]).to eq(2)
    end

    context "when cache is empty" do
      before { write_cache({}) }

      it "returns zeros" do
        expect(catalog.stats).to eq(total_archives: 0, unique_paths: 0, total_size: 0, source_dirs: 0)
      end
    end
  end
end
