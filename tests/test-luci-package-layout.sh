#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(dirname -- "$SCRIPT_DIR")"
LUCI_DIR="$PROJECT_DIR/luci-app-wi-fi-qr"
MAKEFILE="$LUCI_DIR/Makefile"

fail() {
  printf '%s\n' "test-luci-package-layout: $*" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "expected file: $1"
}

grep -Fq 'include $(TOPDIR)/feeds/luci/luci.mk' "$MAKEFILE" \
  || fail 'Makefile does not use the LuCI package helper'
grep -Fq '# call BuildPackage - OpenWrt buildroot signature' "$MAKEFILE" \
  || fail 'Makefile lacks the package scanner signature'

if grep -Fq 'include $(INCLUDE_DIR)/package.mk' "$MAKEFILE"; then
  fail 'Makefile still includes package.mk directly'
fi

if grep -Fq 'define Package/luci-app-wi-fi-qr/install' "$MAKEFILE"; then
  fail 'Makefile still has a manual install recipe'
fi

assert_file "$LUCI_DIR/htdocs/luci-static/resources/wi-fi-qr.css"
assert_file "$LUCI_DIR/htdocs/luci-static/resources/wi-fi-qr.js"
assert_file "$LUCI_DIR/root/usr/lib/wi-fi-qr/wi-fi-qr-catalog"
assert_file "$LUCI_DIR/root/usr/lib/wi-fi-qr/wi-fi-qr-render"
assert_file "$LUCI_DIR/root/usr/share/rpcd/acl.d/luci-app-wi-fi-qr.json"
assert_file "$LUCI_DIR/root/usr/share/rpcd/ucode/wi-fi-qr.uc"

[ -x "$LUCI_DIR/root/usr/lib/wi-fi-qr/wi-fi-qr-catalog" ] \
  || fail 'catalog helper is not executable'

[ -x "$LUCI_DIR/root/usr/lib/wi-fi-qr/wi-fi-qr-render" ] \
  || fail 'renderer is not executable'

if [ -d "$LUCI_DIR/files" ] &&
   find "$LUCI_DIR/files" -type f -print -quit | grep -q .; then
  fail 'legacy files/ layout still contains packaged files'
fi

printf '%s\n' 'test-luci-package-layout: ok'
