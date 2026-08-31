#!/usr/bin/env sh
set -eu

repository="${ALFREDO_GITHUB_REPOSITORY:-faustobdls/alfredo}"
install_dir="${ALFREDO_INSTALL_DIR:-${HOME}/.alfredo/bin}"

case "$(uname -s)" in
  Darwin) platform="macos" ;;
  Linux) platform="linux" ;;
  *)
    echo "Unsupported operating system. Use install.ps1 on Windows." >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  x86_64|amd64) architecture="x64" ;;
  arm64|aarch64) architecture="arm64" ;;
  *)
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

asset="alfredo-${platform}-${architecture}.tar.gz"
base_url="${ALFREDO_DOWNLOAD_BASE_URL:-https://github.com/${repository}/releases/latest/download}"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT HUP INT TERM

download() {
  source_url="$1"
  destination="$2"
  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --silent --show-error "$source_url" --output "$destination"
  elif command -v wget >/dev/null 2>&1; then
    wget --quiet "$source_url" --output-document "$destination"
  else
    echo "curl or wget is required." >&2
    exit 1
  fi
}

echo "Downloading ${asset}..."
download "${base_url}/${asset}" "${temporary_dir}/${asset}"
download "${base_url}/SHA256SUMS" "${temporary_dir}/SHA256SUMS"

expected_checksum="$(awk -v file="$asset" '$2 == file { print $1 }' "${temporary_dir}/SHA256SUMS")"
if [ -z "$expected_checksum" ]; then
  echo "No checksum found for ${asset}." >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  actual_checksum="$(sha256sum "${temporary_dir}/${asset}" | awk '{ print $1 }')"
else
  actual_checksum="$(shasum -a 256 "${temporary_dir}/${asset}" | awk '{ print $1 }')"
fi

if [ "$actual_checksum" != "$expected_checksum" ]; then
  echo "Checksum verification failed for ${asset}." >&2
  exit 1
fi

mkdir -p "$install_dir"
tar -xzf "${temporary_dir}/${asset}" -C "$temporary_dir"
install -m 0755 "${temporary_dir}/alfredo" "${install_dir}/alfredo"

shell_name="$(basename "${SHELL:-sh}")"
case "$shell_name" in
  zsh) profile="${ZDOTDIR:-$HOME}/.zshrc" ;;
  bash)
    if [ "$platform" = "macos" ]; then
      profile="$HOME/.bash_profile"
    else
      profile="$HOME/.bashrc"
    fi
    ;;
  fish) profile="$HOME/.config/fish/config.fish" ;;
  *) profile="$HOME/.profile" ;;
esac

if [ "$shell_name" = "fish" ]; then
  path_line="fish_add_path \"${install_dir}\""
else
  path_line="export PATH=\"${install_dir}:\$PATH\""
fi

mkdir -p "$(dirname "$profile")"
touch "$profile"
if ! grep -Fqx "$path_line" "$profile"; then
  {
    printf '\n# Alfredo CLI\n'
    printf '%s\n' "$path_line"
  } >> "$profile"
fi

echo "Alfredo installed at ${install_dir}/alfredo"
echo "PATH updated in ${profile}. Restart your shell or load that file to use alfredo."
