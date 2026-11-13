# frozen_string_literal: true

require "test_helper"

class TestBudgetAndSecurity < Minitest::Test
  def test_budget_exceeded_raises_and_near_budget_warns
    Dir.mktmpdir("rtf-budget-") do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      # Write ~20 KB incompressible random payload
      random_blob = Random.new(42).bytes(20 * 1024)
      File.binwrite(File.join(dir, "lib/blob.bin"), random_blob)

      assert_raises(RubyToFaster::BudgetExceededError) do
        RubyToFaster.build(root_dir: dir, report: false) do |pkg|
          pkg.budget max_unpacked_kb: 10
          pkg.spec do |s|
            s.name    = "heavy_gem"
            s.version = "0.1.0"
            s.summary = "Exceeds unpacked budget"
            s.authors = ["HNM Labs"]
            s.files   = ["lib/blob.bin"]
          end
        end
      end

      res = RubyToFaster.build(root_dir: dir, report: false) do |pkg|
        pkg.budget max_unpacked_kb: 22, warn_ratio: 0.80
        pkg.spec do |s|
          s.name    = "near_limit_gem"
          s.version = "0.1.0"
          s.summary = "Triggers warning near budget"
          s.authors = ["HNM Labs"]
          s.files   = ["lib/blob.bin"]
        end
      end

      assert_equal 1, res.budget_warnings.size
      assert_match(/approaching budget/, res.budget_warnings.first)
    end
  end

  def test_blocks_path_traversal_and_escaping_symlinks_and_string_shell_commands
    Dir.mktmpdir("rtf-sec-") do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/ok.rb"), "true\n")

      # 1. Path traversal in spec.files
      assert_raises(RubyToFaster::SecurityError) do
        RubyToFaster.build(root_dir: dir, report: false) do |pkg|
          pkg.spec do |s|
            s.name    = "bad_traversal"
            s.version = "0.1.0"
            s.summary = "Traversal test"
            s.authors = ["HNM Labs"]
            s.files   = ["../outside.rb"]
          end
        end
      end

      # 2. Escaping symlink
      Dir.mktmpdir("rtf-outside-") do |outside_dir|
        outside_secret = File.join(outside_dir, "secret.txt")
        File.write(outside_secret, "TOP_SECRET")
        File.symlink(outside_secret, File.join(dir, "lib/leak.txt"))

        assert_raises(RubyToFaster::SecurityError) do
          RubyToFaster.build(root_dir: dir, report: false) do |pkg|
            pkg.spec do |s|
              s.name    = "bad_symlink"
              s.version = "0.1.0"
              s.summary = "Symlink escape test"
              s.authors = ["HNM Labs"]
              s.files   = ["lib/leak.txt"]
            end
          end
        end
      end

      # 3. String build_command rejected to prevent shell injection
      FileUtils.mkdir_p(File.join(dir, "frontend/dist"))
      assert_raises(RubyToFaster::ConfigError) do
        RubyToFaster.build(root_dir: dir, report: false) do |pkg|
          pkg.vite root: "frontend", build_command: "npm run build && rm -rf /"
          pkg.spec do |s|
            s.name    = "bad_cmd"
            s.version = "0.1.0"
            s.summary = "Shell string rejection test"
            s.authors = ["HNM Labs"]
            s.files   = ["lib/ok.rb"]
          end
        end
      end
    end
  end

  def test_default_excludes_tree_shake_dotenv_and_node_modules
    Dir.mktmpdir("rtf-prune-") do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      FileUtils.mkdir_p(File.join(dir, "node_modules/pkg"))
      File.write(File.join(dir, "lib/clean.rb"), "module Clean; end\n")
      File.write(File.join(dir, ".env.production"), "DATABASE_URL=secret\n")
      File.write(File.join(dir, "private.pem"), "-----BEGIN PRIVATE KEY-----\n")
      File.write(File.join(dir, "node_modules/pkg/index.js"), "module.exports = {}\n")

      res = RubyToFaster.build(root_dir: dir, report: false) do |pkg|
        pkg.spec do |s|
          s.name    = "pruned_gem"
          s.version = "0.1.0"
          s.summary = "Tree-shaking test"
          s.authors = ["HNM Labs"]
          s.files   = ["lib/clean.rb", ".env.production", "private.pem", "node_modules/pkg/index.js"]
        end
      end

      assert_equal 1, res.entry_count
      assert_equal 3, res.pruned_count
      info = RubyToFaster.inspect_gem(res.gem_path)
      assert_equal ["lib/clean.rb"], info[:entries].map { |e| e[:path] }
    end
  end
end
