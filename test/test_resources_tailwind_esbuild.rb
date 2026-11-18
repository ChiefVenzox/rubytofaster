# frozen_string_literal: true

require "test_helper"

class TestResourcesTailwindEsbuild < Minitest::Test
  def test_tailwind_detection_and_collection
    Dir.mktmpdir("rtf-tailwind-test-") do |dir|
      File.write(File.join(dir, "tailwind.config.js"), "module.exports = {};\n")
      assert RubyToFaster::Resources::Tailwind.detect?(dir)

      # Create prebuilt dist/tailwind.css
      FileUtils.mkdir_p(File.join(dir, "dist"))
      css_content = "/*! tailwindcss v3.4 */ .btn { padding: 0.5rem; }\n"
      File.write(File.join(dir, "dist/tailwind.css"), css_content)

      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/theme.rb"), "module Theme; end\n")

      res = RubyToFaster.build(root_dir: dir, report: false) do |pkg|
        pkg.incremental = false
        pkg.tailwind(
          root: ".",
          input: "src/input.css",
          output: "dist/tailwind.css",
          mount_to: "public/tailwind"
        )
        pkg.spec do |s|
          s.name = "tailwind_gem"
          s.version = "0.1.0"
          s.summary = "Tailwind CSS integration gem"
          s.authors = ["HNM Labs"]
          s.license = "MIT"
          s.files = ["lib/theme.rb"]
        end
      end

      assert_equal 1, res.resources.size
      tw_res = res.resources.first
      assert_equal :tailwind, tw_res.framework
      assert_equal "public/tailwind", tw_res.mount_to
      assert tw_res.assets.key?("tailwind.css")
      assert_equal "public/tailwind/tailwind.css", tw_res.assets["tailwind.css"][:gem_path]

      # Verify compiled gem contains the mounted CSS and manifest
      inspection = RubyToFaster.inspect_gem(res.gem_path)
      entry_paths = inspection[:entries].map { |e| e[:path] }
      assert_includes entry_paths, "public/tailwind/tailwind.css"
      assert_includes entry_paths, "public/rtf-manifest.json"

      manifest = inspection[:frontend_manifests]["public/rtf-manifest.json"]
      assert manifest["frameworks"].key?("tailwind")
    end
  end

  def test_esbuild_detection_metafile_and_collection
    Dir.mktmpdir("rtf-esbuild-test-") do |dir|
      File.write(File.join(dir, "package.json"), '{"devDependencies":{"esbuild":"^0.20.0"}}')
      assert RubyToFaster::Resources::Esbuild.detect?(dir)

      # Create prebuilt dist/ with JS, CSS, and metafile.json
      out_dir = File.join(dir, "dist")
      FileUtils.mkdir_p(out_dir)
      File.write(File.join(out_dir, "app.js"), "console.log('esbuild bundle');\n")
      File.write(File.join(out_dir, "app.css"), ".esbuild { color: red; }\n")

      metafile = {
        "inputs" => { "src/index.js" => { "bytes" => 100 } },
        "outputs" => {
          "dist/app.js" => {
            "bytes" => 500,
            "entryPoint" => "src/index.js",
            "cssBundle" => "dist/app.css"
          }
        }
      }
      File.write(File.join(out_dir, "metafile.json"), JSON.generate(metafile))

      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/js_gem.rb"), "module JsGem; end\n")

      res = RubyToFaster.build(root_dir: dir, report: false) do |pkg|
        pkg.incremental = false
        pkg.esbuild(
          root: ".",
          out_dir: "dist",
          mount_to: "public/esbuild"
        )
        pkg.spec do |s|
          s.name = "esbuild_gem"
          s.version = "0.1.0"
          s.summary = "Esbuild integration gem"
          s.authors = ["HNM Labs"]
          s.license = "MIT"
          s.files = ["lib/js_gem.rb"]
        end
      end

      assert_equal 1, res.resources.size
      es_res = res.resources.first
      assert_equal :esbuild, es_res.framework
      assert_equal "public/esbuild", es_res.mount_to
      assert es_res.assets.key?("app.js")
      assert es_res.assets.key?("app.css")

      # Verify compiled gem contains the mounted JS/CSS files
      inspection = RubyToFaster.inspect_gem(res.gem_path)
      entry_paths = inspection[:entries].map { |e| e[:path] }
      assert_includes entry_paths, "public/esbuild/app.js"
      assert_includes entry_paths, "public/esbuild/app.css"
      assert_includes entry_paths, "public/rtf-manifest.json"
    end
  end
end
