# frozen_string_literal: true

require "digest"
require "json"
require "rubygems/package"
require "zlib"

module RubyToFaster
  # Zero-unpack `.gem` package inspector and cryptographic integrity verifier.
  class Inspector
    def self.inspect_gem(gem_path)
      raise ConfigError, "Gem file not found: #{gem_path}" unless File.file?(gem_path)

      pkg = Gem::Package.new(gem_path)
      pkg.verify

      spec = pkg.spec
      entries = []
      embedded_manifests = {}
      unpacked_bytes = 0

      File.open(gem_path, "rb") do |outer_io|
        Gem::Package::TarReader.new(outer_io) do |outer_tar|
          outer_tar.each do |outer_entry|
            next unless outer_entry.full_name == "data.tar.gz"

            Zlib::GzipReader.wrap(outer_entry) do |gz_io|
              Gem::Package::TarReader.new(gz_io) do |data_tar|
                data_tar.each do |item|
                  size = item.header.size
                  unpacked_bytes += size
                  entries << {
                    path: item.full_name,
                    size: size,
                    mode: format("0%o", item.header.mode & 0o777)
                  }

                  if item.full_name.end_with?("rtf-manifest.json")
                    embedded_manifests[item.full_name] = JSON.parse(item.read)
                  end
                end
              end
            end
          end
        end
      end

      {
        file: File.expand_path(gem_path),
        name: spec.name,
        version: spec.version.to_s,
        platform: spec.platform.to_s,
        summary: spec.summary,
        licenses: spec.licenses,
        required_ruby_version: spec.required_ruby_version.to_s,
        compressed_bytes: File.size(gem_path),
        unpacked_bytes: unpacked_bytes,
        sha256: Digest::SHA256.file(gem_path).hexdigest,
        checksums_verified: true,
        entry_count: entries.size,
        entries: entries,
        frontend_manifests: embedded_manifests
      }
    end
  end
end
