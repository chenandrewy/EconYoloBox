#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s FOLDER\n' "$(basename "$0")" >&2
  printf 'Sync .lyx and .tex pairs in FOLDER (newer wins) and (re)build .pdf.\n' >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

input_dir=$1

if [[ ! -d "$input_dir" ]]; then
  printf 'Error: not a directory: %s\n' "$input_dir" >&2
  exit 1
fi

for cmd in lyx tex2lyx; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'Error: %s is not installed or not on PATH.\n' "$cmd" >&2
    exit 1
  fi
done

mtime() {
  if [[ -f $1 ]]; then stat -c %Y "$1"; else printf 0; fi
}

declare -A seen
while IFS= read -r -d '' f; do
  case $f in
    *.lyx) base=${f%.lyx} ;;
    *.tex) base=${f%.tex} ;;
    *) continue ;;
  esac
  seen[$base]=1
done < <(find "$input_dir" -maxdepth 1 -type f \( -name '*.lyx' -o -name '*.tex' \) -print0)

if [[ ${#seen[@]} -eq 0 ]]; then
  printf 'No .lyx or .tex files found in %s\n' "$input_dir" >&2
  exit 0
fi

mapfile -t bases < <(printf '%s\n' "${!seen[@]}" | sort)
for base in "${bases[@]}"; do
  lyx_file=$base.lyx
  tex_file=$base.tex
  pdf_file=$base.pdf

  if [[ -f $lyx_file && ! -f $tex_file ]]; then
    printf '%s: lyx -> tex+pdf\n' "$base"
    lyx --export pdflatex "$lyx_file"
    lyx --export pdf2 "$lyx_file"
    touch -r "$lyx_file" "$tex_file"
  elif [[ -f $tex_file && ! -f $lyx_file ]]; then
    printf '%s: tex -> lyx, then pdf\n' "$base"
    tex2lyx -f "$tex_file" "$lyx_file"
    lyx --export pdf2 "$lyx_file"
    touch -r "$tex_file" "$lyx_file"
  else
    lyx_mt=$(mtime "$lyx_file")
    tex_mt=$(mtime "$tex_file")
    if (( lyx_mt > tex_mt )); then
      printf '%s: lyx newer -> tex+pdf\n' "$base"
      lyx --export pdflatex "$lyx_file"
      lyx --export pdf2 "$lyx_file"
      touch -r "$lyx_file" "$tex_file"
    elif (( tex_mt > lyx_mt )); then
      printf '%s: tex newer -> lyx, then pdf\n' "$base"
      tex2lyx -f "$tex_file" "$lyx_file"
      lyx --export pdf2 "$lyx_file"
      touch -r "$tex_file" "$lyx_file"
    else
      pdf_mt=$(mtime "$pdf_file")
      if (( pdf_mt < lyx_mt )); then
        printf '%s: in sync, rebuilding pdf\n' "$base"
        lyx --export pdf2 "$lyx_file"
      else
        printf '%s: up to date\n' "$base"
      fi
    fi
  fi
done
