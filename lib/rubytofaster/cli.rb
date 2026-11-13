# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "rbconfig"

module RubyToFaster
  # Minimalist zero-dependency command-line interface (`rubytofaster` / `rtf`).
  class CLI
    DEFAULT_SCRIPT_NAMES = %w[gem.build.rb build.rtf.rb Fastbuild.rb].freeze

    def self.start(argv = ARGV, out: $stdout, err: $stderr)
      new(argv, out: out, err: err).run
    end

    def initialize(argv, out: $stdout, err: $stderr)
      @argv = argv.dup
      @out  = out
      @err  = err
    end

    def run
      if @argv.first == "-v" || @argv.first == "--version"
        @out.puts "rubytofaster #{RubyToFaster::VERSION}"
        return 0
      end

      if @argv.first == "-h" || @argv.first == "--help"
        print_help
        return 0
      end

      command = if @argv.empty? || @argv.first.start_with?("-")
                  "build"
                else
                  @argv.shift
                end

      case command
      when "build"   then cmd_build
      when "init"    then cmd_init
      when "inspect" then cmd_inspect
      when "clean"   then cmd_clean
      when "doctor"  then cmd_doctor
      when "watch"   then cmd_watch
      when "version"
        @out.puts "rubytofaster #{RubyToFaster::VERSION}"
        0
      when "help"
        print_help
        0
      else
        # Allow `rtf my_script.rb` or `rtf my_gem.gemspec` directly as shorthand for `rtf build <target>`
        if File.file?(command)
          @argv.unshift(command)
          cmd_build
        else
          @err.puts "Unknown command: #{command}. Run `rtf --help` for usage."
          1
        end
      end
    rescue RubyToFaster::Error => e
      @err.puts "[RubyToFaster::#{e.class.name.split('::').last}] #{e.message}"
      1
    end

    private

    def cmd_build
      opts = {
        incremental: true,
        skip_assets: false,
        skip_extensions: false,
        out_dir: nil,
        json: false,
        quiet: false,
        verbose: false
      }

      parser = OptionParser.new do |o|
        o.banner = "Usage: rtf build [gem.build.rb | my_gem.gemspec] [options]"
        o.on("--no-cache", "Disable content-addressable incremental cache") { opts[:incremental] = false }
        o.on("--skip-assets", "Skip Angular, Vite, and Next.js resource collection") { opts[:skip_assets] = true }
        o.on("--skip-extensions", "Skip native extension compilation check") { opts[:skip_extensions] = true }
        o.on("-o", "--out-dir DIR", "Output directory for built .gem (default: pkg)") { |d| opts[:out_dir] = d }
        o.on("--json", "Emit structured JSON build summary") { opts[:json] = true }
        o.on("-q", "--quiet", "Suppress terminal output") { opts[:quiet] = true }
        o.on("-V", "--verbose", "Show per-stage monotonic timing breakdown") { opts[:verbose] = true }
      end
      parser.parse!(@argv)

      target = @argv.first
      result = execute_build_target(target, opts)
      Reporter.new(io: @out, json: opts[:json], quiet: opts[:quiet], verbose: opts[:verbose]).report_build(result)
      0
    end

    def execute_build_target(target, opts)
      script_path = resolve_script_target(target)
      if script_path
        config = RubyToFaster.load_script_config(script_path)
        apply_cli_overrides!(config, opts)
        return Compiler.new(config).run
      end

      RubyToFaster.build(root_dir: Dir.pwd, report: false) do |cfg|
        cfg.gemspec(target) if target && target.end_with?(".gemspec")
        apply_cli_overrides!(cfg, opts)
      end
    end

    def resolve_script_target(target)
      if target
        raise ConfigError, "Target file not found: #{target}" unless File.file?(target)

        return File.expand_path(target) if target.end_with?(".rb")

        return nil
      end

      found = DEFAULT_SCRIPT_NAMES.find { |name| File.file?(name) }
      found ? File.expand_path(found) : nil
    end

    def apply_cli_overrides!(config, opts)
      config.incremental     = false unless opts[:incremental]
      config.skip_assets     = true  if opts[:skip_assets]
      config.skip_extensions = true  if opts[:skip_extensions]
      config.out_dir         = opts[:out_dir] if opts[:out_dir]
      config.quiet           = opts[:quiet]
      config.verbose         = opts[:verbose]
    end

    def cmd_init
      opts = { vite: false, nextjs: false, angular: false, force: false, file: "gem.build.rb" }
      OptionParser.new do |o|
        o.banner = "Usage: rtf init [options]"
        o.on("--vite", "Include Vite resource pipeline configuration") { opts[:vite] = true }
        o.on("--nextjs", "Include Next.js resource pipeline configuration") { opts[:nextjs] = true }
        o.on("--angular", "Include Angular resource pipeline configuration") { opts[:angular] = true }
        o.on("-f", "--file PATH", "Script filename (default: gem.build.rb)") { |f| opts[:file] = f }
        o.on("--force", "Overwrite existing build script") { opts[:force] = true }
      end.parse!(@argv)

      dest = File.expand_path(opts[:file], Dir.pwd)
      if File.exist?(dest) && !opts[:force]
        raise ConfigError, "#{opts[:file]} already exists (pass --force to overwrite)."
      end

      gemspec_file = Dir.glob("*.gemspec").first || "my_gem.gemspec"
      lines = [
        "#!/usr/bin/env ruby",
        "# frozen_string_literal: true",
        "",
        'require "rubytofaster"',
        "",
        "RubyToFaster.build do |pkg|",
        "  pkg.gemspec #{gemspec_file.dump}",
        "  pkg.incremental = true"
      ]
      lines << '  pkg.vite root: "frontend", out_dir: "dist", mount_to: "public/vite"' if opts[:vite]
      lines << '  pkg.nextjs root: "web", mode: :auto, mount_to: "public/nextjs"' if opts[:nextjs]
      lines << '  pkg.angular root: "admin", mount_to: "public/angular"' if opts[:angular]
      lines << "  pkg.budget max_compressed_kb: 512, max_unpacked_kb: 2048"
      lines << "end"
      lines << ""

      File.write(dest, lines.join("\n"))
      File.chmod(0o755, dest)
      @out.puts "Created executable compiler script: #{opts[:file]}"
      0
    end

    def cmd_inspect
      json = false
      OptionParser.new do |o|
        o.banner = "Usage: rtf inspect <path/to/file.gem> [--json]"
        o.on("--json", "Emit JSON inspection output") { json = true }
      end.parse!(@argv)

      gem_file = @argv.first
      raise ConfigError, "Usage: rtf inspect <path/to/file.gem>" unless gem_file

      info = Inspector.inspect_gem(gem_file)
      Reporter.new(io: @out, json: json).report_inspection(info)
      0
    end

    def cmd_clean
      cfg = Config.new(root_dir: Dir.pwd)
      Cache.new(cfg).clear!
      FileUtils.rm_rf(cfg.resolved_out_dir) if Dir.exist?(cfg.resolved_out_dir)
      @out.puts "Cleaned #{cfg.cache_dir}/ and #{cfg.out_dir}/"
      0
    end

    def cmd_doctor
      checks = {
        rubytofaster_version: RubyToFaster::VERSION,
        ruby_version: RUBY_VERSION,
        ruby_platform: RUBY_PLATFORM,
        rubygems_version: Gem::VERSION,
        gemspecs_found: Dir.glob("*.gemspec").sort,
        build_scripts_found: DEFAULT_SCRIPT_NAMES.select { |f| File.file?(f) },
        detected_frameworks: {
          vite: Resources::Vite.detect?(Dir.pwd),
          nextjs: Resources::Nextjs.detect?(Dir.pwd),
          angular: Resources::Angular.detect?(Dir.pwd)
        }
      }
      @out.puts JSON.pretty_generate(checks)
      0
    end

    def cmd_watch
      interval = 0.5
      max_cycles = nil
      OptionParser.new do |o|
        o.banner = "Usage: rtf watch [script_or_gemspec] [--interval SECONDS]"
        o.on("-i", "--interval SEC", Float, "Polling interval in seconds (default: 0.5)") { |s| interval = s }
        o.on("--cycles N", Integer, "Stop after N watch cycles (for automated testing)") { |n| max_cycles = n }
      end.parse!(@argv)

      target = @argv.first
      last_signature = nil
      cycles = 0

      @out.puts "Watching #{Dir.pwd} for changes (Ctrl+C to stop)..."
      loop do
        sig = workspace_mtime_signature
        if sig != last_signature
          last_signature = sig
          begin
            res = execute_build_target(target, { incremental: true })
            Reporter.new(io: @out).report_build(res)
          rescue RubyToFaster::Error => e
            @err.puts "[Build Error] #{e.message}"
          end
        end

        cycles += 1
        break if max_cycles && cycles >= max_cycles

        sleep(interval)
      end
      0
    rescue Interrupt
      @out.puts "\nStopped watch mode."
      0
    end

    def workspace_mtime_signature
      files = Dir.glob("{lib,exe,ext,*.gemspec,gem.build.rb}/**/*", File::FNM_DOTMATCH).select { |f| File.file?(f) }
      files += Dir.glob("{*.gemspec,gem.build.rb}").select { |f| File.file?(f) }
      files.uniq.sort.map { |f| "#{f}:#{File.mtime(f).to_f}" }.join("|")
    end

    def print_help
      @out.puts <<~HELP
        RubyToFaster (rtf) v#{RubyToFaster::VERSION}
        Minimalist, script-first Ruby gem compiler with Angular, Vite, and Next.js resources.

        Usage:
          rtf [build] [gem.build.rb | *.gemspec] [options]
          rtf init [--vite] [--nextjs] [--angular]
          rtf inspect <pkg/name-version.gem> [--json]
          rtf watch [gem.build.rb]
          rtf clean
          rtf doctor
          rtf version

        Build Options:
          --no-cache         Rebuild from scratch ignoring .rtf-cache
          --skip-assets      Skip frontend resource collection
          --skip-extensions  Skip native C/Rust extension verification
          -o, --out-dir DIR  Output directory (default: pkg)
          --json             Output structured JSON metrics
          -q, --quiet        Suppress build output
          -V, --verbose      Print per-stage monotonic timings
      HELP
    end
  end
end
