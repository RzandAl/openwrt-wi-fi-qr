#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(dirname -- "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

fail() {
  printf '%s\n' "test-qrencode-stdin: $*" >&2
  exit 1
}

CORE="$PROJECT_DIR/wi-fi-qr/files/usr/lib/wi-fi-qr/wi-fi-qr.sh"
ARGS_FILE="$TMP_DIR/args"
PAYLOAD_FILE="$TMP_DIR/payload"

mkdir -p "$TMP_DIR/bin"

cat >"$TMP_DIR/bin/qrencode" <<'EOF'
#!/bin/sh

{
  printf 'argc=%s\n' "$#"
  for argument in "$@"; do
    printf 'arg=%s\n' "$argument"
  done
} >"$WIFI_QR_TEST_ARGS_FILE"

[ "$#" -eq 6 ] &&
  [ "$1" = '-m' ] && [ "$2" = '0' ] &&
  [ "$3" = '-t' ] && [ "$4" = 'SVG' ] &&
  [ "$5" = '-o' ] && [ "$6" = '-' ] || exit 64

cat >"$WIFI_QR_TEST_PAYLOAD_FILE"

printf '%s\n' \
  '<svg xmlns="http://www.w3.org/2000/svg" width="21" height="21" viewBox="0 0 21 21">' \
  '<path d="M0 0h1v1H0z"/>' \
  '</svg>'
EOF

cat >"$TMP_DIR/run-generation" <<'EOF'
#!/bin/bash

. "$WIFI_QR_TEST_CORE"
gen_wifi_qr_svg 'TestNet' 'super-secret' 'psk2' '5GHz'
EOF

chmod +x "$TMP_DIR/bin/qrencode" "$TMP_DIR/run-generation"

export WIFI_QR_TEST_CORE="$CORE"
export WIFI_QR_TEST_ARGS_FILE="$ARGS_FILE"
export WIFI_QR_TEST_PAYLOAD_FILE="$PAYLOAD_FILE"

set +e
PATH="$TMP_DIR/bin:$PATH" bash "$TMP_DIR/run-generation" >"$TMP_DIR/output"
status="$?"
set -e

if [ "$status" -ne 0 ]; then
  args="$(tr '\n' ' ' <"$ARGS_FILE" 2>/dev/null || :)"
  fail "generation failed with status $status; qrencode arguments: $args"
fi

expected_args='argc=6
arg=-m
arg=0
arg=-t
arg=SVG
arg=-o
arg=-'

[ "$(cat "$ARGS_FILE")" = "$expected_args" ] \
  || fail 'qrencode received an unexpected positional payload'

[ "$(cat "$PAYLOAD_FILE")" = \
    'WIFI:T:WPA;S:TestNet;P:super-secret;;' ] \
  || fail 'qrencode received an unexpected payload on stdin'

grep -q '<svg' "$TMP_DIR/output" \
  || fail 'generator did not return SVG output'

printf '%s\n' 'test-qrencode-stdin: ok'
