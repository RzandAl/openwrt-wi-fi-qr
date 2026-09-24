#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CLI="$ROOT_DIR/wi-fi-qr/files/usr/lib/wi-fi-qr/wi-fi-qr-cli"
CORE="$ROOT_DIR/wi-fi-qr/files/usr/lib/wi-fi-qr/wi-fi-qr.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

BIN_DIR="$TMP_DIR/bin"
OUT_DIR="$TMP_DIR/out"
mkdir -p "$BIN_DIR" "$OUT_DIR"

cat >"$BIN_DIR/uci" <<'EOF'
#!/bin/sh

if [ "${WIFI_QR_TEST_COLLISION:-0}" = '1' ]; then
  [ "${1-}" = '-q' ] && shift

  case "${1-}:${2-}" in
    'show:wireless.@wifi-iface[0]'|'show:wireless.@wifi-iface[1]')
      printf '%s\n' "${2-}=wifi-iface"
      ;;
    'get:wireless.@wifi-iface[0].ssid') printf '%s\n' 'Guest WiFi' ;;
    'get:wireless.@wifi-iface[1].ssid') printf '%s\n' 'Guest@WiFi' ;;
    'get:wireless.@wifi-iface[0].device') printf '%s\n' 'radio0' ;;
    'get:wireless.@wifi-iface[1].device') printf '%s\n' 'radio1' ;;
    'get:wireless.@wifi-iface[0].encryption') printf '%s\n' 'psk2' ;;
    'get:wireless.@wifi-iface[1].encryption') printf '%s\n' 'none' ;;
    'get:wireless.@wifi-iface[0].key') printf '%s\n' 'secret' ;;
    'get:wireless.radio0.band') printf '%s\n' '5g' ;;
    'get:wireless.radio1.band') printf '%s\n' '2g' ;;
    'get:network.lan.ipaddr') printf '%s\n' '192.0.2.1/24' ;;
    *) exit 1 ;;
  esac

  exit 0
fi

case "$*" in
  *'show wireless.@wifi-iface[0]') exit 1 ;;
  *'get network.lan.ipaddr') printf '%s\n' '192.0.2.1/24' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$BIN_DIR/uci"

PATH="$BIN_DIR:$PATH" \
WIFI_QR_CORE="$CORE" \
WIFI_QR_OUTDIR="$OUT_DIR" \
  sh "$CLI" --list >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"

grep -q '^wi-fi-qr-cli: no Wi-Fi QR codes found\.$' "$TMP_DIR/stdout" \
  || { echo "test-cli-streams: successful status was not written to stdout" >&2; exit 1; }

[ ! -s "$TMP_DIR/stderr" ] \
  || { echo "test-cli-streams: successful command wrote to stderr" >&2; exit 1; }

if PATH="$BIN_DIR" WIFI_QR_CORE="$CORE" WIFI_QR_OUTDIR="$OUT_DIR" \
     /bin/sh "$CLI" --gen >"$TMP_DIR/error.stdout" 2>"$TMP_DIR/error.stderr"; then
  echo "test-cli-streams: missing qrencode unexpectedly succeeded" >&2
  exit 1
fi

[ ! -s "$TMP_DIR/error.stdout" ] \
  || { echo "test-cli-streams: failed command wrote to stdout" >&2; exit 1; }

grep -q '^wi-fi-qr-cli: missing dependency: qrencode ' "$TMP_DIR/error.stderr" \
  || { echo "test-cli-streams: dependency error was not written to stderr" >&2; exit 1; }

# Two different SSIDs may collapse to the same safe filename component. The
# canonical UCI index must keep their display metadata distinct.
printf '%s\n' '<svg/>' >"$OUT_DIR/id0_5GHz_Guest_WiFi.svg"
printf '%s\n' '<svg/>' >"$OUT_DIR/id1_2.4GHz_Guest_WiFi.svg"

PATH="$BIN_DIR:$PATH" \
WIFI_QR_CORE="$CORE" \
WIFI_QR_OUTDIR="$OUT_DIR" \
WIFI_QR_TEST_COLLISION=1 \
  bash "$CLI" --list >"$TMP_DIR/collision.stdout" 2>"$TMP_DIR/collision.stderr"

[ ! -s "$TMP_DIR/collision.stderr" ] \
  || { echo "test-cli-streams: collision listing wrote to stderr" >&2; exit 1; }
grep -Eq '^Wi-Fi SSID[[:space:]]+Radio[[:space:]]+QR type[[:space:]]+SVG' \
  "$TMP_DIR/collision.stdout" \
  || { echo "test-cli-streams: table does not identify the QR authentication type" >&2; exit 1; }
if grep -q 'Encryption' "$TMP_DIR/collision.stdout"; then
  echo "test-cli-streams: ambiguous Encryption column is still present" >&2
  exit 1
fi

grep -Eq '^Guest WiFi[[:space:]]+5GHz[[:space:]]+WPA[[:space:]].*id0_5GHz_Guest_WiFi\.svg' \
  "$TMP_DIR/collision.stdout" \
  || { echo "test-cli-streams: first colliding SSID metadata is wrong" >&2; exit 1; }

grep -Eq '^Guest@WiFi[[:space:]]+2\.4GHz[[:space:]]+nopass[[:space:]].*id1_2\.4GHz_Guest_WiFi\.svg' \
  "$TMP_DIR/collision.stdout" \
  || { echo "test-cli-streams: second colliding SSID metadata is wrong" >&2; exit 1; }

printf '%s\n' 'test-cli-streams: ok'
