# frozen_string_literal: true

require "test_helper"

class TestCompilerAndPackager < Minitest::Test
  def test_inline_spec_reproducible_build_and_rubygems_verify
    Dir.mktmpdir("rtf-inline-") do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      FileUtils.mkdir_p(File.join(dir, "exe"))
      File.write(File.join(dir, "lib/tiny.rb"), "# frozen_string_literal: true\nmodule Tiny; V = '1.0.0'; end\n")
      File.write(File.join(dir, "exe/tiny"), "#!/usr/bin/env ruby\nputs 'hi'\n")

      res1 = RubyToFaster.build(root_dir: dir, report: false) do |pkg|
        pkg.incremental = false
        pkg.reproducible = true
        pkg.source_date_epoch = 1_700_000_000
        pkg.spec do |s|
          s.name        = "tiny_demo"
          s.version     = "1.0.0"
          s.summary     = "Tiny inline gem"
          s.authors     = ["HNM Labs"]
          s.license     = "MIT"
          s.files       = ["lib/tiny.rb", "exe/tiny"]
          s.bindir      = "exe"
          s.executables = ["tiny"]
        end
      end

      assert File.file?(res1.gem_path)
      assert_equal "tiny_demo", res1.gem_name
      assert_equal 2, res1.entry_count

      # Verify compatibility with standard RubyGems Gem::Package
      gem_pkg = Gem::Package.new(res1.gem_path)
      gem_pkg.verify
      assert_equal ["exe/tiny", "lib/tiny.rb"], gem_pkg.contents.sort

      # Rebuild into another folder and assert bit-for-bit identical SHA-256 reproducibility
      res2 = RubyToFaster.build(root_dir: dir, report: false) do |pkg|
        pkg.incremental = false
        pkg.reproducible = true
        pkg.source_date_epoch = 1_700_000_000
        pkg.output_dir "pkg2"
        pkg.spec do |s|
          s.name        = "tiny_demo"
          s.version     = "1.0.0"
          s.summary     = "Tiny inline gem"
          s.authors     = ["HNM Labs"]
          s.license     = "MIT"
          s.files       = ["exe/tiny", "lib/tiny.rb"] # reversed input order must still sort deterministically
          s.bindir      = "exe"
          s.executables = ["tiny"]
        end
      end

      assert_equal res1.gem_sha256, res2.gem_sha256
      assert_equal res1.gem_sha512, res2.gem_sha512
    end
  end

  def test_plugin_transform_and_lifecycle_hooks
    Dir.mktmpdir("rtf-plugin-") do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/banner.rb"), "VERSION_TOKEN = '__BUILD_STAMP__'\n")

      events = []
      result = RubyToFaster.build(root_dir: dir, report: false) do |pkg|
        pkg.before_resolve { events << :before_resolve }
        pkg.transform do |path, content|
          path == "lib/banner.rb" ? content.gsub("__BUILD_STAMP__", "2026.11") : nil
        end
        pkg.generate_bundle { |_entries, _cfg| events << :generate_bundle }
        pkg.after_package { |res| events << [:after_package, res.gem_name] }

        pkg.spec do |s|
          s.name    = "hooked_gem"
          s.version = "0.2.0"
          s.summary = "Plugin transform test"
          s.authors = ["HNM Labs"]
          s.files   = ["lib/banner.rb"]
        end
      end

      assert_equal [:before_resolve, :generate_bundle, [:after_package, "hooked_gem"]], events

      # Extract via Gem::Package and confirm transformed content is inside the .gem while disk file is untouched
      assert_includes File.read(File.join(dir, "lib/banner.rb")), "__BUILD_STAMP__"
      Dir.mktmpdir("rtf-extract-") do |extract_dir|
        Gem::Package.new(result.gem_path).extract_files(extract_dir)
        assert_equal "VERSION_TOKEN = '2026.11'\n", File.read(File.join(extract_dir, "lib/banner.rb"))
      end
    end
  end

  def test_parallel_native_c_extension_compilation
    Dir.mktmpdir("rtf-native-") do |dir|
      ext_dir = File.join(dir, "ext/fast_adder")
      lib_dir = File.join(dir, "lib")
      FileUtils.mkdir_p(ext_dir)
      FileUtils.mkdir_p(lib_dir)

      File.write(File.join(lib_dir, "fast_adder.rb"), "# frozen_string_literal: true\n")
      File.write(
        File.join(ext_dir, "extconf.rb"),
        <<~RUBY
          require "mkmf"
          create_makefile("fast_adder/fast_adder")
        RUBY
      )
      File.write(
        File.join(ext_dir, "fast_adder.c"),
        <<~C
          #include <ruby.h>
          static VALUE rb_add(VALUE self, VALUE a, VALUE b) {
            return LONG2NUM(NUM2LONG(a) + NUM2LONG(b));
          }
          void Init_fast_adder(void) {
            VALUE mod = rb_define_module("FastAdder");
            rb_define_singleton_method(mod, "add", rb_add, 2);
          }
        C
      )

      res = RubyToFaster.build(root_dir: dir, report: false) do |pkg|
        pkg.parallel 2
        pkg.spec do |s|
          s.name       = "fast_adder"
          s.version    = "0.1.0"
          s.summary    = "Native C extension gem"
          s.authors    = ["HNM Labs"]
          s.files      = ["lib/fast_adder.rb", "ext/fast_adder/extconf.rb", "ext/fast_adder/fast_adder.c"]
          s.extensions = ["ext/fast_adder/extconf.rb"]
        end
      end

      assert_equal 1, res.extensions.size
      assert_equal :ok, res.extensions.first.status
      assert File.file?(res.gem_path)
    end
  end
end
