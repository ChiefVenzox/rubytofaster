# Changelog

All notable changes to **RubyToFaster** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-11-19

### Added
- **6 New Frontend & Bundler Resource Adapters (11 Total)**:
  - **Astro (`pkg.astro` / `Resources::Astro`)**: Stages static `dist/` and SSR `dist/client/` builds, `_astro/` chunks, and page routes.
  - **SvelteKit (`pkg.sveltekit` / `Resources::SvelteKit`)**: Supports static `build/` and `.svelte-kit/output/client/` with Vite manifest parsing and `_app/immutable/` chunk resolution.
  - **Nuxt (`pkg.nuxt` / `Resources::Nuxt`)**: Supports Nuxt 3/4 `.output/public/` and `dist/` builds while pruning `.nuxt/` caches.
  - **Webpack (`pkg.webpack` / `Resources::Webpack`)**: Parses `manifest.json`, `assets-manifest.json`, and `stats.json` from `dist/` or `public/packs/`.
  - **Parcel (`pkg.parcel` / `Resources::Parcel`)**: Stages `dist/` bundles while automatically pruning `.parcel-cache/`.
  - **Dart Sass / SCSS (`pkg.sass` / `Resources::Sass`)**: Compiles and packages `.scss`/`.sass` stylesheets with standalone `sass` CLI or npm `sass`.
- **Native Rust Extension Support (`ExtensionBuilder`)**:
  - Added parallel `Cargo.toml` (rb-sys / magnus) extension verification in isolated `CARGO_TARGET_DIR` alongside C/C++ `extconf.rb` extensions.
- **CycloneDX 1.5 & SPDX 2.3 SBOM Generation (`rtf sbom` / `RubyToFaster::SBOM` / `pkg.embed_sbom`)**:
  - Zero-dependency SBOM generation including Package URLs (`purl`), runtime/dev dependencies, staged frontend bundles, and SHA-256 hashes for every file. Can also be embedded directly inside `.gem` archives (`sbom.cdx.json` / `sbom.spdx.json`).
- **Package Composition & Size Analytics (`rtf stats` / `rtf size` / `RubyToFaster::Analyzer`)**:
  - Instant in-memory size breakdown by directory, file extension, compression ratio, embedded frameworks, and top largest files with visual ASCII bars and `--json` telemetry.
- **Cryptographic & Reproducibility Verifier (`rtf verify` / `RubyToFaster::Verifier`)**:
  - Verify `.gem` tar checksums, validate against expected `--sha256`, perform two isolated clean builds via `--reproducible` to prove bit-for-bit determinism, and emit `<name>.gem.sha256` checksum files (`--checksums` / `pkg.checksums_file = true`).
- **Monorepo / Multi-Gem Workspaces (`rtf workspace` / `rtf ws` / `RubyToFaster::Workspace`)**:
  - Discovers sibling gems across `gems/*`, `packages/*`, `engines/*`, and `plugins/*`, topologically sorts intra-workspace dependencies, and executes `build`, `check`, and `clean` across the entire monorepo.
- **Subresource Integrity (SRI) & HTTP/2 Early Hints (`AssetManifest`)**:
  - Automatic SHA-384 SRI hash generation for all staged assets, `html_tags(..., sri: true)` emitting `integrity="sha384-..." crossorigin="anonymous"`, and `preload_headers(...)` generating HTTP `Link` headers.
- **Deterministic In-Memory Gzip Precompression (`--precompress` / `pkg.precompress_assets true`)**:
  - Generates deterministic `.gz` sibling files in-memory for compressible frontend assets (`.js`, `.css`, `.html`, `.svg`, `.json`, `.wasm`) when compression saves bytes.
- **Configurable Compression Levels (`pkg.compression_level`)**:
  - Supports `:fast`, `:default` (1.7x faster cold builds vs `gem build`), `:best`, or `0..9`.
- **TTY-Aware ANSI Color Reporter & New Animated Demo GIFs**:
  - Automatic ANSI colorized terminal output (respecting `NO_COLOR` and non-TTY pipes) and 4 high-FPS animated demo GIFs in `docs/assets/`.
- **Expanded `RakeTask`**:
  - Added `rake rtf:sbom`, `rake rtf:stats`, and `rake rtf:verify`.

### Fixed
- **Dynamic CI Version Resolution**: Updated `.github/workflows/ci.yml` to resolve `RubyToFaster::VERSION` dynamically instead of hardcoding `0.1.0`.

## [0.2.0] - 2026-11-17

### Added
- **New CLI Commands**:
  - `rtf install`: Streamlined local gem installation (`gem install --local`) with flags for `--prerelease`, `--user-install`, `--force`, and `--document`.
  - `rtf diff`: Deep in-memory semantic gem diffing comparing metadata, added/removed/modified files, POSIX modes, and byte deltas between two `.gem` packages or workspace vs archive. Supports `--json`.
  - `rtf check` (alias `rtf audit`): Supply-chain security, SPDX license compliance, required Ruby version, world-writable file, secret scanning, and executable shebang/permission auditing with `--strict` and `--json`.
  - `rtf bench` (alias `rtf benchmark`): Direct multi-iteration benchmark comparing cold builds, warm Merkle cache hits, and standard `Gem::Package.build` with speedup factor calculations.
- **New Frontend Resource Pipelines**:
  - **Tailwind CSS (`pkg.tailwind` / `Resources::Tailwind`)**: Native adapter for standalone `@tailwindcss/cli`, standalone binary, and custom Tailwind builds. Automatically packages and mounts compiled utility stylesheets into `public/tailwind`.
  - **Esbuild (`pkg.esbuild` / `Resources::Esbuild`)**: Native adapter for Esbuild JS/CSS bundling (standard in Rails 7/8 `jsbundling-rails` and modern gems). Supports `--metafile` entrypoint extraction, source maps, and code minification.
- **Zero-Dependency Rake Integration (`RubyToFaster::RakeTask`)**:
  - Seamless drop-in replacement for `Bundler::GemHelper.install_tasks` defining `rake build`, `rake rtf:build`, `rake rtf:install`, `rake rtf:check`, `rake rtf:clean`, and `rake rtf:bench`.
- **Enhanced `rtf doctor`**:
  - Diagnostic inspection of local developer toolchain: Node.js, npm, pnpm, yarn, bun, Tailwind CLI, Esbuild, Cargo (Rust), Make, and C compilers (`gcc`/`clang`/`cc`).
- **Module-Level API Expansion**:
  - Added `RubyToFaster.diff`, `RubyToFaster.check`, `RubyToFaster.benchmark`, and `RubyToFaster.install`.

## [0.1.0] - 2026-11-13

### Added
- **Minimalist Script-First Compiler (`RubyToFaster.build`, `rubytofaster/autorun`)**: Compile Ruby gems directly from standalone Ruby scripts (`gem.build.rb`) or inline `pkg.spec` definitions without Rake or Bundler overhead.
- **Deterministic In-Memory `.gem` Packager (`RubyToFaster::Packager`)**: Generates RubyGems v2.0+ archives (`metadata.gz`, `data.tar.gz`, `checksums.yaml.gz` with SHA-256 & SHA-512) with lexicographically sorted entries, normalized POSIX modes, and `SOURCE_DATE_EPOCH` reproducibility.
- **Content-Addressable Incremental Cache (`RubyToFaster::Cache`)**: SHA-256 Merkle build cache in `.rtf-cache/` enabling single-digit millisecond incremental rebuilds and `last-build-trace.json` telemetry.
- **Frontend Resource Pipelines (`RubyToFaster::Resources`)**:
  - **Vite Adapter**: Auto-detects `vite.config.*`, parses `.vite/manifest.json` / `manifest.json`, and stages hashed ESM & CSS chunks.
  - **Next.js Adapter**: Supports static exports (`out/`) and `.next/static` + `build-manifest.json` / `routes-manifest.json` while pruning `.next/cache`.
  - **Angular Adapter**: Parses `angular.json` Architect workspaces and Angular v17+ `outputPath: { base, browser }` bundles.
  - **Zero-Dependency Ruby Asset Helper Codegen (`RubyToFaster::AssetManifest`)**: Generates embeddable Ruby modules (`asset_path`, `html_tags`) so host Rack/Rails apps serve hashed assets without Node.js at runtime.
- **Parallel Native Extension Builder (`RubyToFaster::ExtensionBuilder`)**: Concurrent verification and compilation of `extconf.rb` extensions across CPU cores.
- **Angular-Inspired Bundle Budgets (`RubyToFaster::BudgetEvaluator`)**: Configurable `max_compressed_kb`, `max_unpacked_kb`, and `max_entry_kb` thresholds with warning ratios.
- **Vite/Rollup-Style Plugin Hooks (`RubyToFaster::PluginRunner`)**: `before_resolve`, in-memory `transform`, `generate_bundle`, and `after_package` hooks.
- **Minimalist CLI (`rubytofaster` & `rtf`)**: `build`, `init`, `inspect`, `watch`, `doctor`, `clean`, and `version` subcommands.
- **Supply-Chain Security Controls**: Path-traversal prevention, symlink containment, array-only subprocess execution, and automatic `.env`/private-key pruning.
