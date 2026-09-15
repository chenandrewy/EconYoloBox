# LyX conversion failed when the user configuration was missing

Date: 2026-09-10 (NY)

While creating a LyX journal note in `Live,AI-Contracts`, `tex2lyx` failed on
an otherwise ordinary article import. LyX itself and TeX Live were installed,
but `/home/node/.lyx` did not exist.

## Symptoms

The initial command was:

```sh
tex2lyx -f source.tex output.lyx
```

It reported:

```text
tex2lyx error: User directory does not exist.
unable to find textclass file `textclass.lst'
no textclasses found
unable to find modules file `lyxmodules.lst'
Could not read layout file for textclass "article".
```

Despite those errors, `tex2lyx` announced that it was creating the output
file. The resulting `.lyx` file was empty. A caller therefore must not treat
the creation message or mere existence of the output path as success; the
output should be nonempty and subsequently exported by LyX.

The system LyX resources were present under `/usr/local/share/lyx`, including
the layouts and `configure.py`. The generated indexes `textclass.lst` and
`lyxmodules.lst`, however, are expected in a configured user directory and
were absent.

`/usr/local/bin/tex-refresh` also existed, but in this running container it had
mode `711` (`-rwx--x--x`, owned by root). Invoking it as `node` returned
`Permission denied`; reading the script as `node` failed as well. No change to
that file or to the devcontainer configuration was made during this incident.

## Temporary recovery used

For this one conversion and its validation, a disposable user directory was
created under `/tmp`, then populated using LyX's own reconfiguration command:

```sh
lyx_user_dir=$(mktemp -d /tmp/lyx-user.XXXXXX)
QT_QPA_PLATFORM=offscreen \
  lyx -batch -userdir "$lyx_user_dir" -x reconfigure

tex2lyx -userdir "$lyx_user_dir" -f source.tex output.lyx
```

This generated `textclass.lst`, `lyxmodules.lst`, and the other normal LyX
configuration indexes in the temporary directory. The imported document was
then validated with the same `-userdir` value: LyX parsed and exported it, and
the exported LaTeX compiled successfully with `pdflatex`. No persistent user
configuration, package installation, or devcontainer change was made.

## Likely durable resolution

This may simply reflect an already-running container that had not gone through
the new TeX/LyX startup refresh described in
[0910a](0910a,texlive-volume-implemented.md). Reopening or rebuilding should
be tested before changing the setup.

If it also occurs in a fresh container, check the startup invocation and the
ownership/mode of `tex-refresh`. The durable behavior should be:

- startup can invoke `tex-refresh` successfully as `node`;
- a configured user directory supplies `textclass.lst` and `lyxmodules.lst`;
- `tex2lyx` can import a minimal `article` without an explicit temporary
  `-userdir`;
- validation rejects an empty conversion output and checks LyX's stderr for
  structural errors.

The `/tmp` user-directory method is a safe diagnostic and one-off recovery,
not the intended persistent configuration.
