include $(TOPDIR)/rules.mk

PKG_NAME:=wi-fi-qr
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=AmleyID <324701712+AmleyID@users.noreply.github.com>
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/wi-fi-qr
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Wi-Fi QR generator
  DEPENDS:=+qrencode +uci
  PKGARCH:=all
  URL:=https://github.com/RzandAl/openwrt-wi-fi-qr
endef

define Package/wi-fi-qr/description
 Simple helper for generating supported personal Wi-Fi QR codes:
 - core shell module /usr/lib/wi-fi-qr/wi-fi-qr.sh;
 - CLI wrapper /usr/lib/wi-fi-qr/wi-fi-qr-cli;
 - command wi-fi-qr --gen  (generate Wi-Fi QR codes in /www/wi-fi-qr);
 - command wi-fi-qr --del  (delete all generated Wi-Fi QR codes);
 - command wi-fi-qr --list (show table of existing Wi-Fi QR codes).
endef

define Build/Compile
endef

define Package/wi-fi-qr/install
	$(INSTALL_DIR) $(1)/usr/lib/wi-fi-qr
	$(INSTALL_BIN) ./files/usr/lib/wi-fi-qr/wi-fi-qr.sh \
		$(1)/usr/lib/wi-fi-qr/wi-fi-qr.sh
	$(INSTALL_BIN) ./files/usr/lib/wi-fi-qr/wi-fi-qr-cli \
		$(1)/usr/lib/wi-fi-qr/wi-fi-qr-cli

	$(INSTALL_DIR) $(1)/usr/bin
	$(LN) ../lib/wi-fi-qr/wi-fi-qr-cli $(1)/usr/bin/wi-fi-qr
endef

define Package/wi-fi-qr/postinst
#!/bin/sh

# Respect SDK and ImageBuilder staging roots.
[ -n "$$IPKG_INSTROOT" ] && ROOT="$$IPKG_INSTROOT" || ROOT=""

# APK upgrades set PKG_UPGRADE=1. Generated SVGs are derived state and must
# be recreated by the newly installed code.
[ "$${PKG_UPGRADE:-0}" = "1" ] || exit 0

rm -f "$$ROOT/www/wi-fi-qr"/id*_*.svg \
      "$$ROOT/www/wi-fi-qr"/id*_*.svg.tmp 2>/dev/null || true

for STAGE_DIR in "$$ROOT/www/wi-fi-qr"/.wi-fi-qr-stage.*; do
	[ -d "$$STAGE_DIR" ] || continue
	rm -f "$$STAGE_DIR"/id*_*.svg 2>/dev/null || true
	rmdir "$$STAGE_DIR" 2>/dev/null || true
done

exit 0
endef

define Package/wi-fi-qr/postrm
#!/bin/sh

# APK invokes post-deinstall only for final package removal.
[ -n "$$IPKG_INSTROOT" ] && ROOT="$$IPKG_INSTROOT" || ROOT=""

rm -f "$$ROOT/www/wi-fi-qr"/id*_*.svg \
      "$$ROOT/www/wi-fi-qr"/id*_*.svg.tmp 2>/dev/null || true

for STAGE_DIR in "$$ROOT/www/wi-fi-qr"/.wi-fi-qr-stage.*; do
	[ -d "$$STAGE_DIR" ] || continue
	rm -f "$$STAGE_DIR"/id*_*.svg 2>/dev/null || true
	rmdir "$$STAGE_DIR" 2>/dev/null || true
done

rmdir "$$ROOT/www/wi-fi-qr" 2>/dev/null || true
rmdir "$$ROOT/usr/lib/wi-fi-qr" 2>/dev/null || true

exit 0
endef

$(eval $(call BuildPackage,wi-fi-qr))
