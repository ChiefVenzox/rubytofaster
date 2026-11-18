# frozen_string_literal: true

require "open3"
require_relative "file_resolver"

module RubyToFaster
  CheckIssue = Struct.new(:level, :category, :message, keyword_init: true)

  CheckReport = Struct.new(:gem_name, :gem_version, :issues, :checks_run, keyword_init: true) do
    def passed?
      issues.none? { |i| i.level == :fail }
    end

    def clean?
      issues.empty?
    end

    def fails
      issues.select { |i| i.level == :fail }
    end

    def warnings
      issues.select { |i| i.level == :warn }
    end

    def to_h
      {
        gem_name: gem_name,
        gem_version: gem_version,
        passed: passed?,
        clean: clean?,
        checks_run: checks_run,
        fail_count: fails.size,
        warning_count: warnings.size,
        issues: issues.map { |i| { level: i.level, category: i.category, message: i.message } }
      }
    end
  end

  # Comprehensive supply-chain security, gemspec validation, and executable integrity auditor.
  class Checker
    KNOWN_SPDX = %w[MIT Apache-2.0 BSD-2-Clause BSD-3-Clause GPL-2.0-only GPL-3.0-only ISC MPL-2.0 CC0-1.0].freeze

    def initialize(config)
      @config = config
      @root_dir = config.root_dir
    end

    def audit
      issues = []
      checks_run = 0

      resolver = FileResolver.new(@config)
      spec, _path = resolver.load_gemspec
      checks_run += 1

      audit_gemspec_metadata(spec, issues)
      checks_run += 1

      entries, pruned = resolver.resolve_entries(spec)
      checks_run += 1

      audit_supply_chain_and_files(entries, pruned, issues)
      checks_run += 1

      audit_executables(spec, entries, issues)
      checks_run += 1

      audit_git_cleanliness(issues)
      checks_run += 1

      CheckReport.new(
        gem_name: spec.name,
        gem_version: spec.version.to_s,
        issues: issues,
        checks_run: checks_run
      )
    end

    private

    def audit_gemspec_metadata(spec, issues)
      if spec.name.to_s.strip.empty?
        issues << CheckIssue.new(level: :fail, category: :gemspec, message: "Gemspec is missing required field: name")
      end

      if spec.version.nil? || spec.version.to_s.strip.empty?
        issues << CheckIssue.new(level: :fail, category: :gemspec, message: "Gemspec is missing required field: version")
      end

      if spec.summary.to_s.strip.empty? || spec.summary.to_s.include?("TODO")
        issues << CheckIssue.new(level: :warn, category: :gemspec, message: "Gemspec summary is empty or contains placeholder TODO")
      end

      if Array(spec.authors).empty? || Array(spec.authors).any? { |a| a.to_s.include?("TODO") }
        issues << CheckIssue.new(level: :warn, category: :gemspec, message: "Gemspec authors list is empty or contains placeholder TODO")
      end

      licenses = Array(spec.licenses)
      if licenses.empty?
        issues << CheckIssue.new(level: :fail, category: :gemspec, message: "No license specified in gemspec (e.g. spec.license = 'MIT')")
      else
        licenses.each do |lic|
          unless KNOWN_SPDX.include?(lic)
            issues << CheckIssue.new(level: :warn, category: :gemspec, message: "License '#{lic}' is not a recognized standard SPDX identifier")
          end
        end
      end

      if spec.required_ruby_version.nil?
        issues << CheckIssue.new(level: :warn, category: :gemspec, message: "required_ruby_version is not declared (e.g. spec.required_ruby_version = '>= 3.0.0')")
      end

      metadata = spec.metadata || {}
      if metadata["source_code_uri"].to_s.empty? && spec.homepage.to_s.empty?
        issues << CheckIssue.new(level: :warn, category: :gemspec, message: "No source_code_uri or homepage configured in gemspec metadata")
      end
    end

    def audit_supply_chain_and_files(entries, pruned, issues)
      entries.each do |gem_path, entry|
        if FileResolver::SECRET_PATTERNS.any? { |pat| pat.match?(gem_path) }
          issues << CheckIssue.new(level: :fail, category: :security, message: "Potential secret file included in package: #{gem_path}")
        end

        if entry.source_path && File.exist?(entry.source_path)
          stat = File.lstat(entry.source_path)
          if (stat.mode & 0o002) != 0
            issues << CheckIssue.new(level: :warn, category: :security, message: "World-writable file found: #{gem_path} (mode: #{format('0%o', stat.mode & 0o777)})")
          end

          if stat.size > 2 * 1024 * 1024 # 2MB
            issues << CheckIssue.new(level: :warn, category: :budget, message: "Large single file in package (> 2MB): #{gem_path} (#{stat.size / 1024} KB)")
          end
        end
      end

      pruned.each do |pruned_path|
        issues << CheckIssue.new(level: :info, category: :security, message: "Excluded sensitive/temporary path from gem: #{pruned_path}")
      end
    end

    def audit_executables(spec, entries, issues)
      executables = Array(spec.executables)

      executables.each do |exe_name|
        candidate_dirs = [spec.bindir, "exe", "bin"].compact.uniq
        found_rel = candidate_dirs.map { |d| File.join(d, exe_name) }.find { |rel| File.file?(File.expand_path(rel, @root_dir)) }

        unless found_rel
          issues << CheckIssue.new(level: :fail, category: :executable, message: "Declared executable file missing on disk: #{File.join(spec.bindir || 'exe', exe_name)}")
          next
        end

        full_path = File.expand_path(found_rel, @root_dir)
        stat = File.lstat(full_path)
        unless (stat.mode & 0o111) != 0
          issues << CheckIssue.new(level: :warn, category: :executable, message: "Executable #{found_rel} does not have executable bit set (mode: #{format('0%o', stat.mode & 0o777)})")
        end

        first_line = File.open(full_path, "r", &:gets).to_s.strip
        unless first_line.start_with?("#!") && first_line.include?("ruby")
          issues << CheckIssue.new(level: :warn, category: :executable, message: "Executable #{found_rel} lacks a valid Ruby shebang (got: #{first_line.inspect})")
        end
      end
    end

    def audit_git_cleanliness(issues)
      return unless Dir.exist?(File.join(@root_dir, ".git"))

      stdout, _stderr, status = Open3.capture3("git", "status", "--porcelain", chdir: @root_dir)
      return unless status.success?

      changes = stdout.lines.map(&:strip).reject(&:empty?)
      return if changes.empty?

      untracked = changes.select { |l| l.start_with?("??") }
      modified  = changes.reject { |l| l.start_with?("??") }

      if modified.any?
        issues << CheckIssue.new(level: :warn, category: :git, message: "Working tree has #{modified.size} uncommitted modified file(s)")
      end

      lib_untracked = untracked.select { |l| l.include?("lib/") || l.include?("exe/") }
      if lib_untracked.any?
        issues << CheckIssue.new(level: :warn, category: :git, message: "Untracked files exist in lib/ or exe/: #{lib_untracked.map { |l| l.sub(/^\?\?\s+/, '') }.join(', ')}")
      end
    rescue StandardError
      nil
    end
  end
end
