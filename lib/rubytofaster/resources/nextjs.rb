# frozen_string_literal: true

require "json"
require_relative "base"

module RubyToFaster
  module Resources
    # Resource adapter for Next.js static exports (`out/`) and `.next/static` production bundles.
    class Nextjs < Base
      CONFIG_FILES = %w[next.config.ts next.config.mjs next.config.js next.config.cjs].freeze
      CACHE_IGNORE = [%r{\A\.?next/cache(/|\z)}, %r{\Acache(/|\z)}, %r{\Atrace\z}].freeze

      def self.detect?(dir)
        CONFIG_FILES.any? { |cfg| File.file?(File.join(dir, cfg)) }
      end

      def framework_name
        "Next.js"
      end

      def collect
        t0 = monotonic_ms
        run_build_command!(["exec", "next", "build"])

        resolved_mode, source_dir = resolve_mode_and_dir
        if resolved_mode == :export
          collect_static_export(source_dir, t0)
        else
          collect_dot_next_bundle(source_dir, t0)
        end
      end

      private

      def resolve_mode_and_dir
        requested_mode = (@spec_config[:mode] || :auto).to_sym
        custom_out     = @spec_config[:out_dir]

        if custom_out
          full = File.expand_path(custom_out, workspace_dir)
          mode = requested_mode == :auto ? infer_mode_from_dir(full) : requested_mode
          return [mode, full]
        end

        export_dir = File.join(workspace_dir, "out")
        dot_next   = File.join(workspace_dir, ".next")

        case requested_mode
        when :export
          [:export, export_dir]
        when :static, :standalone
          [:static, dot_next]
        when :auto
          if Dir.exist?(export_dir)
            [:export, export_dir]
          elsif Dir.exist?(dot_next)
            [:static, dot_next]
          else
            raise BuildError, "Next.js output not found in #{workspace_dir} (expected `out/` or `.next/`)."
          end
        else
          raise ConfigError, "Unsupported Next.js mode: #{requested_mode.inspect} (use :auto, :export, or :static)"
        end
      end

      def infer_mode_from_dir(dir)
        Dir.exist?(File.join(dir, "static")) && !File.exist?(File.join(dir, "index.html")) ? :static : :export
      end

      def collect_static_export(export_dir, t0)
        staged, asset_map = stage_directory(export_dir, ignore_patterns: CACHE_IGNORE)
        entrypoints = {}

        asset_map.each_key do |rel|
          next unless rel.end_with?(".html")

          route = "/" + rel.sub(/index\.html\z/, "").sub(/\.html\z/, "").sub(%r{/\z}, "")
          route = "/" if route.empty?
          entrypoints[route] = {
            file: rel,
            gem_path: File.join(mount_to, rel),
            css: asset_map.keys.select { |k| k.start_with?("_next/static/css/") && k.end_with?(".css") },
            is_entry: true
          }
        end

        AdapterResult.new(
          framework: :nextjs,
          root: workspace_dir,
          mount_to: mount_to,
          entries: staged,
          entrypoints: entrypoints,
          assets: asset_map,
          metadata: {
            mode: :export,
            out_dir: export_dir,
            routes: entrypoints.keys.sort
          },
          duration_ms: (monotonic_ms - t0).round(2)
        )
      end

      def collect_dot_next_bundle(dot_next_dir, t0)
        static_dir = File.join(dot_next_dir, "static")
        unless Dir.exist?(static_dir)
          raise BuildError, "Next.js `.next/static` directory not found in #{dot_next_dir}"
        end

        static_mount = File.join(mount_to, "_next/static")
        staged, raw_assets = stage_directory(static_dir, target_mount: static_mount, ignore_patterns: CACHE_IGNORE)

        asset_map = raw_assets.transform_keys { |rel| File.join("_next/static", rel) }
        build_id  = read_optional_text(File.join(dot_next_dir, "BUILD_ID"))
        build_manifest  = read_optional_json(File.join(dot_next_dir, "build-manifest.json"))
        routes_manifest = read_optional_json(File.join(dot_next_dir, "routes-manifest.json"))

        entrypoints = extract_next_pages(build_manifest)

        AdapterResult.new(
          framework: :nextjs,
          root: workspace_dir,
          mount_to: mount_to,
          entries: staged,
          entrypoints: entrypoints,
          assets: asset_map,
          metadata: {
            mode: :static,
            build_id: build_id,
            out_dir: dot_next_dir,
            static_routes: extract_static_routes(routes_manifest)
          },
          duration_ms: (monotonic_ms - t0).round(2)
        )
      end

      def extract_next_pages(build_manifest)
        return {} unless build_manifest.is_a?(Hash) && build_manifest["pages"].is_a?(Hash)

        points = {}
        build_manifest["pages"].each do |route, files|
          file_list = Array(files).map { |f| f.start_with?("_next/") ? f : File.join("_next", f) }
          js_files  = file_list.select { |f| f.end_with?(".js") }
          css_files = file_list.select { |f| f.end_with?(".css") }

          points[route] = {
            file: js_files.first,
            scripts: js_files,
            css: css_files,
            gem_path: js_files.first ? File.join(mount_to, js_files.first) : nil,
            is_entry: true
          }
        end
        points
      end

      def extract_static_routes(routes_manifest)
        return [] unless routes_manifest.is_a?(Hash) && routes_manifest["staticRoutes"].is_a?(Array)

        routes_manifest["staticRoutes"].filter_map { |r| r["page"] if r.is_a?(Hash) }
      end

      def read_optional_text(path)
        File.file?(path) ? File.read(path).strip : nil
      end

      def read_optional_json(path)
        File.file?(path) ? JSON.parse(File.read(path)) : nil
      rescue JSON::ParserError => e
        raise BuildError, "Invalid Next.js manifest JSON (#{path}): #{e.message}"
      end
    end
  end
end
