# frozen_string_literal: true

require "fileutils"
require "rubygems/package"
require "tmpdir"
require_relative "compiler"
require_relative "config"

module RubyToFaster
  BenchmarkReport = Struct.new(
    :gem_name,
    :gem_version,
    :iterations,
    :cold_stats,
    :warm_stats,
    :standard_stats,
    :speedup_cold,
    :speedup_warm,
    keyword_init: true
  ) do
    def to_h
      super
    end
  end

  # Benchmarks RubyToFaster (cold & warm cache hits) against standard RubyGems `gem build`.
  class Benchmarker
    def initialize(config, iterations: 3)
      @config = config
      @iterations = [iterations.to_i, 1].max
    end

    def run
      resolver = FileResolver.new(@config)
      spec, _ = resolver.load_gemspec

      Dir.mktmpdir("rtf_bench_") do |tmp_dir|
        # 1. Warm-up and standard gem build benchmark
        standard_times = benchmark_standard_gem_build(spec, tmp_dir)

        # 2. RubyToFaster cold builds (no cache)
        cold_times = benchmark_rtf_cold(tmp_dir)

        # 3. RubyToFaster warm builds (incremental cache hits)
        warm_times = benchmark_rtf_warm(tmp_dir)

        cold_stats = compute_stats(cold_times)
        warm_stats = compute_stats(warm_times)
        std_stats  = compute_stats(standard_times)

        speedup_cold = (std_stats[:avg] / [cold_stats[:avg], 0.001].max).round(2)
        speedup_warm = (std_stats[:avg] / [warm_stats[:avg], 0.001].max).round(2)

        BenchmarkReport.new(
          gem_name: spec.name,
          gem_version: spec.version.to_s,
          iterations: @iterations,
          cold_stats: cold_stats,
          warm_stats: warm_stats,
          standard_stats: std_stats,
          speedup_cold: speedup_cold,
          speedup_warm: speedup_warm
        )
      end
    end

    private

    def benchmark_standard_gem_build(spec, tmp_dir)
      times = []
      out_target = File.join(tmp_dir, "standard_bench.gem")
      Dir.chdir(@config.root_dir) do
        @iterations.times do
          FileUtils.rm_f(out_target)
          t0 = monotonic_ms
          silence_io do
            Gem::Package.build(spec, true, false, out_target)
          end
          times << elapsed_since(t0)
        end
      end
      times
    end

    def silence_io
      orig_stdout = $stdout.dup
      orig_stderr = $stderr.dup
      $stdout.reopen(File::NULL)
      $stderr.reopen(File::NULL)
      yield
    ensure
      $stdout.reopen(orig_stdout)
      $stderr.reopen(orig_stderr)
      orig_stdout.close
      orig_stderr.close
    end

    def benchmark_rtf_cold(tmp_dir)
      times = []
      @iterations.times do |i|
        bench_cfg = @config.dup
        bench_cfg.out_dir = File.join(tmp_dir, "rtf_cold_#{i}")
        bench_cfg.cache_dir = File.join(tmp_dir, "rtf_cache_cold_#{i}")
        bench_cfg.incremental = false
        bench_cfg.quiet = true

        t0 = monotonic_ms
        Compiler.new(bench_cfg).run
        times << elapsed_since(t0)
      end
      times
    end

    def benchmark_rtf_warm(tmp_dir)
      warm_out = File.join(tmp_dir, "rtf_warm")
      warm_cache = File.join(tmp_dir, "rtf_cache_warm")

      bench_cfg = @config.dup
      bench_cfg.out_dir = warm_out
      bench_cfg.cache_dir = warm_cache
      bench_cfg.incremental = true
      bench_cfg.quiet = true

      # Prime cache
      Compiler.new(bench_cfg).run

      times = []
      @iterations.times do
        t0 = monotonic_ms
        Compiler.new(bench_cfg).run
        times << elapsed_since(t0)
      end
      times
    end

    def compute_stats(times)
      avg = (times.sum / times.size).round(2)
      min = times.min.round(2)
      max = times.max.round(2)
      { avg: avg, min: min, max: max, times: times }
    end

    def monotonic_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
    end

    def elapsed_since(t0)
      (monotonic_ms - t0).round(2)
    end
  end
end
