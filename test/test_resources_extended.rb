# frozen_string_literal: true

require "test_helper"

class TestResourcesExtended < Minitest::Test
  def test_astro_sveltekit_nuxt_adapters_and_sri_precompression
    Dir.mktmpdir("rtf-ext-fw-") do |dir|
      # Astro prebuilt dist/
      astro_dir = File.join(dir, "ui/astro")
      FileUtils.mkdir_p(File.join(astro_dir, "dist/_astro"))
      File.write(File.join(astro_dir, "astro.config.mjs"), "export default {};\n")
      File.write(File.join(astro_dir, "dist/index.html"), "<html><body>#{'Hello Astro! ' * 30}</body></html>\n")
      File.write(File.join(astro_dir, "dist/_astro/page.abc123.js"), "console.log('#{'astro-island ' * 30}');\n")
      File.write(File.join(astro_dir, "dist/_astro/style.def456.css"), ".hero { color: #e11d48; }\n" * 20)
      assert RubyToFaster::Resources::Astro.detect?(astro_dir)

      # SvelteKit prebuilt build/
      sk_dir = File.join(dir, "ui/svelte")
      FileUtils.mkdir_p(File.join(sk_dir, "build/_app/immutable/entry"))
      File.write(File.join(sk_dir, "svelte.config.js"), "export default {};\n")
      File.write(File.join(sk_dir, "build/index.html"), "<html><body>SvelteKit</body></html>\n")
      File.write(File.join(sk_dir, "build/_app/immutable/entry/start.xyz.js"), "export const start = () => {};\n" * 15)
      assert RubyToFaster::Resources::SvelteKit.detect?(sk_dir)

      # Nuxt prebuilt .output/public/
      nuxt_dir = File.join(dir, "ui/nuxt")
      FileUtils.mkdir_p(File.join(nuxt_dir, ".output/public/_nuxt"))
      File.write(File.join(nuxt_dir, "nuxt.config.ts"), "export default defineNuxtConfig({});\n")
      File.write(File.join(nuxt_dir, ".output/public/index.html"), "<html><body>Nuxt App</body></html>\n")
      File.write(File.join(nuxt_dir, ".output/public/_nuxt/entry.99aa.js"), "export default function boot() {}\n" * 15)
      File.write(File.join(nuxt_dir, ".output/public/_nuxt/entry.99aa.css"), "body { background: #0f172a; }\n" * 15)
      assert RubyToFaster::Resources::Nuxt.detect?(nuxt_dir)

      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/multi_ui.rb"), "module MultiUi; end\n")

      res = RubyToFaster.build(root_dir: dir, report: false) do |pkg|
        pkg.incremental = false
        pkg.precompress_assets true
        pkg.astro root: "ui/astro", mount_to: "public/astro"
        pkg.sveltekit root: "ui/svelte", mount_to: "public/sveltekit"
        pkg.nuxt root: "ui/nuxt", mount_to: "public/nuxt"
        pkg.generate_asset_helper module_name: "MultiUi::Assets", path: "lib/multi_ui/assets.rb"
        pkg.spec do |s|
          s.name    = "multi_ui"
          s.version = "0.1.0"
          s.summary = "Multi-framework gem"
          s.authors = ["HNM Labs"]
          s.license = "MIT"
          s.files   = ["lib/multi_ui.rb"]
        end
      end

      assert_equal 3, res.resources.size
      inspection = RubyToFaster.inspect_gem(res.gem_path)
      paths = inspection[:entries].map { |e| e[:path] }

      assert_includes paths, "public/astro/index.html"
      assert_includes paths, "public/astro/_astro/page.abc123.js"
      assert_includes paths, "public/astro/_astro/page.abc123.js.gz"
      assert_includes paths, "public/sveltekit/_app/immutable/entry/start.xyz.js"
      assert_includes paths, "public/nuxt/_nuxt/entry.99aa.js"
      assert_includes paths, "lib/multi_ui/assets.rb"

      manifest_data = inspection[:frontend_manifests]["public/rtf-manifest.json"]
      manifest = RubyToFaster::AssetManifest.new(manifest_data)
      assert_equal %w[astro nuxt sveltekit], manifest.frameworks.sort

      # Verify SRI sha384 integrity & HTML tags + Early Hints preload headers
      sri = manifest.integrity("_nuxt/entry.99aa.js", framework: :nuxt)
      assert sri.start_with?("sha384-"), "Expected sha384 SRI hash, got #{sri.inspect}"

      tags = manifest.html_tags("entry", framework: :nuxt, url_prefix: "/nuxt", sri: true)
      assert_includes tags, 'integrity="sha384-'
      assert_includes tags, 'crossorigin="anonymous"'
      assert_includes tags, 'href="/nuxt/_nuxt/entry.99aa.css"'
      assert_includes tags, 'src="/nuxt/_nuxt/entry.99aa.js"'

      preload = manifest.preload_headers("entry", framework: :nuxt, url_prefix: "/nuxt")
      assert_includes preload, "</nuxt/_nuxt/entry.99aa.css>; rel=preload; as=style"
      assert_includes preload, "</nuxt/_nuxt/entry.99aa.js>; rel=modulepreload; as=script"
    end
  end

  def test_webpack_parcel_sass_adapters
    Dir.mktmpdir("rtf-bundlers-") do |dir|
      # Webpack with manifest.json
      wp_dir = File.join(dir, "wp")
      FileUtils.mkdir_p(File.join(wp_dir, "dist"))
      File.write(File.join(wp_dir, "webpack.config.js"), "module.exports = {};\n")
      File.write(File.join(wp_dir, "dist/app.8899.js"), "console.log('webpack');\n")
      File.write(File.join(wp_dir, "dist/app.8899.css"), ".wp { display: flex; }\n")
      File.write(
        File.join(wp_dir, "dist/manifest.json"),
        JSON.generate({
          "entrypoints" => {
            "application" => { "assets" => ["app.8899.js", "app.8899.css"] }
          }
        })
      )
      assert RubyToFaster::Resources::Webpack.detect?(wp_dir)

      # Parcel
      pc_dir = File.join(dir, "pc")
      FileUtils.mkdir_p(File.join(pc_dir, "dist"))
      File.write(File.join(pc_dir, ".parcelrc"), "{}\n")
      File.write(File.join(pc_dir, "dist/index.html"), "<html></html>\n")
      File.write(File.join(pc_dir, "dist/bundle.1234.js"), "console.log('parcel');\n")
      assert RubyToFaster::Resources::Parcel.detect?(pc_dir)

      # Sass / SCSS
      sass_dir = File.join(dir, "styles")
      FileUtils.mkdir_p(File.join(sass_dir, "src/styles"))
      FileUtils.mkdir_p(File.join(sass_dir, "dist"))
      File.write(File.join(sass_dir, "src/styles/main.scss"), "$primary: #cc342d; body { color: $primary; }\n")
      File.write(File.join(sass_dir, "dist/application.css"), "body{color:#cc342d}\n")
      assert RubyToFaster::Resources::Sass.detect?(sass_dir)

      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/bundler_gem.rb"), "module BundlerGem; end\n")

      res = RubyToFaster.build(root_dir: dir, report: false) do |pkg|
        pkg.incremental = false
        pkg.webpack root: "wp", out_dir: "dist", mount_to: "public/webpack"
        pkg.parcel root: "pc", out_dir: "dist", mount_to: "public/parcel"
        pkg.sass root: "styles", output: "dist/application.css", mount_to: "public/sass"
        pkg.spec do |s|
          s.name    = "bundler_gem"
          s.version = "0.2.0"
          s.summary = "Webpack, Parcel, Sass gem"
          s.authors = ["HNM Labs"]
          s.license = "MIT"
          s.files   = ["lib/bundler_gem.rb"]
        end
      end

      assert_equal 3, res.resources.size
      inspection = RubyToFaster.inspect_gem(res.gem_path)
      paths = inspection[:entries].map { |e| e[:path] }

      assert_includes paths, "public/webpack/app.8899.js"
      assert_includes paths, "public/parcel/bundle.1234.js"
      assert_includes paths, "public/sass/application.css"

      manifest = RubyToFaster::AssetManifest.new(inspection[:frontend_manifests]["public/rtf-manifest.json"])
      assert_equal "app.8899.js", manifest.asset_path("application", framework: :webpack)
      assert_equal "application.css", manifest.asset_path("application.css", framework: :sass)
    end
  end
end
