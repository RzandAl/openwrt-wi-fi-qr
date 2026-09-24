#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(dirname -- "$SCRIPT_DIR")"
LUCI_DIR="$PROJECT_DIR/luci-app-wi-fi-qr"
JS="$LUCI_DIR/htdocs/luci-static/resources/wi-fi-qr.js"
CSS="$LUCI_DIR/htdocs/luci-static/resources/wi-fi-qr.css"

fail() {
  printf '%s\n' "test-native-luci-ui: $*" >&2
  exit 1
}

grep -Fq "L.require('ui')" "$JS" \
  || fail 'frontend does not load LuCI ui'
grep -Fq "luciUi.showModal(null, [ content, actions ], 'wifi-qr-modal')" "$JS" \
  || fail 'large QR does not use LuCI showModal'
grep -Fq "close.className = 'btn cbi-button';" "$JS" \
  || fail 'QR modal close action is not a native LuCI button'
grep -Fq 'actions.hidden = true;' "$JS" \
  || fail 'QR modal close action is still visible'
grep -Fq 'if (ev.target === overlay)' "$JS" \
  || fail 'QR modal does not close from the LuCI backdrop'
grep -Fq '#modal_overlay > .modal.wifi-qr-modal {' "$CSS" \
  || fail 'QR modal is not scoped to LuCI modal markup'
grep -Fq 'padding: 2px !important;' "$CSS" \
  || fail 'QR modal does not retain its compact card spacing'
grep -Fq 'min-width: 0;' "$CSS" \
  || fail 'QR modal still inherits LuCI minimum width'
grep -Fq "link.className = 'btn wifi-qr-link wifi-qr-link-small';" "$JS" \
  || fail 'compact QR does not inherit native LuCI button feedback'
grep -Fq "link.className = 'btn wifi-qr-link wifi-qr-link-medium';" "$JS" \
  || fail 'medium QR does not inherit native LuCI button feedback'
grep -Fq 'display: inline-flex;' "$CSS" \
  || fail 'QR button contents are not flex-centered'
grep -Fq 'justify-content: center;' "$CSS" \
  || fail 'QR button contents are not horizontally centered'
grep -Fq 'overflow: hidden;' "$CSS" \
  || fail 'QR image is not clipped to the native LuCI button radius'
grep -Fq 'width: 30px !important;' "$CSS" \
  || fail 'compact QR does not preserve the two-pixel signal-icon reserve'
grep -Fq 'padding: 3px;' "$CSS" \
  || fail 'compact QR artwork does not retain its inset'
grep -Fq 'margin-top: -1px;' "$CSS" \
  || fail 'compact QR vertical alignment regressed'
grep -Fq "qrNode.style.setProperty('width', (w - 2) + 'px', 'important');" "$JS" \
  || fail 'runtime compact QR sizing does not preserve the two-pixel reserve'
grep -Fq "qrNode.style.height = (h - 2) + 'px';" "$JS" \
  || fail 'runtime compact QR height does not preserve the two-pixel reserve'
grep -Fq "link.classList.add('wifi-qr-link-initial');" "$JS" \
  || fail 'new QR links do not suppress the replacement-frame transition'
grep -Fq "link.classList.remove('wifi-qr-link-initial');" "$JS" \
  || fail 'native LuCI transitions are not restored after the first paint'
grep -Fq 'window.requestAnimationFrame(callback);' "$JS" \
  || fail 'QR transition restoration is not synchronized with browser paint'
grep -Fq '.wifi-qr-link.wifi-qr-link-initial {' "$CSS" \
  || fail 'replacement-frame transition guard is missing from CSS'
grep -Fq 'transition: none;' "$CSS" \
  || fail 'replacement QR links still animate from an unhighlighted state'

if grep -Eq '#wifi-qr-overlay|wifi-qr-overlay-inner|#74B8EF|rgba\(116,[[:space:]]*184,[[:space:]]*239|outline:[[:space:]]*none' "$CSS"; then
  fail 'legacy custom overlay or hard-coded focus treatment remains in CSS'
fi

grep -Fq 'Reuse LuCI' "$CSS" \
  || fail 'native LuCI control styling invariant is undocumented'

printf '%s\n' 'test-native-luci-ui: ok'
