include $(TOPDIR)/rules.mk

PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=AmleyID <324701712+AmleyID@users.noreply.github.com>
PKG_LICENSE:=MIT

LUCI_TITLE:=LuCI support for Wi-Fi QR generator
LUCI_DEPENDS:=+luci-base +wi-fi-qr
LUCI_URL:=https://github.com/RzandAl/openwrt-wi-fi-qr
LUCI_MAINTAINER:=$(PKG_MAINTAINER)

define LUCI_DESCRIPTION
LuCI integration for Wi-Fi QR:
- authenticated RPCd catalog and SVG backend luci.wifi-qr with a dedicated ACL;
- static resources /www/luci-static/resources/wi-fi-qr.{js,css};
- native LuCI modal, compact and medium QR codes;
- first-frame suppression and per-network fallback of the built-in LuCI QR.
endef

define Package/luci-app-wi-fi-qr/postinst
#!/bin/sh

# Respect SDK and ImageBuilder staging roots.
[ -n "$$IPKG_INSTROOT" ] && ROOT="$$IPKG_INSTROOT" || ROOT=""

# A soft reload discovers the plugin and ACL without dropping LuCI sessions.
[ -n "$$IPKG_INSTROOT" ] || trap '/etc/init.d/rpcd reload 2>/dev/null || true' EXIT

FOOTER="$$ROOT/usr/share/ucode/luci/template/footer.ut"

[ -f "$$FOOTER" ] || exit 0

BEGIN_COUNT="$$(grep -c '<!-- wi-fi-qr begin -->' "$$FOOTER" || true)"
END_COUNT="$$(grep -c '<!-- wi-fi-qr end -->' "$$FOOTER" || true)"

# Refuse to touch a footer with missing, duplicate, or mismatched markers.
case "$$BEGIN_COUNT:$$END_COUNT" in
	0:0)
		MODE="insert"
		;;

	1:1)
		MODE="replace"
		;;

	*)
		exit 0
		;;
esac

FOOTER_TMP="$$FOOTER.tmp"
rm -f "$$FOOTER_TMP"

# Insert before LuCI delegates to the active theme, or atomically replace our
# existing block during an upgrade to refresh cache-busting asset versions.
if ! awk -v mode="$$MODE" '
  function emit_block(indent) {
    print indent "<!-- wi-fi-qr begin -->";
    print indent "{% if (!blank_page): %}";
    print indent "\t<link rel=\"stylesheet\" href=\"/luci-static/resources/wi-fi-qr.css?v=$(PKG_VERSION)-r$(PKG_RELEASE)\">";
    print indent "\t<script src=\"/luci-static/resources/wi-fi-qr.js?v=$(PKG_VERSION)-r$(PKG_RELEASE)\"></script>";
    print indent "{% endif %}";
    print indent "<!-- wi-fi-qr end -->";
  }

  BEGIN {
    inserted = 0;
    skipping = 0;
  }

  {
    line = $$0;

    if (mode == "replace") {
      if (!skipping && index(line, "<!-- wi-fi-qr begin -->") > 0) {
        indent = line;
        if (match(indent, /[^ \t]/))
          indent = substr(indent, 1, RSTART - 1);
        else
          indent = "";

        emit_block(indent);
        inserted = 1;
        skipping = 1;
        next;
      }

      if (skipping) {
        if (index(line, "<!-- wi-fi-qr end -->") > 0)
          skipping = 0;
        next;
      }
    }
    else if (!inserted &&
             index(line, "include(`themes/$${theme}/footer`)") > 0) {
      indent = line;
      if (match(indent, /[^ \t]/))
        indent = substr(indent, 1, RSTART - 1);
      else
        indent = "";

      emit_block(indent);
      inserted = 1;
    }

    print line;
  }

  END {
    if (!inserted || skipping)
      exit 1;
  }
' "$$FOOTER" >"$$FOOTER_TMP"; then
	rm -f "$$FOOTER_TMP"
	exit 0
fi

if ! mv "$$FOOTER_TMP" "$$FOOTER"; then
	rm -f "$$FOOTER_TMP"
	exit 0
fi

exit 0
endef

define Package/luci-app-wi-fi-qr/prerm
#!/bin/sh

# Leave staged installations self-contained and use the same footer path as
# post-install.
[ -n "$$IPKG_INSTROOT" ] && ROOT="$$IPKG_INSTROOT" || ROOT=""

FOOTER="$$ROOT/usr/share/ucode/luci/template/footer.ut"
[ -f "$$FOOTER" ] || exit 0

FOOTER_TMP="$$FOOTER.tmp"
rm -f "$$FOOTER_TMP"

# Remove exactly one well-formed marked block. Any malformed marker layout
# makes awk fail, preserving the original footer.
if ! awk '
  BEGIN {
    skip    = 0;
    removed = 0;
    invalid = 0;
  }

  {
    line = $$0;

    if (index(line, "<!-- wi-fi-qr begin -->") > 0) {
      if (skip || removed)
        invalid = 1;

      skip = 1;
      removed = 1;
      next;
    }

    if (index(line, "<!-- wi-fi-qr end -->") > 0) {
      if (!skip)
        invalid = 1;
      else
        skip = 0;

      next;
    }

    if (!skip)
      print line;
  }

  END {
    if (!removed || skip || invalid)
      exit 1;
  }
' "$$FOOTER" >"$$FOOTER_TMP"; then
	rm -f "$$FOOTER_TMP"
	exit 0
fi

if ! mv "$$FOOTER_TMP" "$$FOOTER"; then
	rm -f "$$FOOTER_TMP"
	exit 0
fi

exit 0
endef

define Package/luci-app-wi-fi-qr/postrm
#!/bin/sh

# APK reaches this hook only after final removal, not during an upgrade.
[ -n "$$IPKG_INSTROOT" ] && ROOT="$$IPKG_INSTROOT" || ROOT=""

rmdir "$$ROOT/usr/lib/wi-fi-qr" 2>/dev/null || true

[ -n "$$IPKG_INSTROOT" ] || /etc/init.d/rpcd reload 2>/dev/null || true

exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
