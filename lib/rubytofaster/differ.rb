# frozen_string_literal: true

require "digest"
require_relative "inspector"

module RubyToFaster
  # Immutable result representing the differences between two `.gem` archives.
  DiffResult = Struct.new(
    :gem_a_path,
    :gem_b_path,
    :metadata_diff,
    :added_entries,
    :removed_entries,
    :modified_entries,
    :unchanged_count,
    :compressed_bytes_a,
    :compressed_bytes_b,
    :compressed_diff_bytes,
    :unpacked_bytes_a,
    :unpacked_bytes_b,
    :unpacked_diff_bytes,
    keyword_init: true
  ) do
    def identical?
      metadata_diff.empty? &&
        added_entries.empty? &&
        removed_entries.empty? &&
        modified_entries.empty?
    end

    def to_h
      super.merge(
        identical: identical?,
        added_count: added_entries.size,
        removed_count: removed_entries.size,
        modified_count: modified_entries.size
      )
    end
  end

  # Performs deep in-memory semantic and structural diffs between two compiled `.gem` archives.
  class Differ
    def self.diff(gem_a_path, gem_b_path)
      new.diff(gem_a_path, gem_b_path)
    end

    def diff(gem_a_path, gem_b_path)
      info_a = Inspector.inspect_gem(gem_a_path)
      info_b = Inspector.inspect_gem(gem_b_path)

      meta_diff = compute_metadata_diff(info_a, info_b)
      entries_diff = compute_entries_diff(info_a[:entries], info_b[:entries])

      comp_a = info_a[:compressed_bytes]
      comp_b = info_b[:compressed_bytes]
      unp_a  = info_a[:unpacked_bytes]
      unp_b  = info_b[:unpacked_bytes]

      DiffResult.new(
        gem_a_path: info_a[:file],
        gem_b_path: info_b[:file],
        metadata_diff: meta_diff,
        added_entries: entries_diff[:added],
        removed_entries: entries_diff[:removed],
        modified_entries: entries_diff[:modified],
        unchanged_count: entries_diff[:unchanged_count],
        compressed_bytes_a: comp_a,
        compressed_bytes_b: comp_b,
        compressed_diff_bytes: comp_b - comp_a,
        unpacked_bytes_a: unp_a,
        unpacked_bytes_b: unp_b,
        unpacked_diff_bytes: unp_b - unp_a
      )
    end

    private

    def compute_metadata_diff(a, b)
      fields = %i[name version platform summary licenses required_ruby_version]
      diffs = {}
      fields.each do |f|
        val_a = a[f]
        val_b = b[f]
        if val_a != val_b
          diffs[f] = { from: val_a, to: val_b }
        end
      end
      diffs
    end

    def compute_entries_diff(entries_a, entries_b)
      map_a = entries_a.each_with_object({}) { |e, h| h[e[:path]] = e }
      map_b = entries_b.each_with_object({}) { |e, h| h[e[:path]] = e }

      all_paths = (map_a.keys | map_b.keys).sort

      added = []
      removed = []
      modified = []
      unchanged_count = 0

      all_paths.each do |path|
        in_a = map_a[path]
        in_b = map_b[path]

        if in_a && !in_b
          removed << in_a
        elsif !in_a && in_b
          added << in_b
        else
          size_diff = in_b[:size] - in_a[:size]
          mode_changed = in_a[:mode] != in_b[:mode]
          if size_diff != 0 || mode_changed
            modified << {
              path: path,
              old_size: in_a[:size],
              new_size: in_b[:size],
              size_diff: size_diff,
              old_mode: in_a[:mode],
              new_mode: in_b[:mode]
            }
          else
            unchanged_count += 1
          end
        end
      end

      {
        added: added,
        removed: removed,
        modified: modified,
        unchanged_count: unchanged_count
      }
    end
  end
end
