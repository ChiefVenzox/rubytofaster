# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

module RubyToFaster
  # Parallel native extension compiler supporting both C/C++ (`ext/**/extconf.rb`)
  # and Rust (`ext/**/Cargo.toml` via rb-sys/magnus) across CPU cores.
  class ExtensionBuilder
    ExtensionResult = Struct.new(:extconf_path, :duration_ms, :status, :kind, keyword_init: true)

    def initialize(config)
      @config   = config
      @root_dir = config.root_dir
      @jobs     = config.parallel_jobs
    end

    def compile_all(spec)
      return [] if @config.skip_extensions

      ext_targets = Array(spec.extensions).select do |ext|
        ext.end_with?("extconf.rb") || ext.end_with?("Cargo.toml")
      end
      return [] if ext_targets.empty?

      queue = Queue.new
      ext_targets.each { |ext| queue << ext }

      results = []
      errors  = []
      mutex   = Mutex.new

      worker_count = [@jobs, ext_targets.size].min
      workers = Array.new(worker_count) do
        Thread.new do
          loop do
            ext_rel = begin
              queue.pop(true)
            rescue ThreadError
              break
            end

            begin
              res = if ext_rel.end_with?("Cargo.toml")
                      compile_rust_extension(ext_rel)
                    else
                      compile_c_extension(ext_rel)
                    end
              mutex.synchronize { results << res }
            rescue StandardError => e
              mutex.synchronize { errors << e }
            end
          end
        end
      end

      workers.each(&:join)
      raise errors.first unless errors.empty?

      results.sort_by(&:extconf_path)
    end

    private

    def compile_c_extension(ext_rel)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
      full_extconf = File.expand_path(ext_rel, @root_dir)
      raise BuildError, "Native extension file not found: #{ext_rel}" unless File.file?(full_extconf)

      ext_dir = File.dirname(full_extconf)

      Dir.mktmpdir("rtf-ext-") do |work_dir|
        out1, err1, st1 = Open3.capture3(RbConfig.ruby, full_extconf, chdir: work_dir)
        unless st1.success?
          raise BuildError, "extconf.rb failed for #{ext_rel}:\n#{err1.empty? ? out1 : err1}"
        end

        make_bin = ENV["MAKE"] || (RbConfig::CONFIG["configure_args"]&.include?("gmake") ? "gmake" : "make")
        out2, err2, st2 = Open3.capture3(make_bin, "-j#{@jobs}", chdir: work_dir)
        unless st2.success?
          raise BuildError, "make failed for #{ext_rel}:\n#{err2.empty? ? out2 : err2}"
        end

        # Verify a shared object/bundle was produced in the isolated build directory
        dlext = RbConfig::CONFIG["DLEXT"] || "so"
        built_artifacts = Dir.glob(File.join(work_dir, "*.{#{dlext},so,bundle,dll}"))
        if built_artifacts.empty? && Dir.exist?(ext_dir)
          raise BuildError, "Native extension #{ext_rel} compiled without producing a shared library (.#{dlext})"
        end
      end

      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - t0).round(2)
      ExtensionResult.new(extconf_path: ext_rel, duration_ms: elapsed, status: :ok, kind: :c)
    end

    def compile_rust_extension(cargo_rel)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
      full_cargo = File.expand_path(cargo_rel, @root_dir)
      raise BuildError, "Rust extension Cargo.toml not found: #{cargo_rel}" unless File.file?(full_cargo)

      cargo_bin = ENV["CARGO"] || "cargo"
      Dir.mktmpdir("rtf-rust-ext-") do |target_dir|
        env = { "CARGO_TARGET_DIR" => target_dir }
        out, err, status = Open3.capture3(
          env,
          cargo_bin, "check",
          "--manifest-path", full_cargo,
          "--jobs", @jobs.to_s,
          chdir: @root_dir
        )
        unless status.success?
          raise BuildError, "cargo check failed for #{cargo_rel}:\n#{err.empty? ? out : err}"
        end
      end

      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - t0).round(2)
      ExtensionResult.new(extconf_path: cargo_rel, duration_ms: elapsed, status: :ok, kind: :rust)
    rescue Errno::ENOENT
      raise BuildError, "Cargo executable not found while verifying Rust extension: #{cargo_rel}"
    end
  end
end
