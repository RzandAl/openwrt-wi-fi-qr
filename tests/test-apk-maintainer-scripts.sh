#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(dirname -- "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

fail() {
  printf '%s\n' "test-apk-maintainer-scripts: $*" >&2
  exit 1
}

extract_script() {
  makefile="$1"
  definition="$2"
  output="$3"

  awk -v definition="$definition" '
    $0 == "define " definition {
      collecting = 1
      next
    }

    collecting && $0 == "endef" {
      found = 1
      exit
    }

    collecting {
      gsub(/\$\$/, "$")
      print
    }

    END {
      if (!found)
        exit 1
    }
  ' "$makefile" >"$output" || fail "cannot extract $definition"

  [ -s "$output" ] || fail "empty script extracted for $definition"
  sh -n "$output" || fail "invalid shell syntax in $definition"
}

assert_exists() {
  [ -e "$1" ] || fail "expected to exist: $1"
}

assert_missing() {
  [ ! -e "$1" ] || fail "expected to be absent: $1"
}

assert_one_marker() {
  begin_count="$(grep -c '<!-- wi-fi-qr begin -->' "$1" || true)"
  end_count="$(grep -c '<!-- wi-fi-qr end -->' "$1" || true)"

  [ "$begin_count" -eq 1 ] \
    || fail "expected one footer begin marker, found $begin_count"
  [ "$end_count" -eq 1 ] \
    || fail "expected one footer end marker, found $end_count"
}

assert_asset_version() {
  count="$(grep -Fc "?v=$2" "$1" || true)"
  [ "$count" -eq 2 ] \
    || fail "expected two footer assets at version $2, found $count"
}

assert_block_before_theme_footer() {
  block_line="$(grep -nF '<!-- wi-fi-qr begin -->' "$1" | cut -d: -f1)"
  include_line="$(grep -nF 'include(`themes/${theme}/footer`)' "$1" | cut -d: -f1)"

  [ -n "$block_line" ] && [ -n "$include_line" ] \
    || fail 'could not locate the injected block and theme footer include'
  [ "$block_line" -lt "$include_line" ] \
    || fail 'assets are not injected before the active theme footer'
}

assert_prerm_preserves_footer() {
  fixture="$1"
  reason="$2"

  cp "$fixture" "$footer"
  cp "$footer" "$footer.expected"

  IPKG_INSTROOT="$luci_root" sh "$LUCI_PRERM" 1.0.0-r9

  cmp -s "$footer" "$footer.expected" \
    || fail "prerm modified footer with $reason"
  assert_missing "$footer.tmp"
}

BASE_MAKEFILE="$PROJECT_DIR/wi-fi-qr/Makefile"
LUCI_MAKEFILE="$PROJECT_DIR/luci-app-wi-fi-qr/Makefile"

BASE_POSTINST="$TMP_DIR/base-postinst.sh"
BASE_POSTRM="$TMP_DIR/base-postrm.sh"
LUCI_POSTINST="$TMP_DIR/luci-postinst.sh"
LUCI_PRERM="$TMP_DIR/luci-prerm.sh"
LUCI_POSTRM="$TMP_DIR/luci-postrm.sh"

extract_script "$BASE_MAKEFILE" 'Package/wi-fi-qr/postinst' "$BASE_POSTINST"
extract_script "$BASE_MAKEFILE" 'Package/wi-fi-qr/postrm' "$BASE_POSTRM"
extract_script "$LUCI_MAKEFILE" 'Package/luci-app-wi-fi-qr/postinst' "$LUCI_POSTINST"
extract_script "$LUCI_MAKEFILE" 'Package/luci-app-wi-fi-qr/prerm' "$LUCI_PRERM"
extract_script "$LUCI_MAKEFILE" 'Package/luci-app-wi-fi-qr/postrm' "$LUCI_POSTRM"

# The project targets APK-only OpenWrt releases; legacy opkg dispatch and the
# old Lua footer path must not return unnoticed.
if grep -Eq 'opkg|abort-(install|upgrade)|/usr/lib/lua/luci/view' \
  "$BASE_MAKEFILE" "$LUCI_MAKEFILE"; then
  fail 'legacy opkg or Lua compatibility remains in package hooks'
fi

if grep -Fq '/template/themes/bootstrap/footer.ut' "$LUCI_MAKEFILE"; then
  fail 'LuCI hooks still modify a theme-specific footer'
fi

# APK passes the installed package version to post-deinstall.
base_remove_root="$TMP_DIR/base-remove"
mkdir -p "$base_remove_root/www/wi-fi-qr/.wi-fi-qr-stage.stale" \
  "$base_remove_root/usr/lib/wi-fi-qr"
: >"$base_remove_root/www/wi-fi-qr/id1_test.svg"
: >"$base_remove_root/www/wi-fi-qr/id1_test.svg.tmp"
: >"$base_remove_root/www/wi-fi-qr/.wi-fi-qr-stage.stale/id9_stale.svg"
IPKG_INSTROOT="$base_remove_root" sh "$BASE_POSTRM" 1.0.0-r7
assert_missing "$base_remove_root/www/wi-fi-qr/id1_test.svg"
assert_missing "$base_remove_root/www/wi-fi-qr/id1_test.svg.tmp"
assert_missing "$base_remove_root/www/wi-fi-qr/.wi-fi-qr-stage.stale"
assert_missing "$base_remove_root/www/wi-fi-qr"
assert_missing "$base_remove_root/usr/lib/wi-fi-qr"

# APK maps postinst to post-upgrade and exposes the transition via PKG_UPGRADE.
base_upgrade_root="$TMP_DIR/base-upgrade"
mkdir -p "$base_upgrade_root/www/wi-fi-qr/.wi-fi-qr-stage.stale"
: >"$base_upgrade_root/www/wi-fi-qr/id3_test.svg"
: >"$base_upgrade_root/www/wi-fi-qr/.wi-fi-qr-stage.stale/id9_stale.svg"
IPKG_INSTROOT="$base_upgrade_root" sh "$BASE_POSTINST" 1.0.0-r7
assert_exists "$base_upgrade_root/www/wi-fi-qr/id3_test.svg"
IPKG_INSTROOT="$base_upgrade_root" PKG_UPGRADE=1 \
  sh "$BASE_POSTINST" 1.0.0-r7 1.0.0-r6
assert_missing "$base_upgrade_root/www/wi-fi-qr/id3_test.svg"
assert_missing "$base_upgrade_root/www/wi-fi-qr/.wi-fi-qr-stage.stale"

luci_root="$TMP_DIR/luci"
footer_dir="$luci_root/usr/share/ucode/luci/template"
footer="$footer_dir/footer.ut"
footer_original="$TMP_DIR/footer-original.ut"
footer_patched="$TMP_DIR/footer-patched.ut"
theme_footer="$footer_dir/themes/bootstrap/footer.ut"
theme_footer_original="$TMP_DIR/theme-footer-original.ut"

mkdir -p "$footer_dir/themes/bootstrap" "$luci_root/usr/lib/wi-fi-qr"

cat >"$footer" <<'EOF'
{% if (media_error): %}
	<script>showThemeError();</script>
{% endif %}

{% include(`themes/${theme}/footer`) %}

<!-- Lua compatibility mode active: {{ lua_active ? 'yes' : 'no' }} -->
EOF
cp "$footer" "$footer_original"

cat >"$theme_footer" <<'EOF'
{% if (!blank_page): %}
	<footer>LuCI</footer>
{% endif %}
</body>
</html>
EOF
cp "$theme_footer" "$theme_footer_original"

IPKG_INSTROOT="$luci_root" sh "$LUCI_POSTINST" 1.0.0-r9
assert_one_marker "$footer"
assert_asset_version "$footer" '$(PKG_VERSION)-r$(PKG_RELEASE)'
assert_block_before_theme_footer "$footer"
grep -Fq '{% if (!blank_page): %}' "$footer" \
  || fail 'asset block is not guarded from blank login pages'
cmp -s "$theme_footer" "$theme_footer_original" \
  || fail 'postinst modified the active theme footer'

# APK runs post-upgrade without first removing an existing marked block. Use a
# deliberately stale version and require postinst to refresh both asset URLs.
sed 's/?v=[^"]*/?v=1.0.0-r0/g' "$footer" >"$footer.stale"
mv "$footer.stale" "$footer"
assert_asset_version "$footer" '1.0.0-r0'

IPKG_INSTROOT="$luci_root" PKG_UPGRADE=1 \
  sh "$LUCI_POSTINST" 1.0.0-r9 1.0.0-r0
assert_one_marker "$footer"
assert_asset_version "$footer" '$(PKG_VERSION)-r$(PKG_RELEASE)'
assert_block_before_theme_footer "$footer"
if grep -Fq '?v=1.0.0-r0' "$footer"; then
  fail 'post-upgrade retained stale LuCI asset versions'
fi

cp "$footer" "$footer_patched"

# Reinstalling the package must not duplicate the footer block.
IPKG_INSTROOT="$luci_root" sh "$LUCI_POSTINST" 1.0.0-r9
cmp -s "$footer" "$footer_patched" || fail 'postinst is not idempotent'

# APK passes the installed package version to pre-deinstall.
IPKG_INSTROOT="$luci_root" sh "$LUCI_PRERM" 1.0.0-r9
cmp -s "$footer" "$footer_original" || fail 'version-argument prerm did not restore footer'
cmp -s "$theme_footer" "$theme_footer_original" \
  || fail 'prerm modified the active theme footer'

# Malformed or ambiguous marker layouts must be left byte-for-byte intact.
footer_missing_end="$TMP_DIR/footer-missing-end.ut"
cp "$footer_original" "$footer_missing_end"
printf '%s\n' \
  '<!-- wi-fi-qr begin -->' \
  '<script src="/luci-static/resources/wi-fi-qr.js"></script>' \
  >>"$footer_missing_end"
assert_prerm_preserves_footer "$footer_missing_end" 'a missing end marker'

footer_missing_begin="$TMP_DIR/footer-missing-begin.ut"
cp "$footer_original" "$footer_missing_begin"
printf '%s\n' '<!-- wi-fi-qr end -->' >>"$footer_missing_begin"
assert_prerm_preserves_footer "$footer_missing_begin" 'a missing begin marker'

footer_duplicate="$TMP_DIR/footer-duplicate.ut"
cp "$footer_patched" "$footer_duplicate"
printf '%s\n' \
  '<!-- wi-fi-qr begin -->' \
  '<script src="/luci-static/resources/wi-fi-qr.js"></script>' \
  '<!-- wi-fi-qr end -->' \
  >>"$footer_duplicate"
assert_prerm_preserves_footer "$footer_duplicate" 'duplicate marker blocks'

footer_reversed="$TMP_DIR/footer-reversed.ut"
cp "$footer_original" "$footer_reversed"
printf '%s\n' \
  '<!-- wi-fi-qr end -->' \
  '<!-- wi-fi-qr begin -->' \
  >>"$footer_reversed"
assert_prerm_preserves_footer "$footer_reversed" 'reversed markers'

# APK removes package-owned files before post-deinstall, leaving an empty dir.
IPKG_INSTROOT="$luci_root" sh "$LUCI_POSTRM" 1.0.0-r9
assert_missing "$luci_root/usr/lib/wi-fi-qr"

printf '%s\n' 'test-apk-maintainer-scripts: ok'
