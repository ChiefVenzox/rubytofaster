#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/rubytofaster"

# Dogfooding compiler script: RubyToFaster builds its own .gem package!
RubyToFaster.build(root_dir: __dir__) do |pkg|
  pkg.gemspec "rubytofaster.gemspec"
  pkg.incremental = true
  pkg.reproducible = true
  pkg.budget max_compressed_kb: 128, max_unpacked_kb: 512
end
