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
      when "build"       then cmd_build
      when "install"     then cmd_install
      when "diff"        then cmd_diff
      when "check"       then cmd_check
      when "audit"       then cmd_check
      when "bench"       then cmd_bench
      when "benchmark"   then cmd_bench
      when "sbom"        then cmd_sbom
      when "stats"       then cmd_stats
      when "size"        then cmd_stats
      when "verify"      then cmd_verify
      when "workspace"   then cmd_workspace
      when "ws"          then cmd_workspace
      when "init"        then cmd_init
      when "inspect"     then cmd_inspect
      when "clean"       then cmd_clean
      when "doctor"      then cmd_doctor
      when "watch"       then cmd_watch
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
        precompress: nil,
        sbom: nil,
        checksums_file: false,
        json: false,
        quiet: false,
        verbose: false
      }

      parser = OptionParser.new do |o|
        o.banner = "Usage: rtf build [gem.build.rb | my_gem.gemspec] [options]"
        o.on("--no-cache", "Disable content-addressable incremental cache") { opts[:incremental] = false }
        o.on("--skip-assets", "Skip frontend resource collection") { opts[:skip_assets] = true }
        o.on("--skip-extensions", "Skip native C/Rust extension compilation check") { opts[:skip_extensions] = true }
        o.on("--precompress", "Generate deterministic .gz files for staged frontend assets") { opts[:precompress] = true }
        o.on("--sbom FORMAT", "Embed SBOM inside gem (cyclonedx or spdx)") { |f| opts[:sbom] = f.to_sym }
        o.on("--checksums", "Write <gem>.sha256 checksum file alongside built archive") { opts[:checksums_file] = true }
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

      target_dir = (target && target.end_with?(".gemspec") && File.file?(target)) ? File.dirname(File.expand_path(target)) : Dir.pwd
      spec_arg   = (target && target.end_with?(".gemspec") && File.file?(target)) ? File.basename(target) : target

      RubyToFaster.build(root_dir: target_dir, report: false) do |cfg|
        cfg.gemspec(spec_arg) if spec_arg && spec_arg.end_with?(".gemspec")
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
      config.precompress     = true  if opts[:precompress]
      config.sbom            = opts[:sbom] if opts[:sbom]
      config.checksums_file  = true  if opts[:checksums_file]
      config.quiet           = opts[:quiet]
      config.verbose         = opts[:verbose]
    end

    def load_config_for_target(target)
      target_dir = (target && File.file?(target)) ? File.dirname(File.expand_path(target)) : Dir.pwd
      if target && target.end_with?(".rb") && File.file?(target)
        RubyToFaster.load_script_config(target)
      elsif target.nil? && (default_script = DEFAULT_SCRIPT_NAMES.find { |f| File.file?(f) })
        RubyToFaster.load_script_config(default_script)
      else
        cfg = Config.new(root_dir: target_dir)
        cfg.gemspec(File.basename(target)) if target && target.end_with?(".gemspec")
        cfg
      end
    end

    def cmd_install
      opts = {
        prerelease: false,
        user_install: false,
        force: false,
        document: false,
        incremental: true,
        skip_assets: false,
        skip_extensions: false,
        quiet: false,
        json: false
      }
      parser = OptionParser.new do |o|
        o.banner = "Usage: rtf install [gem.build.rb | *.gemspec | pkg/*.gem] [options]"
        o.on("--no-cache", "Disable incremental cache for compilation before install") { opts[:incremental] = false }
        o.on("--prerelease", "Install as prerelease gem") { opts[:prerelease] = true }
        o.on("--user-install", "Install in user's home directory") { opts[:user_install] = true }
        o.on("-f", "--force", "Force gem installation, ignoring conflicts") { opts[:force] = true }
        o.on("--document", "Generate RI and HTML documentation") { opts[:document] = true }
        o.on("--json", "Emit structured JSON result") { opts[:json] = true }
        o.on("-q", "--quiet", "Suppress output") { opts[:quiet] = true }
      end
      parser.parse!(@argv)

      target = @argv.first
      gem_path = if target && target.end_with?(".gem") && File.file?(target)
                   target
                 else
                   res = execute_build_target(target, opts)
                   res.gem_path
                 end

      result = Installer.new(out: @out, err: @err).install(gem_path, opts)
      Reporter.new(io: @out, json: opts[:json], quiet: opts[:quiet]).report_install(result)
      result.success ? 0 : 1
    end

    def cmd_diff
      opts = { json: false }
      OptionParser.new do |o|
        o.banner = "Usage: rtf diff <target_a.gem> [target_b.gem] [--json]"
        o.on("--json", "Emit structured JSON package diff") { opts[:json] = true }
      end.parse!(@argv)

      gem_a = @argv[0]
      gem_b = @argv[1]

      raise ConfigError, "Usage: rtf diff <target_a.gem> [target_b.gem]" unless gem_a

      unless gem_b
        res = execute_build_target(nil, { incremental: true, quiet: true })
        gem_b = res.gem_path
      end

      diff_result = Differ.diff(gem_a, gem_b)
      Reporter.new(io: @out, json: opts[:json]).report_diff(diff_result)
      0
    end

    def cmd_check
      opts = { strict: false, json: false, quiet: false }
      OptionParser.new do |o|
        o.banner = "Usage: rtf check [gem.build.rb | *.gemspec] [options]"
        o.on("-s", "--strict", "Treat warnings as failures (exit code 1)") { opts[:strict] = true }
        o.on("--json", "Emit structured JSON report") { opts[:json] = true }
        o.on("-q", "--quiet", "Suppress non-error output") { opts[:quiet] = true }
      end.parse!(@argv)

      target = @argv.first
      config = load_config_for_target(target)

      report = Checker.new(config).audit
      Reporter.new(io: @out, json: opts[:json], quiet: opts[:quiet]).report_check(report)

      if report.fails.any?
        1
      elsif opts[:strict] && report.warnings.any?
        1
      else
        0
      end
    end

    def cmd_bench
      opts = { iterations: 3, json: false }
      OptionParser.new do |o|
        o.banner = "Usage: rtf bench [gem.build.rb | *.gemspec] [--iterations N] [--json]"
        o.on("-n", "--iterations N", Integer, "Number of benchmark iterations (default: 3)") { |n| opts[:iterations] = n }
        o.on("--json", "Emit structured JSON benchmark report") { opts[:json] = true }
      end.parse!(@argv)

      target = @argv.first
      config = load_config_for_target(target)

      report = Benchmarker.new(config, iterations: opts[:iterations]).run
      Reporter.new(io: @out, json: opts[:json]).report_benchmark(report)
      0
    end

    def cmd_sbom
      opts = { format: :cyclonedx, out_file: nil }
      OptionParser.new do |o|
        o.banner = "Usage: rtf sbom [gem.build.rb | *.gemspec] [--format cyclonedx|spdx] [-o path]"
        o.on("-f", "--format FORMAT", "SBOM format: cyclonedx (default) or spdx") { |f| opts[:format] = f.to_sym }
        o.on("-o", "--output FILE", "Write SBOM JSON to a file instead of stdout") { |p| opts[:out_file] = p }
      end.parse!(@argv)

      target = @argv.first
      config = load_config_for_target(target)
      json_str = RubyToFaster.sbom(config: config, format: opts[:format])

      if opts[:out_file]
        FileUtils.mkdir_p(File.dirname(File.expand_path(opts[:out_file])))
        File.write(opts[:out_file], json_str)
        @out.puts "Wrote #{opts[:format]} SBOM to #{opts[:out_file]} (#{json_str.bytesize} bytes)"
      else
        @out.print json_str
      end
      0
    end

    def cmd_stats
      opts = { top: 10, json: false }
      OptionParser.new do |o|
        o.banner = "Usage: rtf stats [pkg/name.gem | gem.build.rb] [--top N] [--json]"
        o.on("-t", "--top N", Integer, "Number of largest files to list (default: 10)") { |n| opts[:top] = n }
        o.on("--json", "Emit structured JSON stats report") { opts[:json] = true }
      end.parse!(@argv)

      target = @argv.first
      gem_path = if target && target.end_with?(".gem") && File.file?(target)
                   target
                 else
                   res = execute_build_target(target, { incremental: true, quiet: true })
                   res.gem_path
                 end

      stats = Analyzer.analyze(gem_path, top: opts[:top])
      Reporter.new(io: @out, json: opts[:json]).report_stats(stats)
      0
    end

    def cmd_verify
      opts = { expected_sha256: nil, reproducible: false, json: false }
      OptionParser.new do |o|
        o.banner = "Usage: rtf verify [pkg/name.gem | gem.build.rb] [--sha256 HASH] [--reproducible] [--json]"
        o.on("--sha256 HASH", "Verify package matches expected SHA-256 digest") { |h| opts[:expected_sha256] = h }
        o.on("--reproducible", "Perform two isolated clean builds and verify bit-for-bit identical SHA-256") { opts[:reproducible] = true }
        o.on("--json", "Emit structured JSON verification report") { opts[:json] = true }
      end.parse!(@argv)

      target = @argv.first
      report = if opts[:reproducible]
                 config = load_config_for_target(target)
                 Verifier.verify_reproducible(config)
               else
                 gem_path = if target && target.end_with?(".gem")
                              target
                            else
                              res = execute_build_target(target, { incremental: true, quiet: true })
                              res.gem_path
                            end
                 Verifier.verify_gem(gem_path, expected_sha256: opts[:expected_sha256])
               end

      Reporter.new(io: @out, json: opts[:json]).report_verify(report)
      report.passed? ? 0 : 1
    end

    def cmd_workspace
      sub = @argv.first && !@argv.first.start_with?("-") ? @argv.shift : "build"
      opts = { incremental: true, strict: false, patterns: nil, json: false }

      OptionParser.new do |o|
        o.banner = "Usage: rtf workspace [build|check|clean] [options]"
        o.on("--no-cache", "Disable incremental cache for workspace builds") { opts[:incremental] = false }
        o.on("-s", "--strict", "Fail workspace check on warnings") { opts[:strict] = true }
        o.on("-p", "--pattern GLOB", "Workspace glob pattern (repeatable)") { |g| (opts[:patterns] ||= []) << g }
        o.on("--json", "Emit structured JSON workspace report") { opts[:json] = true }
      end.parse!(@argv)

      ws = Workspace.new(root_dir: Dir.pwd, patterns: opts[:patterns])
      report = case sub
               when "build" then ws.build_all(incremental: opts[:incremental])
               when "check" then ws.check_all(strict: opts[:strict])
               when "clean" then ws.clean_all
               else
                 raise ConfigError, "Unknown workspace subcommand: #{sub} (expected build, check, or clean)"
               end

      Reporter.new(io: @out, json: opts[:json]).report_workspace(report)
      report.success? ? 0 : 1
    end

    def cmd_init
      opts = {
        vite: false, nextjs: false, angular: false, tailwind: false, esbuild: false,
        astro: false, sveltekit: false, nuxt: false, webpack: false, parcel: false, sass: false,
        precompress: false, sbom: false, force: false, file: "gem.build.rb"
      }
      OptionParser.new do |o|
        o.banner = "Usage: rtf init [options]"
        o.on("--vite", "Include Vite resource pipeline configuration") { opts[:vite] = true }
        o.on("--nextjs", "Include Next.js resource pipeline configuration") { opts[:nextjs] = true }
        o.on("--angular", "Include Angular resource pipeline configuration") { opts[:angular] = true }
        o.on("--tailwind", "Include Tailwind CSS pipeline configuration") { opts[:tailwind] = true }
        o.on("--esbuild", "Include Esbuild resource pipeline configuration") { opts[:esbuild] = true }
        o.on("--astro", "Include Astro resource pipeline configuration") { opts[:astro] = true }
        o.on("--sveltekit", "Include SvelteKit resource pipeline configuration") { opts[:sveltekit] = true }
        o.on("--nuxt", "Include Nuxt resource pipeline configuration") { opts[:nuxt] = true }
        o.on("--webpack", "Include Webpack resource pipeline configuration") { opts[:webpack] = true }
        o.on("--parcel", "Include Parcel resource pipeline configuration") { opts[:parcel] = true }
        o.on("--sass", "Include Dart Sass/SCSS pipeline configuration") { opts[:sass] = true }
        o.on("--precompress", "Enable deterministic .gz asset precompression") { opts[:precompress] = true }
        o.on("--sbom", "Embed CycloneDX SBOM inside compiled gem") { opts[:sbom] = true }
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
      lines << '  pkg.astro root: "docs_ui", mount_to: "public/astro"' if opts[:astro]
      lines << '  pkg.sveltekit root: "svelte_ui", mount_to: "public/sveltekit"' if opts[:sveltekit]
      lines << '  pkg.nuxt root: "nuxt_ui", mount_to: "public/nuxt"' if opts[:nuxt]
      lines << '  pkg.webpack root: "assets", mount_to: "public/webpack"' if opts[:webpack]
      lines << '  pkg.parcel root: "parcel_ui", out_dir: "dist", mount_to: "public/parcel"' if opts[:parcel]
      lines << '  pkg.tailwind input: "src/input.css", output: "dist/tailwind.css", mount_to: "public/tailwind"' if opts[:tailwind]
      lines << '  pkg.sass input: "src/styles/main.scss", output: "dist/application.css", mount_to: "public/sass"' if opts[:sass]
      lines << '  pkg.esbuild entrypoints: ["src/index.js"], out_dir: "dist", mount_to: "public/esbuild"' if opts[:esbuild]
      lines << "  pkg.precompress_assets true" if opts[:precompress]
      lines << "  pkg.embed_sbom :cyclonedx" if opts[:sbom]
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
          angular: Resources::Angular.detect?(Dir.pwd),
          astro: Resources::Astro.detect?(Dir.pwd),
          sveltekit: Resources::SvelteKit.detect?(Dir.pwd),
          nuxt: Resources::Nuxt.detect?(Dir.pwd),
          webpack: Resources::Webpack.detect?(Dir.pwd),
          parcel: Resources::Parcel.detect?(Dir.pwd),
          tailwind: Resources::Tailwind.detect?(Dir.pwd),
          sass: Resources::Sass.detect?(Dir.pwd),
          esbuild: Resources::Esbuild.detect?(Dir.pwd)
        },
        toolchain: {
          node: detect_tool_version("node", "-v"),
          npm: detect_tool_version("npm", "-v"),
          pnpm: detect_tool_version("pnpm", "-v"),
          yarn: detect_tool_version("yarn", "-v"),
          bun: detect_tool_version("bun", "-v"),
          tailwindcss: detect_tool_version("tailwindcss", "--help") ? "present" : nil,
          sass: detect_tool_version("sass", "--version"),
          esbuild: detect_tool_version("esbuild", "--version"),
          cargo: detect_tool_version("cargo", "--version"),
          rustc: detect_tool_version("rustc", "--version"),
          make: detect_tool_version("make", "--version") ? "present" : nil,
          c_compiler: (detect_tool_version("gcc", "-v") || detect_tool_version("clang", "-v") || detect_tool_version("cc", "-v")) ? "present" : nil
        }
      }
      @out.puts JSON.pretty_generate(checks)
      0
    end

    def detect_tool_version(bin, *args)
      out, _err, status = Open3.capture3(bin, *args)
      status.success? ? out.strip.lines.first.to_s.strip : nil
    rescue StandardError
      nil
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
        Minimalist, script-first Ruby gem compiler with 11 frontend pipelines, Rust/C extensions & SBOM.

        Usage:
          rtf [build] [gem.build.rb | *.gemspec] [options]
          rtf install [gem.build.rb | *.gem] [--prerelease] [--user-install]
          rtf diff <target_a.gem> [target_b.gem] [--json]
          rtf check [gem.build.rb | *.gemspec] [--strict] [--json]
          rtf bench [gem.build.rb | *.gemspec] [--iterations N] [--json]
          rtf sbom [gem.build.rb | *.gemspec] [--format cyclonedx|spdx] [-o FILE]
          rtf stats [pkg/name.gem | gem.build.rb] [--top N] [--json]
          rtf verify [pkg/name.gem | gem.build.rb] [--sha256 HASH] [--reproducible] [--json]
          rtf workspace [build|check|clean] [--no-cache] [--strict] [--json]
          rtf init [--vite|--nextjs|--angular|--astro|--sveltekit|--nuxt|--webpack|--parcel|--tailwind|--sass|--esbuild]
          rtf inspect <pkg/name-version.gem> [--json]
          rtf watch [gem.build.rb]
          rtf clean
          rtf doctor
          rtf version

        Build Options:
          --no-cache         Rebuild from scratch ignoring .rtf-cache
          --skip-assets      Skip frontend resource collection
          --skip-extensions  Skip native C/Rust extension verification
          --precompress      Generate deterministic .gz files for staged assets
          --sbom FORMAT      Embed CycloneDX or SPDX SBOM inside the .gem
          --checksums        Write <name>.gem.sha256 alongside built package
          -o, --out-dir DIR  Output directory (default: pkg)
          --json             Output structured JSON metrics
          -q, --quiet        Suppress build output
          -V, --verbose      Print per-stage monotonic timings
      HELP
    end
  end
end
