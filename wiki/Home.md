# Welcome to the RubyToFaster Wiki

**RubyToFaster (`rtf`)** is a minimalist, zero-dependency, script-first build system for Ruby gems. It allows package compilation to execute directly as a lightweight Ruby script (`gem.build.rb`) while natively incorporating frontend build artifacts and architectural primitives from **Angular**, **Vite**, and **Next.js**.

---

## Core Highlights

- **Script-First Minimalist Execution:** Compile `.gem` packages directly via `./gem.build.rb` or `require "rubytofaster/autorun"` without loading Rake or Bundler task helpers.
- **Content-Addressable Incremental Cache:** Next.js/Turbopack-inspired SHA-256 Merkle caching (`.rtf-cache/`) delivers **~4ms** incremental cache hits.
- **First-Class Frontend Resource Pipelines:** Native adapters stage **Vite**, **Next.js**, and **Angular** bundles into your gem in-memory, prune multi-megabyte bundler caches, and generate a zero-dependency Ruby asset resolver module.
- **Deterministic & Secure by Default:** Honors `SOURCE_DATE_EPOCH`, sorts tar entries lexicographically, writes SHA-256 & SHA-512 checksums, blocks path traversal and escaping symlinks, and prunes `.env`/private key files automatically.
- **Angular-Inspired Bundle Budgets:** Prevent accidental gem bloat with configurable `max_compressed_kb`, `max_unpacked_kb`, and `max_entry_kb` budgets.

---

## Documentation Guide

| Guide | Description |
| :--- | :--- |
| **[[Getting Started\|Getting-Started]]** | Install `rubytofaster`, run a 1-line `autorun` script, scaffold `gem.build.rb`, and verify your first `.gem`. |
| **[[Architecture & Compiler Pipeline\|Architecture-and-Compiler-Pipeline]]** | How the in-memory packager, SHA-256 Merkle cache, plugin transforms, and parallel `extconf.rb` compiler work. |
| **[[Frontend Resources: Vite, Next.js & Angular\|Frontend-Resources-Vite-Nextjs-Angular]]** | Bundle Vite, Next.js, and Angular apps inside Ruby gems and serve hashed assets in Rack/Rails with zero Node.js at runtime. |
| **[[CLI & Script API Reference\|CLI-and-Script-API-Reference]]** | Complete reference for `RubyToFaster::Config`, lifecycle hooks, budgets, and `rtf` CLI flags. |
| **[[Security & Reproducible Builds\|Security-and-Reproducible-Builds]]** | `SOURCE_DATE_EPOCH` bit-for-bit reproducibility, supply-chain protections, and CI verification recipes. |
| **[[Troubleshooting & FAQ\|Troubleshooting-and-FAQ]]** | Solutions for monorepo layouts, native C extensions, source maps, and cache diagnostics. |

---

## Quick Example

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "rubytofaster"

RubyToFaster.build do |pkg|
  pkg.gemspec "my_engine.gemspec"
  pkg.vite    root: "frontend", out_dir: "dist", mount_to: "public/my_engine/vite"
  pkg.budget  max_compressed_kb: 512, max_unpacked_kb: 2048
end
```
