# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

module RubyToFaster
  # Parallel native extension compiler (`ext/**/extconf.rb`) across CPU cores.
  class ExtensionBuilder
    ExtensionResult = Struct.new(:extconf_path, :duration_ms, :status, keyword_init: true)

    def initialize(config)
      @config   = config
      @root_dir = config.root_dir
      @jobs     = config.parallel_jobs
    end

    def compile_all(spec)
      return [] if @config.skip_extensions

      extconfs = Array(spec.extensions).select { |ext| ext.end_with?("extconf.rb") }
      return [] if extconfs.empty?

      queue = Queue.new
      extconfs.each { |ext| queue << ext }

      results = []
      errors  = []
      mutex   = Mutex.new

      worker_count = [@jobs, extconfs.size].min
      workers = Array.new(worker_count) do
        Thread.new do
          loop do
            ext_rel = begin
              queue.pop(true)
            rescue ThreadError
              break
            end

            begin
              res = compile_single(ext_rel)
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

    def compile_single(ext_rel)
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
      ExtensionResult.new(extconf_path: ext_rel, duration_ms: elapsed, status: :ok)
    end
  end
end
