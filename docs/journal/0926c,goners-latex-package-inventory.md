# 0926c — LaTeX packages used by `workspace/goners`

Inventory made 2026-09-26 against the current TeX Live 2026 tree and the
declared setup in `.devcontainer/install-packages.sh` (lean base) and
`.devcontainer/install-optional.sh` (optional collections). I checked package
loads in `Latex/goners.tex`, `Latex/iaw.sty`, and its `iaw/*.sty` modules, plus
the enabled package switches in `dev/journal/0702a,overleaf-response.lyx`.
Presence means `kpsewhich <name>.sty` finds a file; I also checked the four
absent names with `tlmgr info --only-installed`.

## Missing from the current TeX tree at inventory time

| Package name | Referenced by | When needed |
| --- | --- | --- |
| `luacolor` | `Latex/iaw.sty:46` | LuaLaTeX branch of `iaw`; the project's `build.sh` uses pdfLaTeX, so its regular build does not load this branch. |
| `lua-ul` | `Latex/iaw.sty:47` | Same LuaLaTeX branch, for highlighting and underlining. |
| `mathdots` | `dev/journal/0702a,overleaf-response.lyx:42` | Enabled in the LyX document header; whether LyX emits a package load depends on its export. |
| `undertilde` | `dev/journal/0702a,overleaf-response.lyx:47` | Enabled in the same LyX header; export dependency likewise unconfirmed. |

`luacolor`, `lua-ul`, and `mathdots` were added to
`.devcontainer/install-optional.sh` after this inventory and were installed
by the user. `undertilde` was briefly added, then removed: CTAN lists it for
MiKTeX, but it is absent from TeX Live. The LyX file has no `undertilde`
command, so its enabled header switch is not known to require the package.
The first two are unused by the paper's current pdfLaTeX build. A headless
LyX export could not confirm the separate document's emitted preamble:
LyX exited before export because it could not create
`/home/node/.lyx/cache`.

## Present through the optional setup, absent from the lean base

These source loads and LyX header selections are supplied by collections named in
`.devcontainer/install-optional.sh`; the current tree has all five optional
collections installed. They would be missing from a base-only TeX tree.

| Optional collection | Referenced packages |
| --- | --- |
| `collection-latexextra` | `cancel`, `collcell`, `currfile`, `environ`, `esint`, `icomma` (TeX Live package `was`), `multirow`, `needspace`, `newunicodechar`, `xpatch`, `xstring`, `xurl` |
| `collection-fontsextra` | `andika`, `XCharter` (TeX Live package `xcharter`), `newtxmath` (TeX Live package `newtx`) |
| `collection-mathscience` | `mhchem`, `stmaryrd` (enabled in the LyX header) |

The other direct loads used by the paper or local styles resolve in the
current tree and do not require an addition beyond the existing base and
optional declarations. `iaw/*.sty` and `iaw.sty` are project-local files,
not TeX Live packages. The `iaw/beamer.sty` module and `iaw/preview.sty` are
conditional; their direct external loads (`fancyvrb`, `xpatch`, and `eso-pic`)
also resolve.

The inventory itself made no package installation. Three packages were later
added to the optional setup list; `undertilde` remains unavailable in TeX Live.
