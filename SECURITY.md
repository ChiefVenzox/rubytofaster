# Security Policy

HNM Labs takes the security and supply-chain integrity of **RubyToFaster** seriously. Because `rubytofaster` compiles, packages, and stages code and frontend assets into distributable `.gem` archives, security controls are built directly into the core compiler pipeline.

---

## Supported Versions

The following release series currently receive security updates and patches:

| Version | Supported          | Ruby Requirement |
| ------- | ------------------ | ---------------- |
| `0.1.x` | :white_check_mark: | Ruby `>= 3.0.0`  |
| `< 0.1` | :x:                | N/A              |

---

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues, discussions, or pull requests.**

Instead, please report suspected vulnerabilities privately using one of the following channels:

1. **GitHub Private Vulnerability Reporting (Preferred):**
   Submit a confidential advisory directly at:
   https://github.com/HNMLabs/rubytofaster/security/advisories/new
2. **Email:**
   Send a detailed report to **security@hnmlabs.dev** with the subject line `[SECURITY] rubytofaster: <brief summary>`.

### What to Include in Your Report

To help us triage and remediate the issue rapidly, please include:

- Affected `rubytofaster` version, Ruby version (`ruby -v`), and OS platform.
- A minimal proof-of-concept (`gem.build.rb`, `.gemspec`, or directory layout) reproducing the issue.
- Impact assessment (e.g., arbitrary file inclusion, path traversal, command injection, checksum bypass, cache poisoning).
- Suggested remediation or patch, if available.

### Response Timeline & Coordinated Disclosure

| Stage | Target SLA |
| :--- | :--- |
| Initial acknowledgement | Within **48 hours** |
| Triage & severity assessment | Within **5 business days** |
| Fix development & release (Critical/High) | Within **14 days** |
| Public advisory & credit | Coordinated upon patch release |

We follow coordinated vulnerability disclosure and gladly credit reporters in our release notes and GitHub Security Advisories unless anonymity is requested.

---

## Built-in Security Controls

`RubyToFaster` enforces multiple supply-chain and build-time defenses by default (`strict_security = true`):

### 1. Path Traversal & Tar-Slip Protection
Every file path resolved from `.gemspec`, `include_files`, or frontend output directories (`Vite`, `Next.js`, `Angular`) passes through `RubyToFaster::FileResolver#sanitize_relative_path!`. Paths containing `..` segments, leading slashes (`/`), or NUL bytes (`\0`), or paths resolving outside `root_dir`, immediately abort the build with `RubyToFaster::SecurityError`.

### 2. Symlink Escape Prevention
- Symlinks inside source directories are canonicalized via `File.realpath` and verified to remain strictly inside the canonical project root; dangling or escaping symlinks raise `RubyToFaster::SecurityError`.
- Symlinks inside compiled frontend build directories (`dist/`, `.next/`, `out/`) are unconditionally rejected to prevent compromised npm postinstall scripts from symlinking host files into published `.gem` archives.

### 3. Shell-Injection-Free Subprocess Execution
When invoking frontend bundlers (`vite`, `next`, `ng`) or native extension toolchains (`ruby extconf.rb`, `make`), `RubyToFaster` exclusively passes argument arrays directly to `Open3.capture3(env, *argv, chdir: ...)` without invoking `/bin/sh -c`. Passing raw shell command strings to `build_command:` is explicitly rejected with `RubyToFaster::ConfigError`.

### 4. Automatic Secret & Credential Tree-Shaking
To prevent accidental credential publication to RubyGems.org, `RubyToFaster` automatically prunes and blocks common sensitive files from entering `data.tar.gz`, including:
- Environment files (`.env`, `.env.local`, `.env.production`, etc.)
- Private keys and certificates (`*.pem`, `*.key`, `*.p12`, `id_rsa`, `id_ed25519`)
- Encrypted Rails/app credentials (`credentials.yml.enc`)
- Dependency and bundler caches (`node_modules/`, `.next/cache/`, `.angular/cache/`, `.rtf-cache/`)

### 5. Deterministic Builds & Cryptographic Checksums
- Every `.gem` produced by `RubyToFaster::Packager` embeds both **SHA-256** and **SHA-512** digests for `metadata.gz` and `data.tar.gz` inside `checksums.yaml.gz`, verifiable via `rtf inspect <file.gem>` or `Gem::Package.new(path).verify`.
- Reproducible mode (`reproducible = true`, honoring `SOURCE_DATE_EPOCH`) normalizes tar entry ordering, POSIX file modes (`0644` / `0755`), and gzip `mtime` headers so independent parties can reproduce bit-for-bit identical SHA-256 package hashes from source.
- `rubygems_mfa_required` is enabled in `rubytofaster.gemspec`.

---

## Security Best Practices for Users

- **Inspect before publishing:** Run `rtf inspect pkg/<your_gem>-<version>.gem` in CI before running `gem push` to audit exact packaged file paths, modes, and embedded frontend manifests.
- **Pin frontend lockfiles:** Commit `package-lock.json`, `pnpm-lock.yaml`, or `yarn.lock` and use `npm ci` / `pnpm install --frozen-lockfile` in CI before running `rtf build`.
- **Keep source maps private unless intended:** By default, `RubyToFaster` excludes `.map` source maps when staging Vite, Next.js, and Angular production assets so proprietary TypeScript/JSX sources are not inadvertently shipped inside public gems.
