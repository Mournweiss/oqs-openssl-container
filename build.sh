#!/usr/bin/env bash

set -euo pipefail

# ANSI color codes
COLOR_INFO="\033[0m"
COLOR_WARN="\033[1;33m"
COLOR_ERROR="\033[1;31m"
COLOR_SUCCESS="\033[1;32m"
COLOR_RESET="\033[0m"

# Logging functions
info()    { echo -e "${COLOR_INFO}$1${COLOR_RESET}" >&2; }
warn()    { echo -e "${COLOR_WARN}$1${COLOR_RESET}" >&2; }
error()   { echo -e "${COLOR_ERROR}$1${COLOR_RESET}" >&2; exit 1; }
success() { echo -e "${COLOR_SUCCESS}$1${COLOR_RESET}" >&2; }

# Default values
BASE="alpine"
TAG="oqs-openssl:latest"
CONTEXT_DIR="."
BUILD_ARGS=()
AUTO_TEST=true

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --base)
                BASE="$2"
                shift 2
                ;;
            --tag)
                TAG="$2"
                shift 2
                ;;
            --context)
                CONTEXT_DIR="$2"
                shift 2
                ;;
            --openssl-version)
                BUILD_ARGS+=("--build-arg" "OPENSSL_VERSION=$2")
                shift 2
                ;;
            --liboqs-version)
                BUILD_ARGS+=("--build-arg" "LIBOQS_VERSION=$2")
                shift 2
                ;;
            --oqs-provider-version)
                BUILD_ARGS+=("--build-arg" "OQS_PROVIDER_VERSION=$2")
                shift 2
                ;;
            --test)
                AUTO_TEST=true
                shift
                ;;
            --no-test)
                AUTO_TEST=false
                shift
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

# Print usage information
print_usage() {
    info "Usage: $0 [OPTIONS]"
    echo "" >&2
    info "Options:"
    info "  --base BASE                 Base OS: alpine, debian-bookworm, all (default: alpine)"
    info "  --tag TAG                   Image tag (default: oqs-openssl:latest)"
    info "  --context DIR               Build context directory (default: current directory)"
    info "  --openssl-version V         OpenSSL version (default: 3.5.7)"
    info "  --liboqs-version V          liboqs version (default: 0.15.0)"
    info "  --oqs-provider-version V    oqs-provider version (default: 0.11.0)"
    info "  --test, --auto-test         Enable auto-testing after build (default: enabled)"
    info "  --no-test, --no-auto-test   Disable auto-testing after build"
    info "  --help, -h                  Show this help message"
}

# Test a built Docker image
test_image() {
    local image="$1"
    info ""
    info "Running tests for: $image"

    if ! docker image inspect "$image" >/dev/null 2>&1; then
        warn "  Image '$image' not found, skipping tests"
        return 1
    fi

    if [[ ! -x "./scripts/test.sh" ]]; then
        warn "  test.sh not found or not executable, skipping tests"
        return 1
    fi

    if ./scripts/test.sh --image "$image" 2>&1; then
        success "  Tests passed for: $image"
        return 0
    else
        warn "  Tests failed for: $image"
        return 1
    fi
}

# Determine Containerfile path for a given base
get_containerfile() {
    local base="$1"
    case "$base" in
        alpine)
            echo "containerfiles/alpine/Containerfile"
            ;;
        debian-bookworm)
            echo "containerfiles/debian-bookworm/Containerfile"
            ;;
        *)
            error "Unknown base '$base'"
            ;;
    esac
}

# Validate that the Containerfile exists
validate_containerfile() {
    local containerfile="$1"

    if [[ ! -f "$CONTEXT_DIR/$containerfile" ]]; then
        error "Containerfile not found: $containerfile"
    fi
}

# Build a single Docker image
build_image() {
    local base="$1"
    local image_tag="$2"
    local containerfile

    containerfile="$(get_containerfile "$base")"
    validate_containerfile "$containerfile"

    info "Building OQS-OpenSSL image"
    info "  Base:          $base"
    info "  Tag:           $image_tag"
    info "  Containerfile: $containerfile"

    if ! docker build \
        -f "$CONTEXT_DIR/$containerfile" \
        -t "$image_tag" \
        "${BUILD_ARGS[@]}" \
        "$CONTEXT_DIR"; then
        error "Docker build failed for base: $base"
    fi

    success "Successfully built: $image_tag"

    # Run auto-tests if enabled
    if $AUTO_TEST; then
        if ! test_image "$image_tag"; then
            warn "  Auto-testing failed for: $image_tag"
        fi
    fi
}

# Main entry point
main() {
    parse_args "$@"

    info "Building oqs-openssl-container..."

    case "$BASE" in
        alpine)
            build_image "alpine" "$TAG"
            ;;
        debian-bookworm)
            build_image "debian-bookworm" "$TAG"
            ;;
        all)
            build_image "alpine" "${TAG}-alpine"
            build_image "debian-bookworm" "${TAG}-bookworm"
            ;;
        *)
            error "Unknown base '$BASE'. Use 'alpine', 'debian-bookworm', or 'all'."
            ;;
    esac

    success "Done"
}

main "$@"
