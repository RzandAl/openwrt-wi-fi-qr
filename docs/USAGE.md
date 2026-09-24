# Usage

## Command line

```text
wi-fi-qr --gen    Generate QR files for the current enabled networks
wi-fi-qr --list   List valid QR files already present on disk
wi-fi-qr --del    Delete generated QR files
```

### Generate

```sh
wi-fi-qr --gen
```

The command reads enabled `wifi-iface` sections from UCI. It skips disabled
radios, disabled interfaces, interfaces without an SSID, unsupported
enterprise configurations, and password-based networks without a usable key.

OpenWrt security settings are mapped to Wi-Fi QR fields as follows:

| OpenWrt configuration | QR fields |
| --- | --- |
| WPA/WPA2-PSK | `T:WPA` |
| WPA3-SAE | `T:WPA;R:0` |
| WPA2-PSK/WPA3-SAE mixed mode | `T:WPA` |
| Enhanced Open (OWE) | `T:nopass;R:3` |
| Open network | `T:nopass` |
| WEP | `T:WEP` |

A hidden network also receives `H:true`. For WEP, the selected key slot is
resolved before the payload is generated.

Example payloads:

```text
WIFI:T:WPA;S:<ssid>;P:<password>;;
WIFI:T:nopass;S:<ssid>;;
WIFI:T:WPA;S:<hidden-ssid>;H:true;P:<password>;;
WIFI:T:WPA;R:0;S:<wpa3-ssid>;P:<password>;;
```

Interfaces with an identical effective payload share one QR. The first
matching `wifi-iface` in UCI order supplies the canonical index, while all
detected bands are included in the filename and caption.

Generated files use this form:

```text
/www/wi-fi-qr/id<index>_<band-tag>_<safe-ssid>.svg
```

For example:

```text
/www/wi-fi-qr/id0_5GHz_MainWiFi.svg
/www/wi-fi-qr/id1_2.4GHz_Guest_WiFi.svg
/www/wi-fi-qr/id2_2.4-5GHz_SharedNetwork.svg
```

If the LAN address is available from UCI, `--gen` and `--list` also display a
browser URL. A CIDR suffix such as `/24` is removed from the host portion.

New SVGs are written to a temporary staging directory first. The existing set
is replaced only after every QR has been generated successfully. A subsequent
command also cleans stale staging directories left by an interrupted run. If
UCI is read successfully but contains no supported enabled networks, the
successfully published result is an empty set and old project SVGs are
removed. If UCI cannot be read, the previous set is preserved and the command
fails.

### List

```sh
wi-fi-qr --list
```

The command lists valid generated files. When the current UCI configuration is
available, safe filename components are mapped back to readable SSIDs and QR
authentication types.

### Delete

```sh
wi-fi-qr --del
```

The command removes matching `id*_*.svg` files, stale `*.svg.tmp` artifacts,
and project QR files left in staging directories. Unrelated files are
preserved.

## LuCI

The LuCI package augments existing pages instead of adding a separate menu
entry:

- **Status → Overview → Wireless** receives compact QR previews;
- **Network → Wireless** receives medium QR previews.

Left click opens the QR in a native LuCI modal. The modal closes by clicking
the backdrop or pressing Escape. Modified and middle clicks retain normal
browser link behaviour.

The frontend loads each SVG through the authenticated `luci.wifi-qr` RPCd
object and keeps it in a temporary `blob:` URL within the current browser tab.
It obtains QR identities from a committed server-side UCI catalog, so pending
LuCI edits, deletions, and reordering do not make previews disappear or point
at a different network. Until **Save & Apply** completes, previews continue to
represent the currently applied configuration.

Under **Network → Wireless → Edit → Wireless Security**, the built-in
**Generate QR…** control is suppressed from the first rendered frame. The
built-in implementation is neither deleted nor modified. Disabled and
unsupported networks remain suppressed after a successful catalog response.
The control is exposed only if the catalog request or a matching custom SVG
render fails; removing the LuCI package exposes it again.

To augment both existing pages without replacing LuCI's upstream view files or
modifying a theme, the package loads its versioned JavaScript and CSS through
LuCI's common `footer.ut`. This file belongs to `luci-base`, making the footer
hook the integration's one target-version-sensitive seam.

The installer changes only the OpenWrt 25.12.5 common-footer layout it expects,
uses a marked block and an atomic temporary-file replacement, and never edits a
theme-specific footer. Upgrades replace exactly one valid block. Removal
deletes exactly one valid block. An unexpected anchor or malformed marker
layout is left unchanged.
