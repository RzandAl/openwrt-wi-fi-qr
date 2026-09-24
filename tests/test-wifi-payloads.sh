#!/bin/sh

set -eu

# The runtime target is BusyBox ash, whose parameter substitutions match bash.
# Re-exec under bash when the host's /bin/sh is a more restrictive shell.
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(dirname -- "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

fail() {
  printf '%s\n' "test-wifi-payloads: $*" >&2
  exit 1
}

assert_equal() {
  expected="$1"
  actual="$2"

  [ "$actual" = "$expected" ] \
    || fail "expected '$expected', got '$actual'"
}

. "$PROJECT_DIR/wi-fi-qr/files/usr/lib/wi-fi-qr/wi-fi-qr.sh"

assert_equal 'WIFI:T:WPA;S:MainNet;P:secret;;' \
  "$(wifi_qr_payload 'MainNet' 'secret' 'psk2' '0')"

assert_equal 'WIFI:T:WPA;S:HiddenNet;H:true;P:secret;;' \
  "$(wifi_qr_payload 'HiddenNet' 'secret' 'psk2' '1')"

for true_value in 1 on true yes enabled TRUE ' yes '; do
  assert_equal 'WIFI:T:WPA;S:HiddenNet;H:true;P:secret;;' \
    "$(wifi_qr_payload 'HiddenNet' 'secret' 'psk2' "$true_value")"
done

for false_value in 0 off false no disabled FALSE ' no '; do
  assert_equal 'WIFI:T:WPA;S:HiddenNet;P:secret;;' \
    "$(wifi_qr_payload 'HiddenNet' 'secret' 'psk2' "$false_value")"
done

assert_equal 'WIFI:T:WPA;R:0;S:WPA3;P:secret;;' \
  "$(wifi_qr_payload 'WPA3' 'secret' 'sae' '0')"

assert_equal 'WIFI:T:nopass;R:3;S:EnhancedOpen;;' \
  "$(wifi_qr_payload 'EnhancedOpen' '' 'owe' '0')"

assert_equal "WIFI:T:WPA;S:Cafe's\\:Guest;P:don't\\;panic;;" \
  "$(wifi_qr_payload "Cafe's:Guest" "don't;panic" 'psk2' '0')"

if wifi_qr_payload 'EnterpriseNet' '' 'wpa2' '0' >/dev/null 2>&1; then
  fail 'unsupported enterprise encryption produced a misleading personal QR'
fi

mkdir -p "$TMP_DIR/bin"

cat >"$TMP_DIR/bin/uci" <<'EOF'
#!/bin/sh

[ "${1-}" = '-q' ] && shift

case "${1-}:${2-}" in
  'show:wireless.@wifi-iface[0]'|'show:wireless.@wifi-iface[1]'|'show:wireless.@wifi-iface[2]'|'show:wireless.@wifi-iface[3]'|'show:wireless.@wifi-iface[4]')
    printf '%s\n' "${2-}=wifi-iface"
    ;;
  'get:wireless.@wifi-iface[0].ssid')
    printf '%s\n' 'LegacyNet'
    ;;
  'get:wireless.@wifi-iface[1].ssid')
    printf '%s\n' 'EnterpriseNet'
    ;;
  'get:wireless.@wifi-iface[2].ssid')
    printf '%s\n' 'MissingKeyNet'
    ;;
  'get:wireless.@wifi-iface[3].ssid')
    printf '%s\n' 'DisabledIfaceNet'
    ;;
  'get:wireless.@wifi-iface[4].ssid')
    printf '%s\n' 'DisabledRadioNet'
    ;;
  'get:wireless.@wifi-iface[0].device')
    printf '%s\n' 'radio0'
    ;;
  'get:wireless.@wifi-iface[1].device'|'get:wireless.@wifi-iface[2].device'|'get:wireless.@wifi-iface[3].device')
    printf '%s\n' 'radio1'
    ;;
  'get:wireless.@wifi-iface[4].device')
    printf '%s\n' 'radio2'
    ;;
  'get:wireless.@wifi-iface[0].encryption')
    printf '%s\n' 'wep-open'
    ;;
  'get:wireless.@wifi-iface[1].encryption')
    printf '%s\n' 'wpa2'
    ;;
  'get:wireless.@wifi-iface[2].encryption')
    printf '%s\n' 'psk2'
    ;;
  'get:wireless.@wifi-iface[3].encryption'|'get:wireless.@wifi-iface[4].encryption')
    printf '%s\n' 'psk2'
    ;;
  'get:wireless.@wifi-iface[0].hidden')
    printf '%s\n' 'true'
    ;;
  'get:wireless.@wifi-iface[3].disabled')
    printf '%s\n' 'true'
    ;;
  'get:wireless.radio2.disabled')
    printf '%s\n' 'yes'
    ;;
  'get:wireless.@wifi-iface[3].key'|'get:wireless.@wifi-iface[4].key')
    printf '%s\n' 'ignored-secret'
    ;;
  'get:wireless.@wifi-iface[0].key')
    printf '%s\n' '2'
    ;;
  'get:wireless.@wifi-iface[0].key2')
    printf '%s\n' 's:abcde'
    ;;
  'get:wireless.radio0.band')
    printf '%s\n' '2g'
    ;;
  'get:wireless.radio1.band')
    printf '%s\n' '5g'
    ;;
  'get:wireless.radio2.band')
    printf '%s\n' '6g'
    ;;
  *)
    exit 1
    ;;
esac
EOF

chmod +x "$TMP_DIR/bin/uci"

assert_equal 'abcde' \
  "$(PATH="$TMP_DIR/bin:$PATH" wifi_qr_key_for_iface '0' 'wep-open')"

assert_equal 'WIFI:T:WEP;S:LegacyNet;P:abcde;;' \
  "$(wifi_qr_payload 'LegacyNet' 'abcde' 'wep-open' '0')"

PATH="$TMP_DIR/bin:$PATH" wifi_qr_build_groups
assert_equal '1' "$group_count"
assert_equal 'LegacyNet' "$(get_var 'group_ssid_1')"
assert_equal 'abcde' "$(get_var 'group_key_1')"
assert_equal '1' "$(get_var 'group_hidden_1')"
assert_equal 'WIFI:T:WEP;S:LegacyNet;H:true;P:abcde;;' \
  "$(get_var 'group_payload_1')"

printf '%s\n' 'test-wifi-payloads: ok'
