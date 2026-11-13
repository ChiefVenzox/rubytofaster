# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module RubyToFaster
  # Content-addressable Merkle build cache inspired by Next.js / Turbopack and Angular Architect.
  class Cache
    SCHEMA_VERSION = 1

    def initialize(config)
      @config    = config
      @cache_dir = config.resolved_cache_dir
      @blobs_dir = File.join(@cache_dir, "artifacts")
      @meta_dir  = File.join(@cache_dir, "manifests")
    end

    def enabled?
      @config.incremental
    end

    # Computes a deterministic SHA-256 Merkle digest across Ruby runtime, gemspec metadata,
    # sorted package entries (path, mode, SHA-256 content), and build options.
    def compute_key(spec:, entries:)
      root_hash = Digest::SHA256.new
      root_hash << "schema:#{SCHEMA_VERSION}\n"
      root_hash << "rtf:#{RubyToFaster::VERSION}\n"
      root_hash << "ruby:#{RUBY_VERSION}:#{RUBY_PLATFORM}\n"
      root_hash << "reproducible:#{@config.reproducible}:#{@config.source_date_epoch}\n"
      root_hash << "spec:#{spec.name}:#{spec.version}:#{spec.platform}\n"
      root_hash << "summary:#{spec.summary}\n"
      root_hash << "description:#{spec.description}\n"
      root_hash << "license:#{Array(spec.licenses).join(',')}\n"
      root_hash << "bindir:#{spec.bindir}:#{Array(spec.executables).sort.join(',')}\n"
      root_hash << "req_ruby:#{spec.required_ruby_version}\n"

      spec.dependencies.sort_by(&:name).each do |dep|
        root_hash << "dep:#{dep.type}:#{dep.name}:#{dep.requirement}\n"
      end

      (spec.metadata || {}).sort_by { |k, _| k.to_s }.each do |k, v|
        root_hash << "meta:#{k}=#{v}\n"
      end

      entries.keys.sort.each do |gem_path|
        entry = entries[gem_path]
        file_digest = if entry.virtual?
                        Digest::SHA256.hexdigest(entry.content)
                      else
                        Digest::SHA256.file(entry.source_path).hexdigest
                      end
        root_hash << "entry:#{gem_path}:#{entry.mode.to_s(8)}:#{file_digest}\n"
      end

      root_hash.hexdigest
    end

    # Restores a cached .gem artifact into target_gem_path if the Merkle key matches.
    def fetch(cache_key, target_gem_path)
      return nil unless enabled?

      cached_gem = File.join(@blobs_dir, "#{cache_key}.gem")
      cached_meta = File.join(@meta_dir, "#{cache_key}.json")
      return nil unless File.file?(cached_gem) && File.file?(cached_meta)

      metadata = JSON.parse(File.read(cached_meta), symbolize_names: true)
      expected_sha256 = metadata[:gem_sha256]
      actual_sha256   = Digest::SHA256.file(cached_gem).hexdigest
      return nil unless expected_sha256 && expected_sha256 == actual_sha256

      FileUtils.mkdir_p(File.dirname(target_gem_path))
      FileUtils.cp(cached_gem, target_gem_path) unless File.expand_path(cached_gem) == File.expand_path(target_gem_path)
      metadata
    rescue JSON::ParserError, SystemCallError
      nil
    end

    # Stores a newly compiled .gem artifact and its trace metadata in .rtf-cache/.
    def store(cache_key, built_gem_path, trace_metadata)
      return unless enabled?

      FileUtils.mkdir_p(@blobs_dir)
      FileUtils.mkdir_p(@meta_dir)

      cached_gem  = File.join(@blobs_dir, "#{cache_key}.gem")
      cached_meta = File.join(@meta_dir, "#{cache_key}.json")
      trace_file  = File.join(@cache_dir, "last-build-trace.json")

      FileUtils.cp(built_gem_path, cached_gem)
      payload = trace_metadata.merge(
        cache_key: cache_key,
        cached_at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      )
      json_str = JSON.pretty_generate(payload)
      File.write(cached_meta, json_str)
      File.write(trace_file, json_str)
    end

    def clear!
      FileUtils.rm_rf(@cache_dir) if Dir.exist?(@cache_dir)
    end
  end
end
