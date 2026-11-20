# frozen_string_literal: true

require "test_helper"
require "stringio"

class TestSbomStatsVerifyWorkspace < Minitest::Test
  def create_sample_gem(dir, name: "alpha_gem", version: "1.0.0", deps: [])
    FileUtils.mkdir_p(File.join(dir, "lib"))
    File.write(File.join(dir, "lib/#{name}.rb"), "# frozen_string_literal: true\nmodule #{name.split('_').map(&:capitalize).join}\n  VERSION = #{version.dump}\nend\n" * 5)
    File.write(File.join(dir, "README.md"), "# #{name}\n\nSample gem readme.\n")

    dep_lines = deps.map { |d| "  s.add_dependency #{d.dump}, '>= 0.1.0'" }.join("\n")
    gemspec = <<~SPEC
      Gem::Specification.new do |s|
        s.name        = #{name.dump}
        s.version     = #{version.dump}
        s.summary     = "Sample gem #{name}"
        s.authors     = ["HNM Labs"]
        s.license     = "MIT"
        s.homepage    = "https://example.com/#{name}"
        s.required_ruby_version = ">= 3.0.0"
        s.files       = ["lib/#{name}.rb", "README.md"]
      #{dep_lines}
      end
    SPEC
    File.write(File.join(dir, "#{name}.gemspec"), gemspec)
  end

  def test_sbom_cyclonedx_and_spdx_and_embedded
    Dir.mktmpdir("rtf-sbom-") do |dir|
      create_sample_gem(dir, name: "sec_gem", version: "2.1.0", deps: ["rack"])

      cdx = JSON.parse(RubyToFaster.sbom(root_dir: dir, format: :cyclonedx))
      assert_equal "CycloneDX", cdx["bomFormat"]
      assert_equal "1.5", cdx["specVersion"]
      assert_equal "pkg:gem/sec_gem@2.1.0", cdx.dig("metadata", "component", "purl")
      assert cdx["components"].any? { |c| c["name"] == "rack" && c["type"] == "library" }
      assert cdx["components"].any? { |c| c["name"] == "lib/sec_gem.rb" && c["type"] == "file" }

      spdx = JSON.parse(RubyToFaster.sbom(root_dir: dir, format: :spdx))
      assert_equal "SPDX-2.3", spdx["spdxVersion"]
      assert spdx["packages"].any? { |p| p["name"] == "sec_gem" }
      assert spdx["packages"].any? { |p| p["name"] == "rack" }
      assert spdx["files"].any? { |f| f["fileName"] == "./lib/sec_gem.rb" }

      # Embed SBOM directly into compiled gem + emit .sha256 checksums file
      res = RubyToFaster.build(root_dir: dir, report: false) do |pkg|
        pkg.incremental = false
        pkg.embed_sbom :cyclonedx
        pkg.checksums_file = true
      end

      inspection = RubyToFaster.inspect_gem(res.gem_path)
      paths = inspection[:entries].map { |e| e[:path] }
      assert_includes paths, "sbom.cdx.json"
      assert File.file?("#{res.gem_path}.sha256")
      assert_includes File.read("#{res.gem_path}.sha256"), res.gem_sha256
    end
  end

  def test_stats_and_verify_cli_and_reproducible
    Dir.mktmpdir("rtf-stats-verify-") do |dir|
      create_sample_gem(dir, name: "metrics_gem", version: "0.4.0")

      Dir.chdir(dir) do
        out = StringIO.new
        err = StringIO.new
        code = RubyToFaster::CLI.start(["build", "--quiet"], out: out, err: err)
        assert_equal 0, code

        gem_path = File.join(dir, "pkg/metrics_gem-0.4.0.gem")

        # Stats CLI JSON & text
        out_stats = StringIO.new
        code_stats = RubyToFaster::CLI.start(["stats", gem_path, "--json"], out: out_stats, err: err)
        assert_equal 0, code_stats
        stats_json = JSON.parse(out_stats.string)
        assert_equal "metrics_gem", stats_json["gem_name"]
        assert_equal 2, stats_json["entry_count"]
        assert stats_json["by_extension"].any? { |e| e["extension"] == ".rb" }

        # Verify CLI checksum & reproducible mode
        sha = Digest::SHA256.file(gem_path).hexdigest
        out_ver = StringIO.new
        code_ver = RubyToFaster::CLI.start(["verify", gem_path, "--sha256", sha], out: out_ver, err: err)
        assert_equal 0, code_ver
        assert_includes out_ver.string, "[VERIFIED]"

        # Verify mismatch returns 1
        out_bad = StringIO.new
        code_bad = RubyToFaster::CLI.start(["verify", gem_path, "--sha256", "0" * 64], out: out_bad, err: err)
        assert_equal 1, code_bad

        # Reproducible verification across two fresh clean builds
        out_repro = StringIO.new
        code_repro = RubyToFaster::CLI.start(["verify", "--reproducible", "--json"], out: out_repro, err: err)
        assert_equal 0, code_repro
        repro_json = JSON.parse(out_repro.string)
        assert_equal true, repro_json["passed"]
        assert_equal true, repro_json["reproducible_match"]
        assert_equal repro_json["sha256"], repro_json["rebuild_sha256"]

        # SBOM CLI output to file
        out_sbom = StringIO.new
        sbom_file = File.join(dir, "pkg/bom.cdx.json")
        code_sbom = RubyToFaster::CLI.start(["sbom", "--format", "cyclonedx", "-o", sbom_file], out: out_sbom, err: err)
        assert_equal 0, code_sbom
        assert File.file?(sbom_file)
      end
    end
  end

  def test_workspace_topological_discovery_and_cli
    Dir.mktmpdir("rtf-ws-") do |dir|
      # app_gem depends on core_gem -> core_gem must be discovered/built before app_gem
      create_sample_gem(File.join(dir, "gems/app_gem"), name: "app_gem", version: "1.0.0", deps: ["core_gem"])
      create_sample_gem(File.join(dir, "gems/core_gem"), name: "core_gem", version: "1.0.0")

      ws = RubyToFaster.workspace(root_dir: dir)
      discovered = ws.discover
      assert_equal %w[core_gem app_gem], discovered.map { |m| m[:name] }

      Dir.chdir(dir) do
        out = StringIO.new
        err = StringIO.new
        code = RubyToFaster::CLI.start(["workspace", "build", "--json"], out: out, err: err)
        assert_equal 0, code
        report = JSON.parse(out.string)
        assert_equal true, report["success"]
        assert_equal 2, report["member_count"]
        assert_equal %w[core_gem app_gem], report["members"].map { |m| m["name"] }

        # Workspace check
        out_chk = StringIO.new
        code_chk = RubyToFaster::CLI.start(["workspace", "check"], out: out_chk, err: err)
        assert_equal 0, code_chk
        assert_includes out_chk.string, "[OK]"

        # Workspace clean
        out_cln = StringIO.new
        code_cln = RubyToFaster::CLI.start(["workspace", "clean"], out: out_cln, err: err)
        assert_equal 0, code_cln
        refute Dir.exist?(File.join(dir, "gems/core_gem/pkg"))
      end
    end
  end

  def test_rust_extension_missing_cargo_toml_raises_build_error
    Dir.mktmpdir("rtf-rust-ext-") do |dir|
      cfg = RubyToFaster::Config.new(root_dir: dir)
      spec = Gem::Specification.new do |s|
        s.name = "rusty_gem"
        s.version = "0.1.0"
        s.summary = "Rust native extension gem"
        s.authors = ["HNM Labs"]
        s.extensions = ["ext/rusty/Cargo.toml"]
      end

      err = assert_raises(RubyToFaster::BuildError) do
        RubyToFaster::ExtensionBuilder.new(cfg).compile_all(spec)
      end
      assert_includes err.message, "Cargo.toml"
    end
  end
end
