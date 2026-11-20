# frozen_string_literal: true

require "json"

module RubyToFaster
  # Minimalist Vite/Next.js-style terminal build reporter with automatic TTY ANSI colors.
  class Reporter
    ANSI = {
      reset:   "\e[0m",
      bold:    "\e[1m",
      dim:     "\e[2m",
      red:     "\e[31m",
      green:   "\e[32m",
      yellow:  "\e[33m",
      blue:    "\e[34m",
      magenta: "\e[35m",
      cyan:    "\e[36m"
    }.freeze

    def initialize(io: $stdout, json: false, quiet: false, verbose: false, color: nil)
      @io      = io
      @json    = json
      @quiet   = quiet
      @verbose = verbose
      @color   = color.nil? ? tty_color_enabled?(io) : color
    end

    def report_build(result)
      return if @quiet

      if @json
        @io.puts(JSON.pretty_generate(result.to_h))
        return
      end

      badge = result.cache_hit ? paint("[CACHE HIT]", :cyan, :bold) : paint("[BUILT]", :green, :bold)
      @io.puts "#{paint("RubyToFaster v#{RubyToFaster::VERSION}", :magenta, :bold)} #{badge} #{result.gem_name} (#{result.gem_version})"
      @io.puts "  Artifact   : #{result.gem_path}"
      @io.puts format(
        "  Size       : %.2f KB compressed / %.2f KB unpacked (%d files, %d pruned)",
        result.compressed_bytes / 1024.0,
        result.unpacked_bytes / 1024.0,
        result.entry_count,
        result.pruned_count
      )
      @io.puts "  SHA-256    : #{paint(result.gem_sha256, :dim)}"

      unless result.resources.empty?
        res_summary = result.resources.map do |r|
          "#{r.framework}(#{r.assets.size} assets -> #{r.mount_to}, #{r.duration_ms}ms)"
        end.join(", ")
        @io.puts "  Resources  : #{res_summary}"
      end

      unless result.extensions.empty?
        ext_summary = result.extensions.map do |e|
          kind_tag = e.respond_to?(:kind) && e.kind ? "[#{e.kind}] " : ""
          "#{kind_tag}#{e.extconf_path} (#{e.duration_ms}ms)"
        end.join(", ")
        @io.puts "  Extensions : #{ext_summary}"
      end

      if @verbose && result.timings_ms
        stages = result.timings_ms.map { |k, v| "#{k}=#{v}ms" }.join(" ")
        @io.puts "  Timings    : #{stages}"
      end

      result.budget_warnings.each do |warn_msg|
        @io.puts "  #{paint('Warning', :yellow, :bold)}    : #{warn_msg}"
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
        @io.puts "RubyToFaster #{paint('[INSTALLED]', :green, :bold)} #{result.gem_name} (#{result.gem_version})"
        @io.puts "  Package    : #{result.gem_path}"
        @io.puts format("  Done in %.2fms", result.duration_ms)
      else
        @io.puts "RubyToFaster #{paint('[INSTALL FAILED]', :red, :bold)} #{result.gem_name} (#{result.gem_version})"
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
          @io.puts paint(format("    + %s (%d B, %s)", e[:path], e[:size], e[:mode]), :green)
        end
      end

      unless diff.removed_entries.empty?
        @io.puts "  Removed Files (#{diff.removed_entries.size}):"
        diff.removed_entries.each do |e|
          @io.puts paint(format("    - %s (%d B)", e[:path], e[:size]), :red)
        end
      end

      unless diff.modified_entries.empty?
        @io.puts "  Modified Files (#{diff.modified_entries.size}):"
        diff.modified_entries.each do |e|
          delta_sign = e[:size_diff] >= 0 ? "+" : ""
          mode_note = e[:old_mode] != e[:new_mode] ? " [mode: #{e[:old_mode]} -> #{e[:new_mode]}]" : ""
          @io.puts paint(format("    ~ %s (%s%d B -> %d B)%s", e[:path], delta_sign, e[:size_diff], e[:new_size], mode_note), :yellow)
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

      status_label = report.passed? ? paint("[PASS]", :green, :bold) : paint("[FAIL]", :red, :bold)
      @io.puts "RubyToFaster Audit #{status_label} #{report.gem_name} (#{report.gem_version})"
      @io.puts "  Checks Run : #{report.checks_run}"

      if report.clean?
        @io.puts "  Result     : All supply-chain, security, executable, and gemspec checks passed with 0 warnings."
        return
      end

      @io.puts format("  Summary    : %d error(s), %d warning(s)", report.fails.size, report.warnings.size)
      report.issues.each do |issue|
        prefix = case issue.level
                 when :fail then paint("  [ERROR]", :red, :bold)
                 when :warn then paint("  [WARN] ", :yellow, :bold)
                 else            paint("  [INFO] ", :cyan)
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

    def report_stats(stats)
      return if @quiet

      if @json
        @io.puts(JSON.pretty_generate(stats.to_h))
        return
      end

      @io.puts "RubyToFaster Package Stats: #{stats.gem_name} v#{stats.gem_version}"
      @io.puts format(
        "  Archive    : %.2f KB compressed / %.2f KB unpacked (%.1f%% compression, %d files)",
        stats.compressed_bytes / 1024.0,
        stats.unpacked_bytes / 1024.0,
        stats.compression_ratio,
        stats.entry_count
      )
      unless stats.frameworks.empty?
        @io.puts "  Frameworks : #{stats.frameworks.join(', ')}"
      end

      @io.puts "  By Directory:"
      stats.by_directory.each do |d|
        bar = ascii_bar(d[:percent], width: 20)
        @io.puts format("    %-18s %s %5.1f%%  (%7.2f KB, %d files)", d[:directory], bar, d[:percent], d[:bytes] / 1024.0, d[:count])
      end

      @io.puts "  By Extension:"
      stats.by_extension.first(8).each do |e|
        bar = ascii_bar(e[:percent], width: 20)
        @io.puts format("    %-18s %s %5.1f%%  (%7.2f KB, %d files)", e[:extension], bar, e[:percent], e[:bytes] / 1024.0, e[:count])
      end

      @io.puts "  Largest Files:"
      stats.largest_files.each do |f|
        @io.puts format("    %8.2f KB (%5.1f%%)  %s", f[:bytes] / 1024.0, f[:percent], f[:path])
      end
    end

    def report_verify(report)
      return if @quiet

      if @json
        @io.puts(JSON.pretty_generate(report.to_h))
        return
      end

      badge = report.passed? ? paint("[VERIFIED]", :green, :bold) : paint("[FAILED]", :red, :bold)
      @io.puts "RubyToFaster Verify #{badge} #{report.gem_name} (#{report.gem_version})"
      @io.puts "  Checksums  : #{report.checksums_valid ? 'valid (SHA-256 & SHA-512)' : 'INVALID'}"
      @io.puts "  SHA-256    : #{report.sha256}"
      if report.expected_sha256
        @io.puts "  Expected   : #{report.expected_sha256} (match: #{report.sha256_match})"
      end
      if report.reproducible_checked
        @io.puts "  Repro Build: #{report.reproducible_match ? 'BIT-FOR-BIT IDENTICAL' : 'MISMATCH'} (#{report.rebuild_sha256})"
      end
      report.errors.each do |err|
        @io.puts "  #{paint('[ERROR]', :red, :bold)} #{err}"
      end
    end

    def report_workspace(report)
      return if @quiet

      if @json
        @io.puts(JSON.pretty_generate(report.to_h))
        return
      end

      badge = report.success? ? paint("[OK]", :green, :bold) : paint("[FAILED]", :red, :bold)
      @io.puts "RubyToFaster Workspace #{report.action.to_s.upcase} #{badge} (#{report.members.size} gems in #{report.total_ms}ms)"
      report.members.each do |m|
        st = m.status == :ok ? paint("OK  ", :green) : paint("FAIL", :red)
        detail = if m.status == :ok && m.result.is_a?(BuildResult)
                   cache_note = m.result.cache_hit ? "cache hit" : "built"
                   format("%.2f KB [%s]", m.result.compressed_bytes / 1024.0, cache_note)
                 elsif m.error
                   m.error
                 else
                   "done"
                 end
        @io.puts format("  [%s] %-24s %7.2f ms  %s", st, m.name, m.duration_ms, detail)
      end
    end

    private

    def ascii_bar(percent, width: 20)
      filled = ((percent.to_f / 100.0) * width).round
      filled = [[filled, 0].max, width].min
      "[#{'#' * filled}#{'.' * (width - filled)}]"
    end

    def tty_color_enabled?(io)
      return false if ENV["NO_COLOR"] && !ENV["NO_COLOR"].empty?

      io.respond_to?(:tty?) && io.tty?
    end

    def paint(text, *styles)
      return text unless @color

      codes = styles.map { |s| ANSI[s] }.compact.join
      "#{codes}#{text}#{ANSI[:reset]}"
    end
  end
end
