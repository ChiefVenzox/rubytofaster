# frozen_string_literal: true

require "json"
require_relative "base"

module RubyToFaster
  module Resources
    # Resource adapter for Angular (`angular.json`) Architect workspaces & v17+ application builder.
    class Angular < Base
      CONFIG_FILE = "angular.json"
      CACHE_IGNORE = [%r{\A\.angular(/|\z)}, %r{\Aserver(/|\z)}, %r{\Aprerendered-routes\.json\z}].freeze

      def self.detect?(dir)
        File.file?(File.join(dir, CONFIG_FILE))
      end

      def framework_name
        "Angular"
      end

      def collect
        t0 = monotonic_ms
        project_name, browser_dir = resolve_angular_output_dir

        build_args = ["exec", "ng", "build"]
        build_args << project_name if project_name
        run_build_command!(build_args)

        # Re-check `browser/` subfolder after build in case Angular v17+ created `dist/<app>/browser`
        effective_dir = Dir.exist?(File.join(browser_dir, "browser")) ? File.join(browser_dir, "browser") : browser_dir

        staged, asset_map = stage_directory(effective_dir, ignore_patterns: CACHE_IGNORE)
        entrypoints = extract_angular_entrypoints(effective_dir, asset_map)

        AdapterResult.new(
          framework: :angular,
          root: workspace_dir,
          mount_to: mount_to,
          entries: staged,
          entrypoints: entrypoints,
          assets: asset_map,
          metadata: {
            project: project_name,
            out_dir: effective_dir,
            bundle_count: asset_map.size
          },
          duration_ms: (monotonic_ms - t0).round(2)
        )
      end

      private

      def resolve_angular_output_dir
        if @spec_config[:out_dir]
          return [@spec_config[:project], File.expand_path(@spec_config[:out_dir], workspace_dir)]
        end

        angular_json_path = File.join(workspace_dir, CONFIG_FILE)
        unless File.file?(angular_json_path)
          raise BuildError, "angular.json not found in #{workspace_dir} and no `out_dir:` was specified."
        end

        workspace = JSON.parse(File.read(angular_json_path))
        projects  = workspace["projects"]
        unless projects.is_a?(Hash) && !projects.empty?
          raise ConfigError, "No projects defined in #{angular_json_path}"
        end

        project_name = @spec_config[:project] || workspace["defaultProject"] || projects.keys.first
        project_cfg  = projects[project_name]
        raise ConfigError, "Angular project '#{project_name}' not found in #{angular_json_path}" unless project_cfg

        build_opts = project_cfg.dig("architect", "build", "options") ||
                     project_cfg.dig("targets", "build", "options") || {}
        raw_output = build_opts["outputPath"]

        resolved_path = case raw_output
                        when Hash
                          base    = raw_output["base"] || "dist/#{project_name}"
                          browser = raw_output.fetch("browser", "browser")
                          browser.empty? ? base : File.join(base, browser)
                        when String
                          raw_output
                        else
                          "dist/#{project_name}"
                        end

        [project_name, File.expand_path(resolved_path, workspace_dir)]
      rescue JSON::ParserError => e
        raise ConfigError, "Invalid JSON in angular.json: #{e.message}"
      end

      # Extracts hashed main/polyfills/styles bundles from index.html or bundle naming conventions.
      def extract_angular_entrypoints(dir, asset_map)
        index_path = File.join(dir, "index.html")
        scripts = []
        styles  = []

        if File.file?(index_path)
          html = File.read(index_path)
          html.scan(/<script\b[^>]*\bsrc=["']([^"']+)["']/i) { |m| scripts << m.first.sub(%r{\A/}, "") }
          html.scan(/<link\b[^>]*rel=["']stylesheet["'][^>]*href=["']([^"']+)["']/i) { |m| styles << m.first.sub(%r{\A/}, "") }
          html.scan(/<link\b[^>]*href=["']([^"']+)["'][^>]*rel=["']stylesheet["']/i) { |m| styles << m.first.sub(%r{\A/}, "") }
        end

        if scripts.empty?
          scripts = asset_map.keys.select { |k| k.match?(/\A(?:polyfills|runtime|main)(?:-[a-zA-Z0-9]+)?\.js\z/) }
        end
        if styles.empty?
          styles = asset_map.keys.select { |k| k.match?(/\Astyles(?:-[a-zA-Z0-9]+)?\.css\z/) }
        end

        styles.uniq!
        scripts.uniq!

        main_file = scripts.find { |s| s.start_with?("main") } || scripts.last
        return {} unless main_file || !styles.empty?

        {
          "index" => {
            file: main_file,
            scripts: scripts,
            css: styles,
            gem_path: main_file ? File.join(mount_to, main_file) : nil,
            is_entry: true
          }
        }
      end
    end
  end
end
