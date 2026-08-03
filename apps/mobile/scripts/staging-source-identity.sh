#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
commit="$(git -C "$repo_root" rev-parse --short=8 HEAD)"
working_status="$(git -C "$repo_root" status --porcelain --untracked-files=all)"

if [[ -z "$working_status" ]]; then
  print -r -- "$commit"
  exit 0
fi

fingerprint="$({
  git -C "$repo_root" diff --binary HEAD -- .
  git -C "$repo_root" ls-files --others --exclude-standard | while IFS= read -r file; do
    [[ -f "$repo_root/$file" ]] && shasum -a 256 "$repo_root/$file"
  done
} | shasum -a 256 | awk '{print substr($1, 1, 8)}')"

print -r -- "${commit}-dirty.${fingerprint}"
