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
  end
end
