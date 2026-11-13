# frozen_string_literal: true

require "test_helper"

class TestCacheAndIncremental < Minitest::Test
  def test_merkle_cache_hit_and_invalidation_on_content_change
    Dir.mktmpdir("rtf-cache-test-") do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      lib_file = File.join(dir, "lib/sample.rb")
      File.write(lib_file, "module Sample; X = 1; end\n")

      build_fn = lambda do
        RubyToFaster.build(root_dir: dir, report: false) do |pkg|
          pkg.incremental = true
          pkg.spec do |s|
            s.name    = "cached_gem"
            s.version = "0.1.0"
            s.summary = "Incremental cache verification"
            s.authors = ["HNM Labs"]
            s.files   = ["lib/sample.rb"]
          end
        end
      end

      first = build_fn.call
      refute first.cache_hit

      # Remove pkg/ output and confirm second run restores directly from .rtf-cache
      FileUtils.rm_rf(File.join(dir, "pkg"))
      second = build_fn.call
      assert second.cache_hit
      assert_equal first.cache_key, second.cache_key
      assert_equal first.gem_sha256, second.gem_sha256
      assert File.file?(second.gem_path)

      # Modify source file and confirm cache invalidates cleanly
      File.write(lib_file, "module Sample; X = 2; end\n")
      third = build_fn.call
      refute third.cache_hit
      refute_equal first.cache_key, third.cache_key
      refute_equal first.gem_sha256, third.gem_sha256
    end
  end
end
