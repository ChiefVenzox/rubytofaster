# Frontend Resources: Vite, Next.js & Angular

Many modern Ruby gems—such as admin dashboards, background job monitors (similar to Sidekiq Web or GoodJob), APM UIs, and mountable Rails Engines—include rich web interfaces.

`RubyToFaster` provides first-class resource adapters for **Vite**, **Next.js**, and **Angular** so gem authors can ship compiled frontend assets cleanly inside `.gem` archives **without requiring Node.js in the end user's production Ruby environment**.

---

## 1. Vite Resource Adapter (`pkg.vite`)

- **Auto-detection:** Recognizes `vite.config.{ts,js,mjs,cjs}`.
- **Manifest support:** Parses Vite 5/6 `dist/.vite/manifest.json` as well as Vite 4 `dist/manifest.json`.
- **Entrypoint mapping:** Maps source keys (e.g., `"src/main.ts"`) to hashed JS output, CSS chunks, and dynamic imports.

```ruby
RubyToFaster.build do |pkg|
  pkg.gemspec "metrics_ui.gemspec"

  pkg.vite(
    root: "frontend",
    out_dir: "dist",
    mount_to: "public/metrics_ui/vite",
    auto_build: true,          # Runs `<npm|pnpm|yarn|bun> exec vite build` safely
    sourcemaps: false          # Excludes .map files by default (set true to include)
  )
end
```

---

## 2. Next.js Resource Adapter (`pkg.nextjs`)

- **Auto-detection:** Recognizes `next.config.{ts,mjs,js,cjs}`.
- **Two supported modes (`mode: :auto` detects automatically):**
  - **`:export` mode:** Stages Next.js static exports (`output: 'export'` in `out/`), indexing all exported HTML routes (`/`, `/docs`, etc.) and `_next/static/css/*` bundles.
  - **`:static` mode:** Stages `.next/static/` into `<mount_to>/_next/static/`, reads `BUILD_ID`, `build-manifest.json`, and `routes-manifest.json`, and **strips `.next/cache/`** so multi-hundred-megabyte webpack/turbopack caches never bloat your `.gem`.

```ruby
RubyToFaster.build do |pkg|
  pkg.gemspec "portal_engine.gemspec"

  pkg.nextjs(
    root: "portal-web",
    mode: :auto,               # :auto, :export, or :static
    mount_to: "public/portal",
    auto_build: true
  )
end
```

---

## 3. Angular Resource Adapter (`pkg.angular`)

- **Auto-detection:** Recognizes `angular.json`.
- **Workspace & v17+ Application Builder support:** Parses `angular.json` directly in Ruby, supporting both classic string `outputPath` (`"dist/my-app"`) and Angular v17/v18/v19+ object `outputPath` (`{ "base": "dist/my-app", "browser": "browser" }`).
- **Entrypoint extraction:** Parses `index.html` (or bundle conventions) to extract hashed `polyfills-*.js`, `main-*.js`, and `styles-*.css` in exact load order while excluding `.angular/` caches and SSR `server/` artifacts.

```ruby
RubyToFaster.build do |pkg|
  pkg.gemspec "console_gem.gemspec"

  pkg.angular(
    root: "ng-workspace",
    project: "admin-console",  # Defaults to defaultProject or first project in angular.json
    mount_to: "public/console",
    auto_build: true
  )
end
```

---

## 4. Zero-Dependency Ruby Runtime Asset Helper

Add `pkg.generate_asset_helper` to embed a standalone Ruby module inside your gem:

```ruby
pkg.generate_asset_helper(
  module_name: "MetricsUi::Assets",
  path: "lib/metrics_ui/assets.rb"
)
```

In your Rack middleware, Sinatra app, or Rails Engine ERB layout:

```erb
<!DOCTYPE html>
<html>
  <head>
    <title>Metrics UI</title>
    <%= MetricsUi::Assets.html_tags("src/main.ts", framework: :vite, url_prefix: "/metrics/vite") %>
  </head>
  <body>
    <div id="app"></div>
  </body>
</html>
```

And mount static files in Rack (`config.ru` or Rails Engine):

```ruby
use Rack::Static,
    urls: ["/metrics/vite"],
    root: File.expand_path("../public/metrics_ui", __dir__)
```
