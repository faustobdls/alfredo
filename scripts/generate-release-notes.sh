#!/usr/bin/env bash
set -euo pipefail

previous_tag="${1:-}"
output="${2:-RELEASE_NOTES.md}"
range="HEAD"
if [[ -n "$previous_tag" ]]; then
  range="${previous_tag}..HEAD"
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

for section in breaking features fixes documentation chores other; do
  : > "$work_dir/$section"
done

while IFS= read -r subject; do
  [[ -n "$subject" ]] || continue
  entry="- $subject"
  case "$subject" in
    *"!: "*|BREAKING*) printf '%s\n' "$entry" >> "$work_dir/breaking" ;;
    feat:*|feat\(*\):*) printf '%s\n' "$entry" >> "$work_dir/features" ;;
    fix:*|fix\(*\):*) printf '%s\n' "$entry" >> "$work_dir/fixes" ;;
    docs:*|docs\(*\):*) printf '%s\n' "$entry" >> "$work_dir/documentation" ;;
    chore:*|chore\(*\):*|ci:*|ci\(*\):*|build:*|build\(*\):*)
      printf '%s\n' "$entry" >> "$work_dir/chores"
      ;;
    *) printf '%s\n' "$entry" >> "$work_dir/other" ;;
  esac
done < <(git log "$range" --no-merges --format='%s')

version="${GITHUB_REF_NAME:-Unreleased}"
compare_url=""
repository="${GITHUB_REPOSITORY:-}"
if [[ -n "$previous_tag" && -n "$repository" ]]; then
  compare_url="https://github.com/$repository/compare/$previous_tag...$version"
fi

{
  printf '# Alfredo %s\n\n' "$version"
  for item in \
    'breaking:Breaking changes' \
    'features:Features' \
    'fixes:Fixes' \
    'documentation:Documentation' \
    'chores:Maintenance' \
    'other:Other changes'; do
    file="${item%%:*}"
    title="${item#*:}"
    if [[ -s "$work_dir/$file" ]]; then
      printf '## %s\n\n' "$title"
      cat "$work_dir/$file"
      printf '\n'
    fi
  done
  if [[ -n "$compare_url" ]]; then
    printf '**Full changelog:** %s\n' "$compare_url"
  fi
} > "$output"

