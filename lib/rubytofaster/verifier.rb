# frozen_string_literal: true

require "digest"
require "tmpdir"
require_relative "inspector"

module RubyToFaster
  # Cryptographic `.gem` integrity & bit-for-bit reproducibility verifier (`rtf verify`).
  class Verifier
    VerifyReport = Struct.new(
      :gem_path,
      :gem_name,
      :gem_version,
      :sha256,
      :sha512,
      :checksums_valid,
      :expected_sha256,
      :sha256_match,
      :reproducible_checked,
      :reproducible_match,
      :rebuild_sha256,
      :passed,
      :errors,
      keyword_init: true
    ) do
      def passed?
        !!passed
      end

      def to_h
        {
          gem_path: gem_path,
          gem_name: gem_name,
          gem_version: gem_version,
          sha256: sha256,
          sha512: sha512,
          checksums_valid: checksums_valid,
          expected_sha256: expected_sha256,
          sha256_match: sha256_match,
          reproducible_checked: reproducible_checked,
          reproducible_match: reproducible_match,
          rebuild_sha256: rebuild_sha256,
          passed: passed?,
          errors: errors
        }
      end
    end

    def self.verify_gem(gem_path, expected_sha256: nil)
      raise ConfigError, "Gem file not found: #{gem_path}" unless File.file?(gem_path)

      errors = []
      info = nil
      checksums_valid = false

      begin
        info = Inspector.inspect_gem(gem_path)
        checksums_valid = info[:checksums_verified]
      rescue StandardError => e
        errors << "RubyGems package verification failed: #{e.message}"
      end

      actual_sha256 = Digest::SHA256.file(gem_path).hexdigest
      actual_sha512 = Digest::SHA512.file(gem_path).hexdigest

      sha256_match = nil
      if expected_sha256
        norm_expected = expected_sha256.to_s.strip.downcase
        sha256_match = (actual_sha256 == norm_expected)
        errors << "SHA-256 mismatch: expected #{norm_expected}, got #{actual_sha256}" unless sha256_match
      end

      VerifyReport.new(
        gem_path: File.expand_path(gem_path),
        gem_name: info ? info[:name] : File.basename(gem_path),
        gem_version: info ? info[:version] : "unknown",
        sha256: actual_sha256,
        sha512: actual_sha512,
        checksums_valid: checksums_valid,
        expected_sha256: expected_sha256,
        sha256_match: sha256_match,
        reproducible_checked: false,
        reproducible_match: nil,
        rebuild_sha256: nil,
        passed: checksums_valid && errors.empty?,
        errors: errors
      )
    end

    # Performs two independent clean builds (no cache) into isolated temp directories
    # and verifies that both `.gem` archives are bit-for-bit cryptographically identical.
    def self.verify_reproducible(config)
      errors = []
      build1 = nil
      build2 = nil

      Dir.mktmpdir("rtf-repro-a-") do |dir_a|
        Dir.mktmpdir("rtf-repro-b-") do |dir_b|
          cfg_a = clone_for_clean_build(config, dir_a)
          cfg_b = clone_for_clean_build(config, dir_b)

          build1 = Compiler.new(cfg_a).run
          build2 = Compiler.new(cfg_b).run

          match = (build1.gem_sha256 == build2.gem_sha256)
          unless match
            errors << "Non-deterministic build detected: build #1 (#{build1.gem_sha256}) != build #2 (#{build2.gem_sha256})"
          end

          info = Inspector.inspect_gem(build1.gem_path)
          return VerifyReport.new(
            gem_path: build1.gem_path,
            gem_name: build1.gem_name,
            gem_version: build1.gem_version,
            sha256: build1.gem_sha256,
            sha512: build1.gem_sha512,
            checksums_valid: info[:checksums_verified],
            expected_sha256: nil,
            sha256_match: nil,
            reproducible_checked: true,
            reproducible_match: match,
            rebuild_sha256: build2.gem_sha256,
            passed: info[:checksums_verified] && match && errors.empty?,
            errors: errors
          )
        end
      end
    end

    def self.checksums_line(gem_path)
      sha = Digest::SHA256.file(gem_path).hexdigest
      "#{sha}  #{File.basename(gem_path)}\n"
    end

    def self.clone_for_clean_build(config, out_dir)
      cfg = config.dup
      cfg.incremental = false
      cfg.reproducible = true
      cfg.out_dir = out_dir
      cfg.quiet = true
      cfg
    end
    private_class_method :clone_for_clean_build
  end
end
