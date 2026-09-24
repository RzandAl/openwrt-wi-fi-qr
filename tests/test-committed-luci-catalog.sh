#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(dirname -- "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

fail() {
  printf '%s\n' "test-committed-luci-catalog: $*" >&2
  exit 1
}

LUCI_DIR="$PROJECT_DIR/luci-app-wi-fi-qr"
JS="$LUCI_DIR/htdocs/luci-static/resources/wi-fi-qr.js"
CATALOG="$LUCI_DIR/root/usr/lib/wi-fi-qr/wi-fi-qr-catalog"
RPC_PLUGIN="$LUCI_DIR/root/usr/share/rpcd/ucode/wi-fi-qr.uc"
CORE="$PROJECT_DIR/wi-fi-qr/files/usr/lib/wi-fi-qr/wi-fi-qr.sh"

grep -Fq "method: 'get_catalog'" "$JS" \
  || fail 'frontend does not request the committed catalog'
grep -Fq "expect: { networks: [] }" "$JS" \
  || fail 'frontend does not validate the catalog response shape'
grep -Fq 'var catalog = indexWifiCatalog(networks);' "$JS" \
  || fail 'frontend does not index the server catalog'
grep -Fq 'createQrImg(entry.ssid, true, entry.token)' "$JS" \
  || fail 'status QR controls do not use server-issued tokens'
grep -Fq "img.setAttribute('data-token', token);" "$JS" \
  || fail 'rendered QR controls do not retain their canonical token'

if grep -Fq "L.require('uci')" "$JS" || grep -Fq "uci.load('wireless')" "$JS"; then
  fail 'frontend still derives QR identities from pending LuCI UCI state'
fi

grep -Fq "const uci = cursor();" "$RPC_PLUGIN" \
  || fail 'RPC catalog does not use its own committed libuci cursor'

mkdir -p "$TMP_DIR/bin"

cat >"$TMP_DIR/bin/uci" <<'EOF'
#!/bin/sh

[ "${1-}" = '-q' ] && shift
command="${1-}"
spec="${2-}"

case "$command:$spec" in
  'show:wireless.@wifi-iface[0]'|'show:wireless.@wifi-iface[1]'|\
  'show:wireless.@wifi-iface[2]'|'show:wireless.@wifi-iface[3]')
    printf '%s\n' "$spec=wifi-iface"
    ;;
  'get:wireless.@wifi-iface[0].ssid') printf '%s\n' 'MainNet' ;;
  'get:wireless.@wifi-iface[1].ssid') printf '%s\n' 'GuestNet' ;;
  'get:wireless.@wifi-iface[2].ssid') printf '%s\n' 'IoTNet' ;;
  'get:wireless.@wifi-iface[3].ssid') printf '%s\n' 'LabNet' ;;
  'get:wireless.@wifi-iface[0].device'|'get:wireless.@wifi-iface[2].device')
    printf '%s\n' 'radio0'
    ;;
  'get:wireless.@wifi-iface[1].device'|'get:wireless.@wifi-iface[3].device')
    printf '%s\n' 'radio1'
    ;;
  'get:wireless.@wifi-iface[0].key') printf '%s\n' 'main-secret' ;;
  'get:wireless.@wifi-iface[1].key') printf '%s\n' 'guest-secret' ;;
  'get:wireless.@wifi-iface[2].key') printf '%s\n' 'iot-secret' ;;
  'get:wireless.@wifi-iface[3].key') printf '%s\n' 'lab-secret' ;;
  'get:wireless.@wifi-iface[0].encryption'|\
  'get:wireless.@wifi-iface[1].encryption'|\
  'get:wireless.@wifi-iface[2].encryption'|\
  'get:wireless.@wifi-iface[3].encryption')
    printf '%s\n' 'psk2'
    ;;
  'get:wireless.radio0.band') printf '%s\n' '2g' ;;
  'get:wireless.radio1.band') printf '%s\n' '5g' ;;
  *) exit 1 ;;
esac
EOF

chmod +x "$TMP_DIR/bin/uci"

catalog="$(PATH="$TMP_DIR/bin:$PATH" WIFI_QR_CORE="$CORE" bash "$CATALOG")" \
  || fail 'catalog helper failed for four committed networks'

expected="$(printf '%s\n' \
  '0	id0_2.4GHz_MainNet.svg' \
  '1	id1_5GHz_GuestNet.svg' \
  '2	id2_2.4GHz_IoTNet.svg' \
  '3	id3_5GHz_LabNet.svg')"

[ "$catalog" = "$expected" ] \
  || fail 'catalog did not preserve all four committed network tokens'

case "$catalog" in
  *-secret*) fail 'catalog exposed Wi-Fi credentials' ;;
esac

if command -v node >/dev/null 2>&1; then
  node - "$JS" <<'EOF' \
    || fail 'frontend catalog indexing regression test failed'
const fs = require('fs');
const vm = require('vm');
const path = process.argv[2];
const source = fs.readFileSync(path, 'utf8');
const instrumented = source.replace(
    /\n\}\)\(\);\s*$/,
    '\n    globalThis.__indexWifiCatalog = indexWifiCatalog;\n})();\n'
);

if (instrumented === source)
    throw new Error('could not expose catalog indexer');

const context = {
    window: { addEventListener() {} },
    location: { pathname: '/cgi-bin/luci/admin/status/overview' },
    document: { readyState: 'loading', addEventListener() {} }
};

vm.runInNewContext(instrumented, context);

const committed = [
    { sid: 'wifi0', ssid: 'MainNet',  token: 'id0_2.4GHz_MainNet.svg' },
    { sid: 'wifi1', ssid: 'GuestNet', token: 'id1_5GHz_GuestNet.svg' },
    { sid: 'wifi2', ssid: 'IoTNet',   token: 'id2_2.4GHz_IoTNet.svg' },
    { sid: 'wifi3', ssid: 'LabNet',   token: 'id3_5GHz_LabNet.svg' }
];

// LuCI may stage wifi1 and wifi2 for deletion, but this index is deliberately
// built only from the committed RPC response above.
const stagedRemainingSids = [ 'wifi0', 'wifi3' ];
const indexed = context.__indexWifiCatalog(committed);

if (Object.keys(indexed.bySid).length !== 4)
    throw new Error('pending deletions removed committed catalog entries');

for (const network of committed) {
    if (!indexed.bySid[network.sid] ||
        indexed.bySid[network.sid].token !== network.token)
        throw new Error(`missing committed token for ${network.sid}`);
}

if (stagedRemainingSids.length !== 2 || !indexed.bySsid.GuestNet || !indexed.bySsid.IoTNet)
    throw new Error('catalog unexpectedly followed staged LuCI deletions');
EOF
fi

printf '%s\n' 'test-committed-luci-catalog: ok'
