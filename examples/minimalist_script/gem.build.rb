#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimalist single-script Ruby gem build (no Rakefile or external .gemspec needed!)
require "rubytofaster"

RubyToFaster.build(root_dir: __dir__) do |pkg|
  pkg.incremental  = true
  pkg.reproducible = true

  pkg.spec do |s|
    s.name        = "micro_service_sdk"
    s.version     = "0.1.0"
    s.summary     = "Built directly from a standalone Ruby script via RubyToFaster."
    s.authors     = ["HNM Labs"]
    s.license     = "MIT"
    s.files       = Dir.glob("lib/**/*.rb")
  end

  pkg.budget max_compressed_kb: 64, max_unpacked_kb: 256
end
