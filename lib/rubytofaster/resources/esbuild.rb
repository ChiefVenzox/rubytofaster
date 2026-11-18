# frozen_string_literal: true

require "json"
require_relative "base"

module RubyToFaster
  module Resources
    # Resource adapter for Esbuild JS/CSS bundling (standard in Rails 7/8 jsbundling-rails & modern gems).
    class Esbuild < Base
      CONFIG_FILES = %w[
        esbuild.config.js
        esbuild.config.mjs
        esbuild.config.cjs
        esbuild.config.ts
      ].freeze

      def self.detect?(dir)
        return true if CONFIG_FILES.any? { |cfg| File.file?(File.join(dir, cfg)) }

        pkg_json = File.join(dir, "package.json")
        if File.file?(pkg_json)
          content = File.read(pkg_json)
          return true if content.include?('"esbuild"')
        end

        File.file?(File.join(dir, "app/javascript/application.js")) &&
          Dir.exist?(File.join(dir, "app/assets/builds"))
      end

      def framework_name
        "Esbuild"
      end

      def collect
        t0 = monotonic_ms
        out_dir = File.expand_path(@spec_config[:out_dir] || "dist", workspace_dir)

        if @spec_config[:auto_build] || @spec_config[:build_command]
          run_esbuild_build!(out_dir)
        end

        staged, asset_map = stage_directory(out_dir)
        entrypoints = extract_entrypoints(out_dir, asset_map)

        AdapterResult.new(
          framework: :esbuild,
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

      def run_esbuild_build!(out_dir)
        if @spec_config[:build_command]
          run_build_command!([])
          return
        end

        FileUtils.mkdir_p(out_dir)
        entry_list = Array(@spec_config[:entrypoints] || @spec_config[:entry] || "src/index.js")
        args = ["exec", "esbuild"] + entry_list + ["--bundle", "--outdir=#{out_dir}"]
        args << "--minify" unless @options[:minify] == false
        args << "--sourcemap" if include_sourcemaps?

        run_build_command!(args)
      end

      def extract_entrypoints(out_dir, asset_map)
        metafile_path = File.join(out_dir, "metafile.json")
        if File.file?(metafile_path)
          parsed = parse_metafile(metafile_path)
          return parsed unless parsed.empty?
        end

        entrypoints = {}
        asset_map.each_key do |rel|
          next unless rel.end_with?(".js") || rel.end_with?(".css")

          name = File.basename(rel)
          entrypoints[name] = {
            file: rel,
            gem_path: File.join(mount_to, rel),
            css: rel.end_with?(".css") ? [rel] : [],
            scripts: rel.end_with?(".js") ? [rel] : [],
            is_entry: true
          }
        end
        entrypoints
      end

      def parse_metafile(path)
        data = JSON.parse(File.read(path))
        outputs = data["outputs"] || {}
        entrypoints = {}

        outputs.each do |out_rel, meta|
          next unless meta["entryPoint"]

          entrypoints[meta["entryPoint"]] = {
            file: out_rel,
            gem_path: File.join(mount_to, out_rel),
            css: Array(meta["cssBundle"]),
            scripts: [out_rel],
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
