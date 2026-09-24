#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(dirname -- "$SCRIPT_DIR")"

. "$PROJECT_DIR/wi-fi-qr/files/usr/lib/wi-fi-qr/wi-fi-qr.sh"

fail() {
  printf '%s\n' "test-svg-escaping: $*" >&2
  exit 1
}

assert_contains() {
  case "$output" in
    *"$1"*) ;;
    *) fail "missing expected fragment: $1" ;;
  esac
}

control_char="$(printf '\001')"
label="Cafe <Guest> & \"Friends\" 'Lab'$control_char"
band='5 & 6GHz'

output="$(
  printf '%s\n' \
    '<svg xmlns="http://www.w3.org/2000/svg" width="21" height="21" viewBox="0 0 21 21">' \
    '<path d="M0 0h1v1H0z"/>' \
    '</svg>' \
    | fix_svg_size 256 "$label" "$band"
)"

assert_contains 'Cafe &lt;Guest&gt; &amp; &quot;Friends&quot; &apos;Lab&apos;'
assert_contains '• 5 &amp; 6GHz'

case "$output" in
  *"$control_char"*)
    fail 'found an XML 1.0 control character in the SVG label'
    ;;
esac

case "$output" in
  *'<lt;'*|*'>gt;'*|*'"quot;'*)
    fail 'found malformed legacy escaping'
    ;;
esac

printf '%s\n' 'test-svg-escaping: ok'
