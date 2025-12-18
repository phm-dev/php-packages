#!/usr/bin/env bash
#
# Package creation utilities for PHM
# This file is sourced by other build scripts
#
# Package format: .tar.zst (zstandard compression)
# Compression level: 3 (good balance between speed and ratio)
#
# NEW NAMING CONVENTION:
# - PHP core packages: php{VERSION}-{type}_{platform}.tar.zst
#   Example: php8.5.0-cli_darwin-arm64.tar.zst
# - Extension packages: php{PHP_VERSION}-{ext}{EXT_VERSION}_{platform}.tar.zst
#   Example: php8.5.0-redis6.3.0_darwin-arm64.tar.zst
#

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"
DIST_DIR="${DIST_DIR:-${PROJECT_ROOT}/dist}"

# Compression settings
ZSTD_LEVEL=3

# Ensure dist directory exists
mkdir -p "$DIST_DIR"

# Check for zstd
if ! command -v zstd &> /dev/null; then
    echo "[ERROR] zstd is required but not installed. Install with: brew install zstd"
    exit 1
fi

# =============================================================================
# NEW NAMING CONVENTION HELPERS
# =============================================================================

# Get PHP core package filename
# Usage: get_php_package_name <type> <php_version> <platform>
# Example: get_php_package_name cli 8.5.0 darwin-arm64 -> php8.5.0-cli_darwin-arm64.tar.zst
get_php_package_name() {
    local type="$1"       # cli, fpm, common, cgi, dev
    local php_version="$2" # 8.5.0
    local platform="$3"   # darwin-arm64

    echo "php${php_version}-${type}_${platform}.tar.zst"
}

# Get extension package filename
# Usage: get_extension_package_name <ext_name> <ext_version> <php_version> <platform>
# Example: get_extension_package_name redis 6.3.0 8.5.0 darwin-arm64 -> php8.5.0-redis6.3.0_darwin-arm64.tar.zst
get_extension_package_name() {
    local ext_name="$1"    # redis
    local ext_version="$2" # 6.3.0
    local php_version="$3" # 8.5.0
    local platform="$4"    # darwin-arm64

    echo "php${php_version}-${ext_name}${ext_version}_${platform}.tar.zst"
}

# Parse PHP version from new-style package name
# Usage: parse_php_version_from_package "php8.5.0-cli_darwin-arm64.tar.zst" -> 8.5.0
parse_php_version_from_package() {
    local filename="$1"
    if [[ "$filename" =~ ^php([0-9]+\.[0-9]+\.[0-9]+)- ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# Parse package type from new-style package name
# Usage: parse_type_from_package "php8.5.0-cli_darwin-arm64.tar.zst" -> cli
parse_type_from_package() {
    local filename="$1"
    if [[ "$filename" =~ ^php[0-9]+\.[0-9]+\.[0-9]+-([a-z]+)_ ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# Parse extension info from new-style package name
# Usage: parse_extension_from_package "php8.5.0-redis6.3.0_darwin-arm64.tar.zst"
# Returns: "redis 6.3.0"
parse_extension_from_package() {
    local filename="$1"
    if [[ "$filename" =~ ^php[0-9]+\.[0-9]+\.[0-9]+-([a-z]+)([0-9]+\.[0-9]+\.[0-9]+)_ ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    fi
}

# =============================================================================
# PACKAGE CREATION FUNCTIONS (V2 - NEW NAMING CONVENTION)
# =============================================================================

# Create PHP core package with new naming convention
# Usage: create_php_core_package <type> <php_version> <platform> <files...> [--description <desc>] [--depends <deps>]
# Example: create_php_core_package cli 8.5.0 darwin-arm64 <files...>
# Output: php8.5.0-cli_darwin-arm64.tar.zst
create_php_core_package() {
    local pkg_type="$1"      # cli, fpm, common, cgi, dev
    local php_version="$2"   # 8.5.0
    local platform="$3"      # darwin-arm64
    shift 3

    local description=""
    local depends=""
    local provides=""
    local files=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --description)
                description="$2"
                shift 2
                ;;
            --depends)
                depends="$2"
                shift 2
                ;;
            --provides)
                provides="$2"
                shift 2
                ;;
            *)
                files+=("$1")
                shift
                ;;
        esac
    done

    local pkg_filename="php${php_version}-${pkg_type}_${platform}.tar.zst"
    local pkg_name="php${php_version}-${pkg_type}"
    local pkg_dir="${DIST_DIR}/.pkg-${pkg_name}-$$"
    local php_major_minor="${php_version%.*}"

    echo "[PACKAGE] Creating ${pkg_filename}..."

    # Create package directory structure
    mkdir -p "${pkg_dir}/files"

    # Copy files to package
    local file_list=()
    for file in "${files[@]}"; do
        if [[ -e "$file" ]]; then
            local rel_path="${file#*staging}"
            rel_path="${rel_path#/}"

            local target_dir="${pkg_dir}/files/$(dirname "$rel_path")"
            mkdir -p "$target_dir"

            if [[ -d "$file" ]]; then
                cp -R "$file" "$target_dir/"
            else
                cp -P "$file" "$target_dir/"
            fi

            if [[ -d "$file" ]]; then
                while IFS= read -r -d '' f; do
                    local frel="${f#*staging}"
                    frel="${frel#/}"
                    file_list+=("$frel")
                done < <(find "$file" -type f -print0)
            else
                file_list+=("$rel_path")
            fi
        else
            echo "[WARN] File not found: $file"
        fi
    done

    # Calculate installed size
    local installed_size=0
    if [[ -d "${pkg_dir}/files" ]]; then
        installed_size=$(du -sk "${pkg_dir}/files" | cut -f1)
        installed_size=$((installed_size * 1024))
    fi

    # Build depends array
    local depends_json="[]"
    if [[ -n "$depends" ]]; then
        depends_json="["
        IFS=',' read -ra deps_array <<< "$depends"
        local first=true
        for dep in "${deps_array[@]}"; do
            dep="${dep## }"
            dep="${dep%% }"
            if [[ -n "$dep" ]]; then
                if [[ "$first" == true ]]; then
                    first=false
                else
                    depends_json+=","
                fi
                depends_json+="\"${dep}\""
            fi
        done
        depends_json+="]"
    fi

    # Build provides array
    local provides_json="[]"
    if [[ -n "$provides" ]]; then
        provides_json="["
        IFS=',' read -ra provides_array <<< "$provides"
        local first=true
        for prov in "${provides_array[@]}"; do
            prov="${prov## }"
            prov="${prov%% }"
            if [[ -n "$prov" ]]; then
                if [[ "$first" == true ]]; then
                    first=false
                else
                    provides_json+=","
                fi
                provides_json+="\"${prov}\""
            fi
        done
        provides_json+="]"
    fi

    # Build files array
    local files_json="["
    local first=true
    for f in "${file_list[@]}"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            files_json+=","
        fi
        files_json+="\"${f}\""
    done
    files_json+="]"

    # Create pkginfo.json
    cat > "${pkg_dir}/pkginfo.json" << EOF
{
  "name": "${pkg_name}",
  "version": "${php_version}",
  "php_version": "${php_major_minor}",
  "php_full_version": "${php_version}",
  "type": "${pkg_type}",
  "description": "${description}",
  "platform": "${platform}",
  "depends": ${depends_json},
  "conflicts": [],
  "provides": ${provides_json},
  "installed_size": ${installed_size},
  "maintainer": "PHM Team",
  "files": ${files_json}
}
EOF

    # Create tarball with zstd compression
    tar -cf - -C "${pkg_dir}" pkginfo.json files | zstd -${ZSTD_LEVEL} -f -o "${DIST_DIR}/${pkg_filename}"

    # Generate SHA256
    if command -v sha256sum &> /dev/null; then
        sha256sum "${DIST_DIR}/${pkg_filename}" | cut -d' ' -f1 > "${DIST_DIR}/${pkg_filename}.sha256"
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "${DIST_DIR}/${pkg_filename}" | cut -d' ' -f1 > "${DIST_DIR}/${pkg_filename}.sha256"
    fi

    # Cleanup
    rm -rf "${pkg_dir}"

    echo "[PACKAGE] Created: ${pkg_filename} ($(du -h "${DIST_DIR}/${pkg_filename}" | cut -f1))"
}

# Create extension package with new naming convention
# Usage: create_extension_package_v2 <ext_name> <ext_version> <php_version> <platform> <so_file> [options...]
# Example: create_extension_package_v2 redis 6.3.0 8.5.0 darwin-arm64 /path/to/redis.so
# Output: php8.5.0-redis6.3.0_darwin-arm64.tar.zst
create_extension_package_v2() {
    local ext_name="$1"
    local ext_version="$2"
    local php_version="$3"
    local platform="$4"
    local so_file="$5"
    shift 5

    local description=""
    local depends=""
    local load_priority="20"
    local is_zend_extension="false"
    local ext_dir_name=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --description)
                description="$2"
                shift 2
                ;;
            --depends)
                depends="$2"
                shift 2
                ;;
            --priority)
                load_priority="$2"
                shift 2
                ;;
            --zend)
                is_zend_extension="true"
                shift
                ;;
            --ext-dir)
                ext_dir_name="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    local php_major_minor="${php_version%.*}"
    local pkg_name="php${php_version}-${ext_name}${ext_version}"
    local pkg_filename="${pkg_name}_${platform}.tar.zst"
    local pkg_dir="${DIST_DIR}/.pkg-${ext_name}-$$"

    echo "[EXTENSION] Creating ${pkg_filename}..."

    mkdir -p "${pkg_dir}/files/opt/php/${php_major_minor}/lib/php/extensions"
    mkdir -p "${pkg_dir}/files/opt/php/${php_major_minor}/etc/conf.d"

    # Find the extension directory name if not provided
    if [[ -z "$ext_dir_name" ]]; then
        if [[ -d "/opt/php/${php_major_minor}/lib/php/extensions" ]]; then
            ext_dir_name=$(ls "/opt/php/${php_major_minor}/lib/php/extensions" 2>/dev/null | head -1)
        fi
        if [[ -z "$ext_dir_name" ]]; then
            ext_dir_name="no-debug-non-zts-$(date +%Y%m%d)"
        fi
    fi

    mkdir -p "${pkg_dir}/files/opt/php/${php_major_minor}/lib/php/extensions/${ext_dir_name}"

    # Copy .so file
    cp "$so_file" "${pkg_dir}/files/opt/php/${php_major_minor}/lib/php/extensions/${ext_dir_name}/${ext_name}.so"

    # Create ini file
    local ini_file="${pkg_dir}/files/opt/php/${php_major_minor}/etc/conf.d/${load_priority}-${ext_name}.ini"
    if [[ "$is_zend_extension" == "true" ]]; then
        echo "zend_extension=${ext_name}.so" > "$ini_file"
    else
        echo "extension=${ext_name}.so" > "$ini_file"
    fi

    # Calculate installed size
    local installed_size
    installed_size=$(du -sk "${pkg_dir}/files" | cut -f1)
    installed_size=$((installed_size * 1024))

    # Build depends array - use full PHP version in dependency
    local base_depends="php${php_version}-common"
    if [[ -n "$depends" ]]; then
        depends="${base_depends}, ${depends}"
    else
        depends="$base_depends"
    fi

    local depends_json="["
    IFS=',' read -ra deps_array <<< "$depends"
    local first=true
    for dep in "${deps_array[@]}"; do
        dep="${dep## }"
        dep="${dep%% }"
        if [[ -n "$dep" ]]; then
            if [[ "$first" == true ]]; then
                first=false
            else
                depends_json+=","
            fi
            depends_json+="\"${dep}\""
        fi
    done
    depends_json+="]"

    # Create pkginfo.json
    cat > "${pkg_dir}/pkginfo.json" << EOF
{
  "name": "${pkg_name}",
  "version": "${ext_version}",
  "php_version": "${php_major_minor}",
  "php_full_version": "${php_version}",
  "description": "${description}",
  "platform": "${platform}",
  "depends": ${depends_json},
  "conflicts": [],
  "provides": ["php-${ext_name}"],
  "installed_size": ${installed_size},
  "maintainer": "PHM Team",
  "extension": {
    "name": "${ext_name}",
    "version": "${ext_version}",
    "zend": ${is_zend_extension},
    "priority": ${load_priority}
  },
  "files": [
    "opt/php/${php_major_minor}/lib/php/extensions/${ext_dir_name}/${ext_name}.so",
    "opt/php/${php_major_minor}/etc/conf.d/${load_priority}-${ext_name}.ini"
  ]
}
EOF

    # Create tarball with zstd compression
    tar -cf - -C "${pkg_dir}" pkginfo.json files | zstd -${ZSTD_LEVEL} -f -o "${DIST_DIR}/${pkg_filename}"

    # Generate SHA256
    if command -v sha256sum &> /dev/null; then
        sha256sum "${DIST_DIR}/${pkg_filename}" | cut -d' ' -f1 > "${DIST_DIR}/${pkg_filename}.sha256"
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "${DIST_DIR}/${pkg_filename}" | cut -d' ' -f1 > "${DIST_DIR}/${pkg_filename}.sha256"
    fi

    # Cleanup
    rm -rf "${pkg_dir}"

    echo "[EXTENSION] Created: ${pkg_filename} ($(du -h "${DIST_DIR}/${pkg_filename}" | cut -f1))"
}

# =============================================================================
# LEGACY PACKAGE CREATION FUNCTIONS (for backward compatibility)
# =============================================================================

# Create a package from files
# Usage: create_package <name> <version> <revision> <platform> <files...> [--description <desc>] [--depends <deps>] [--provides <provides>]
create_package() {
    local name="$1"
    local version="$2"
    local revision="$3"
    local platform="$4"
    shift 4

    local description=""
    local depends=""
    local provides=""
    local conflicts=""
    local files=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --description)
                description="$2"
                shift 2
                ;;
            --depends)
                depends="$2"
                shift 2
                ;;
            --provides)
                provides="$2"
                shift 2
                ;;
            --conflicts)
                conflicts="$2"
                shift 2
                ;;
            *)
                files+=("$1")
                shift
                ;;
        esac
    done

    local pkg_filename="${name}_${version}-${revision}_${platform}.tar.zst"
    local pkg_dir="${DIST_DIR}/.pkg-${name}-$$"

    echo "[PACKAGE] Creating ${pkg_filename}..."

    # Create package directory structure
    mkdir -p "${pkg_dir}/files"

    # Copy files to package
    local file_list=()
    for file in "${files[@]}"; do
        if [[ -e "$file" ]]; then
            # Determine relative path (strip staging dir prefix)
            local rel_path="${file#*staging}"
            rel_path="${rel_path#/}"

            # Create target directory
            local target_dir="${pkg_dir}/files/$(dirname "$rel_path")"
            mkdir -p "$target_dir"

            # Copy file or directory
            if [[ -d "$file" ]]; then
                cp -R "$file" "$target_dir/"
            else
                cp -P "$file" "$target_dir/"
            fi

            # Track files
            if [[ -d "$file" ]]; then
                while IFS= read -r -d '' f; do
                    local frel="${f#*staging}"
                    frel="${frel#/}"
                    file_list+=("$frel")
                done < <(find "$file" -type f -print0)
            else
                file_list+=("$rel_path")
            fi
        else
            echo "[WARN] File not found: $file"
        fi
    done

    # Calculate installed size
    local installed_size=0
    if [[ -d "${pkg_dir}/files" ]]; then
        installed_size=$(du -sk "${pkg_dir}/files" | cut -f1)
        installed_size=$((installed_size * 1024))
    fi

    # Extract PHP version from package name (e.g., php8.5-cli -> 8.5)
    local php_version=""
    if [[ "$name" =~ ^php([0-9]+\.[0-9]+) ]]; then
        php_version="${BASH_REMATCH[1]}"
    fi

    # Build depends array
    local depends_json="[]"
    if [[ -n "$depends" ]]; then
        depends_json="["
        IFS=',' read -ra deps_array <<< "$depends"
        local first=true
        for dep in "${deps_array[@]}"; do
            dep="${dep## }"  # trim leading space
            dep="${dep%% }"  # trim trailing space
            if [[ -n "$dep" ]]; then
                if [[ "$first" == true ]]; then
                    first=false
                else
                    depends_json+=","
                fi
                depends_json+="\"${dep}\""
            fi
        done
        depends_json+="]"
    fi

    # Build provides array
    local provides_json="[]"
    if [[ -n "$provides" ]]; then
        provides_json="["
        IFS=',' read -ra provides_array <<< "$provides"
        local first=true
        for prov in "${provides_array[@]}"; do
            prov="${prov## }"
            prov="${prov%% }"
            if [[ -n "$prov" ]]; then
                if [[ "$first" == true ]]; then
                    first=false
                else
                    provides_json+=","
                fi
                provides_json+="\"${prov}\""
            fi
        done
        provides_json+="]"
    fi

    # Build files array
    local files_json="["
    local first=true
    for f in "${file_list[@]}"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            files_json+=","
        fi
        files_json+="\"${f}\""
    done
    files_json+="]"

    # Create pkginfo.json
    cat > "${pkg_dir}/pkginfo.json" << EOF
{
  "name": "${name}",
  "version": "${version}",
  "revision": ${revision},
  "php_version": "${php_version}",
  "description": "${description}",
  "platform": "${platform}",
  "depends": ${depends_json},
  "conflicts": [],
  "provides": ${provides_json},
  "installed_size": ${installed_size},
  "maintainer": "PHM Team",
  "files": ${files_json}
}
EOF

    # Create tarball with zstd compression
    tar -cf - -C "${pkg_dir}" pkginfo.json files | zstd -${ZSTD_LEVEL} -f -o "${DIST_DIR}/${pkg_filename}"

    # Generate SHA256
    if command -v sha256sum &> /dev/null; then
        sha256sum "${DIST_DIR}/${pkg_filename}" | cut -d' ' -f1 > "${DIST_DIR}/${pkg_filename}.sha256"
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "${DIST_DIR}/${pkg_filename}" | cut -d' ' -f1 > "${DIST_DIR}/${pkg_filename}.sha256"
    fi

    # Cleanup
    rm -rf "${pkg_dir}"

    echo "[PACKAGE] Created: ${pkg_filename} ($(du -h "${DIST_DIR}/${pkg_filename}" | cut -f1))"
}

# Create a meta-package (no files, just dependencies)
# Usage: create_meta_package <name> <version> <revision> <platform> [--description <desc>] [--depends <deps>] [--provides <provides>]
create_meta_package() {
    local name="$1"
    local version="$2"
    local revision="$3"
    local platform="$4"
    shift 4

    local description=""
    local depends=""
    local provides=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --description)
                description="$2"
                shift 2
                ;;
            --depends)
                depends="$2"
                shift 2
                ;;
            --provides)
                provides="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    local pkg_filename="${name}_${version}-${revision}_${platform}.tar.zst"
    local pkg_dir="${DIST_DIR}/.pkg-${name}-$$"

    echo "[META-PACKAGE] Creating ${pkg_filename}..."

    mkdir -p "${pkg_dir}/files"

    # Extract PHP version from package name
    local php_version=""
    if [[ "$name" =~ ^php([0-9]+\.[0-9]+) ]]; then
        php_version="${BASH_REMATCH[1]}"
    fi

    # Build depends array
    local depends_json="[]"
    if [[ -n "$depends" ]]; then
        depends_json="["
        IFS=',' read -ra deps_array <<< "$depends"
        local first=true
        for dep in "${deps_array[@]}"; do
            dep="${dep## }"
            dep="${dep%% }"
            if [[ -n "$dep" ]]; then
                if [[ "$first" == true ]]; then
                    first=false
                else
                    depends_json+=","
                fi
                depends_json+="\"${dep}\""
            fi
        done
        depends_json+="]"
    fi

    # Build provides array
    local provides_json="[]"
    if [[ -n "$provides" ]]; then
        provides_json="["
        IFS=',' read -ra provides_array <<< "$provides"
        local first=true
        for prov in "${provides_array[@]}"; do
            prov="${prov## }"
            prov="${prov%% }"
            if [[ -n "$prov" ]]; then
                if [[ "$first" == true ]]; then
                    first=false
                else
                    provides_json+=","
                fi
                provides_json+="\"${prov}\""
            fi
        done
        provides_json+="]"
    fi

    # Create pkginfo.json
    cat > "${pkg_dir}/pkginfo.json" << EOF
{
  "name": "${name}",
  "version": "${version}",
  "revision": ${revision},
  "php_version": "${php_version}",
  "description": "${description}",
  "platform": "${platform}",
  "depends": ${depends_json},
  "conflicts": [],
  "provides": ${provides_json},
  "installed_size": 0,
  "maintainer": "PHM Team",
  "meta": true,
  "files": []
}
EOF

    # Create tarball with zstd compression
    tar -cf - -C "${pkg_dir}" pkginfo.json files | zstd -${ZSTD_LEVEL} -f -o "${DIST_DIR}/${pkg_filename}"

    # Generate SHA256
    if command -v sha256sum &> /dev/null; then
        sha256sum "${DIST_DIR}/${pkg_filename}" | cut -d' ' -f1 > "${DIST_DIR}/${pkg_filename}.sha256"
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "${DIST_DIR}/${pkg_filename}" | cut -d' ' -f1 > "${DIST_DIR}/${pkg_filename}.sha256"
    fi

    # Cleanup
    rm -rf "${pkg_dir}"

    echo "[META-PACKAGE] Created: ${pkg_filename}"
}

# Create extension package from .so file
# Usage: create_extension_package <ext_name> <ext_version> <php_version> <revision> <platform> <so_file> [--description <desc>] [--depends <deps>]
create_extension_package() {
    local ext_name="$1"
    local ext_version="$2"
    local php_version="$3"
    local revision="$4"
    local platform="$5"
    local so_file="$6"
    shift 6

    local description=""
    local depends=""
    local load_priority="20"
    local is_zend_extension="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --description)
                description="$2"
                shift 2
                ;;
            --depends)
                depends="$2"
                shift 2
                ;;
            --priority)
                load_priority="$2"
                shift 2
                ;;
            --zend)
                is_zend_extension="true"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    local php_major_minor="${php_version%.*}"
    local pkg_name="php${php_major_minor}-${ext_name}"
    local pkg_filename="${pkg_name}_${ext_version}-${revision}_${platform}.tar.zst"
    local pkg_dir="${DIST_DIR}/.pkg-${pkg_name}-$$"

    echo "[EXTENSION] Creating ${pkg_filename}..."

    mkdir -p "${pkg_dir}/files/opt/php/${php_major_minor}/lib/php/extensions"
    mkdir -p "${pkg_dir}/files/opt/php/${php_major_minor}/etc/conf.d"

    # Find the extension directory name
    local ext_dir_name
    if [[ -d "/opt/php/${php_major_minor}/lib/php/extensions" ]]; then
        ext_dir_name=$(ls "/opt/php/${php_major_minor}/lib/php/extensions" | head -1)
    else
        # Fallback: try to determine from PHP version
        ext_dir_name="no-debug-non-zts-$(date +%Y%m%d)"
    fi

    mkdir -p "${pkg_dir}/files/opt/php/${php_major_minor}/lib/php/extensions/${ext_dir_name}"

    # Copy .so file
    cp "$so_file" "${pkg_dir}/files/opt/php/${php_major_minor}/lib/php/extensions/${ext_dir_name}/${ext_name}.so"

    # Create ini file
    local ini_file="${pkg_dir}/files/opt/php/${php_major_minor}/etc/conf.d/${load_priority}-${ext_name}.ini"
    if [[ "$is_zend_extension" == "true" ]]; then
        echo "zend_extension=${ext_name}.so" > "$ini_file"
    else
        echo "extension=${ext_name}.so" > "$ini_file"
    fi

    # Calculate installed size
    local installed_size
    installed_size=$(du -sk "${pkg_dir}/files" | cut -f1)
    installed_size=$((installed_size * 1024))

    # Build depends array
    local base_depends="php${php_major_minor}-common (>= ${php_version})"
    if [[ -n "$depends" ]]; then
        depends="${base_depends}, ${depends}"
    else
        depends="$base_depends"
    fi

    local depends_json="["
    IFS=',' read -ra deps_array <<< "$depends"
    local first=true
    for dep in "${deps_array[@]}"; do
        dep="${dep## }"
        dep="${dep%% }"
        if [[ -n "$dep" ]]; then
            if [[ "$first" == true ]]; then
                first=false
            else
                depends_json+=","
            fi
            depends_json+="\"${dep}\""
        fi
    done
    depends_json+="]"

    # Create pkginfo.json
    cat > "${pkg_dir}/pkginfo.json" << EOF
{
  "name": "${pkg_name}",
  "version": "${ext_version}",
  "revision": ${revision},
  "php_version": "${php_major_minor}",
  "description": "${description}",
  "platform": "${platform}",
  "depends": ${depends_json},
  "conflicts": [],
  "provides": ["php-${ext_name}"],
  "installed_size": ${installed_size},
  "maintainer": "PHM Team",
  "extension": {
    "name": "${ext_name}",
    "zend": ${is_zend_extension},
    "priority": ${load_priority}
  },
  "files": [
    "opt/php/${php_major_minor}/lib/php/extensions/${ext_dir_name}/${ext_name}.so",
    "opt/php/${php_major_minor}/etc/conf.d/${load_priority}-${ext_name}.ini"
  ]
}
EOF

    # Create tarball with zstd compression
    tar -cf - -C "${pkg_dir}" pkginfo.json files | zstd -${ZSTD_LEVEL} -f -o "${DIST_DIR}/${pkg_filename}"

    # Generate SHA256
    if command -v sha256sum &> /dev/null; then
        sha256sum "${DIST_DIR}/${pkg_filename}" | cut -d' ' -f1 > "${DIST_DIR}/${pkg_filename}.sha256"
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "${DIST_DIR}/${pkg_filename}" | cut -d' ' -f1 > "${DIST_DIR}/${pkg_filename}.sha256"
    fi

    # Cleanup
    rm -rf "${pkg_dir}"

    echo "[EXTENSION] Created: ${pkg_filename} ($(du -h "${DIST_DIR}/${pkg_filename}" | cut -d' ' -f1))"
}
