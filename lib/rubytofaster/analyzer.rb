# frozen_string_literal: true

require_relative "inspector"

module RubyToFaster
  # Deep in-memory package composition & size analyzer (`rtf stats` / `RubyToFaster.stats`).
  class Analyzer
    StatsReport = Struct.new(
      :gem_path,
      :gem_name,
      :gem_version,
      :compressed_bytes,
      :unpacked_bytes,
      :compression_ratio,
      :entry_count,
      :by_extension,
      :by_directory,
      :largest_files,
      :frameworks,
      keyword_init: true
    ) do
      def to_h
        {
          gem_path: gem_path,
          gem_name: gem_name,
          gem_version: gem_version,
          compressed_bytes: compressed_bytes,
          unpacked_bytes: unpacked_bytes,
          compression_ratio: compression_ratio,
          entry_count: entry_count,
          by_extension: by_extension,
          by_directory: by_directory,
          largest_files: largest_files,
          frameworks: frameworks
        }
      end
    end

    def self.analyze(gem_path, top: 10)
      info = Inspector.inspect_gem(gem_path)
      entries = info[:entries]
      unpacked = info[:unpacked_bytes]
      compressed = info[:compressed_bytes]
      ratio = unpacked.positive? ? (100.0 * (1.0 - (compressed.to_f / unpacked))).round(2) : 0.0

      ext_buckets = Hash.new { |h, k| h[k] = { count: 0, bytes: 0 } }
      dir_buckets = Hash.new { |h, k| h[k] = { count: 0, bytes: 0 } }

      entries.each do |entry|
        path = entry[:path]
        size = entry[:size]

        ext = File.extname(path).downcase
        ext = "(no ext)" if ext.empty?
        ext_buckets[ext][:count] += 1
        ext_buckets[ext][:bytes] += size

        top_dir = path.include?("/") ? path.split("/").first : "(root)"
        dir_buckets[top_dir][:count] += 1
        dir_buckets[top_dir][:bytes] += size
      end

      sorted_ext = ext_buckets.map do |ext, data|
        pct = unpacked.positive? ? ((data[:bytes].to_f / unpacked) * 100.0).round(1) : 0.0
        { extension: ext, count: data[:count], bytes: data[:bytes], percent: pct }
      end.sort_by { |e| -e[:bytes] }

      sorted_dir = dir_buckets.map do |dir, data|
        pct = unpacked.positive? ? ((data[:bytes].to_f / unpacked) * 100.0).round(1) : 0.0
        { directory: dir, count: data[:count], bytes: data[:bytes], percent: pct }
      end.sort_by { |d| -d[:bytes] }

      largest = entries.sort_by { |e| -e[:size] }.first(top).map do |e|
        pct = unpacked.positive? ? ((e[:size].to_f / unpacked) * 100.0).round(1) : 0.0
        { path: e[:path], bytes: e[:size], mode: e[:mode], percent: pct }
      end

      fws = info[:frontend_manifests].values.flat_map { |m| (m["frameworks"] || {}).keys }.uniq.sort

      StatsReport.new(
        gem_path: info[:file],
        gem_name: info[:name],
        gem_version: info[:version],
        compressed_bytes: compressed,
        unpacked_bytes: unpacked,
        compression_ratio: ratio,
        entry_count: entries.size,
        by_extension: sorted_ext,
        by_directory: sorted_dir,
        largest_files: largest,
        frameworks: fws
      )
    end
  end
end
