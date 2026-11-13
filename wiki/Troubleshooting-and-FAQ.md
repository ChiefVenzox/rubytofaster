# Troubleshooting & FAQ

### Why did `rtf build` report `[BUILT]` instead of `[CACHE HIT]`?
Run `rtf build --verbose` and inspect `.rtf-cache/last-build-trace.json`. The Merkle cache invalidates whenever any of the following change:
- Any packaged source file's SHA-256 content digest or executable bit
- Staged Vite, Next.js, or Angular bundle files
- `Gem::Specification` version, summary, dependencies, or metadata
- `SOURCE_DATE_EPOCH` or Ruby runtime version

### Error: `String build commands are disallowed for security`
`RubyToFaster` blocks shell command strings to prevent command injection. Change:
```ruby
# Disallowed:
pkg.vite root: "frontend", build_command: "npm run build:prod"

# Allowed (safe argv array):
pkg.vite root: "frontend", build_command: ["npm", "run", "build:prod"]
```

### How do I include `.map` source maps for Vite, Next.js, or Angular?
Source maps are excluded by default to keep `.gem` downloads compact and protect source code. Enable them explicitly per adapter:
```ruby
pkg.vite root: "frontend", out_dir: "dist", mount_to: "public/vite", sourcemaps: true
```

### Can I write staged frontend assets and the generated Ruby helper to disk for local Rails/Rack development?
Yes! By default, `RubyToFaster` stages frontend bundles in-memory directly into `data.tar.gz` so your working tree stays clean. Set `write_staged_assets = true` in `gem.build.rb` when you also want local copies written to disk:
```ruby
RubyToFaster.build do |pkg|
  pkg.gemspec "my_engine.gemspec"
  pkg.write_staged_assets = true
  pkg.vite root: "frontend", mount_to: "public/vite"
  pkg.generate_asset_helper module_name: "MyEngine::Assets", path: "lib/my_engine/assets.rb"
end
```

### How do I cache `.rtf-cache` in GitHub Actions?
Add `actions/cache@v4` pointing at `.rtf-cache`:
```yaml
- uses: actions/cache@v4
  with:
    path: .rtf-cache
    key: rtf-${{ runner.os }}-${{ hashFiles('**/*.rb', '**/*.gemspec', '**/package-lock.json') }}
```
