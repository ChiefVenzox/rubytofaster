# frozen_string_literal: true

require "fileutils"
require_relative "base"

module RubyToFaster
  module Resources
    # Resource adapter for Dart Sass / SCSS stylesheets (standalone `sass` CLI or npm `sass`).
    class Sass < Base
      INPUT_CANDIDATES = %w[
        app/assets/stylesheets/application.scss
        app/assets/stylesheets/application.sass
        src/styles/main.scss
        src/styles/index.scss
        src/main.scss
        src/app.scss
      ].freeze

      def self.detect?(dir)
        return true if INPUT_CANDIDATES.any? { |c| File.file?(File.join(dir, c)) }

        pkg_json = File.join(dir, "package.json")
        return false unless File.file?(pkg_json)

        content = File.read(pkg_json)
        content.include?('"sass"') || content.include?('"sass-embedded"')
      end

      def framework_name
        "Sass"
      end

      def collect
        t0 = monotonic_ms
        input_path, output_path, is_dir = resolve_paths

        if @spec_config[:auto_build] || @spec_config[:build_command]
          run_sass_build!(input_path, output_path)
        end

        staged = {}
        asset_map = {}
        entrypoints = {}

        if is_dir
          staged, asset_map = stage_directory(output_path)
          asset_map.each_key do |rel|
            next unless rel.end_with?(".css")

            entrypoints[rel] = {
              file: rel,
              gem_path: File.join(mount_to, rel),
              css: [rel],
              is_entry: true
            }
          end
        else
          unless File.file?(output_path)
            raise BuildError, "Sass compiled CSS output not found: #{output_path}"
          end

          rel_name = File.basename(output_path)
          gem_dest = @file_resolver.sanitize_relative_path!(File.join(mount_to, rel_name))
          stat = File.lstat(output_path)

          staged[gem_dest] = PackageEntry.new(
            gem_path: gem_dest,
            source_path: output_path,
            content: nil,
            mode: 0o644,
            executable: false
          )

          asset_map[rel_name] = {
            gem_path: gem_dest,
            size: stat.size,
            sha256: Digest::SHA256.file(output_path).hexdigest,
            integrity: compute_sri_file(output_path)
          }

          entrypoints[rel_name] = {
            file: rel_name,
            gem_path: gem_dest,
            css: [rel_name],
            is_entry: true
          }
        end

        AdapterResult.new(
          framework: :sass,
          root: workspace_dir,
          mount_to: mount_to,
          entries: staged,
          entrypoints: entrypoints,
          assets: asset_map,
          metadata: {
            input: input_path,
            output: output_path,
            is_dir: is_dir,
            css_count: asset_map.size
          },
          duration_ms: (monotonic_ms - t0).round(2)
        )
      end

      private

      def resolve_paths
        raw_out = @spec_config[:output] || @spec_config[:out_dir] || "dist/application.css"
        output_full = File.expand_path(raw_out, workspace_dir)
        is_dir = raw_out.end_with?("/") || (!raw_out.include?(".") && !File.file?(output_full))

        raw_in = @spec_config[:input]
        input_full = if raw_in
                       File.expand_path(raw_in, workspace_dir)
                     else
                       found = INPUT_CANDIDATES.find { |c| File.file?(File.join(workspace_dir, c)) }
                       found ? File.join(workspace_dir, found) : nil
                     end

        [input_full, output_full, is_dir]
      end

      def run_sass_build!(input_path, output_path)
        if @spec_config[:build_command]
          run_build_command!([])
          return
        end

        raise ConfigError, "Sass auto_build requires an input .scss/.sass file" unless input_path && File.file?(input_path)

        FileUtils.mkdir_p(File.dirname(output_path))
        args = [input_path, output_path]
        args << "--style=compressed" unless @options[:minify] == false
        args << "--no-source-map" unless include_sourcemaps?

        sass_bin = detect_sass_bin
        if sass_bin.is_a?(Array)
          run_build_command!(sass_bin[1..] + args)
        else
          stdout, stderr, status = Open3.capture3(sass_bin, *args, chdir: workspace_dir)
          return if status.success?

          raise BuildError, "Sass build failed (exit #{status.exitstatus}): #{stderr.empty? ? stdout : stderr}"
        end
      end

      def detect_sass_bin
        path_bin = ENV["PATH"].to_s.split(File::PATH_SEPARATOR).map { |p| File.join(p, "sass") }.find { |f| File.executable?(f) }
        return path_bin if path_bin

        ["exec", "sass"]
      end
    end
  end
end
