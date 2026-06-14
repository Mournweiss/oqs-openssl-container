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
IMAGE=""
TEST_ALL=false

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image)
                IMAGE="$2"
                shift 2
                ;;
            --all)
                TEST_ALL=true
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
    info "  --image IMAGE    Test specific image"
    info "  --all            Test all built images"
    info "  --help, -h       Show this help message"
}

# Check OpenSSL version
test_openssl_version() {
    local image="$1"
    info "  [1/5] Checking OpenSSL version..."

    local version
    version=$(docker run --rm "$image" openssl version 2>&1)
    info "    OpenSSL: $version"

    if [[ "$version" == *"3.5"* ]] || [[ "$version" == *"3.6"* ]] || [[ "$version" == *"4.0"* ]]; then
        success "    PASS: OpenSSL version is 3.x+"
    else
        warn "    WARN: Unexpected OpenSSL version"
    fi
}

# Check provider status
test_provider_status() {
    local image="$1"
    info "  [2/5] Checking provider status..."

    local status
    status=$(docker run --rm "$image" openssl list -providers 2>&1)
    echo "$status" | sed 's/^/    /'

    if echo "$status" | grep -q "default"; then
        success "    PASS: Default provider loaded"
    else
        warn "    WARN: Default provider not found"
    fi

    if echo "$status" | grep -q "oqsprovider"; then
        success "    PASS: OQS provider loaded"
    else
        warn "    WARN: OQS provider not found in status"
    fi
}

# List KEM algorithms
test_kem_algorithms() {
    local image="$1"
    info "  [3/5] Listing KEM algorithms..."

    local kem_algs
    kem_algs=$(docker run --rm "$image" openssl list -kem-algorithms -provider oqsprovider 2>&1) || true

    if [[ -n "$kem_algs" ]]; then
        echo "$kem_algs" | head -20 | sed 's/^/    /'
        local count
        count=$(echo "$kem_algs" | wc -l)
        info "    Total KEM algorithms: $count"
    else
        info "    (No KEM algorithms listed - OpenSSL >= 3.5.0 has native ML-KEM)"
    fi
}

# List signature algorithms
test_signature_algorithms() {
    local image="$1"
    info "  [4/5] Listing signature algorithms..."

    local sig_algs
    sig_algs=$(docker run --rm "$image" openssl list -signature-algorithms -provider oqsprovider 2>&1) || true

    if [[ -n "$sig_algs" ]]; then
        echo "$sig_algs" | head -20 | sed 's/^/    /'
        local count
        count=$(echo "$sig_algs" | wc -l)
        info "    Total signature algorithms: $count"
    else
        info "    (No signature algorithms listed - OpenSSL >= 3.5.0 has native ML-DSA/SLH-DSA)"
    fi
}

# Generate a test key
test_key_generation() {
    local image="$1"
    info "  [5/5] Testing key generation..."

    local result
    result=$(docker run --rm "$image" openssl genpkey -algorithm mldsa65 -out /tmp/test.key 2>&1) || true

    if [[ "$result" == *"Error"* ]] || [[ "$result" == *"error"* ]]; then
        warn "    WARN: Key generation failed: $result"
    else
        success "    PASS: Key generation successful"
    fi
}

# Run tests for a single image
test_image() {
    local image="$1"

    info ""
    info "Testing image: $image"

    # Check if image exists
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        warn "  SKIP: Image '$image' not found. Build it first."
        return 1
    fi

    test_openssl_version "$image"
    test_provider_status "$image"
    test_kem_algorithms "$image"
    test_signature_algorithms "$image"
    test_key_generation "$image"

    info ""
    info "Tests completed for: $image"
}

# Main entry point
main() {
    parse_args "$@"

    info "OQS-OpenSSL Container Test Suite"

    if $TEST_ALL; then
        test_image "oqs-openssl:alpine-latest" || true
        test_image "oqs-openssl:bookworm-latest" || true
    else
        if [[ -z "$IMAGE" ]]; then
            error "Please specify --image or --all"
        fi
        test_image "$IMAGE"
    fi

    info ""
    info "Test suite completed"
}

main "$@"
