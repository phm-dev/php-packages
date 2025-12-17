#!/usr/bin/env bash
#
# Package creation utilities for PHM
# This file is sourced by other build scripts
#
# Package format: .tar.zst (zstandard compression)
# Compression level: 3 (good balance between speed and ratio)
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
    tar -cf - -C "${pkg_dir}" pkginfo.json files | zstd -${ZSTD_LEVEL} -o "${DIST_DIR}/${pkg_filename}"

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
    tar -cf - -C "${pkg_dir}" pkginfo.json files | zstd -${ZSTD_LEVEL} -o "${DIST_DIR}/${pkg_filename}"

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
    tar -cf - -C "${pkg_dir}" pkginfo.json files | zstd -${ZSTD_LEVEL} -o "${DIST_DIR}/${pkg_filename}"

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
