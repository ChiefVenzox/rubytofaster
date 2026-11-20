# frozen_string_literal: true

require_relative "base"

module RubyToFaster
  module Resources
    # Resource adapter for Nuxt 3/4 static builds (`.output/public/` or `dist/`).
    class Nuxt < Base
      CONFIG_FILES = %w[
        nuxt.config.ts
        nuxt.config.js
        nuxt.config.mjs
        nuxt.config.cjs
      ].freeze

      def self.detect?(dir)
        return true if CONFIG_FILES.any? { |cfg| File.file?(File.join(dir, cfg)) }

        pkg_json = File.join(dir, "package.json")
        return false unless File.file?(pkg_json)

        File.read(pkg_json).include?('"nuxt"')
      end

      def framework_name
        "Nuxt"
      end

      def collect
        t0 = monotonic_ms
        run_build_command!(%w[run generate])

        out_dir = resolve_output_dir
        staged, asset_map = stage_directory(out_dir, ignore_patterns: [%r{\A\.nuxt(/|\z)}])
        entrypoints = extract_entrypoints(asset_map)

        AdapterResult.new(
          framework: :nuxt,
          root: workspace_dir,
          mount_to: mount_to,
          entries: staged,
          entrypoints: entrypoints,
          assets: asset_map,
          metadata: {
            out_dir: out_dir,
            nuxt_chunks: asset_map.keys.count { |k| k.start_with?("_nuxt/") },
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

        output_public = File.join(workspace_dir, ".output", "public")
        return output_public if Dir.exist?(output_public)

        File.join(workspace_dir, "dist")
      end

      def extract_entrypoints(asset_map)
        entrypoints = {}
        css_files = asset_map.keys.select { |k| k.start_with?("_nuxt/") && k.end_with?(".css") }.sort
        js_files  = asset_map.keys.select { |k| k.start_with?("_nuxt/") && k.end_with?(".js", ".mjs") }.sort

        entry_js = js_files.find { |f| File.basename(f).start_with?("entry") } || js_files.first
        if entry_js
          entrypoints["entry"] = {
            file: entry_js,
            gem_path: File.join(mount_to, entry_js),
            css: css_files,
            scripts: [entry_js],
            is_entry: true
          }
        end

        asset_map.each_key do |rel|
          next unless rel.end_with?(".html")

          route = rel == "index.html" ? "/" : "/#{rel.sub(%r{/index\.html\z}, '').sub(/\.html\z/, '')}"
          entrypoints[route] = {
            file: rel,
            gem_path: File.join(mount_to, rel),
            css: css_files,
            scripts: entry_js ? [entry_js] : js_files,
            is_entry: true
          }
        end

        entrypoints
      end
    end
  end
end
