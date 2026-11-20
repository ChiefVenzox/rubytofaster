# frozen_string_literal: true

require "etc"

module RubyToFaster
  # Monorepo / multi-gem workspace compiler and auditor (`rtf workspace build|check|clean`).
  # Discovers sibling gems, resolves intra-workspace dependencies in topological order,
  # and compiles them cleanly with aggregated telemetry.
  class Workspace
    DEFAULT_PATTERNS = %w[gems/* packages/* engines/* plugins/* .].freeze

    MemberResult = Struct.new(:name, :root_dir, :gemspec, :status, :result, :error, :duration_ms, keyword_init: true) do
      def to_h
        {
          name: name,
          root_dir: root_dir,
          gemspec: gemspec,
          status: status,
          duration_ms: duration_ms,
          error: error,
          result: result.respond_to?(:to_h) ? result.to_h : result
        }
      end
    end

    WorkspaceReport = Struct.new(:action, :root_dir, :members, :total_ms, keyword_init: true) do
      def success?
        members.all? { |m| m.status == :ok }
      end

      def to_h
        {
          action: action,
          root_dir: root_dir,
          success: success?,
          member_count: members.size,
          passed_count: members.count { |m| m.status == :ok },
          failed_count: members.count { |m| m.status != :ok },
          total_ms: total_ms,
          members: members.map(&:to_h)
        }
      end
    end

    def initialize(root_dir: Dir.pwd, patterns: nil, parallel_jobs: nil)
      @root_dir      = File.expand_path(root_dir)
      @patterns      = patterns && !patterns.empty? ? Array(patterns) : DEFAULT_PATTERNS
      @parallel_jobs = [parallel_jobs || Etc.nprocessors, 1].max
    end

    # Discovers all gem packages matching workspace globs, returning topologically ordered members.
    def discover
      found = {}
      @patterns.each do |pat|
        Dir.glob(File.join(@root_dir, pat)).sort.each do |dir|
          next unless File.directory?(dir)

          expanded = File.expand_path(dir)
          gemspec = Dir.glob(File.join(expanded, "*.gemspec")).sort.first
          next unless gemspec

          spec = Dir.chdir(expanded) { Gem::Specification.load(gemspec) }
          next unless spec

          found[spec.name] ||= {
            name: spec.name,
            root_dir: expanded,
            gemspec: gemspec,
            deps: spec.dependencies.map(&:name)
          }
        end
      end

      topological_sort(found)
    end

    def build_all(incremental: true, skip_assets: false, skip_extensions: false)
      t0 = monotonic_ms
      members = discover
      raise ConfigError, "No workspace gems discovered in #{@root_dir}" if members.empty?

      results = members.map do |m|
        mt0 = monotonic_ms
        begin
          script = CLI::DEFAULT_SCRIPT_NAMES.map { |n| File.join(m[:root_dir], n) }.find { |p| File.file?(p) }
          cfg = if script
                  RubyToFaster.load_script_config(script)
                else
                  c = Config.new(root_dir: m[:root_dir])
                  c.gemspec(File.basename(m[:gemspec]))
                  c
                end
          cfg.incremental     = false unless incremental
          cfg.skip_assets     = true if skip_assets
          cfg.skip_extensions = true if skip_extensions
          cfg.quiet           = true

          res = Compiler.new(cfg).run
          MemberResult.new(
            name: m[:name],
            root_dir: m[:root_dir],
            gemspec: m[:gemspec],
            status: :ok,
            result: res,
            error: nil,
            duration_ms: (monotonic_ms - mt0).round(2)
          )
        rescue StandardError => e
          MemberResult.new(
            name: m[:name],
            root_dir: m[:root_dir],
            gemspec: m[:gemspec],
            status: :error,
            result: nil,
            error: e.message,
            duration_ms: (monotonic_ms - mt0).round(2)
          )
        end
      end

      WorkspaceReport.new(
        action: :build,
        root_dir: @root_dir,
        members: results,
        total_ms: (monotonic_ms - t0).round(2)
      )
    end

    def check_all(strict: false)
      t0 = monotonic_ms
      members = discover
      raise ConfigError, "No workspace gems discovered in #{@root_dir}" if members.empty?

      results = members.map do |m|
        mt0 = monotonic_ms
        begin
          cfg = Config.new(root_dir: m[:root_dir])
          cfg.gemspec(File.basename(m[:gemspec]))
          report = Checker.new(cfg).audit
          ok = report.passed? && (!strict || report.warnings.empty?)
          MemberResult.new(
            name: m[:name],
            root_dir: m[:root_dir],
            gemspec: m[:gemspec],
            status: ok ? :ok : :failed,
            result: report,
            error: ok ? nil : "#{report.fails.size} error(s), #{report.warnings.size} warning(s)",
            duration_ms: (monotonic_ms - mt0).round(2)
          )
        rescue StandardError => e
          MemberResult.new(
            name: m[:name],
            root_dir: m[:root_dir],
            gemspec: m[:gemspec],
            status: :error,
            result: nil,
            error: e.message,
            duration_ms: (monotonic_ms - mt0).round(2)
          )
        end
      end

      WorkspaceReport.new(
        action: :check,
        root_dir: @root_dir,
        members: results,
        total_ms: (monotonic_ms - t0).round(2)
      )
    end

    def clean_all
      t0 = monotonic_ms
      members = discover
      results = members.map do |m|
        mt0 = monotonic_ms
        cfg = Config.new(root_dir: m[:root_dir])
        Cache.new(cfg).clear!
        FileUtils.rm_rf(cfg.resolved_out_dir) if Dir.exist?(cfg.resolved_out_dir)
        MemberResult.new(
          name: m[:name],
          root_dir: m[:root_dir],
          gemspec: m[:gemspec],
          status: :ok,
          result: { cleaned: true },
          error: nil,
          duration_ms: (monotonic_ms - mt0).round(2)
        )
      end

      WorkspaceReport.new(
        action: :clean,
        root_dir: @root_dir,
        members: results,
        total_ms: (monotonic_ms - t0).round(2)
      )
    end

    private

    # Kahn-like DFS topological sort so internal workspace gem dependencies build before dependents.
    def topological_sort(member_map)
      visited = {}
      ordered = []

      visit = lambda do |name|
        return if visited[name] == :done
        return if visited[name] == :visiting # break cycles gracefully

        visited[name] = :visiting
        info = member_map[name]
        info[:deps].each do |dep|
          visit.call(dep) if member_map.key?(dep)
        end
        visited[name] = :done
        ordered << info
      end

      member_map.keys.sort.each { |name| visit.call(name) }
      ordered
    end

    def monotonic_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
    end
  end
end
