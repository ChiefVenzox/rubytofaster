# frozen_string_literal: true

require "json"

module RubyToFaster
  # Builds unified frontend resource manifests and zero-dependency Ruby runtime asset helpers
  # so gems bundling Vite, Next.js, Angular, Astro, SvelteKit, Nuxt, Tailwind, Esbuild, Webpack,
  # Parcel, or Sass UIs can resolve hashed chunks with SRI & HTTP/2 preload headers without Node.js.
  class AssetManifest
    MANIFEST_SCHEMA = 1

    attr_reader :data

    def initialize(manifest_hash)
      @data = manifest_hash
    end

    def self.from_adapter_results(results)
      frameworks = {}
      results.each do |res|
        key = res.framework.to_s
        frameworks[key] = {
          "mount_to" => res.mount_to,
          "entrypoints" => deep_stringify(res.entrypoints),
          "assets" => deep_stringify(res.assets),
          "metadata" => deep_stringify(res.metadata)
        }
      end

      new(
        "schema" => MANIFEST_SCHEMA,
        "generator" => "rubytofaster/#{RubyToFaster::VERSION}",
        "frameworks" => frameworks
      )
    end

    def self.load_file(path)
      new(JSON.parse(File.read(path)))
    end

    def to_json_pretty
      "#{JSON.pretty_generate(@data)}\n"
    end

    def frameworks
      (@data["frameworks"] || {}).keys
    end

    # Resolves a logical asset or entrypoint path to its mounted relative URL/file path.
    def asset_path(logical_name, framework: nil)
      fw_map = @data["frameworks"] || {}
      targets = framework ? { framework.to_s => fw_map[framework.to_s] }.compact : fw_map

      targets.each_value do |info|
        ep = info.dig("entrypoints", logical_name.to_s)
        return ep["file"] if ep && ep["file"]

        asset = info.dig("assets", logical_name.to_s)
        return logical_name.to_s if asset
      end
      nil
    end

    # Returns the SHA-384 Subresource Integrity (SRI) string for a logical asset or entrypoint.
    def integrity(logical_name, framework: nil)
      fw_map = @data["frameworks"] || {}
      targets = framework ? { framework.to_s => fw_map[framework.to_s] }.compact : fw_map

      targets.each_value do |info|
        ep = info.dig("entrypoints", logical_name.to_s)
        resolved = ep && ep["file"] ? ep["file"] : logical_name.to_s
        sri = info.dig("assets", resolved, "integrity")
        return sri if sri
      end
      nil
    end

    # Generates `<link rel="stylesheet">` and `<script type="module">` HTML tags for an entrypoint.
    # Pass `sri: true` to emit `integrity="sha384-..." crossorigin="anonymous"` attributes.
    def html_tags(entry_name, framework: nil, url_prefix: "/", sri: false)
      prefix = url_prefix.end_with?("/") ? url_prefix : "#{url_prefix}/"
      fw_map = @data["frameworks"] || {}
      targets = framework ? { framework.to_s => fw_map[framework.to_s] }.compact : fw_map

      targets.each_value do |info|
        ep = info.dig("entrypoints", entry_name.to_s)
        next unless ep

        assets = info["assets"] || {}
        tags = []
        Array(ep["css"]).each do |css_rel|
          clean = css_rel.sub(%r{\A/}, "")
          sri_attr = sri_attribute(assets, clean, sri)
          tags << %(<link rel="stylesheet" href="#{prefix}#{clean}"#{sri_attr}>)
        end
        scripts = ep["scripts"] ? Array(ep["scripts"]) : [ep["file"]].compact
        scripts.each do |js_rel|
          next if js_rel.end_with?(".css")

          clean = js_rel.sub(%r{\A/}, "")
          sri_attr = sri_attribute(assets, clean, sri)
          tags << %(<script type="module" src="#{prefix}#{clean}"#{sri_attr}></script>)
        end
        return tags.join("\n")
      end

      ""
    end

    # Generates an HTTP `Link` header value suitable for HTTP/2 Push or HTTP 103 Early Hints.
    def preload_headers(entry_name, framework: nil, url_prefix: "/")
      prefix = url_prefix.end_with?("/") ? url_prefix : "#{url_prefix}/"
      fw_map = @data["frameworks"] || {}
      targets = framework ? { framework.to_s => fw_map[framework.to_s] }.compact : fw_map

      targets.each_value do |info|
        ep = info.dig("entrypoints", entry_name.to_s)
        next unless ep

        links = []
        Array(ep["css"]).each do |css_rel|
          links << %(<#{prefix}#{css_rel.sub(%r{\A/}, '')}>; rel=preload; as=style)
        end
        scripts = ep["scripts"] ? Array(ep["scripts"]) : [ep["file"]].compact
        scripts.each do |js_rel|
          next if js_rel.end_with?(".css")

          links << %(<#{prefix}#{js_rel.sub(%r{\A/}, '')}>; rel=modulepreload; as=script)
        end
        return links.join(", ")
      end

      ""
    end

    # Emits a standalone, zero-dependency Ruby helper file that can be required inside the target gem.
    def generate_ruby_helper_source(module_name)
      embedded_json = JSON.generate(@data)
      parts = module_name.to_s.split("::").reject(&:empty?)
      raise ConfigError, "Invalid Ruby module name: #{module_name.inspect}" if parts.empty?

      indent = "  "
      openers = parts.each_with_index.map { |mod, idx| "#{indent * idx}module #{mod}" }.join("\n")
      closers = (parts.size - 1).downto(0).map { |idx| "#{indent * idx}end" }.join("\n")
      body_indent = indent * parts.size

      body = <<~RUBY
        MANIFEST = JSON.parse(#{embedded_json.dump}).freeze

        def self.manifest
          MANIFEST
        end

        def self.asset_path(name, framework: nil)
          fws = MANIFEST["frameworks"] || {}
          scope = framework ? { framework.to_s => fws[framework.to_s] }.compact : fws
          scope.each_value do |info|
            ep = info.dig("entrypoints", name.to_s)
            return ep["file"] if ep && ep["file"]
            return name.to_s if info.dig("assets", name.to_s)
          end
          nil
        end

        def self.integrity(name, framework: nil)
          fws = MANIFEST["frameworks"] || {}
          scope = framework ? { framework.to_s => fws[framework.to_s] }.compact : fws
          scope.each_value do |info|
            ep = info.dig("entrypoints", name.to_s)
            resolved = ep && ep["file"] ? ep["file"] : name.to_s
            sri = info.dig("assets", resolved, "integrity")
            return sri if sri
          end
          nil
        end

        def self.html_tags(entry, framework: nil, url_prefix: "/", sri: false)
          prefix = url_prefix.end_with?("/") ? url_prefix : "\#{url_prefix}/"
          fws = MANIFEST["frameworks"] || {}
          scope = framework ? { framework.to_s => fws[framework.to_s] }.compact : fws
          scope.each_value do |info|
            ep = info.dig("entrypoints", entry.to_s)
            next unless ep

            assets = info["assets"] || {}
            tags = []
            Array(ep["css"]).each do |c|
              clean = c.sub(%r{\\A/}, "")
              sri_val = sri ? assets.dig(clean, "integrity") : nil
              sri_attr = sri_val ? %( integrity="\#{sri_val}" crossorigin="anonymous") : ""
              tags << %(<link rel="stylesheet" href="\#{prefix}\#{clean}"\#{sri_attr}>)
            end
            scripts = ep["scripts"] ? Array(ep["scripts"]) : [ep["file"]].compact
            scripts.each do |j|
              next if j.end_with?(".css")

              clean = j.sub(%r{\\A/}, "")
              sri_val = sri ? assets.dig(clean, "integrity") : nil
              sri_attr = sri_val ? %( integrity="\#{sri_val}" crossorigin="anonymous") : ""
              tags << %(<script type="module" src="\#{prefix}\#{clean}"\#{sri_attr}></script>)
            end
            return tags.join("\\n")
          end
          ""
        end

        def self.preload_headers(entry, framework: nil, url_prefix: "/")
          prefix = url_prefix.end_with?("/") ? url_prefix : "\#{url_prefix}/"
          fws = MANIFEST["frameworks"] || {}
          scope = framework ? { framework.to_s => fws[framework.to_s] }.compact : fws
          scope.each_value do |info|
            ep = info.dig("entrypoints", entry.to_s)
            next unless ep

            links = []
            Array(ep["css"]).each { |c| links << %(<\#{prefix}\#{c.sub(%r{\\A/}, '')}>; rel=preload; as=style) }
            scripts = ep["scripts"] ? Array(ep["scripts"]) : [ep["file"]].compact
            scripts.each { |j| links << %(<\#{prefix}\#{j.sub(%r{\\A/}, '')}>; rel=modulepreload; as=script) unless j.end_with?(".css") }
            return links.join(", ")
          end
          ""
        end
      RUBY

      indented_body = body.lines.map { |l| l.strip.empty? ? "\n" : "#{body_indent}#{l}" }.join

      <<~FILE
        # frozen_string_literal: true
        # Generated by RubyToFaster v#{RubyToFaster::VERSION} — DO NOT EDIT MANUALLY

        require "json"

        #{openers}
        #{indented_body.chomp}
        #{closers}
      FILE
    end

    def self.deep_stringify(obj)
      case obj
      when Hash
        obj.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
      when Array
        obj.map { |v| deep_stringify(v) }
      when Symbol
        obj.to_s
      else
        obj
      end
    end

    private

    def sri_attribute(assets, clean_path, enabled)
      return "" unless enabled

      val = assets.dig(clean_path, "integrity")
      val ? %( integrity="#{val}" crossorigin="anonymous") : ""
    end
  end
end
