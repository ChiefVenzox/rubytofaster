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
require_relative "rubytofaster/extension_builder"
require_relative "rubytofaster/budget"
require_relative "rubytofaster/packager"
require_relative "rubytofaster/inspector"
require_relative "rubytofaster/installer"
require_relative "rubytofaster/differ"
require_relative "rubytofaster/checker"
require_relative "rubytofaster/benchmarker"
require_relative "rubytofaster/compiler"
require_relative "rubytofaster/reporter"
require_relative "rubytofaster/cli"

# RubyToFaster: Minimalist, script-first build system for Ruby gems
# with native resource pipelines for Angular, Vite, Next.js, Tailwind CSS, and Esbuild.
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
