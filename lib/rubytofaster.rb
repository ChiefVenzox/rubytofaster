# frozen_string_literal: true

require_relative "rubytofaster/version"
require_relative "rubytofaster/errors"
require_relative "rubytofaster/config"
require_relative "rubytofaster/plugin"
require_relative "rubytofaster/file_resolver"
require_relative "rubytofaster/cache"
require_relative "rubytofaster/asset_manifest"
require_relative "rubytofaster/resources/base"
require_relative "rubytofaster/resources/vite"
require_relative "rubytofaster/resources/nextjs"
require_relative "rubytofaster/resources/angular"
require_relative "rubytofaster/resources/tailwind"
require_relative "rubytofaster/resources/esbuild"
require_relative "rubytofaster/resources/astro"
require_relative "rubytofaster/resources/sveltekit"
require_relative "rubytofaster/resources/nuxt"
require_relative "rubytofaster/resources/webpack"
require_relative "rubytofaster/resources/parcel"
require_relative "rubytofaster/resources/sass"
require_relative "rubytofaster/extension_builder"
require_relative "rubytofaster/budget"
require_relative "rubytofaster/packager"
require_relative "rubytofaster/inspector"
require_relative "rubytofaster/installer"
require_relative "rubytofaster/differ"
require_relative "rubytofaster/checker"
require_relative "rubytofaster/benchmarker"
require_relative "rubytofaster/sbom"
require_relative "rubytofaster/analyzer"
require_relative "rubytofaster/verifier"
require_relative "rubytofaster/workspace"
require_relative "rubytofaster/compiler"
require_relative "rubytofaster/reporter"
require_relative "rubytofaster/cli"

# RubyToFaster: Minimalist, script-first build system for Ruby gems
# with native resource pipelines for 11 frontend frameworks/bundlers,
# parallel C & Rust extensions, SBOM generation, and monorepo workspaces.
module RubyToFaster
  class << self
    attr_accessor :pending_script_capture

    # Executes a gem build directly from a Ruby script or caller.
    # When invoked inside `rtf build gem.build.rb`, captures the Config object so CLI flags apply cleanly.
    def build(root_dir: Dir.pwd, report: nil, out: $stdout)
      config = Config.new(root_dir: root_dir)
      yield(config) if block_given?

      if @pending_script_capture
        @pending_script_capture.call(config)
        return nil
      end

      result = Compiler.new(config).run
      should_report = report.nil? ? !config.quiet : report
      Reporter.new(io: out, quiet: !should_report, verbose: config.verbose).report_build(result) if should_report
      result
    end

    # Defines a reusable Config object without immediately running the compiler.
    def define(root_dir: Dir.pwd)
      config = Config.new(root_dir: root_dir)
      yield(config) if block_given?
      if @pending_script_capture
        @pending_script_capture.call(config)
      end
      config
    end

    # Inspects and verifies an existing `.gem` file without extracting to disk.
    def inspect_gem(gem_path)
      Inspector.inspect_gem(gem_path)
    end

    # Diffs two compiled `.gem` files in-memory.
    def diff(gem_a_path, gem_b_path)
      Differ.diff(gem_a_path, gem_b_path)
    end

    # Audits project gemspec, supply-chain security, and executables.
    def check(root_dir: Dir.pwd, config: nil)
      cfg = config || Config.new(root_dir: root_dir)
      Checker.new(cfg).audit
    end

    # Benchmarks RubyToFaster vs standard gem build.
    def benchmark(root_dir: Dir.pwd, config: nil, iterations: 3)
      cfg = config || Config.new(root_dir: root_dir)
      Benchmarker.new(cfg, iterations: iterations).run
    end

    # Generates a CycloneDX 1.5 or SPDX 2.3 JSON SBOM for a project.
    def sbom(root_dir: Dir.pwd, config: nil, format: :cyclonedx)
      cfg = config || Config.new(root_dir: root_dir)
      resolver = FileResolver.new(cfg)
      spec, _ = resolver.load_gemspec
      entries, _ = resolver.resolve_entries(spec)
      epoch = cfg.source_date_epoch || (cfg.reproducible ? Packager::DEFAULT_EPOCH : nil)
      SBOM.new(spec: spec, entries: entries, reproducible_epoch: epoch).to_json_pretty(format: format)
    end

    # Analyzes package composition and file size distribution for a `.gem` archive.
    def stats(gem_path, top: 10)
      Analyzer.analyze(gem_path, top: top)
    end

    # Verifies cryptographic integrity (and optional expected SHA-256) of a `.gem` archive.
    def verify(gem_path, expected_sha256: nil)
      Verifier.verify_gem(gem_path, expected_sha256: expected_sha256)
    end

    # Creates a monorepo multi-gem Workspace handle.
    def workspace(root_dir: Dir.pwd, patterns: nil)
      Workspace.new(root_dir: root_dir, patterns: patterns)
    end

    # Installs a built `.gem` package into the local environment.
    def install(gem_path, options = {})
      Installer.new.install(gem_path, options)
    end

    # Loads a standalone compiler script (`gem.build.rb`) and captures its Config.
    def load_script_config(script_path)
      captured = nil
      script_dir = File.dirname(File.expand_path(script_path))

      prev_capture = @pending_script_capture
      @pending_script_capture = ->(cfg) { captured = cfg }

      Dir.chdir(script_dir) do
        Kernel.load(File.expand_path(script_path), true)
      end

      captured || Config.new(root_dir: script_dir)
    ensure
      @pending_script_capture = prev_capture
    end
  end
end
