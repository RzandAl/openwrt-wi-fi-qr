#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(dirname -- "$SCRIPT_DIR")"

. "$PROJECT_DIR/wi-fi-qr/files/usr/lib/wi-fi-qr/wi-fi-qr.sh"

fail() {
  printf '%s\n' "test-lan-url: $*" >&2
  exit 1
}

assert_equal() {
  expected="$1"
  actual="$2"

  [ "$actual" = "$expected" ] \
    || fail "expected '$expected', got '$actual'"
}

assert_equal 'http://192.168.1.1' \
  "$(wifi_qr_http_base_url '192.168.1.1/24')"
assert_equal 'http://192.168.1.1' \
  "$(wifi_qr_http_base_url '192.168.1.1')"
assert_equal '' "$(wifi_qr_http_base_url '')"

printf '%s\n' 'test-lan-url: ok'
