# frozen_string_literal: true

require "digest"
require "json"
require "time"

module RubyToFaster
  # Zero-dependency Software Bill of Materials (SBOM) generator supporting
  # CycloneDX 1.5 JSON and SPDX 2.3 JSON formats for supply-chain compliance.
  class SBOM
    SUPPORTED_FORMATS = %i[cyclonedx spdx].freeze

    def initialize(spec:, entries:, gem_sha256: nil, reproducible_epoch: nil, adapter_results: [])
      @spec               = spec
      @entries            = entries
      @gem_sha256         = gem_sha256
      @reproducible_epoch = reproducible_epoch
      @adapter_results    = Array(adapter_results)
    end

    def generate(format: :cyclonedx)
      fmt = format.to_sym
      unless SUPPORTED_FORMATS.include?(fmt)
        raise ConfigError, "Unsupported SBOM format: #{format.inspect} (expected :cyclonedx or :spdx)"
      end

      case fmt
      when :cyclonedx then build_cyclonedx
      when :spdx      then build_spdx
      end
    end

    def to_json_pretty(format: :cyclonedx)
      "#{JSON.pretty_generate(generate(format: format))}\n"
    end

    private

    def timestamp_iso8601
      t = @reproducible_epoch ? Time.at(@reproducible_epoch).utc : Time.now.utc
      t.strftime("%Y-%m-%dT%H:%M:%SZ")
    end

    def purl_for(name, version = nil)
      version ? "pkg:gem/#{name}@#{version}" : "pkg:gem/#{name}"
    end

    def build_cyclonedx
      pkg_purl = purl_for(@spec.name, @spec.version.to_s)
      serial_seed = Digest::SHA256.hexdigest("#{pkg_purl}:#{@gem_sha256 || @entries.keys.sort.join(',')}")
      uuid = "#{serial_seed[0, 8]}-#{serial_seed[8, 4]}-5#{serial_seed[13, 3]}-8#{serial_seed[17, 3]}-#{serial_seed[20, 12]}"

      components = []

      # Runtime & development gem dependencies
      @spec.dependencies.sort_by(&:name).each do |dep|
        scope = dep.type == :runtime ? "required" : "optional"
        components << {
          "type" => "library",
          "bom-ref" => "dep:#{dep.name}",
          "name" => dep.name,
          "version" => dep.requirement.to_s,
          "scope" => scope,
          "purl" => purl_for(dep.name),
          "properties" => [
            { "name" => "rubygems:dependency_type", "value" => dep.type.to_s }
          ]
        }
      end

      # Frontend framework bundles staged inside the gem
      @adapter_results.each do |res|
        components << {
          "type" => "application",
          "bom-ref" => "frontend:#{res.framework}:#{res.mount_to}",
          "name" => "#{@spec.name}-#{res.framework}-assets",
          "version" => @spec.version.to_s,
          "description" => "Staged #{res.framework} frontend assets mounted at #{res.mount_to}",
          "properties" => [
            { "name" => "rtf:framework", "value" => res.framework.to_s },
            { "name" => "rtf:mount_to", "value" => res.mount_to.to_s },
            { "name" => "rtf:asset_count", "value" => res.assets.size.to_s }
          ]
        }
      end

      # Individual file components with SHA-256 hashes
      file_entries = @entries.keys.sort.map do |gem_path|
        entry = @entries[gem_path]
        sha = entry.virtual? ? Digest::SHA256.hexdigest(entry.content) : Digest::SHA256.file(entry.source_path).hexdigest
        {
          "type" => "file",
          "bom-ref" => "file:#{gem_path}",
          "name" => gem_path,
          "hashes" => [{ "alg" => "SHA-256", "content" => sha }],
          "properties" => [
            { "name" => "rtf:bytes", "value" => entry.size.to_s },
            { "name" => "rtf:mode", "value" => format("0%o", entry.mode) }
          ]
        }
      end

      main_component = {
        "type" => "library",
        "bom-ref" => pkg_purl,
        "name" => @spec.name,
        "version" => @spec.version.to_s,
        "description" => @spec.summary.to_s,
        "purl" => pkg_purl,
        "licenses" => Array(@spec.licenses).map { |lic| { "license" => { "id" => lic } } }
      }
      if @gem_sha256
        main_component["hashes"] = [{ "alg" => "SHA-256", "content" => @gem_sha256 }]
      end

      {
        "bomFormat" => "CycloneDX",
        "specVersion" => "1.5",
        "serialNumber" => "urn:uuid:#{uuid}",
        "version" => 1,
        "metadata" => {
          "timestamp" => timestamp_iso8601,
          "tools" => {
            "components" => [
              {
                "type" => "application",
                "name" => "rubytofaster",
                "version" => RubyToFaster::VERSION
              }
            ]
          },
          "component" => main_component
        },
        "components" => components + file_entries,
        "dependencies" => [
          {
            "ref" => pkg_purl,
            "dependsOn" => @spec.dependencies.sort_by(&:name).map { |d| "dep:#{d.name}" }
          }
        ]
      }
    end

    def build_spdx
      pkg_spdx_id = "SPDXRef-Package-#{sanitize_spdx_id(@spec.name)}"
      doc_namespace = "https://rubytofaster.dev/spdx/#{@spec.name}-#{@spec.version}"
      license_expr = Array(@spec.licenses).empty? ? "NOASSERTION" : Array(@spec.licenses).join(" AND ")

      packages = [
        {
          "SPDXID" => pkg_spdx_id,
          "name" => @spec.name,
          "versionInfo" => @spec.version.to_s,
          "downloadLocation" => @spec.homepage.to_s.empty? ? "NOASSERTION" : @spec.homepage.to_s,
          "filesAnalyzed" => true,
          "licenseConcluded" => license_expr,
          "licenseDeclared" => license_expr,
          "summary" => @spec.summary.to_s,
          "externalRefs" => [
            {
              "referenceCategory" => "PACKAGE-MANAGER",
              "referenceType" => "purl",
              "referenceLocator" => purl_for(@spec.name, @spec.version.to_s)
            }
          ]
        }
      ]
      if @gem_sha256
        packages.first["checksums"] = [{ "algorithm" => "SHA256", "checksumValue" => @gem_sha256 }]
      end

      relationships = [
        {
          "spdxElementId" => "SPDXRef-DOCUMENT",
          "relationshipType" => "DESCRIBES",
          "relatedSpdxElement" => pkg_spdx_id
        }
      ]

      @spec.dependencies.sort_by(&:name).each do |dep|
        dep_id = "SPDXRef-Dep-#{sanitize_spdx_id(dep.name)}"
        packages << {
          "SPDXID" => dep_id,
          "name" => dep.name,
          "versionInfo" => dep.requirement.to_s,
          "downloadLocation" => "NOASSERTION",
          "filesAnalyzed" => false,
          "licenseConcluded" => "NOASSERTION",
          "externalRefs" => [
            {
              "referenceCategory" => "PACKAGE-MANAGER",
              "referenceType" => "purl",
              "referenceLocator" => purl_for(dep.name)
            }
          ]
        }
        relationships << {
          "spdxElementId" => pkg_spdx_id,
          "relationshipType" => dep.type == :runtime ? "DEPENDS_ON" : "DEV_DEPENDENCY_OF",
          "relatedSpdxElement" => dep_id
        }
      end

      files = @entries.keys.sort.each_with_index.map do |gem_path, idx|
        entry = @entries[gem_path]
        sha = entry.virtual? ? Digest::SHA256.hexdigest(entry.content) : Digest::SHA256.file(entry.source_path).hexdigest
        file_id = "SPDXRef-File-#{idx + 1}"
        relationships << {
          "spdxElementId" => pkg_spdx_id,
          "relationshipType" => "CONTAINS",
          "relatedSpdxElement" => file_id
        }
        {
          "SPDXID" => file_id,
          "fileName" => "./#{gem_path}",
          "checksums" => [{ "algorithm" => "SHA256", "checksumValue" => sha }],
          "licenseConcluded" => license_expr,
          "copyrightText" => "NOASSERTION"
        }
      end

      {
        "spdxVersion" => "SPDX-2.3",
        "dataLicense" => "CC0-1.0",
        "SPDXID" => "SPDXRef-DOCUMENT",
        "name" => "#{@spec.name}-#{@spec.version}",
        "documentNamespace" => doc_namespace,
        "creationInfo" => {
          "created" => timestamp_iso8601,
          "creators" => ["Tool: rubytofaster-#{RubyToFaster::VERSION}"]
        },
        "packages" => packages,
        "files" => files,
        "relationships" => relationships
      }
    end

    def sanitize_spdx_id(str)
      str.to_s.gsub(/[^A-Za-z0-9.\-]/, "-")
    end
  end
end
