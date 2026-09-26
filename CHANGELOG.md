# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.0.0] - 2026-09-24

### Added

- Architecture-independent `wi-fi-qr` and `luci-app-wi-fi-qr` APK packages
  for OpenWrt 25.12.5.
- A CLI for generating, listing, and deleting persistent Wi-Fi QR SVG files.
- LuCI QR previews in `Network → Wireless` and `Status → Overview`, with a
  native modal for larger previews.
- Authenticated RPCd catalog access and on-demand SVG rendering.
- Support for WPA/WPA2-PSK, WPA3-SAE, mixed WPA2/WPA3, OWE, open networks,
  selected WEP key slots, and hidden SSIDs.
- Atomic SVG publication that preserves the previous set if generation or UCI
  access fails.
- First-frame suppression of LuCI's built-in QR control, including for disabled
  and unsupported networks.
- Automated coverage for payloads, CLI behavior, SVG escaping, package layout,
  lifecycle hooks, LuCI integration, and RPC security.

### Security

- Local-only QR generation; SSIDs and credentials are not sent to external
  services.
- ACL-restricted RPC methods, validated catalog tokens, and escaped SVG output.

[Unreleased]: https://github.com/RzandAl/openwrt-wi-fi-qr/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/RzandAl/openwrt-wi-fi-qr/releases/tag/v1.0.0
