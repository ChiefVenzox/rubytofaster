# Getting Started

`RubyToFaster` is designed to eliminate build-system ceremony. It runs on **Ruby >= 3.0** with **zero external runtime gem dependencies**.

---

## 1. Installation

Install via RubyGems:

```bash
gem install rubytofaster
```

Or add to your `Gemfile`:

```ruby
group :development do
  gem "rubytofaster"
end
```

Verify both executables (`rubytofaster` and the short alias `rtf`):

```bash
rtf --version
# => rubytofaster 0.1.0
```

---

## 2. Three Ways to Build a Gem

### Option A: Zero-Config CLI

Inside any directory containing a `*.gemspec`:

```bash
rtf build
```

### Option B: 1-Line Minimalist Script (`autorun`)

Create `gem.build.rb`:

```ruby
#!/usr/bin/env ruby
require "rubytofaster/autorun"
```

Run directly with Ruby:

```bash
ruby gem.build.rb
```

### Option C: Declarative Compiler Script (Recommended)

Generate a customizable `gem.build.rb` script using `rtf init`:

```bash
rtf init --vite --nextjs --angular
```

This creates an executable `gem.build.rb` file:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "rubytofaster"

RubyToFaster.build do |pkg|
  pkg.gemspec "my_gem.gemspec"
  pkg.incremental = true
  pkg.vite root: "frontend", out_dir: "dist", mount_to: "public/vite"
  pkg.nextjs root: "web", mode: :auto, mount_to: "public/nextjs"
  pkg.angular root: "admin", mount_to: "public/angular"
  pkg.budget max_compressed_kb: 512, max_unpacked_kb: 2048
end
```

---

## 3. Inspecting & Verifying Your Built `.gem`

Before publishing to RubyGems.org, verify cryptographic SHA-256/SHA-512 checksums, inspect file modes, and audit staged frontend manifests without extracting files to disk:

```bash
rtf inspect pkg/my_gem-0.1.0.gem
```

You can also emit machine-readable JSON for CI checks:

```bash
rtf inspect pkg/my_gem-0.1.0.gem --json
```
