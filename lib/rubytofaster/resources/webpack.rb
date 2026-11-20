# frozen_string_literal: true

require "json"
require_relative "base"

module RubyToFaster
  module Resources
    # Resource adapter for Webpack builds (`dist/` or `public/packs/`, parsing manifest.json / stats.json).
    class Webpack < Base
      CONFIG_FILES = %w[
        webpack.config.js
        webpack.config.cjs
        webpack.config.mjs
        webpack.config.ts
      ].freeze

      def self.detect?(dir)
        return true if CONFIG_FILES.any? { |cfg| File.file?(File.join(dir, cfg)) }

        pkg_json = File.join(dir, "package.json")
        return false unless File.file?(pkg_json)

        File.read(pkg_json).include?('"webpack"')
      end

      def framework_name
        "Webpack"
      end

      def collect
        t0 = monotonic_ms
        run_build_command!(%w[run build])

        out_dir = resolve_output_dir
        staged, asset_map = stage_directory(out_dir)
        entrypoints = extract_entrypoints(out_dir, asset_map)

        AdapterResult.new(
          framework: :webpack,
          root: workspace_dir,
          mount_to: mount_to,
          entries: staged,
          entrypoints: entrypoints,
          assets: asset_map,
          metadata: {
            out_dir: out_dir,
            entrypoints: entrypoints.keys.sort,
            chunk_count: asset_map.size
          },
          duration_ms: (monotonic_ms - t0).round(2)
        )
      end

      private

      def resolve_output_dir
        if @spec_config[:out_dir]
          return File.expand_path(@spec_config[:out_dir], workspace_dir)
        end

        packs = File.join(workspace_dir, "public", "packs")
        return packs if Dir.exist?(packs)

        File.join(workspace_dir, "dist")
      end

      def extract_entrypoints(out_dir, asset_map)
        %w[manifest.json assets-manifest.json stats.json].each do |candidate|
          path = File.join(out_dir, candidate)
          next unless File.file?(path)

          parsed = parse_webpack_manifest(path)
          return parsed unless parsed.empty?
        end

        entrypoints = {}
        asset_map.each_key do |rel|
          next unless rel.end_with?(".js", ".css")

          entrypoints[File.basename(rel)] = {
            file: rel,
            gem_path: File.join(mount_to, rel),
            css: rel.end_with?(".css") ? [rel] : [],
            scripts: rel.end_with?(".js") ? [rel] : [],
            is_entry: true
          }
        end
        entrypoints
      end

      def parse_webpack_manifest(path)
        data = JSON.parse(File.read(path))
        entrypoints = {}

        # Webpack stats.json / webpacker manifest with "entrypoints" hash
        if data["entrypoints"].is_a?(Hash)
          data["entrypoints"].each do |name, info|
            assets = if info.is_a?(Hash) && info["assets"].is_a?(Array)
                       info["assets"].map { |a| a.is_a?(Hash) ? a["name"] : a.to_s }
                     elsif info.is_a?(Hash)
                       Array(info["js"]) + Array(info["css"])
                     else
                       []
                     end
            js  = assets.select { |a| a.end_with?(".js") }.map { |a| a.sub(%r{\A/}, "") }
            css = assets.select { |a| a.end_with?(".css") }.map { |a| a.sub(%r{\A/}, "") }
            primary = js.first || css.first
            next unless primary

            entrypoints[name] = {
              file: primary,
              gem_path: File.join(mount_to, primary),
              css: css,
              scripts: js,
              is_entry: true
            }
          end
          return entrypoints unless entrypoints.empty?
        end

        # Flat webpack-manifest-plugin format: { "main.js": "main.abc123.js", "main.css": "main.def456.css" }
        data.each do |logical, hashed|
          next unless hashed.is_a?(String)
          next unless hashed.end_with?(".js", ".css")

          clean = hashed.sub(%r{\A/}, "")
          entrypoints[logical] = {
            file: clean,
            gem_path: File.join(mount_to, clean),
            css: clean.end_with?(".css") ? [clean] : [],
            scripts: clean.end_with?(".js") ? [clean] : [],
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
