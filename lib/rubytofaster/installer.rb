# frozen_string_literal: true

require "open3"
require "rubygems"

module RubyToFaster
  # Immutable result returned by `Installer#install`.
  InstallResult = Struct.new(
    :gem_name,
    :gem_version,
    :gem_path,
    :success,
    :stdout,
    :stderr,
    :duration_ms,
    keyword_init: true
  )

  # Installs compiled `.gem` packages directly into the active Ruby environment (`gem install --local`).
  class Installer
    def initialize(out: $stdout, err: $stderr)
      @out = out
      @err = err
    end

    def install(gem_path, options = {})
      raise ConfigError, "Gem archive not found: #{gem_path}" unless File.file?(gem_path)

      t0 = monotonic_ms
      cmd = [RbConfig.ruby, "-S", "gem", "install", "--local", File.expand_path(gem_path)]

      cmd << "--prerelease" if options[:prerelease]
      cmd << "--user-install" if options[:user_install]
      cmd << "--force" if options[:force]

      if options.key?(:document)
        cmd << (options[:document] ? "--document" : "--no-document")
      else
        cmd << "--no-document"
      end

      cmd.concat(Array(options[:extra_args]))

      env = { "CI" => "true" }
      stdout, stderr, status = Open3.capture3(env, *cmd)
      duration_ms = (monotonic_ms - t0).round(2)

      gem_basename = File.basename(gem_path, ".gem")
      parts = gem_basename.rpartition("-")
      name = parts.first.empty? ? gem_basename : parts.first
      version = parts.last

      InstallResult.new(
        gem_name: name,
        gem_version: version,
        gem_path: gem_path,
        success: status.success?,
        stdout: stdout,
        stderr: stderr,
        duration_ms: duration_ms
      )
    end

    private

    def monotonic_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
    end
  end
end
