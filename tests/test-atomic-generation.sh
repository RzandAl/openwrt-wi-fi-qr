#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(dirname -- "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

fail() {
  printf '%s\n' "test-atomic-generation: $*" >&2
  exit 1
}

CORE="$PROJECT_DIR/wi-fi-qr/files/usr/lib/wi-fi-qr/wi-fi-qr.sh"
CLI="$PROJECT_DIR/wi-fi-qr/files/usr/lib/wi-fi-qr/wi-fi-qr-cli"
OUTDIR="$TMP_DIR/www/wi-fi-qr"
FAIL_FILE="$TMP_DIR/fail-second-network"
UCI_FAIL_FILE="$TMP_DIR/fail-wireless-uci"
EMPTY_FILE="$TMP_DIR/empty-wireless-config"
LOG_FILE="$TMP_DIR/cli.log"

mkdir -p "$TMP_DIR/bin" "$OUTDIR"

cat >"$TMP_DIR/bin/uci" <<'EOF'
#!/bin/sh

[ "${1-}" = '-q' ] && shift
command="${1-}"
spec="${2-}"

if [ "$command:$spec" = 'show:wireless' ]; then
  [ ! -e "$WIFI_QR_TEST_UCI_FAIL_FILE" ] || exit 1
  exit 0
fi

if [ -e "$WIFI_QR_TEST_EMPTY_FILE" ]; then
  case "$command:$spec" in
    'get:network.lan.ipaddr')
      printf '%s\n' '192.168.1.1/24'
      ;;
    *)
      exit 1
      ;;
  esac
  exit 0
fi

case "$command:$spec" in
  'show:wireless.@wifi-iface[0]'|'show:wireless.@wifi-iface[1]')
    printf '%s\n' "$spec=wifi-iface"
    ;;
  'get:wireless.@wifi-iface[0].ssid')
    printf '%s\n' 'FirstNet'
    ;;
  'get:wireless.@wifi-iface[1].ssid')
    printf '%s\n' 'SecondNet'
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
  'get:network.lan.ipaddr')
    printf '%s\n' '192.168.1.1/24'
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

payload="$(cat)"

case "$payload" in
  *'S:SecondNet;'*)
    [ ! -e "$WIFI_QR_TEST_FAIL_FILE" ] || exit 70
    ;;
esac

printf '%s\n' \
  '<svg xmlns="http://www.w3.org/2000/svg" width="21" height="21" viewBox="0 0 21 21">' \
  '<path d="M0 0h1v1H0z"/>' \
  '</svg>'
EOF

chmod +x "$TMP_DIR/bin/uci" "$TMP_DIR/bin/qrencode"

run_cli() {
  PATH="$TMP_DIR/bin:$PATH" \
  WIFI_QR_CORE="$CORE" \
  WIFI_QR_OUTDIR="$OUTDIR" \
  WIFI_QR_TEST_FAIL_FILE="$FAIL_FILE" \
  WIFI_QR_TEST_UCI_FAIL_FILE="$UCI_FAIL_FILE" \
  WIFI_QR_TEST_EMPTY_FILE="$EMPTY_FILE" \
    bash "$CLI" --gen >"$LOG_FILE" 2>&1
}

assert_no_staging_directory() {
  if find "$OUTDIR" -mindepth 1 -maxdepth 1 -type d \
      -name '.wi-fi-qr-stage.*' | grep -q .; then
    fail 'a staging directory was left behind'
  fi
}

# A prior power loss may leave a complete or partial staging directory. The
# next command must remove project QR files from it before doing other work.
mkdir -p "$OUTDIR/.wi-fi-qr-stage.stale"
printf '%s\n' 'stale-secret' >"$OUTDIR/.wi-fi-qr-stage.stale/id9_5GHz_Stale.svg"

printf '%s\n' 'old-main' >"$OUTDIR/id7_5GHz_OldNet.svg"
printf '%s\n' 'old-guest' >"$OUTDIR/id8_2.4GHz_OldGuest.svg"
printf '%s\n' 'keep-me' >"$OUTDIR/unrelated.txt"
: >"$FAIL_FILE"

set +e
run_cli
status="$?"
set -e

[ "$status" -ne 0 ] \
  || fail 'partial generation unexpectedly succeeded'
[ "$(cat "$OUTDIR/id7_5GHz_OldNet.svg")" = 'old-main' ] \
  || fail 'the first old QR code was replaced after a generation failure'
[ "$(cat "$OUTDIR/id8_2.4GHz_OldGuest.svg")" = 'old-guest' ] \
  || fail 'the second old QR code was replaced after a generation failure'
[ ! -e "$OUTDIR/id0_5GHz_FirstNet.svg" ] \
  || fail 'a partially generated QR code was published'
[ ! -e "$OUTDIR/id1_2.4GHz_SecondNet.svg" ] \
  || fail 'the failing QR code was published'
[ "$(cat "$OUTDIR/unrelated.txt")" = 'keep-me' ] \
  || fail 'an unrelated output file was modified'
grep -q "failed to generate Wi-Fi QR code for 'SecondNet'" "$LOG_FILE" \
  || fail 'the failing network was not reported'
grep -q 'existing Wi-Fi QR codes were left unchanged' "$LOG_FILE" \
  || fail 'the rollback result was not reported'
assert_no_staging_directory

rm -f "$FAIL_FILE"

run_cli || fail 'complete generation failed'

[ ! -e "$OUTDIR/id7_5GHz_OldNet.svg" ] \
  || fail 'an obsolete QR code survived successful generation'
[ ! -e "$OUTDIR/id8_2.4GHz_OldGuest.svg" ] \
  || fail 'a second obsolete QR code survived successful generation'
[ -s "$OUTDIR/id0_5GHz_FirstNet.svg" ] \
  || fail 'the first new QR code was not published'
[ -s "$OUTDIR/id1_2.4GHz_SecondNet.svg" ] \
  || fail 'the second new QR code was not published'
[ "$(cat "$OUTDIR/unrelated.txt")" = 'keep-me' ] \
  || fail 'an unrelated output file was removed'
assert_no_staging_directory

# Failure to read the wireless package must not be mistaken for a valid empty
# configuration, because that would erase the currently published QR set.
: >"$UCI_FAIL_FILE"

set +e
run_cli
status="$?"
set -e

[ "$status" -ne 0 ] \
  || fail 'an unreadable wireless configuration unexpectedly succeeded'
[ -s "$OUTDIR/id0_5GHz_FirstNet.svg" ] \
  || fail 'the first QR code was removed after a UCI read failure'
[ -s "$OUTDIR/id1_2.4GHz_SecondNet.svg" ] \
  || fail 'the second QR code was removed after a UCI read failure'
grep -q 'unable to read the wireless UCI configuration' "$LOG_FILE" \
  || fail 'the UCI read failure was not reported'
grep -q 'existing Wi-Fi QR codes were left unchanged' "$LOG_FILE" \
  || fail 'the preserved set was not reported after a UCI read failure'
assert_no_staging_directory

rm -f "$UCI_FAIL_FILE"

# A successfully read configuration with no supported enabled networks is a
# valid empty result and must retire stale project QR files.
: >"$EMPTY_FILE"
run_cli || fail 'an empty wireless configuration failed'

if find "$OUTDIR" -mindepth 1 -maxdepth 1 -type f \
    -name 'id*_*.svg' | grep -q .; then
  fail 'stale QR codes survived a successful empty generation'
fi
[ "$(cat "$OUTDIR/unrelated.txt")" = 'keep-me' ] \
  || fail 'an unrelated output file was removed by empty generation'
grep -q 'no supported enabled Wi-Fi networks found; removed existing Wi-Fi QR codes' "$LOG_FILE" \
  || fail 'the published empty set was not reported'
assert_no_staging_directory

printf '%s\n' 'test-atomic-generation: ok'
