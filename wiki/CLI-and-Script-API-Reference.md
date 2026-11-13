# CLI & Script API Reference

## CLI Commands (`rtf` / `rubytofaster`)

| Command | Description |
| :--- | :--- |
| `rtf [build] [target]` | Compiles `.gem` from `gem.build.rb`, `*.gemspec`, or explicit target script/gemspec. |
| `rtf init [flags]` | Generates an executable `gem.build.rb` script (`--vite`, `--nextjs`, `--angular`, `--force`, `-f PATH`). |
| `rtf inspect <file.gem>` | Verifies SHA-256/SHA-512 checksums and prints file table & frontend manifests (`--json`). |
| `rtf watch [target]` | Watches source files and runs incremental builds (`-i SECONDS`). |
| `rtf doctor` | Prints JSON diagnostics for Ruby, RubyGems, gemspecs, and detected frontend frameworks. |
| `rtf clean` | Deletes `.rtf-cache/` and `pkg/`. |
| `rtf version` | Prints `rubytofaster` version (`-v`, `--version`). |

### `rtf build` Options

- `--no-cache` — Ignore `.rtf-cache` and force a fresh package build.
- `--skip-assets` — Skip Vite, Next.js, and Angular resource collection.
- `--skip-extensions` — Skip native C/Rust extension verification.
- `-o, --out-dir DIR` — Output directory for the compiled `.gem` (default: `pkg`).
- `--json` — Print structured JSON build telemetry (`BuildResult#to_h`).
- `-q, --quiet` — Suppress stdout summary.
- `-V, --verbose` — Display per-stage monotonic timings (`resolve_ms`, `resources_ms`, `cache_ms`, `extensions_ms`, `package_ms`).

---

## Ruby Script DSL (`RubyToFaster.build`)

```ruby
result = RubyToFaster.build(root_dir: __dir__, report: true) do |pkg|
  # 1. Gem specification source
  pkg.gemspec "my_gem.gemspec"
  # OR inline:
  # pkg.spec { |s| s.name = "my_gem"; ... }

  # 2. Output & Caching
  pkg.output_dir "pkg"
  pkg.cache true, dir: ".rtf-cache"
  pkg.reproducible = true
  pkg.source_date_epoch = 1_700_000_000
  pkg.parallel 4

  # 3. File Inclusion & Pruning
  pkg.include_files "config/locales/*.yml"
  pkg.exclude "spec/**/*", "docs/**/*"

  # 4. Frontend Resource Adapters
  pkg.vite    root: "frontend", out_dir: "dist", mount_to: "public/vite"
  pkg.nextjs  root: "portal",   mode: :auto,     mount_to: "public/nextjs"
  pkg.angular root: "admin",    project: "app",  mount_to: "public/angular"
  pkg.generate_asset_helper module_name: "MyGem::Assets", path: "lib/my_gem/assets.rb"
  pkg.write_staged_assets = false

  # 5. Angular-Style Size Budgets
  pkg.budget(
    max_compressed_kb: 512,
    max_unpacked_kb: 2048,
    max_entry_kb: 256,
    warn_ratio: 0.85
  )

  # 6. Lifecycle Hooks & Plugins
  pkg.use MyCustomPlugin.new
  pkg.before_resolve  { |cfg| }
  pkg.transform       { |gem_path, raw_bytes| nil } # return String to replace bytes in-memory
  pkg.generate_bundle { |entries_hash, cfg| }
  pkg.after_package   { |build_result| }
end
```

---

## Custom Plugin Interface

Any Ruby object implementing one or more of the following methods can be passed to `pkg.use(plugin)`:

```ruby
class StampLicenseHeaderPlugin
  def before_resolve(config); end

  def transform(gem_path, content)
    return nil unless gem_path.end_with?(".rb")

    "# Built with RubyToFaster\n#{content}"
  end

  def generate_bundle(entries, config); end

  def after_package(result); end
end
```
