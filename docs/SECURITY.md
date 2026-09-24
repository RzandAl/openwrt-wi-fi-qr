# Security model

Wi-Fi QR codes contain network credentials. This project keeps generation on
the router and does not send SSIDs, passwords, or SVGs to an external QR
service.

## LuCI rendering

The LuCI integration renders QR codes on demand through the authenticated
`luci.wifi-qr` RPCd object and a dedicated ACL.

The catalog method returns only committed UCI section names, SSIDs, and
canonical QR tokens; it never returns keys or complete Wi-Fi payloads. This
keeps browser-session changes from altering QR identities before they are
applied.

The SVG method accepts only a restricted ASCII token. The renderer verifies
the canonical interface index, band tag, and safe SSID against the committed
UCI configuration before returning an SVG. It does not expose a public
`/cgi-bin/wi-fi-qr` endpoint or write on-demand LuCI images below `/www`.

The browser receives the SVG through the authenticated LuCI session and keeps
it in a temporary `blob:` URL within the current tab.

## Credential handling

Wi-Fi payloads are passed to `qrencode` through standard input, so SSIDs and
passwords do not appear in its process arguments. Text embedded in SVG labels
is XML-escaped, and invalid XML 1.0 control characters are removed.

Unsupported enterprise encryption and password-based interfaces without a
usable key are skipped rather than represented as a different security mode.

## Persistent CLI output

Files created explicitly by `wi-fi-qr --gen` are intentionally persistent and
served from `/www/wi-fi-qr`. Any client able to reach those URLs may be able to
read the encoded Wi-Fi credentials.

Use the authenticated LuCI previews when persistent public files are not
needed. Remove CLI-generated files after use with:

```sh
wi-fi-qr --del
```

Access to LuCI, the router filesystem, or the generated public path remains
part of the router administrator's security boundary.
