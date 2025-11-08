#!/usr/bin/env bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONFIG_DIR="${HOME}/.config/ghbin"
CONFIG_FILE="${CONFIG_DIR}/config"
DB_FILE="${CONFIG_DIR}/packages.db"
CACHE_DIR="${HOME}/.cache/ghbin"
INSTALL_DIR="${HOME}/.local/bin"
GITHUB_API="https://api.github.com"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$ARCH" in
x86_64 | amd64)
  ARCH_ALIASES="x86_64 amd64 x64"
  ;;
i386 | i686 | x86)
  ARCH_ALIASES="i386 i686 x86 386"
  ;;
aarch64 | arm64)
  ARCH_ALIASES="aarch64 arm64"
  ;;
armv7l | arm)
  ARCH_ALIASES="armv7l armv7 arm"
  ;;
*)
  ARCH_ALIASES="$ARCH"
  ;;
esac

print_error() {
  echo -e "${RED}Error: $1${NC}" >&2
}

print_success() {
  echo -e "${GREEN}$1${NC}"
}

print_info() {
  echo -e "${BLUE}$1${NC}"
}

print_warning() {
  echo -e "${YELLOW}$1${NC}"
}

confirm() {
  local prompt="$1"
  local response

  read -p "$prompt [Y/n]: " response
  case "$response" in
  [nN][oO] | [nN])
    return 1
    ;;
  *)
    return 0
    ;;
  esac
}

check_and_add_to_path() {
  local dir="$1"

  if [[ ":$PATH:" == *":$dir:"* ]]; then
    return 0
  fi

  local shell_config=""
  local shell_name=$(basename "$SHELL")

  case "$shell_name" in
  bash)
    if [[ -f "$HOME/.bashrc" ]]; then
      shell_config="$HOME/.bashrc"
    elif [[ -f "$HOME/.bash_profile" ]]; then
      shell_config="$HOME/.bash_profile"
    fi
    ;;
  zsh)
    if [[ -f "$HOME/.zshrc" ]]; then
      shell_config="$HOME/.zshrc"
    fi
    ;;
  *)
    if [[ -f "$HOME/.profile" ]]; then
      shell_config="$HOME/.profile"
    fi
    ;;
  esac

  if [[ -z "$shell_config" ]]; then
    print_warning "$dir is not in your PATH"
    print_info "Please add this line to your shell configuration file:"
    print_info "  export PATH=\"$dir:\$PATH\""
    return 0
  fi

  if grep -q "export PATH=\"$dir:\$PATH\"" "$shell_config" 2>/dev/null ||
    grep -q "export PATH=$dir:\$PATH" "$shell_config" 2>/dev/null ||
    grep -q "PATH=\"$dir:\$PATH\"" "$shell_config" 2>/dev/null; then
    print_warning "$dir is configured in $shell_config but not in current PATH"
    print_info "Please restart your shell or run: source $shell_config"
    return 0
  fi

  print_info "Adding $dir to PATH in $shell_config"

  echo "" >>"$shell_config"
  echo "# Added by ghbin" >>"$shell_config"
  echo "export PATH=\"$dir:\$PATH\"" >>"$shell_config"

  print_success "Added $dir to $shell_config"
  print_info "Please restart your shell or run: source $shell_config"
}

init_config() {
  mkdir -p "$CONFIG_DIR"
  mkdir -p "$CACHE_DIR"

  if [[ ! -f "$CONFIG_FILE" ]]; then
    cat >"$CONFIG_FILE" <<EOF
# ghbin configuration
# Default install directory
INSTALL_DIR=${HOME}/.local/bin
GITHUB_TOKEN=
EOF
  fi

  if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
  fi

  mkdir -p "$INSTALL_DIR"

  if [[ ! -f "$DB_FILE" ]]; then
    echo "# ghbin package database" >"$DB_FILE"
    echo "# Format: owner|repo|version|binaries|installed_at" >>"$DB_FILE"
  fi

  check_and_add_to_path "$INSTALL_DIR"
}

gh_api_request() {
  local endpoint="$1"
  local headers=""

  if [[ -n "$GITHUB_TOKEN" ]]; then
    headers="-H Authorization: token $GITHUB_TOKEN"
  fi

  curl -s $headers "${GITHUB_API}${endpoint}"
}

get_latest_release() {
  local owner="$1"
  local repo="$2"

  gh_api_request "/repos/${owner}/${repo}/releases/latest"
}

get_release_by_tag() {
  local owner="$1"
  local repo="$2"
  local tag="$3"

  gh_api_request "/repos/${owner}/${repo}/releases/tags/${tag}"
}

list_releases() {
  local owner="$1"
  local repo="$2"
  local limit="${3:-10}"

  gh_api_request "/repos/${owner}/${repo}/releases?per_page=${limit}"
}

get_repo_info() {
  local owner="$1"
  local repo="$2"

  gh_api_request "/repos/${owner}/${repo}"
}

select_asset() {
  local release_json="$1"
  local selected_asset=""
  local selected_url=""

  local assets=$(echo "$release_json" | jq -r '.assets[] | @json')

  if [[ -z "$assets" ]]; then
    return 1
  fi

  while IFS= read -r asset; do
    local name=$(echo "$asset" | jq -r '.name' | tr '[:upper:]' '[:lower:]')
    local url=$(echo "$asset" | jq -r '.browser_download_url')

    if [[ "$name" == *"$OS"* ]] || [[ "$name" == *"linux"* ]]; then
      for arch_alias in $ARCH_ALIASES; do
        if [[ "$name" == *"$arch_alias"* ]]; then
          selected_asset=$(echo "$asset" | jq -r '.name')
          selected_url="$url"
          echo "$selected_asset|$selected_url"
          return 0
        fi
      done
    fi
  done <<<"$assets"

  while IFS= read -r asset; do
    local name=$(echo "$asset" | jq -r '.name' | tr '[:upper:]' '[:lower:]')
    local url=$(echo "$asset" | jq -r '.browser_download_url')

    for arch_alias in $ARCH_ALIASES; do
      if [[ "$name" == *"$arch_alias"* ]]; then
        selected_asset=$(echo "$asset" | jq -r '.name')
        selected_url="$url"
        echo "$selected_asset|$selected_url"
        return 0
      fi
    done
  done <<<"$assets"

  if command -v fzf >/dev/null 2>&1; then
    selected_name=$(echo "$release_json" | jq -r '.assets[] | .name' | fzf --prompt="Select asset: ")
    if [[ -n "$selected_name" ]]; then
      selected_url=$(echo "$release_json" | jq -r ".assets[] | select(.name == \"$selected_name\") | .browser_download_url")
      echo "$selected_name|$selected_url"
      return 0
    fi
  else
    local assets_array=()
    local urls_array=()
    local sizes_array=()

    while IFS='|' read -r name url size; do
      assets_array+=("$name")
      urls_array+=("$url")
      sizes_array+=("$size")
    done < <(echo "$release_json" | jq -r '.assets[] | "\(.name)|\(.browser_download_url)|\(.size)"')

    if [[ ${#assets_array[@]} -eq 0 ]]; then
      return 1
    fi

    if [[ ${#assets_array[@]} -eq 1 ]]; then
      echo "${assets_array[0]}|${urls_array[0]}"
      return 0
    fi

    print_warning "Could not automatically detect suitable asset for ${OS}/${ARCH}"
    echo ""
    echo "Available assets:"
    echo ""

    local i
    for i in "${!assets_array[@]}"; do
      local idx=$((i + 1))
      printf "  %2d) %-50s (%s)\n" "$idx" "${assets_array[$i]}" "$(format_bytes ${sizes_array[$i]})"
    done

    echo ""

    local selection
    while true; do
      read -p "Select asset number (1-${#assets_array[@]}) or 'q' to quit: " selection

      if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
        return 1
      fi

      if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#assets_array[@]} ]]; then
        local idx=$((selection - 1))
        echo "${assets_array[$idx]}|${urls_array[$idx]}"
        return 0
      else
        print_error "Invalid selection. Please enter a number between 1 and ${#assets_array[@]}"
      fi
    done
  fi

  return 1
}

download_file() {
  local url="$1"
  local dest="$2"

  curl --progress-bar -L -o "$dest" "$url"
}

extract_archive() {
  local archive="$1"
  local dest_dir="$2"

  mkdir -p "$dest_dir"

  case "$archive" in
  *.tar.gz | *.tgz)
    tar -xzf "$archive" -C "$dest_dir"
    ;;
  *.tar.bz2)
    tar -xjf "$archive" -C "$dest_dir"
    ;;
  *.tar.xz)
    tar -xJf "$archive" -C "$dest_dir"
    ;;
  *.zip)
    unzip -q "$archive" -d "$dest_dir"
    ;;
  *.gz)
    gunzip -c "$archive" >"$dest_dir/$(basename "$archive" .gz)"
    ;;
  *)
    return 1
    ;;
  esac
}

is_archive() {
  local filename="$1"
  [[ "$filename" =~ \.(tar\.gz|tgz|tar\.bz2|tar\.xz|zip|gz)$ ]]
}

find_executables() {
  local dir="$1"
  find "$dir" -type f -executable 2>/dev/null || find "$dir" -type f -perm -u+x 2>/dev/null
}

clean_binary_name() {
  local name="$1"
  local repo="$2"

  name="${name%-linux-*}"
  name="${name%-darwin-*}"
  name="${name%-windows-*}"
  name="${name%_linux_*}"
  name="${name%_darwin_*}"
  name="${name%.linux-*}"
  name="${name%.exe}"
  name="${name%.bin}"

  if [[ -z "$name" || "$name" == "binary" ]]; then
    name="$repo"
  fi

  echo "$name"
}

format_bytes() {
  local bytes=$1
  if ((bytes < 1024)); then
    echo "${bytes}B"
  elif ((bytes < 1048576)); then
    echo "$(((bytes + 1023) / 1024))KB"
  elif ((bytes < 1073741824)); then
    echo "$(((bytes + 1048575) / 1048576))MB"
  else
    echo "$(((bytes + 1073741823) / 1073741824))GB"
  fi
}

db_add_package() {
  local owner="$1"
  local repo="$2"
  local version="$3"
  local binaries="$4"
  local timestamp=$(date +%s)

  db_remove_package "$owner" "$repo" 2>/dev/null || true

  echo "${owner}|${repo}|${version}|${binaries}|${timestamp}" >>"$DB_FILE"
}

db_get_package() {
  local owner="$1"
  local repo="$2"

  grep "^${owner}|${repo}|" "$DB_FILE" 2>/dev/null || true
}

db_remove_package() {
  local owner="$1"
  local repo="$2"

  if [[ -f "$DB_FILE" ]]; then
    sed -i.bak "/^${owner}|${repo}|/d" "$DB_FILE"
    rm -f "${DB_FILE}.bak"
  fi
}

db_list_packages() {
  grep -v "^#" "$DB_FILE" 2>/dev/null | grep -v "^$" || true
}

cmd_install() {
  local package_spec="$1"

  if [[ -z "$package_spec" ]]; then
    print_error "Package specification required: owner/repo[@version]"
    exit 1
  fi

  local owner repo version
  if [[ "$package_spec" =~ ^([^/]+)/([^@]+)(@(.+))?$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
    version="${BASH_REMATCH[4]}"
  else
    print_error "Invalid package format. Expected: owner/repo[@version]"
    exit 1
  fi

  if [[ ! -d "$INSTALL_DIR" ]]; then
    print_info "Creating install directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
  fi

  if [[ ! -w "$INSTALL_DIR" ]]; then
    print_error "Install directory not writable: $INSTALL_DIR"
    exit 1
  fi

  print_info "Installing ${owner}/${repo}$([ -n "$version" ] && echo "@$version")..."

  local release_json
  if [[ -n "$version" ]]; then
    release_json=$(get_release_by_tag "$owner" "$repo" "$version")
  else
    release_json=$(get_latest_release "$owner" "$repo")
  fi

  if [[ -z "$release_json" ]] || echo "$release_json" | jq -e '.message == "Not Found"' >/dev/null 2>&1; then
    print_error "Release not found for ${owner}/${repo}"
    exit 1
  fi

  local release_tag=$(echo "$release_json" | jq -r '.tag_name')
  print_info "Found release: $release_tag"

  local asset_info=$(select_asset "$release_json")

  if [[ -z "$asset_info" ]]; then
    print_warning "No suitable asset found"
    exit 1
  fi

  local asset_name="${asset_info%%|*}"
  local asset_url="${asset_info##*|}"
  local asset_size=$(echo "$release_json" | jq -r ".assets[] | select(.name == \"$asset_name\") | .size")

  print_info "Selected asset: $asset_name ($(format_bytes $asset_size))"

  if ! confirm "Proceed with installation?"; then
    print_warning "Installation cancelled"
    exit 0
  fi

  print_info "Downloading..."

  local work_dir="${CACHE_DIR}/install-$$"
  mkdir -p "$work_dir"
  trap "rm -rf '$work_dir'" EXIT

  local download_path="${work_dir}/${asset_name}"
  if ! download_file "$asset_url" "$download_path"; then
    print_error "Download failed"
    exit 1
  fi

  local installed_binaries=""

  if is_archive "$asset_name"; then
    print_info "Extracting archive..."
    local extract_dir="${work_dir}/extract"

    if ! extract_archive "$download_path" "$extract_dir"; then
      print_error "Extraction failed"
      exit 1
    fi

    local executables=$(find_executables "$extract_dir")
    local count=0

    if [[ -z "$executables" ]]; then
      print_error "No executable files found in archive"
      exit 1
    fi

    while IFS= read -r exe || [[ -n "$exe" ]]; do
      [[ -z "$exe" ]] && continue
      local binary_name=$(basename "$exe")
      binary_name=$(clean_binary_name "$binary_name" "$repo")
      local dest_path="${INSTALL_DIR}/${binary_name}"

      cp "$exe" "$dest_path"
      chmod +x "$dest_path"

      if [[ -n "$installed_binaries" ]]; then
        installed_binaries="${installed_binaries},"
      fi
      installed_binaries="${installed_binaries}${binary_name}"
      count=$((count + 1))
    done <<<"$executables"

    print_info "Installed $count binary(ies)"
  else
    print_info "Installing binary..."
    local binary_name=$(clean_binary_name "$asset_name" "$repo")
    local dest_path="${INSTALL_DIR}/${binary_name}"

    cp "$download_path" "$dest_path"
    chmod +x "$dest_path"

    installed_binaries="$binary_name"
  fi

  db_add_package "$owner" "$repo" "$release_tag" "$installed_binaries"

  print_success "Successfully installed ${owner}/${repo} (${release_tag})"
  print_info "  Installed to: $INSTALL_DIR"
  print_info "  Binaries: $installed_binaries"
}

cmd_list() {
  local packages=$(db_list_packages)

  if [[ -z "$packages" ]]; then
    echo "No packages installed."
    return
  fi

  printf "%-30s %-15s %-12s %s\n" "PACKAGE" "VERSION" "INSTALLED" "BINARIES"
  printf "%-30s %-15s %-12s %s\n" "-------" "-------" "---------" "--------"

  while IFS='|' read -r owner repo version binaries timestamp; do
    local package="${owner}/${repo}"
    local date=$(date -d "@${timestamp}" +%Y-%m-%d 2>/dev/null || date -r "${timestamp}" +%Y-%m-%d 2>/dev/null || echo "unknown")
    local binary_list="${binaries//,/ }"
    local first_binary="${binary_list%% *}"
    local binary_count=$(echo "$binary_list" | wc -w)

    if ((binary_count > 1)); then
      first_binary="${first_binary} (+$((binary_count - 1)) more)"
    fi

    printf "%-30s %-15s %-12s %s\n" "$package" "$version" "$date" "$first_binary"
  done <<<"$packages"
}

cmd_remove() {
  local package_spec="$1"

  if [[ -z "$package_spec" ]]; then
    print_error "Package specification required: owner/repo"
    exit 1
  fi

  local owner repo
  if [[ "$package_spec" =~ ^([^/]+)/([^@]+) ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
  else
    print_error "Invalid package format. Expected: owner/repo"
    exit 1
  fi

  local pkg_info=$(db_get_package "$owner" "$repo")

  if [[ -z "$pkg_info" ]]; then
    print_error "Package not found: ${owner}/${repo}"
    exit 1
  fi

  IFS='|' read -r _ _ version binaries _ <<<"$pkg_info"

  print_info "Removing ${owner}/${repo} (${version})..."

  IFS=',' read -ra BINARY_ARRAY <<<"$binaries"
  for binary in "${BINARY_ARRAY[@]}"; do
    local binary_path="${INSTALL_DIR}/${binary}"
    if [[ -f "$binary_path" ]]; then
      rm -f "$binary_path"
      print_info "  Removed: $binary_path"
    fi
  done

  db_remove_package "$owner" "$repo"

  print_success "Successfully removed ${owner}/${repo}"
}

cmd_update() {
  local package_spec="$1"

  if [[ -z "$package_spec" ]]; then
    print_error "Package specification required: owner/repo"
    exit 1
  fi

  local owner repo
  if [[ "$package_spec" =~ ^([^/]+)/([^@]+) ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
  else
    print_error "Invalid package format. Expected: owner/repo"
    exit 1
  fi

  local pkg_info=$(db_get_package "$owner" "$repo")

  if [[ -z "$pkg_info" ]]; then
    print_error "Package not found: ${owner}/${repo} (use 'install' instead)"
    exit 1
  fi

  IFS='|' read -r _ _ current_version _ _ <<<"$pkg_info"
  print_info "Current version: $current_version"
  print_info "Checking for updates..."

  local release_json=$(get_latest_release "$owner" "$repo")
  local latest_version=$(echo "$release_json" | jq -r '.tag_name')

  if [[ "$latest_version" == "$current_version" ]]; then
    print_success "Already up to date!"
    return
  fi

  print_info "New version available: $latest_version"
  print_info "Updating..."

  cmd_remove "${owner}/${repo}"

  cmd_install "${owner}/${repo}"

  print_success "Successfully updated ${owner}/${repo}: ${current_version} → ${latest_version}"
}

cmd_search() {
  local package_spec="$1"
  local limit="${2:-10}"

  if [[ -z "$package_spec" ]]; then
    print_error "Package specification required: owner/repo"
    exit 1
  fi

  local owner repo
  if [[ "$package_spec" =~ ^([^/]+)/([^@]+) ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
  else
    print_error "Invalid package format. Expected: owner/repo"
    exit 1
  fi

  print_info "Searching releases for ${owner}/${repo}...\n"

  local releases=$(list_releases "$owner" "$repo" "$limit")

  if [[ -z "$releases" ]] || echo "$releases" | jq -e 'length == 0' >/dev/null 2>&1; then
    echo "No releases found."
    return
  fi

  printf "%-20s %-30s %-12s %s\n" "TAG" "NAME" "PUBLISHED" "ASSETS"
  printf "%-20s %-30s %-12s %s\n" "---" "----" "---------" "------"

  echo "$releases" | jq -r '.[] | "\(.tag_name)|\(.name // "-")|\(.published_at)|\(.assets | length)"' | while IFS='|' read -r tag name published assets; do
    local date=$(echo "$published" | cut -d'T' -f1)
    printf "%-20s %-30s %-12s %s\n" "$tag" "${name:0:30}" "$date" "$assets"
  done
}

cmd_info() {
  local package_spec="$1"

  if [[ -z "$package_spec" ]]; then
    print_error "Package specification required: owner/repo"
    exit 1
  fi

  local owner repo
  if [[ "$package_spec" =~ ^([^/]+)/([^@]+) ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
  else
    print_error "Invalid package format. Expected: owner/repo"
    exit 1
  fi

  local repo_info=$(get_repo_info "$owner" "$repo")

  if [[ -z "$repo_info" ]] || echo "$repo_info" | jq -e '.message == "Not Found"' >/dev/null 2>&1; then
    print_error "Repository not found: ${owner}/${repo}"
    exit 1
  fi

  local description=$(echo "$repo_info" | jq -r '.description // "No description"')
  local stars=$(echo "$repo_info" | jq -r '.stargazers_count')
  local url=$(echo "$repo_info" | jq -r '.html_url')
  local language=$(echo "$repo_info" | jq -r '.language // "Unknown"')
  local license_name=$(echo "$repo_info" | jq -r '.license.name // "No license"')

  echo "Repository: ${owner}/${repo}"
  echo "Description: $description"
  echo "Stars: $stars"
  echo "URL: $url"
  echo "Language: $language"
  echo "License: $license_name"
  echo ""

  local release_json=$(get_latest_release "$owner" "$repo")
  if [[ -n "$release_json" ]] && ! echo "$release_json" | jq -e '.message == "Not Found"' >/dev/null 2>&1; then
    local tag=$(echo "$release_json" | jq -r '.tag_name')
    local published=$(echo "$release_json" | jq -r '.published_at' | cut -d'T' -f1)
    local asset_count=$(echo "$release_json" | jq -r '.assets | length')

    echo "Latest Release: $tag"
    echo "Published: $published"
    echo "Assets: $asset_count"
    echo ""
  fi

  local pkg_info=$(db_get_package "$owner" "$repo")
  if [[ -n "$pkg_info" ]]; then
    IFS='|' read -r _ _ version binaries timestamp <<<"$pkg_info"
    local date=$(date -d "@${timestamp}" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date -r "${timestamp}" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")

    echo "Installation Status: ✓ Installed"
    echo "  Version: $version"
    echo "  Installed: $date"
    echo "  Binaries: ${binaries//,/, }"
  else
    echo "Installation Status: Not installed"
  fi
}

cmd_help() {
  cat <<'EOF'
Usage:
    ghbin <command>

Commands:
    install <owner>/<repo>[@version]    Install a package from GitHub releases
    list                                List all installed packages
    remove <owner>/<repo>               Remove an installed package
    update <owner>/<repo>               Update a package to the latest version
    search <owner>/<repo> [limit]       Search for available releases
    info <owner>/<repo>                 Show detailed package information

For more information, visit: https://github.com/ayanrajpoot10/ghbin
EOF
}

main() {
  for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
      print_error "Required command not found: $cmd"
      print_info "Please install: $cmd"
      exit 1
    fi
  done

  init_config

  local command="${1:-help}"
  shift || true

  case "$command" in
  install)
    cmd_install "$@"
    ;;
  list | ls)
    cmd_list "$@"
    ;;
  remove | rm | uninstall)
    cmd_remove "$@"
    ;;
  update | upgrade)
    cmd_update "$@"
    ;;
  search)
    cmd_search "$@"
    ;;
  info)
    cmd_info "$@"
    ;;
  help | --help | -h)
    cmd_help
    ;;
  *)
    print_error "Unknown command: $command"
    echo "Run 'ghbin help' for usage information."
    exit 1
    ;;
  esac
}

main "$@"
