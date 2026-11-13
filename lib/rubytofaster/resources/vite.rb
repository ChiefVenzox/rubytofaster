# frozen_string_literal: true

require "json"
require_relative "base"

module RubyToFaster
  module Resources
    # Resource adapter for Vite (v4/v5/v6+) frontend bundles and `.vite/manifest.json`.
    class Vite < Base
      CONFIG_FILES = %w[vite.config.ts vite.config.js vite.config.mjs vite.config.cjs].freeze
      MANIFEST_CANDIDATES = %w[.vite/manifest.json manifest.json].freeze

      def self.detect?(dir)
        CONFIG_FILES.any? { |cfg| File.file?(File.join(dir, cfg)) }
      end

      def framework_name
        "Vite"
      end

      def collect
        t0 = monotonic_ms
        run_build_command!(["exec", "vite", "build"])

        out_dir = File.expand_path(@spec_config[:out_dir] || "dist", workspace_dir)
        staged, asset_map = stage_directory(out_dir)

        manifest_data = load_vite_manifest(out_dir)
        entrypoints   = extract_entrypoints(manifest_data)

        AdapterResult.new(
          framework: :vite,
          root: workspace_dir,
          mount_to: mount_to,
          entries: staged,
          entrypoints: entrypoints,
          assets: asset_map,
          metadata: {
            out_dir: out_dir,
            manifest_found: !manifest_data.nil?,
            chunk_count: asset_map.size
          },
          duration_ms: (monotonic_ms - t0).round(2)
        )
      end

      private

      def load_vite_manifest(out_dir)
        MANIFEST_CANDIDATES.each do |rel|
          candidate = File.join(out_dir, rel)
          return JSON.parse(File.read(candidate)) if File.file?(candidate)
        end
        nil
      rescue JSON::ParserError => e
        raise BuildError, "Invalid Vite manifest JSON in #{out_dir}: #{e.message}"
      end

      def extract_entrypoints(manifest)
        return {} unless manifest.is_a?(Hash)

        points = {}
        manifest.each do |source_key, chunk|
          next unless chunk.is_a?(Hash) && chunk["file"]

          points[source_key] = {
            file: chunk["file"],
            gem_path: File.join(mount_to, chunk["file"]),
            css: Array(chunk["css"]),
            imports: Array(chunk["imports"]),
            is_entry: chunk.fetch("isEntry", false)
          }
        end
        points
      end
    end
  end
end
