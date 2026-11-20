# frozen_string_literal: true

require_relative "base"

module RubyToFaster
  module Resources
    # Resource adapter for Parcel zero-config bundler (`dist/` while pruning `.parcel-cache/`).
    class Parcel < Base
      def self.detect?(dir)
        return true if File.file?(File.join(dir, ".parcelrc"))

        pkg_json = File.join(dir, "package.json")
        return false unless File.file?(pkg_json)

        File.read(pkg_json).include?('"parcel"')
      end

      def framework_name
        "Parcel"
      end

      def collect
        t0 = monotonic_ms
        run_build_command!(%w[run build])

        out_dir = File.expand_path(@spec_config[:out_dir] || "dist", workspace_dir)
        staged, asset_map = stage_directory(out_dir, ignore_patterns: [%r{\A\.parcel-cache(/|\z)}])
        entrypoints = extract_entrypoints(asset_map)

        AdapterResult.new(
          framework: :parcel,
          root: workspace_dir,
          mount_to: mount_to,
          entries: staged,
          entrypoints: entrypoints,
          assets: asset_map,
          metadata: {
            out_dir: out_dir,
            chunk_count: asset_map.size
          },
          duration_ms: (monotonic_ms - t0).round(2)
        )
      end

      private

      def extract_entrypoints(asset_map)
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
    end
  end
end
