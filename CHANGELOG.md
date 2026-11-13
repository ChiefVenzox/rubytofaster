# Changelog

All notable changes to **RubyToFaster** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
