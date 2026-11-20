# frozen_string_literal: true

require_relative "base"

module RubyToFaster
  module Resources
    # Resource adapter for Astro static and hybrid client builds (`dist/` or `dist/client/`).
    class Astro < Base
      CONFIG_FILES = %w[
        astro.config.mjs
        astro.config.js
        astro.config.ts
        astro.config.cjs
      ].freeze

      def self.detect?(dir)
        return true if CONFIG_FILES.any? { |cfg| File.file?(File.join(dir, cfg)) }

        pkg_json = File.join(dir, "package.json")
        return false unless File.file?(pkg_json)

        File.read(pkg_json).include?('"astro"')
      end

      def framework_name
        "Astro"
      end

      def collect
        t0 = monotonic_ms
        run_build_command!(%w[run build])

        out_dir = resolve_output_dir
        staged, asset_map = stage_directory(out_dir, ignore_patterns: [%r{\A\.astro(/|\z)}])
        entrypoints = extract_entrypoints(asset_map)

        AdapterResult.new(
          framework: :astro,
          root: workspace_dir,
          mount_to: mount_to,
          entries: staged,
          entrypoints: entrypoints,
          assets: asset_map,
          metadata: {
            out_dir: out_dir,
            astro_chunks: asset_map.keys.count { |k| k.start_with?("_astro/") },
            pages: entrypoints.keys.select { |k| k.end_with?(".html") }.sort
          },
          duration_ms: (monotonic_ms - t0).round(2)
        )
      end

      private

      def resolve_output_dir
        if @spec_config[:out_dir]
          return File.expand_path(@spec_config[:out_dir], workspace_dir)
        end

        client_dir = File.join(workspace_dir, "dist", "client")
        return client_dir if Dir.exist?(client_dir)

        File.join(workspace_dir, "dist")
      end

      def extract_entrypoints(asset_map)
        entrypoints = {}
        css_files = asset_map.keys.select { |k| k.end_with?(".css") }.sort
        js_files  = asset_map.keys.select { |k| k.end_with?(".js", ".mjs") }.sort

        asset_map.each_key do |rel|
          if rel.end_with?(".html")
            route = rel == "index.html" ? "/" : "/#{rel.sub(%r{/index\.html\z}, '').sub(/\.html\z/, '')}"
            entrypoints[route] = {
              file: rel,
              gem_path: File.join(mount_to, rel),
              css: css_files,
              scripts: js_files,
              is_entry: true
            }
          elsif rel.start_with?("_astro/") && rel.end_with?(".js", ".css")
            name = File.basename(rel)
            entrypoints[name] = {
              file: rel,
              gem_path: File.join(mount_to, rel),
              css: rel.end_with?(".css") ? [rel] : [],
              scripts: rel.end_with?(".js") ? [rel] : [],
              is_entry: true
            }
          end
        end

        entrypoints
      end
    end
  end
end
