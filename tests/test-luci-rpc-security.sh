#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(dirname -- "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

fail() {
  printf '%s\n' "test-luci-rpc-security: $*" >&2
  exit 1
}

assert_status() {
  expected="$1"
  shift

  set +e
  "$@" >/dev/null 2>&1
  actual="$?"
  set -e

  [ "$actual" -eq "$expected" ] \
    || fail "expected status $expected, got $actual: $*"
}

LUCI_DIR="$PROJECT_DIR/luci-app-wi-fi-qr"
MAKEFILE="$LUCI_DIR/Makefile"
JS="$LUCI_DIR/htdocs/luci-static/resources/wi-fi-qr.js"
CATALOG="$LUCI_DIR/root/usr/lib/wi-fi-qr/wi-fi-qr-catalog"
RENDERER="$LUCI_DIR/root/usr/lib/wi-fi-qr/wi-fi-qr-render"
RPC_PLUGIN="$LUCI_DIR/root/usr/share/rpcd/ucode/wi-fi-qr.uc"
ACL="$LUCI_DIR/root/usr/share/rpcd/acl.d/luci-app-wi-fi-qr.json"
CORE="$PROJECT_DIR/wi-fi-qr/files/usr/lib/wi-fi-qr/wi-fi-qr.sh"

[ ! -e "$LUCI_DIR/root/usr/lib/wi-fi-qr/wi-fi-qr-cgi" ] \
  || fail 'legacy CGI backend is still packaged'

if grep -q '\$(1)/www/cgi-bin\|/cgi-bin/wi-fi-qr?\|wi-fi-qr-cgi' "$MAKEFILE" "$JS"; then
  fail 'public CGI endpoint is still referenced'
fi

grep -q "object: 'luci.wifi-qr'" "$JS" \
  || fail 'frontend does not call the authenticated RPC object'
grep -q "method: 'get_catalog'" "$JS" \
  || fail 'frontend does not request the committed Wi-Fi catalog'
grep -q "URL.createObjectURL" "$JS" \
  || fail 'frontend does not create a browser-local SVG URL'
grep -q "'luci.wifi-qr'" "$RPC_PLUGIN" \
  || fail 'RPCd plugin does not export luci.wifi-qr'
grep -Fq 'match(token, /^[A-Za-z0-9._-]+$/)' "$RPC_PLUGIN" \
  || fail 'RPCd plugin does not restrict shell-bound tokens to an ASCII allowlist'
grep -Fq "const cataloger = '/usr/lib/wi-fi-qr/wi-fi-qr-catalog';" "$RPC_PLUGIN" \
  || fail 'RPCd plugin does not use the fixed catalog helper'
grep -Fq "import { cursor } from 'uci';" "$RPC_PLUGIN" \
  || fail 'RPCd plugin does not read committed UCI metadata directly'
if grep -Fq 'popen([ renderer, token ]' "$RPC_PLUGIN"; then
  fail 'RPCd plugin uses an unsupported fs.popen() argv array'
fi
grep -q '"luci.wifi-qr"' "$ACL" \
  || fail 'ACL does not grant access to luci.wifi-qr'
grep -q '"get_catalog"' "$ACL" \
  || fail 'ACL does not grant access to the committed Wi-Fi catalog'

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null \
    || fail 'frontend JavaScript has invalid syntax'
fi

if command -v python3 >/dev/null 2>&1; then
  python3 -m json.tool "$ACL" >/dev/null \
    || fail 'ACL JSON is invalid'
fi

if command -v ucode >/dev/null 2>&1; then
  ucode -c -o "$TMP_DIR/wi-fi-qr.ucb" "$RPC_PLUGIN" \
    || fail 'RPCd ucode plugin has invalid syntax'
fi

mkdir -p "$TMP_DIR/bin"

cat >"$TMP_DIR/bin/uci" <<'EOF'
#!/bin/sh

[ "${1-}" = '-q' ] && shift
command="${1-}"
spec="${2-}"

case "$command:$spec" in
  'show:wireless.@wifi-iface[0]'|'show:wireless.@wifi-iface[1]')
    printf '%s\n' "$spec=wifi-iface"
    ;;
  'get:wireless.@wifi-iface[0].ssid'|'get:wireless.@wifi-iface[1].ssid')
    printf '%s\n' 'TestNet'
    ;;
  'get:wireless.@wifi-iface[0].device')
    printf '%s\n' 'radio0'
    ;;
  'get:wireless.@wifi-iface[1].device')
    printf '%s\n' 'radio1'
    ;;
  'get:wireless.@wifi-iface[0].key'|'get:wireless.@wifi-iface[1].key')
    printf '%s\n' 'super-secret'
    ;;
  'get:wireless.@wifi-iface[0].encryption'|'get:wireless.@wifi-iface[1].encryption')
    printf '%s\n' 'psk2'
    ;;
  'get:wireless.radio0.band')
    printf '%s\n' '5g'
    ;;
  'get:wireless.radio1.band')
    printf '%s\n' '2g'
    ;;
  *)
    exit 1
    ;;
esac
EOF

cat >"$TMP_DIR/bin/qrencode" <<'EOF'
#!/bin/sh

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

chmod +x "$TMP_DIR/bin/uci" "$TMP_DIR/bin/qrencode"

export WIFI_QR_TEST_PAYLOAD_FILE="$TMP_DIR/payload"

run_renderer() {
  PATH="$TMP_DIR/bin:$PATH" WIFI_QR_CORE="$CORE" \
    bash "$RENDERER" "$@"
}

run_catalog() {
  PATH="$TMP_DIR/bin:$PATH" WIFI_QR_CORE="$CORE" \
    bash "$CATALOG" "$@"
}

catalog="$(run_catalog)" \
  || fail 'committed Wi-Fi catalog generation failed'

[ "$catalog" = "$(printf '0\tid0_2.4-5GHz_TestNet.svg\n1\tid0_2.4-5GHz_TestNet.svg')" ] \
  || fail 'catalog did not map both interfaces to their canonical token'

case "$catalog" in
  *super-secret*) fail 'catalog exposed a Wi-Fi password' ;;
esac

output="$(run_renderer 'id0_2.4-5GHz_TestNet.svg')" \
  || fail 'canonical token was rejected'

case "$output" in
  *'<svg'*'TestNet'*'2.4/5GHz'*'</svg>'*) ;;
  *) fail 'renderer did not return the expected labelled SVG' ;;
esac

[ "$(cat "$WIFI_QR_TEST_PAYLOAD_FILE")" = \
    'WIFI:T:WPA;S:TestNet;P:super-secret;;' ] \
  || fail 'renderer generated an unexpected Wi-Fi payload'

# Both interfaces share one payload group, but only interface 0 is canonical.
assert_status 3 run_renderer 'id1_2.4-5GHz_TestNet.svg'
assert_status 3 run_renderer 'id0_5GHz_TestNet.svg'
assert_status 3 run_renderer 'id0_2.4-5GHz_WrongName.svg'

# Reject paths, query metacharacters, and malformed tokens before generation.
assert_status 2 run_renderer '../id0_2.4-5GHz_TestNet.svg'
assert_status 2 run_renderer 'id0_2.4-5GHz_TestNet.svg?x=1'
assert_status 2 run_renderer 'not-a-token.svg'

printf '%s\n' 'test-luci-rpc-security: ok'
