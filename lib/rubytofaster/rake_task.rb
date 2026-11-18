# frozen_string_literal: true

require "rake"
require "rake/tasklib"
require_relative "../rubytofaster"

module RubyToFaster
  # Zero-dependency Rake integration for RubyToFaster.
  # Drop-in replacement for `Bundler::GemHelper.install_tasks`.
  #
  # Usage in Rakefile:
  #   require "rubytofaster/rake_task"
  #   RubyToFaster::RakeTask.new
  class RakeTask < ::Rake::TaskLib
    attr_accessor :name, :gemspec, :out_dir, :incremental

    def initialize(name = :build)
      @name        = name
      @gemspec     = nil
      @out_dir     = "pkg"
      @incremental = true

      yield self if block_given?
      define_tasks
    end

    private

    def define_tasks
      desc "Build gem with RubyToFaster (Merkle cached)"
      task(name) do
        RubyToFaster.build do |cfg|
          cfg.gemspec(@gemspec) if @gemspec
          cfg.out_dir = @out_dir
          cfg.incremental = @incremental
        end
      end

      namespace :rtf do
        desc "Build gem with RubyToFaster"
        task(:build => name)

        desc "Build and install gem locally"
        task :install => name do
          built = Dir.glob(File.join(@out_dir, "*.gem")).max_by { |f| File.mtime(f) }
          raise "No built gem found in #{@out_dir}" unless built

          sh "gem install --local #{built} --no-document"
        end

        desc "Clean build artifacts and Merkle cache"
        task :clean do
          RubyToFaster::CLI.start(["clean"])
        end

        desc "Audit gem supply-chain security and gemspec"
        task :check do
          cfg = RubyToFaster::Config.new
          cfg.gemspec(@gemspec) if @gemspec
          report = RubyToFaster::Checker.new(cfg).audit
          RubyToFaster::Reporter.new.report_check(report)
          exit(1) unless report.passed?
        end

        desc "Benchmark RubyToFaster vs standard gem build"
        task :bench do
          cfg = RubyToFaster::Config.new
          cfg.gemspec(@gemspec) if @gemspec
          report = RubyToFaster::Benchmarker.new(cfg).run
          RubyToFaster::Reporter.new.report_benchmark(report)
        end
      end
    end
  end
end
