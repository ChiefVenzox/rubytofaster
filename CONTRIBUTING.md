# Contributing to RubyToFaster

Thank you for your interest in contributing to **RubyToFaster**! We aim to keep Ruby gem compilation fast, deterministic, minimalist, and dependency-free.

## Design Principles

1. **Zero Runtime Gem Dependencies:** `lib/rubytofaster` relies strictly on the Ruby 3.0+ standard library so standalone scripts start in milliseconds without requiring `bundle exec`.
2. **Deterministic & Reproducible:** Given identical inputs and `SOURCE_DATE_EPOCH`, `RubyToFaster::Packager` must always emit byte-for-byte identical `.gem` archives.
3. **Security First:** Never pass untrusted strings to subshells (`sh -c`); always use array-form `Open3.capture3` and sanitize relative archive paths via `FileResolver#sanitize_relative_path!`.

## Local Development

```bash
git clone https://github.com/HNMLabs/rubytofaster.git
cd rubytofaster

# Run the full test suite (runs with Ruby warnings enabled)
rake test

# Dogfood: build rubytofaster.gem using RubyToFaster itself
./gem.build.rb

# Inspect the built package
./exe/rtf inspect pkg/rubytofaster-0.1.0.gem
```

## Pull Request Checklist

- [ ] New features and bug fixes include Minitest coverage under `test/`.
- [ ] `rake test` passes with `0 failures, 0 errors` and zero Ruby warnings.
- [ ] `./gem.build.rb` builds cleanly and passes `./exe/rtf inspect`.
- [ ] Documentation (`README.md` or Wiki) and `CHANGELOG.md` are updated where applicable.
