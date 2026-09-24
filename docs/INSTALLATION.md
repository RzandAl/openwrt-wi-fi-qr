# Build and installation

The repository contains OpenWrt package sources. Prebuilt packages for
[v1.0.0](https://github.com/RzandAl/openwrt-wi-fi-qr/releases/tag/v1.0.0)
are published with a `SHA256SUMS` file.

## Requirements

- an official OpenWrt SDK matching the target release and architecture;
- the SDK feeds required by `luci-base`, `qrencode`, and `uci`;
- a Linux build host with the tools required by the OpenWrt SDK.

The current development target is OpenWrt 25.12.5 with APK. The packages are
architecture-independent (`noarch`), but their dependencies are resolved for
the selected SDK target.

## Build from source

1. Download and unpack the official OpenWrt 25.12.5 SDK for the target.
2. Clone this repository outside or inside the SDK.
3. Update and install the configured feeds if needed:

   ```sh
   ./scripts/feeds update -a
   ./scripts/feeds install -a
   ```

4. Link the two package directories into the SDK:

   ```sh
   REPO=/absolute/path/to/openwrt-wi-fi-qr
   ln -s "$REPO/wi-fi-qr" package/wi-fi-qr
   ln -s "$REPO/luci-app-wi-fi-qr" package/luci-app-wi-fi-qr
   ```

5. Prepare the SDK configuration and build both packages:

   ```sh
   make defconfig
   make package/wi-fi-qr/clean package/wi-fi-qr/compile V=s
   make package/luci-app-wi-fi-qr/clean \
        package/luci-app-wi-fi-qr/compile V=s
   ```

The APKs are written below `bin/packages/*/base/`.

## Download a release

Download both APKs and `SHA256SUMS` from the
[v1.0.0 release](https://github.com/RzandAl/openwrt-wi-fi-qr/releases/tag/v1.0.0),
then verify them before copying anything to the router:

```sh
sha256sum -c SHA256SUMS
```

The release APKs are intentionally unsigned. A successful checksum verification
is required before installing them with `--allow-untrusted`.

## Copy to the router

Copy both APKs to a temporary directory on the router. For example:

```sh
scp wi-fi-qr-1.0.0-r1.apk \
    luci-app-wi-fi-qr-1.0.0-r1.apk \
    root@192.168.1.1:/tmp/
```

## Install

Install the base package first, followed by the LuCI integration:

```sh
apk add --allow-untrusted /tmp/wi-fi-qr-1.0.0-r1.apk
apk add --allow-untrusted /tmp/luci-app-wi-fi-qr-1.0.0-r1.apk
```

`--allow-untrusted` is required for locally built APKs that are not signed by
a key trusted by the router. Refresh LuCI after installation; a router reboot
is not required.

## Verify

```sh
apk list --installed wi-fi-qr
apk list --installed luci-app-wi-fi-qr
ubus -v list luci.wifi-qr
wi-fi-qr --list
```

Then verify both supported LuCI pages, open and close the larger QR modal, and
refresh the page once to confirm that controls are not duplicated. Under
**Network → Wireless → Edit → Wireless Security**, LuCI's built-in
**Generate QR…** control should be hidden immediately, including for disabled
or unsupported networks. It should reappear only if the catalog request or a
matching custom SVG render fails.

## Upgrade

Install newer APKs with the same `apk add --allow-untrusted` commands. APK runs
the package upgrade hooks and replaces the marked LuCI asset block atomically.

When validating a deliberately clean installation or a change to package
lifecycle hooks, remove the existing LuCI package before installing the new
one. This also verifies that the built-in LuCI QR control is restored.

## Uninstall

Remove the LuCI integration before the base package:

```sh
apk del luci-app-wi-fi-qr
apk del wi-fi-qr
```

The package hooks remove generated project QR files, clean empty project
directories, remove the LuCI footer block, and reload RPCd. Unrelated files
are left untouched.
