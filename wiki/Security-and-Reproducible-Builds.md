# Security & Reproducible Builds

Supply-chain integrity is a first-class design goal of `RubyToFaster`.

---

## Bit-for-Bit Reproducible `.gem` Archives

By default, `pkg.reproducible = true` is active:

1. **Deterministic Timestamps:** Honors the standard `SOURCE_DATE_EPOCH` environment variable (or `pkg.source_date_epoch = ...`). When unset, defaults to RubyGems' canonical deterministic epoch (`315619200` / `1980-01-02 00:00:00 UTC`).
2. **Sorted Tar Entries:** Regardless of filesystem directory traversal order or `spec.files` array ordering, `data.tar.gz` entries are sorted lexicographically by path.
3. **Normalized POSIX Modes:** Executable scripts in `spec.bindir` receive `0755`; all regular files receive `0644`; outer `.gem` tar components (`metadata.gz`, `data.tar.gz`, `checksums.yaml.gz`) receive `0444`.
4. **Deterministic Gzip Headers:** `Zlib::GzipWriter#mtime=` is pinned to the resolved epoch.

### Verifying Reproducibility in CI

```bash
SOURCE_DATE_EPOCH=1700000000 rtf build --no-cache -o pkg-a
SOURCE_DATE_EPOCH=1700000000 rtf build --no-cache -o pkg-b
sha256sum pkg-a/*.gem pkg-b/*.gem
# Both SHA-256 digests will match identically.
```

---

## Built-In Supply-Chain Protections

- **Tar-Slip & Path Traversal Prevention:** Relative paths containing `..`, leading `/`, or NUL bytes raise `RubyToFaster::SecurityError`.
- **Symlink Containment:** Source symlinks pointing outside the repository root—and *all* symlinks inside frontend build output directories (`dist/`, `.next/`, `out/`)—are blocked.
- **No Shell String Execution:** Custom `build_command:` arguments must be passed as an `Array` of strings (e.g., `["pnpm", "run", "build"]`) and are executed via `Open3.capture3(env, *argv)` without `/bin/sh`.
- **Automatic Credential Pruning:** `.env*`, `*.pem`, `*.key`, `*.p12`, `id_rsa`, `id_ed25519`, and `credentials.yml.enc` are excluded by default and rejected if forced under `strict_security = true`.

For vulnerability reporting procedures, see [SECURITY.md](https://github.com/HNMLabs/rubytofaster/blob/main/SECURITY.md).
