#!/usr/bin/env ruby
# frozen_string_literal: true

# Full-stack Ruby Engine / Dashboard gem embedding Vite, Next.js, and Angular assets
require "rubytofaster"

RubyToFaster.build(root_dir: __dir__) do |pkg|
  pkg.gemspec "admin_engine.gemspec"
  pkg.incremental  = true
  pkg.reproducible = true

  # 1. Vite asset pipeline (parses dist/.vite/manifest.json)
  pkg.vite(
    root: "ui/vite-widgets",
    out_dir: "dist",
    mount_to: "public/admin_engine/vite",
    auto_build: true
  )

  # 2. Next.js static or standalone UI bundle (strips .next/cache automatically)
  pkg.nextjs(
    root: "ui/next-portal",
    mode: :auto,
    mount_to: "public/admin_engine/portal",
    auto_build: true
  )

  # 3. Angular Architect workspace (supports Angular v17+ `browser/` application builder)
  pkg.angular(
    root: "ui/ng-console",
    project: "console",
    mount_to: "public/admin_engine/console",
    auto_build: true
  )

  # Emit zero-dependency Ruby helper so Rack/Rails views resolve hashed assets without Node.js at runtime
  pkg.generate_asset_helper(
    module_name: "AdminEngine::Assets",
    path: "lib/admin_engine/assets.rb"
  )

  # Enforce Angular-style bundle & gem size budgets
  pkg.budget max_compressed_kb: 2048, max_unpacked_kb: 8192, max_entry_kb: 1024
end
