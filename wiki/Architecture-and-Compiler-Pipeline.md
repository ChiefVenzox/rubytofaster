# Architecture & Compiler Pipeline

Traditional Ruby gem builds (`bundle exec rake build`) load Bundler, Rake, task prerequisites, shell out to `git ls-files`, stat files repeatedly on disk, and rebuild identical tarballs from scratch on every invocation.

`RubyToFaster` replaces that stack with a streamlined, deterministic compiler pipeline inspired by **Vite**, **Next.js (Turbopack)**, and **Angular Architect**.

---

## Pipeline Stages

1. **Lifecycle `before_resolve`**
   Executes registered plugins and inline `pkg.before_resolve` hooks.
2. **Specification & File Resolution (`RubyToFaster::FileResolver`)**
   Loads either a `.gemspec` file or an inline `pkg.spec { |s| ... }` block. Prunes excluded caches (`node_modules/`, `.next/cache/`, `.angular/cache/`, `.rtf-cache/`), enforces path-traversal and symlink containment, and rejects accidental secret files (`.env*`, `*.pem`, `*.key`).
3. **Frontend Resource Staging (`RubyToFaster::Resources`)**
   Collects production bundles from **Vite**, **Next.js**, and **Angular** into virtual `PackageEntry` structs—meaning staged files and generated manifests (`public/rtf-manifest.json` and optional Ruby helper modules) are streamed directly into the `.gem` without dirtying your Git working directory (unless `pkg.write_staged_assets = true` is enabled).
4. **Lifecycle `generate_bundle`**
   Allows plugins to inspect or add virtual entries to the `entries` map before hashing.
5. **SHA-256 Merkle Cache Lookup (`RubyToFaster::Cache`)**
   Computes a single deterministic SHA-256 root digest over:
   - Ruby & RubyToFaster versions
   - Reproducibility settings (`SOURCE_DATE_EPOCH`)
   - Normalized `Gem::Specification` metadata & dependencies
   - Sorted relative entry paths, POSIX modes (`0644` / `0755`), and SHA-256 content digests
   If `.rtf-cache/artifacts/<merkle_key>.gem` exists and passes SHA-256 integrity verification, the artifact is restored in **~4ms**.
6. **Parallel Native Extension Verification (`RubyToFaster::ExtensionBuilder`)**
   On cache miss, any `ext/**/extconf.rb` extensions are compiled concurrently in isolated temporary directories across `Etc.nprocessors` worker threads using `make -jN`.
7. **Deterministic In-Memory Packaging (`RubyToFaster::Packager`)**
   Streams `metadata.gz`, `data.tar.gz` (running inline `pkg.transform` hooks on bytes in flight), and `checksums.yaml.gz` (containing both `SHA256` and `SHA512` digests) directly into `Gem::Package::TarWriter` with `Zlib::BEST_COMPRESSION`.
8. **Budget Governance (`RubyToFaster::BudgetEvaluator`)**
   Evaluates compressed `.gem` KB, unpacked payload KB, and per-entry KB against configured budgets.
9. **Build Trace Persistence & `after_package`**
   Writes `.rtf-cache/last-build-trace.json` and invokes `after_package` hooks.
