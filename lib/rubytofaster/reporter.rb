# frozen_string_literal: true

require "json"

module RubyToFaster
  # Minimalist Vite/Next.js-style terminal build reporter.
  class Reporter
    def initialize(io: $stdout, json: false, quiet: false, verbose: false)
      @io      = io
      @json    = json
      @quiet   = quiet
      @verbose = verbose
    end

    def report_build(result)
      return if @quiet

      if @json
        @io.puts(JSON.pretty_generate(result.to_h))
        return
      end

      badge = result.cache_hit ? "[CACHE HIT]" : "[BUILT]"
      @io.puts "RubyToFaster v#{RubyToFaster::VERSION} #{badge} #{result.gem_name} (#{result.gem_version})"
      @io.puts "  Artifact   : #{result.gem_path}"
      @io.puts format(
        "  Size       : %.2f KB compressed / %.2f KB unpacked (%d files, %d pruned)",
        result.compressed_bytes / 1024.0,
        result.unpacked_bytes / 1024.0,
        result.entry_count,
        result.pruned_count
      )
      @io.puts "  SHA-256    : #{result.gem_sha256}"

      unless result.resources.empty?
        res_summary = result.resources.map do |r|
          "#{r.framework}(#{r.assets.size} assets -> #{r.mount_to}, #{r.duration_ms}ms)"
        end.join(", ")
        @io.puts "  Resources  : #{res_summary}"
      end

      unless result.extensions.empty?
        ext_summary = result.extensions.map { |e| "#{e.extconf_path} (#{e.duration_ms}ms)" }.join(", ")
        @io.puts "  Extensions : #{ext_summary}"
      end

      if @verbose && result.timings_ms
        stages = result.timings_ms.map { |k, v| "#{k}=#{v}ms" }.join(" ")
        @io.puts "  Timings    : #{stages}"
      end

      result.budget_warnings.each do |warn_msg|
        @io.puts "  Warning    : #{warn_msg}"
      end

      @io.puts format("  Done in %.2fms", result.total_ms)
    end

    def report_inspection(info)
      if @json
        @io.puts(JSON.pretty_generate(info))
        return
      end

      @io.puts "Package: #{info[:name]} v#{info[:version]} (#{info[:platform]})"
      @io.puts "  Summary    : #{info[:summary]}"
      @io.puts "  License    : #{Array(info[:licenses]).join(', ')}"
      @io.puts "  Ruby Req   : #{info[:required_ruby_version]}"
      @io.puts format(
        "  Payload    : %.2f KB compressed / %.2f KB unpacked (%d entries)",
        info[:compressed_bytes] / 1024.0,
        info[:unpacked_bytes] / 1024.0,
        info[:entry_count]
      )
      @io.puts "  SHA-256    : #{info[:sha256]} (checksums verified: #{info[:checksums_verified]})"

      unless info[:frontend_manifests].empty?
        @io.puts "  Frontend   :"
        info[:frontend_manifests].each do |path, data|
          fws = (data["frameworks"] || {}).keys.join(", ")
          @io.puts "    - #{path} [frameworks: #{fws}]"
        end
      end

      @io.puts "  Files      :"
      info[:entries].each do |entry|
        @io.puts format("    %s  %8d B  %s", entry[:mode], entry[:size], entry[:path])
      end
    end

    def report_install(result)
      return if @quiet

      if @json
        @io.puts(JSON.pretty_generate(result.to_h))
        return
      end

      if result.success
        @io.puts "RubyToFaster [INSTALLED] #{result.gem_name} (#{result.gem_version})"
        @io.puts "  Package    : #{result.gem_path}"
        @io.puts format("  Done in %.2fms", result.duration_ms)
      else
        @io.puts "RubyToFaster [INSTALL FAILED] #{result.gem_name} (#{result.gem_version})"
        @io.puts "  Error      : #{result.stderr.strip}"
      end
    end

    def report_diff(diff)
      return if @quiet

      if @json
        @io.puts(JSON.pretty_generate(diff.to_h))
        return
      end

      @io.puts "RubyToFaster Package Diff:"
      @io.puts "  Target A   : #{diff.gem_a_path}"
      @io.puts "  Target B   : #{diff.gem_b_path}"

      if diff.identical?
        @io.puts "  Result     : Packages are structurally and cryptographically IDENTICAL."
        return
      end

      unless diff.metadata_diff.empty?
        @io.puts "  Metadata Changes:"
        diff.metadata_diff.each do |k, v|
          @io.puts "    - #{k}: #{v[:from].inspect} -> #{v[:to].inspect}"
        end
      end

      comp_sign = diff.compressed_diff_bytes >= 0 ? "+" : ""
      unp_sign  = diff.unpacked_diff_bytes >= 0 ? "+" : ""
      @io.puts format(
        "  Size Delta : %s%.2f KB compressed (%d -> %d B) | %s%.2f KB unpacked (%d -> %d B)",
        comp_sign, diff.compressed_diff_bytes / 1024.0, diff.compressed_bytes_a, diff.compressed_bytes_b,
        unp_sign, diff.unpacked_diff_bytes / 1024.0, diff.unpacked_bytes_a, diff.unpacked_bytes_b
      )

      unless diff.added_entries.empty?
        @io.puts "  Added Files (#{diff.added_entries.size}):"
        diff.added_entries.each do |e|
          @io.puts format("    + %s (%d B, %s)", e[:path], e[:size], e[:mode])
        end
      end

      unless diff.removed_entries.empty?
        @io.puts "  Removed Files (#{diff.removed_entries.size}):"
        diff.removed_entries.each do |e|
          @io.puts format("    - %s (%d B)", e[:path], e[:size])
        end
      end

      unless diff.modified_entries.empty?
        @io.puts "  Modified Files (#{diff.modified_entries.size}):"
        diff.modified_entries.each do |e|
          delta_sign = e[:size_diff] >= 0 ? "+" : ""
          mode_note = e[:old_mode] != e[:new_mode] ? " [mode: #{e[:old_mode]} -> #{e[:new_mode]}]" : ""
          @io.puts format("    ~ %s (%s%d B -> %d B)%s", e[:path], delta_sign, e[:size_diff], e[:new_size], mode_note)
        end
      end

      @io.puts "  Unchanged  : #{diff.unchanged_count} files"
    end

    def report_check(report)
      return if @quiet

      if @json
        @io.puts(JSON.pretty_generate(report.to_h))
        return
      end

      status_label = report.passed? ? "[PASS]" : "[FAIL]"
      @io.puts "RubyToFaster Audit #{status_label} #{report.gem_name} (#{report.gem_version})"
      @io.puts "  Checks Run : #{report.checks_run}"

      if report.clean?
        @io.puts "  Result     : All supply-chain, security, executable, and gemspec checks passed with 0 warnings."
        return
      end

      @io.puts format("  Summary    : %d error(s), %d warning(s)", report.fails.size, report.warnings.size)
      report.issues.each do |issue|
        prefix = case issue.level
                 when :fail then "  [ERROR]"
                 when :warn then "  [WARN] "
                 else            "  [INFO] "
                 end
        @io.puts "#{prefix} [#{issue.category}] #{issue.message}"
      end
    end

    def report_benchmark(report)
      return if @quiet

      if @json
        @io.puts(JSON.pretty_generate(report.to_h))
        return
      end

      @io.puts "RubyToFaster Benchmark (#{report.gem_name} v#{report.gem_version}, #{report.iterations} iterations):"
      @io.puts format("  Standard `gem build`       : %6.2f ms (min: %.2fms, max: %.2fms)", report.standard_stats[:avg], report.standard_stats[:min], report.standard_stats[:max])
      @io.puts format("  RubyToFaster Cold Build    : %6.2f ms (min: %.2fms, max: %.2fms) -> %5.1fx faster", report.cold_stats[:avg], report.cold_stats[:min], report.cold_stats[:max], report.speedup_cold)
      @io.puts format("  RubyToFaster Merkle Warm   : %6.2f ms (min: %.2fms, max: %.2fms) -> %5.1fx faster", report.warm_stats[:avg], report.warm_stats[:min], report.warm_stats[:max], report.speedup_warm)
    end
  end
end
