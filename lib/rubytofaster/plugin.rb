# frozen_string_literal: true

module RubyToFaster
  # Minimalist Vite/Rollup-inspired plugin runner for gem build pipelines.
  class PluginRunner
    def initialize(config)
      @plugins = config.plugins
      @hooks   = config.hooks
    end

    def run_before_resolve(context)
      @plugins.each do |plugin|
        plugin.before_resolve(context) if plugin.respond_to?(:before_resolve)
      end
      @hooks[:before_resolve].each { |fn| fn.call(context) }
    end

    # Allows plugins/hooks to transform file contents in-memory before tar packaging.
    # Returning a String replaces the packaged bytes; returning nil keeps original bytes.
    def run_transform(gem_path, content)
      current = content
      @plugins.each do |plugin|
        next unless plugin.respond_to?(:transform)

        replaced = plugin.transform(gem_path, current)
        current = replaced if replaced.is_a?(String)
      end
      @hooks[:transform].each do |fn|
        replaced = fn.call(gem_path, current)
        current = replaced if replaced.is_a?(String)
      end
      current
    end

    def run_generate_bundle(entries_map, context)
      @plugins.each do |plugin|
        plugin.generate_bundle(entries_map, context) if plugin.respond_to?(:generate_bundle)
      end
      @hooks[:generate_bundle].each { |fn| fn.call(entries_map, context) }
    end

    def run_after_package(result)
      @plugins.each do |plugin|
        plugin.after_package(result) if plugin.respond_to?(:after_package)
      end
      @hooks[:after_package].each { |fn| fn.call(result) }
    end
  end
end
