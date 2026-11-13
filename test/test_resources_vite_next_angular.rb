# frozen_string_literal: true

require "test_helper"

class TestResourcesViteNextAngular < Minitest::Test
  def test_combined_vite_nextjs_and_angular_resources_with_generated_ruby_helper
    Dir.mktmpdir("rtf-fullstack-") do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib/ui_kit"))
      File.write(File.join(dir, "lib/ui_kit.rb"), "require_relative 'ui_kit/assets'\nmodule UiKit; end\n")

      # 1. Setup simulated Vite v5 build output (`frontend/dist/.vite/manifest.json`)
      vite_dist = File.join(dir, "frontend/dist")
      FileUtils.mkdir_p(File.join(vite_dist, ".vite"))
      FileUtils.mkdir_p(File.join(vite_dist, "assets"))
      File.write(File.join(dir, "frontend/vite.config.ts"), "export default {}\n")
      File.write(File.join(vite_dist, "assets/app-8f91a.js"), "console.log('vite');\n")
      File.write(File.join(vite_dist, "assets/app-8f91a.js.map"), "{\"mappings\":\"AAAA\"}\n")
      File.write(File.join(vite_dist, "assets/app-12b3c.css"), "body{margin:0}\n")
      File.write(
        File.join(vite_dist, ".vite/manifest.json"),
        JSON.pretty_generate(
          "src/main.ts" => {
            "file" => "assets/app-8f91a.js",
            "src" => "src/main.ts",
            "isEntry" => true,
            "css" => ["assets/app-12b3c.css"]
          }
        )
      )

      # 2. Setup simulated Next.js `.next/static` + manifests + `.next/cache` bloat
      next_dir = File.join(dir, "portal/.next")
      FileUtils.mkdir_p(File.join(next_dir, "static/chunks"))
      FileUtils.mkdir_p(File.join(next_dir, "cache/webpack"))
      File.write(File.join(dir, "portal/next.config.mjs"), "export default {}\n")
      File.write(File.join(next_dir, "BUILD_ID"), "build-2026\n")
      File.write(File.join(next_dir, "static/chunks/main-abc.js"), "console.log('next');\n")
      File.write(File.join(next_dir, "cache/webpack/huge.pack"), "BLOAT_THAT_MUST_BE_EXCLUDED")
      File.write(
        File.join(next_dir, "build-manifest.json"),
        JSON.pretty_generate("pages" => { "/dashboard" => ["static/chunks/main-abc.js"] })
      )

      # 3. Setup simulated Angular v18+ workspace (`angular.json` with object outputPath + `browser/`)
      ng_dir = File.join(dir, "admin")
      ng_browser = File.join(ng_dir, "dist/admin-panel/browser")
      FileUtils.mkdir_p(ng_browser)
      File.write(
        File.join(ng_dir, "angular.json"),
        JSON.pretty_generate(
          "version" => 1,
          "projects" => {
            "admin-panel" => {
              "architect" => {
                "build" => {
                  "options" => {
                    "outputPath" => { "base" => "dist/admin-panel", "browser" => "browser" }
                  }
                }
              }
            }
          }
        )
      )
      File.write(File.join(ng_browser, "polyfills-FF12.js"), "// polyfills\n")
      File.write(File.join(ng_browser, "main-AA99.js"), "// ng main\n")
      File.write(File.join(ng_browser, "styles-CC33.css"), "app-root{display:block}\n")
      File.write(
        File.join(ng_browser, "index.html"),
        <<~HTML
          <!doctype html>
          <html>
            <head><link rel="stylesheet" href="styles-CC33.css"></head>
            <body>
              <app-root></app-root>
              <script src="polyfills-FF12.js" type="module"></script>
              <script src="main-AA99.js" type="module"></script>
            </body>
          </html>
        HTML
      )

      result = RubyToFaster.build(root_dir: dir, report: false) do |pkg|
        pkg.vite    root: "frontend", out_dir: "dist", mount_to: "public/vite"
        pkg.nextjs  root: "portal",   mode: :static,   mount_to: "public/nextjs"
        pkg.angular root: "admin",    project: "admin-panel", mount_to: "public/angular"
        pkg.generate_asset_helper module_name: "UiKit::Assets", path: "lib/ui_kit/assets.rb"

        pkg.spec do |s|
          s.name    = "ui_kit"
          s.version = "1.2.0"
          s.summary = "Fullstack gem with Vite, Next.js, and Angular UIs"
          s.authors = ["HNM Labs"]
          s.files   = ["lib/ui_kit.rb"]
        end
      end

      assert_equal 3, result.resources.size
      inspection = RubyToFaster.inspect_gem(result.gem_path)
      paths = inspection[:entries].map { |e| e[:path] }

      # Vite staged assets present, .map excluded by default
      assert_includes paths, "public/vite/assets/app-8f91a.js"
      assert_includes paths, "public/vite/assets/app-12b3c.css"
      refute_includes paths, "public/vite/assets/app-8f91a.js.map"

      # Next.js static chunks staged, .next/cache excluded
      assert_includes paths, "public/nextjs/_next/static/chunks/main-abc.js"
      assert_empty paths.grep(/huge\.pack/)

      # Angular browser bundles staged
      assert_includes paths, "public/angular/main-AA99.js"
      assert_includes paths, "public/angular/polyfills-FF12.js"
      assert_includes paths, "public/angular/styles-CC33.css"

      # Unified manifest & generated Ruby helper present
      assert_includes paths, "public/rtf-manifest.json"
      assert_includes paths, "lib/ui_kit/assets.rb"

      # Extract & actually load the generated zero-dependency Ruby helper!
      Dir.mktmpdir("rtf-ui-extract-") do |ext_dir|
        Gem::Package.new(result.gem_path).extract_files(ext_dir)
        helper_code = File.read(File.join(ext_dir, "lib/ui_kit/assets.rb"))

        sandbox = Module.new
        sandbox.module_eval(helper_code)
        assets_mod = sandbox.const_get(:UiKit).const_get(:Assets)

        assert_equal "assets/app-8f91a.js", assets_mod.asset_path("src/main.ts", framework: :vite)
        assert_equal "_next/static/chunks/main-abc.js", assets_mod.asset_path("/dashboard", framework: :nextjs)
        assert_equal "main-AA99.js", assets_mod.asset_path("index", framework: :angular)

        vite_html = assets_mod.html_tags("src/main.ts", framework: :vite, url_prefix: "/vite")
        assert_includes vite_html, '<link rel="stylesheet" href="/vite/assets/app-12b3c.css">'
        assert_includes vite_html, '<script type="module" src="/vite/assets/app-8f91a.js"></script>'
      end
    end
  end

  def test_nextjs_static_export_mode
    Dir.mktmpdir("rtf-next-export-") do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/site.rb"), "module Site; end\n")

      out_dir = File.join(dir, "web/out")
      FileUtils.mkdir_p(File.join(out_dir, "_next/static/css"))
      FileUtils.mkdir_p(File.join(out_dir, "docs"))
      File.write(File.join(dir, "web/next.config.js"), "module.exports = { output: 'export' }\n")
      File.write(File.join(out_dir, "index.html"), "<html><body>Home</body></html>\n")
      File.write(File.join(out_dir, "docs/index.html"), "<html><body>Docs</body></html>\n")
      File.write(File.join(out_dir, "_next/static/css/site.css"), "h1{color:red}\n")

      res = RubyToFaster.build(root_dir: dir, report: false) do |pkg|
        pkg.nextjs root: "web", mode: :auto, mount_to: "public/site"
        pkg.spec do |s|
          s.name    = "next_export_gem"
          s.version = "0.1.0"
          s.summary = "Next.js static export test"
          s.authors = ["HNM Labs"]
          s.files   = ["lib/site.rb"]
        end
      end

      assert_equal :export, res.resources.first.metadata[:mode]
      assert_equal ["/", "/docs"], res.resources.first.metadata[:routes]
    end
  end
end
