# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestCliAndScriptExecution < Minitest::Test
  def test_cli_init_build_inspect_doctor_and_clean
    Dir.mktmpdir("rtf-cli-") do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("lib")
        File.write("lib/hello.rb", "module Hello; end\n")
        File.write(
          "hello.gemspec",
          <<~RUBY
            Gem::Specification.new do |s|
              s.name    = "hello_rtf"
              s.version = "0.3.0"
              s.summary = "CLI end-to-end test"
              s.authors = ["HNM Labs"]
              s.files   = ["lib/hello.rb"]
            end
          RUBY
        )

        out = StringIO.new
        err = StringIO.new

        assert_equal 0, RubyToFaster::CLI.start(["init", "--vite"], out: out, err: err)
        assert File.file?("gem.build.rb")

        # Rewrite gem.build.rb without vite since no frontend/dist exists in this minimal fixture
        assert_equal 0, RubyToFaster::CLI.start(["init", "--force"], out: out, err: err)

        build_out = StringIO.new
        assert_equal 0, RubyToFaster::CLI.start(["build", "--json"], out: build_out, err: err)
        parsed_build = JSON.parse(build_out.string)
        assert_equal "hello_rtf", parsed_build["gem_name"]
        assert File.file?("pkg/hello_rtf-0.3.0.gem")

        inspect_out = StringIO.new
        assert_equal 0, RubyToFaster::CLI.start(["inspect", "pkg/hello_rtf-0.3.0.gem", "--json"], out: inspect_out, err: err)
        parsed_inspect = JSON.parse(inspect_out.string)
        assert_equal true, parsed_inspect["checksums_verified"]

        doctor_out = StringIO.new
        assert_equal 0, RubyToFaster::CLI.start(["doctor"], out: doctor_out, err: err)
        parsed_doc = JSON.parse(doctor_out.string)
        assert_equal ["hello.gemspec"], parsed_doc["gemspecs_found"]

        watch_out = StringIO.new
        assert_equal 0, RubyToFaster::CLI.start(["watch", "--cycles", "1"], out: watch_out, err: err)
        assert_includes watch_out.string, "hello_rtf"

        clean_out = StringIO.new
        assert_equal 0, RubyToFaster::CLI.start(["clean"], out: clean_out, err: err)
        refute Dir.exist?(".rtf-cache")
        refute Dir.exist?("pkg")
      end
    end
  end

  def test_autorun_one_liner_script
    Dir.mktmpdir("rtf-autorun-") do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib/auto.rb"), "module Auto; end\n")
      File.write(
        File.join(dir, "auto.gemspec"),
        <<~RUBY
          Gem::Specification.new do |s|
            s.name    = "auto_gem"
            s.version = "0.0.1"
            s.summary = "Autorun test"
            s.authors = ["HNM Labs"]
            s.files   = ["lib/auto.rb"]
          end
        RUBY
      )
      script_path = File.join(dir, "build.rb")
      File.write(script_path, "require 'rubytofaster/autorun'\n")

      lib_path = File.expand_path("../lib", __dir__)
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I#{lib_path}", script_path, chdir: dir)
      assert status.success?, "autorun failed: #{stderr}"
      assert_includes stdout, "auto_gem (0.0.1)"
      assert File.file?(File.join(dir, "pkg/auto_gem-0.0.1.gem"))
    end
  end
end
