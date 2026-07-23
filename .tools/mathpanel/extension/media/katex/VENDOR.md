# Vendored KaTeX

- **Version:** 0.16.47 (exact pin; latest 0.16.x at acquisition)
- **Tarball URL:** https://registry.npmjs.org/katex/-/katex-0.16.47.tgz
- **npm integrity:** `sha512-Eeo8Ys1doU1z+x8AZsPpQu+p/QcZBI5PeOo7QGQdy2x2m0MU/hYagBbGOmXwr5KVbEfVuWv9LpnQWeehogurjg==`
  (verified byte-for-byte against the downloaded tarball via
  `openssl dgst -sha512 -binary | base64`)
- **SHA-256 of tarball:** `ad2d1ab2f7fcc227019784320e8a2c5218ff6bb333b36df4136d10365ae29375`
- **Acquired:** 2026-07-23 (New York)
- **Command:** `npm pack katex@0.16.47` (tarball download only; no lifecycle
  scripts run), then `tar xzf katex-0.16.47.tgz`
- **Files copied from the tarball:**
  - `package/dist/katex.min.js` → `katex.min.js`
  - `package/dist/katex.min.css` → `katex.min.css`
  - `package/LICENSE` → `LICENSE`
  - `package/dist/fonts/*` → `fonts/` (60 files; verified every font URL
    referenced in `katex.min.css` resolves to a vendored file)

On any later rebuild: download the same tarball URL, compare against the
SHA-256 above **before** extracting.
