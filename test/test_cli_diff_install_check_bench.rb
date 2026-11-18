# frozen_string_literal: true

require "test_helper"

class TestCliDiffInstallCheckBench < Minitest::Test
  def test_differ_detects_metadata_and_file_changes
    Dir.mktmpdir("rtf-diff-test-") do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/app.rb"), "module App; V = 1; end\n")

      gem_v1 = RubyToFaster.build(root_dir: dir, report: false) do |pkg|
        pkg.incremental = false
        pkg.spec do |s|
          s.name = "diffable"
          s.version = "1.0.0"
          s.summary = "Diff test gem"
          s.authors = ["HNM Labs"]
          s.license = "MIT"
          s.files = ["lib/app.rb"]
        end
      end

      # Identical check
      self_diff = RubyToFaster.diff(gem_v1.gem_path, gem_v1.gem_path)
      assert self_diff.identical?
      assert_equal 0, self_diff.added_entries.size
      assert_equal 0, self_diff.removed_entries.size
      assert_equal 0, self_diff.modified_entries.size

      # Modify app.rb and add lib/extra.rb for v1.1.0
      File.write(File.join(dir, "lib/app.rb"), "module App; V = 2; EXTRA_LINE = true; end\n")
      File.write(File.join(dir, "lib/extra.rb"), "module Extra; end\n")

      gem_v2 = RubyToFaster.build(root_dir: dir, report: false) do |pkg|
        pkg.incremental = false
        pkg.out_dir = "pkg_v2"
        pkg.spec do |s|
          s.name = "diffable"
          s.version = "1.1.0"
          s.summary = "Diff test gem updated"
          s.authors = ["HNM Labs"]
          s.license = "MIT"
          s.files = ["lib/app.rb", "lib/extra.rb"]
        end
      end

      diff = RubyToFaster.diff(gem_v1.gem_path, gem_v2.gem_path)
      refute diff.identical?
      assert_equal "1.0.0", diff.metadata_diff[:version][:from]
      assert_equal "1.1.0", diff.metadata_diff[:version][:to]
      assert diff.added_entries.any? { |e| e[:path] == "lib/extra.rb" }
      assert diff.modified_entries.any? { |e| e[:path] == "lib/app.rb" }
      assert_equal 0, diff.removed_entries.size

      # Test CLI diff output
      out = StringIO.new
      status = RubyToFaster::CLI.start(["diff", gem_v1.gem_path, gem_v2.gem_path, "--json"], out: out)
      assert_equal 0, status
      parsed = JSON.parse(out.string)
      assert_equal 1, parsed["added_count"]
      assert_equal 1, parsed["modified_count"]
    end
  end

  def test_checker_audits_gemspec_secrets_and_executables
    Dir.mktmpdir("rtf-check-test-") do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      FileUtils.mkdir_p(File.join(dir, "exe"))
      File.write(File.join(dir, "lib/tool.rb"), "module Tool; end\n")

      exe_path = File.join(dir, "exe/tool")
      File.write(exe_path, "#!/usr/bin/env ruby\nputs 'hello'\n")
      File.chmod(0o755, exe_path)

      gemspec_path = File.join(dir, "tool.gemspec")
      File.write(gemspec_path, <<~SPEC)
        Gem::Specification.new do |s|
          s.name = "tool"
          s.version = "0.1.0"
          s.summary = "Valid tool summary"
          s.authors = ["Developer"]
          s.license = "MIT"
          s.required_ruby_version = ">= 3.0"
          s.files = ["lib/tool.rb", "exe/tool"]
          s.executables = ["tool"]
        end
      SPEC

      cfg = RubyToFaster::Config.new(root_dir: dir)
      cfg.gemspec("tool.gemspec")
      report = RubyToFaster::Checker.new(cfg).audit

      assert report.passed?, "Expected audit to pass for valid gem"

      # Introduce missing license and broken executable shebang
      File.write(exe_path, "puts 'missing shebang'\n")
      File.chmod(0o644, exe_path)
      broken_spec = File.join(dir, "broken.gemspec")
      File.write(broken_spec, <<~SPEC)
        Gem::Specification.new do |s|
          s.name = "tool"
          s.version = "0.1.0"
          s.summary = "Valid tool summary"
          s.authors = ["Developer"]
          s.files = ["lib/tool.rb", "exe/tool"]
          s.executables = ["tool"]
        end
      SPEC

      cfg_broken = RubyToFaster::Config.new(root_dir: dir)
      cfg_broken.gemspec("broken.gemspec")
      broken_report = RubyToFaster::Checker.new(cfg_broken).audit

      refute broken_report.passed?, "Expected missing license to fail audit"
      assert broken_report.fails.any? { |i| i.category == :gemspec && i.message.include?("license") }
      assert broken_report.warnings.any? { |i| i.category == :executable && i.message.include?("shebang") }

      # Test CLI check output
      out = StringIO.new
      status = RubyToFaster::CLI.start(["check", broken_spec, "--json"], out: out)
      assert_equal 1, status
      parsed = JSON.parse(out.string)
      refute parsed["passed"]
      assert parsed["fail_count"] > 0
    end
  end

  def test_benchmarker_runs_and_measures_speedup
    Dir.mktmpdir("rtf-bench-test-") do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/bench.rb"), "module Bench; VALUE = 42; end\n")
      File.write(File.join(dir, "README.md"), "# Bench\n")

      gemspec_path = File.join(dir, "bench.gemspec")
      File.write(gemspec_path, <<~SPEC)
        Gem::Specification.new do |s|
          s.name = "benchgem"
          s.version = "0.1.0"
          s.summary = "Benchmark test"
          s.authors = ["Benchmarker"]
          s.license = "MIT"
          s.files = ["lib/bench.rb", "README.md"]
        end
      SPEC

      cfg = RubyToFaster::Config.new(root_dir: dir)
      cfg.gemspec("bench.gemspec")
      benchmarker = RubyToFaster::Benchmarker.new(cfg, iterations: 2)
      report = benchmarker.run

      assert_equal "benchgem", report.gem_name
      assert_equal 2, report.iterations
      assert report.cold_stats[:avg] > 0
      assert report.warm_stats[:avg] > 0
      assert report.standard_stats[:avg] > 0
      assert report.speedup_warm > 0

      # Test CLI bench output
      out = StringIO.new
      status = RubyToFaster::CLI.start(["bench", gemspec_path, "--iterations", "1", "--json"], out: out)
      assert_equal 0, status
      parsed = JSON.parse(out.string)
      assert_equal "benchgem", parsed["gem_name"]
      assert parsed.key?("speedup_warm")
    end
  end

  def test_installer_handles_missing_file_and_executes
    installer = RubyToFaster::Installer.new
    assert_raises(RubyToFaster::ConfigError) do
      installer.install("non_existent_file.gem")
    end
  end
end
