# frozen_string_literal: true

require "json"
require_relative "base"

module RubyToFaster
  module Resources
    # Resource adapter for SvelteKit (`build/` static adapter or `.svelte-kit/output/client/`).
    class SvelteKit < Base
      CONFIG_FILES = %w[
        svelte.config.js
        svelte.config.mjs
        svelte.config.cjs
        svelte.config.ts
      ].freeze

      def self.detect?(dir)
        return true if CONFIG_FILES.any? { |cfg| File.file?(File.join(dir, cfg)) }

        pkg_json = File.join(dir, "package.json")
        return false unless File.file?(pkg_json)

        content = File.read(pkg_json)
        content.include?('"@sveltejs/kit"') || content.include?('"svelte"')
      end

      def framework_name
        "SvelteKit"
      end

      def collect
        t0 = monotonic_ms
        run_build_command!(%w[run build])

        out_dir = resolve_output_dir
        staged, asset_map = stage_directory(out_dir, ignore_patterns: [%r{\A\.svelte-kit/cache(/|\z)}])
        entrypoints = extract_entrypoints(out_dir, asset_map)

        AdapterResult.new(
          framework: :sveltekit,
          root: workspace_dir,
          mount_to: mount_to,
          entries: staged,
          entrypoints: entrypoints,
          assets: asset_map,
          metadata: {
            out_dir: out_dir,
            immutable_chunks: asset_map.keys.count { |k| k.include?("_app/immutable/") },
            asset_count: asset_map.size
          },
          duration_ms: (monotonic_ms - t0).round(2)
        )
      end

      private

      def resolve_output_dir
        if @spec_config[:out_dir]
          return File.expand_path(@spec_config[:out_dir], workspace_dir)
        end

        build_dir = File.join(workspace_dir, "build")
        return build_dir if Dir.exist?(build_dir)

        client_dir = File.join(workspace_dir, ".svelte-kit", "output", "client")
        return client_dir if Dir.exist?(client_dir)

        build_dir
      end

      def extract_entrypoints(out_dir, asset_map)
        manifest_candidates = [
          File.join(out_dir, ".vite", "manifest.json"),
          File.join(workspace_dir, ".svelte-kit", "output", "client", ".vite", "manifest.json"),
          File.join(out_dir, "manifest.json")
        ]
        manifest_path = manifest_candidates.find { |p| File.file?(p) }
        if manifest_path
          parsed = parse_vite_manifest(manifest_path)
          return parsed unless parsed.empty?
        end

        entrypoints = {}
        css_files = asset_map.keys.select { |k| k.end_with?(".css") }.sort
        js_files  = asset_map.keys.select { |k| k.end_with?(".js") }.sort

        if asset_map.key?("index.html")
          entrypoints["index"] = {
            file: "index.html",
            gem_path: File.join(mount_to, "index.html"),
            css: css_files,
            scripts: js_files,
            is_entry: true
          }
        end

        js_files.select { |f| f.include?("entry/") || f.include?("start.") }.each do |js_rel|
          entrypoints[File.basename(js_rel)] = {
            file: js_rel,
            gem_path: File.join(mount_to, js_rel),
            css: css_files,
            scripts: [js_rel],
            is_entry: true
          }
        end

        entrypoints
      end

      def parse_vite_manifest(path)
        data = JSON.parse(File.read(path))
        entrypoints = {}
        data.each do |src, meta|
          next unless meta.is_a?(Hash) && meta["isEntry"]

          file = meta["file"]
          next unless file

          entrypoints[src] = {
            file: file,
            gem_path: File.join(mount_to, file),
            css: Array(meta["css"]),
            scripts: [file],
            is_entry: true
          }
        end
        entrypoints
      rescue JSON::ParserError
        {}
      end
    end
  end
end
