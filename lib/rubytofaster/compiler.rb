# frozen_string_literal: true

require "fileutils"

module RubyToFaster
  # Immutable result returned by `RubyToFaster.build` and `Compiler#run`.
  BuildResult = Struct.new(
    :gem_name,
    :gem_version,
    :gem_path,
    :gem_sha256,
    :gem_sha512,
    :compressed_bytes,
    :unpacked_bytes,
    :entry_count,
    :pruned_count,
    :cache_hit,
    :cache_key,
    :resources,
    :extensions,
    :budget_warnings,
    :timings_ms,
    :total_ms,
    keyword_init: true
  ) do
    def to_h
      super.merge(
        resources: Array(resources).map do |r|
          r.is_a?(Hash) ? r : {
            framework: r.framework,
            mount_to: r.mount_to,
            asset_count: r.assets.size,
            entrypoints: r.entrypoints.keys,
            duration_ms: r.duration_ms
          }
        end,
        extensions: Array(extensions).map do |e|
          e.is_a?(Hash) ? e : e.to_h
        end
      )
    end
  end

  # Orchestrates file resolution, Angular/Vite/Next.js resource collection,
  # Merkle cache lookup, native extension verification, and deterministic `.gem` packaging.
  class Compiler
    def initialize(config)
      @config        = config
      @file_resolver = FileResolver.new(config)
      @plugin_runner = PluginRunner.new(config)
      @cache         = Cache.new(config)
      @packager      = Packager.new(config, @plugin_runner)
    end

    def run
      total_t0 = monotonic_ms
      timings  = {}

      @plugin_runner.run_before_resolve(@config)

      t0 = monotonic_ms
      spec, _spec_path = @file_resolver.load_gemspec
      entries, pruned_files = @file_resolver.resolve_entries(spec)
      timings[:resolve_ms] = elapsed_since(t0)

      t0 = monotonic_ms
      adapter_results = @config.skip_assets ? [] : collect_frontend_resources
      merge_frontend_resources!(entries, adapter_results)
      timings[:resources_ms] = elapsed_since(t0)

      @plugin_runner.run_generate_bundle(entries, @config)

      out_file_name = spec.file_name
      target_gem_path = File.join(@config.resolved_out_dir, out_file_name)

      t0 = monotonic_ms
      cache_key = @cache.compute_key(spec: spec, entries: entries)
      cached_meta = @cache.fetch(cache_key, target_gem_path)
      timings[:cache_ms] = elapsed_since(t0)

      if cached_meta
        entry_sizes = entries.transform_values(&:size)
        warnings = BudgetEvaluator.new(@config.budgets).evaluate!(
          compressed_bytes: cached_meta[:compressed_bytes],
          unpacked_bytes: cached_meta[:unpacked_bytes],
          entry_sizes: entry_sizes
        )

        result = BuildResult.new(
          gem_name: spec.name,
          gem_version: spec.version.to_s,
          gem_path: target_gem_path,
          gem_sha256: cached_meta[:gem_sha256],
          gem_sha512: cached_meta[:gem_sha512],
          compressed_bytes: cached_meta[:compressed_bytes],
          unpacked_bytes: cached_meta[:unpacked_bytes],
          entry_count: entries.size,
          pruned_count: pruned_files.size,
          cache_hit: true,
          cache_key: cache_key,
          resources: adapter_results,
          extensions: [],
          budget_warnings: warnings,
          timings_ms: timings,
          total_ms: elapsed_since(total_t0)
        )
        @plugin_runner.run_after_package(result)
        return result
      end

      t0 = monotonic_ms
      ext_results = ExtensionBuilder.new(@config).compile_all(spec)
      timings[:extensions_ms] = elapsed_since(t0)

      t0 = monotonic_ms
      pkg_stats = @packager.build(spec: spec, entries: entries, out_path: target_gem_path)
      timings[:package_ms] = elapsed_since(t0)

      warnings = BudgetEvaluator.new(@config.budgets).evaluate!(
        compressed_bytes: pkg_stats.compressed_bytes,
        unpacked_bytes: pkg_stats.unpacked_bytes,
        entry_sizes: pkg_stats.entry_sizes
      )

      total_ms = elapsed_since(total_t0)

      @cache.store(
        cache_key,
        target_gem_path,
        {
          gem_name: spec.name,
          gem_version: spec.version.to_s,
          gem_sha256: pkg_stats.gem_sha256,
          gem_sha512: pkg_stats.gem_sha512,
          compressed_bytes: pkg_stats.compressed_bytes,
          unpacked_bytes: pkg_stats.unpacked_bytes,
          entry_count: pkg_stats.entry_count
        }
      )

      result = BuildResult.new(
        gem_name: spec.name,
        gem_version: spec.version.to_s,
        gem_path: target_gem_path,
        gem_sha256: pkg_stats.gem_sha256,
        gem_sha512: pkg_stats.gem_sha512,
        compressed_bytes: pkg_stats.compressed_bytes,
        unpacked_bytes: pkg_stats.unpacked_bytes,
        entry_count: pkg_stats.entry_count,
        pruned_count: pruned_files.size,
        cache_hit: false,
        cache_key: cache_key,
        resources: adapter_results,
        extensions: ext_results,
        budget_warnings: warnings,
        timings_ms: timings,
        total_ms: total_ms
      )

      @plugin_runner.run_after_package(result)
      result
    end

    private

    def collect_frontend_resources
      configured = @config.resources.dup

      if @config.auto_detect_resources
        configured.concat(auto_discovered_resources(configured))
      end

      configured.map do |res_cfg|
        adapter_klass = case res_cfg[:type]
                        when :vite     then Resources::Vite
                        when :nextjs   then Resources::Nextjs
                        when :angular  then Resources::Angular
                        when :tailwind then Resources::Tailwind
                        when :esbuild  then Resources::Esbuild
                        else
                          raise ConfigError, "Unknown resource adapter type: #{res_cfg[:type].inspect}"
                        end
        adapter_klass.new(
          project_root: @config.root_dir,
          spec_config: res_cfg,
          file_resolver: @file_resolver
        ).collect
      end
    end

    def auto_discovered_resources(existing)
      existing_types = existing.map { |r| r[:type] }
      discovered = []
      root = @config.root_dir

      if !existing_types.include?(:vite) && Resources::Vite.detect?(root) && Dir.exist?(File.join(root, "dist"))
        discovered << { type: :vite, root: ".", out_dir: "dist", mount_to: "public/vite", auto_build: false }
      end

      if !existing_types.include?(:nextjs) && Resources::Nextjs.detect?(root) &&
         (Dir.exist?(File.join(root, "out")) || Dir.exist?(File.join(root, ".next/static")))
        discovered << { type: :nextjs, root: ".", mode: :auto, mount_to: "public/nextjs", auto_build: false }
      end

      if !existing_types.include?(:angular) && Resources::Angular.detect?(root) && Dir.exist?(File.join(root, "dist"))
        discovered << { type: :angular, root: ".", mount_to: "public/angular", auto_build: false }
      end

      if !existing_types.include?(:tailwind) && Resources::Tailwind.detect?(root) &&
         (File.file?(File.join(root, "dist/tailwind.css")) || File.file?(File.join(root, "app/assets/builds/application.css")))
        out = File.file?(File.join(root, "dist/tailwind.css")) ? "dist/tailwind.css" : "app/assets/builds/application.css"
        discovered << { type: :tailwind, root: ".", output: out, mount_to: "public/tailwind", auto_build: false }
      end

      if !existing_types.include?(:esbuild) && Resources::Esbuild.detect?(root) &&
         (Dir.exist?(File.join(root, "dist")) || Dir.exist?(File.join(root, "app/assets/builds")))
        out = Dir.exist?(File.join(root, "dist")) ? "dist" : "app/assets/builds"
        discovered << { type: :esbuild, root: ".", out_dir: out, mount_to: "public/esbuild", auto_build: false }
      end

      discovered
    end

    def merge_frontend_resources!(entries, adapter_results)
      return if adapter_results.empty?

      adapter_results.each do |res|
        res.entries.each do |gem_path, entry|
          entries[gem_path] = entry
          persist_staged_entry(gem_path, entry) if @config.write_staged_assets
        end
      end

      manifest = AssetManifest.from_adapter_results(adapter_results)
      manifest_json = manifest.to_json_pretty
      manifest_path = "public/rtf-manifest.json"
      entries[manifest_path] = PackageEntry.new(
        gem_path: manifest_path,
        source_path: nil,
        content: manifest_json,
        mode: 0o644,
        executable: false
      )
      persist_staged_entry(manifest_path, entries[manifest_path]) if @config.write_staged_assets

      return unless @config.asset_helper_module && @config.asset_helper_path

      helper_rel  = @file_resolver.sanitize_relative_path!(@config.asset_helper_path)
      helper_code = manifest.generate_ruby_helper_source(@config.asset_helper_module)
      entries[helper_rel] = PackageEntry.new(
        gem_path: helper_rel,
        source_path: nil,
        content: helper_code,
        mode: 0o644,
        executable: false
      )
      persist_staged_entry(helper_rel, entries[helper_rel]) if @config.write_staged_assets
    end

    def persist_staged_entry(gem_path, entry)
      dest = File.expand_path(gem_path, @config.root_dir)
      FileUtils.mkdir_p(File.dirname(dest))
      if entry.virtual?
        File.binwrite(dest, entry.content)
      elsif File.expand_path(entry.source_path) != dest
        FileUtils.cp(entry.source_path, dest)
      end
    end

    def monotonic_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
    end

    def elapsed_since(t0)
      (monotonic_ms - t0).round(2)
    end
  end
end
