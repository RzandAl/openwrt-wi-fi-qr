#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LUCI_PACKAGE_DIR="${LUCI_PACKAGE_DIR:-$ROOT_DIR/luci-app-wi-fi-qr}"
JS="$LUCI_PACKAGE_DIR/htdocs/luci-static/resources/wi-fi-qr.js"
CSS="$LUCI_PACKAGE_DIR/htdocs/luci-static/resources/wi-fi-qr.css"

fail() {
	printf '%s\n' "test-stock-qr-hiding: $*" >&2
	exit 1
}

[ -f "$JS" ] || fail "missing $JS"
[ -f "$CSS" ] || fail "missing $CSS"

grep -Fq "var options = document.querySelectorAll('.cbi-value[data-name=\"_qrops\"]');" "$JS" \
	|| fail 'stock QR selector does not use the LuCI _qrops option name'

grep -Fq "option.classList.add('wifi-qr-stock-hidden');" "$JS" \
	|| fail 'stock QR row is not assigned the project-owned hiding class'

grep -Fq "document.documentElement.classList.add('wifi-qr-stock-managed');" "$JS" \
    || fail 'wireless page is not marked for first-frame stock QR suppression'

grep -Fq "option.classList.add('wifi-qr-stock-fallback');" "$JS" \
    || fail 'stock QR fallback is not explicitly opted into CSS rendering'

grep -Fq 'customQrStateByToken = Object.create(null),' "$JS" \
    || fail 'per-network custom QR state map is missing'

grep -Fq "customQrStateByToken[token] = 'pending';" "$JS" \
    || fail 'custom QR requests are not marked pending before image loading'

grep -Fq "customQrStateByToken[token] = 'ready';" "$JS" \
    || fail 'successful custom QR loading does not mark its network ready'

grep -Fq "customQrStateByToken[token] = 'failed';" "$JS" \
    || fail 'failed custom QR loading does not enable the stock fallback'

grep -Fq "option.closest('[data-section-id]')" "$JS" \
    || fail 'stock QR hiding is not scoped to the active UCI section'

grep -Fq "qrCatalogState === 'pending'" "$JS" \
    || fail 'stock QR is not hidden while the committed catalog loads'

grep -Fq "state !== 'failed'" "$JS" \
    || fail 'stock QR is exposed before a custom SVG has explicitly failed'

grep -Fq "(!entry || state !== 'failed')" "$JS" \
    || fail 'successful catalog omissions expose the stock QR control'

grep -Fq 'var uncommitted = !hasWirelessOverviewRow(sid);' "$JS" \
    || fail 'browser-only Add/Join sections are not detected'

grep -Fq "option.classList.remove('wifi-qr-stock-hidden');" "$JS" \
    || fail 'stock QR fallback is not restored for an unavailable custom QR'

grep -Fq '.cbi-value[data-name="_qrops"].wifi-qr-stock-hidden {' "$CSS" \
	|| fail 'missing scoped CSS rule for the stock QR row'

grep -Fq 'html.wifi-qr-stock-managed .cbi-value[data-name="_qrops"]:not(.wifi-qr-stock-fallback),' "$CSS" \
    || fail 'missing first-frame CSS suppression for stock QR controls'

rule_line="$(grep -nF '.cbi-value[data-name="_qrops"].wifi-qr-stock-hidden {' "$CSS" | cut -d: -f1)"
display_line="$(awk -v start="$rule_line" 'NR > start && NR <= start + 3 && /display:[[:space:]]*none[[:space:]]*!important/ { print NR; exit }' "$CSS")"
[ -n "$display_line" ] || fail 'stock QR hiding rule does not set display: none !important'

pending_line="$(grep -nF '        markCustomQrPending(token);' "$JS" | cut -d: -f1)"
load_listener_line="$(grep -nF "img.addEventListener('load'" "$JS" | cut -d: -f1)"

[ -n "$pending_line" ] && [ -n "$load_listener_line" ] \
    || fail 'could not locate pre-load custom QR state handling'
[ "$pending_line" -lt "$load_listener_line" ] \
    || fail 'custom QR is not marked pending before image loading begins'

observer_start_line="$(grep -nF '        startQrObserver(onWireless, onStatus);' "$JS" | cut -d: -f1)"
catalog_start_line="$(grep -nF '        buildWifiCatalog(function() {' "$JS" | cut -d: -f1)"

[ -n "$observer_start_line" ] && [ -n "$catalog_start_line" ] \
    || fail 'could not locate observer/catalog initialization order'
[ "$observer_start_line" -lt "$catalog_start_line" ] \
    || fail 'modal observer starts only after the catalog RPC'

observer_calls="$(grep -Fc '            hideStockQrOptions();' "$JS")"
[ "$observer_calls" -ge 2 ] \
	|| fail 'stock QR hiding is not reapplied when LuCI inserts modal DOM'

if command -v node >/dev/null 2>&1; then
  node - "$JS" <<'EOF' \
    || fail 'stock QR state regression test failed'
const fs = require('fs');
const vm = require('vm');
const path = process.argv[2];
const source = fs.readFileSync(path, 'utf8');
const instrumented = source.replace(
    /\n\}\)\(\);\s*$/,
    `
    globalThis.__stockQrTest = {
        setCatalog(state, entries) {
            qrCatalogState = state;
            wifiEntryBySid = entries;
        },
        hide: hideStockQrOptions,
        pending: markCustomQrPending,
        ready: markCustomQrReady,
        failed: markCustomQrFailed
    };
})();
`
);

if (instrumented === source)
    throw new Error('could not expose stock QR helpers');

let options = [];
let rowSids = [];
const rootClasses = new Set();

function makeOption(sid) {
    const classes = new Set();

    return {
        classes,
        classList: {
            add(name) { classes.add(name); },
            remove(name) { classes.delete(name); }
        },
        closest() {
            if (sid == null)
                return null;

            return { getAttribute() { return sid; } };
        }
    };
}

const context = {
    window: { addEventListener() {}, MutationObserver: function() {} },
    location: { pathname: '/cgi-bin/luci/admin/network/wireless' },
    document: {
        documentElement: {
            classList: {
                add(name) { rootClasses.add(name); }
            }
        },
        readyState: 'loading',
        addEventListener() {},
        querySelectorAll(selector) {
            if (selector === '.cbi-value[data-name="_qrops"]')
                return options;

            if (selector === '.cbi-section-table-row[data-sid]')
                return rowSids.map(sid => ({ getAttribute() { return sid; } }));

            return [];
        }
    }
};

vm.runInNewContext(instrumented, context);
const test = context.__stockQrTest;
const hidden = 'wifi-qr-stock-hidden';
const fallback = 'wifi-qr-stock-fallback';
const entry = { sid: 'wifi0', ssid: 'MainNet', token: 'id0_MainNet.svg' };

if (!rootClasses.has('wifi-qr-stock-managed'))
    throw new Error('wireless page lacks its first-frame CSS marker');

rowSids = [ 'wifi0' ];
options = [ makeOption('wifi0') ];
test.setCatalog('pending', null);
test.hide();
if (!options[0].classes.has(hidden) || options[0].classes.has(fallback))
    throw new Error('stock QR flashes while the catalog is pending');

test.setCatalog('ready', { wifi0: entry });
options = [ makeOption('wifi0') ];
test.hide();
if (!options[0].classes.has(hidden) || options[0].classes.has(fallback))
    throw new Error('stock QR flashes before custom SVG loading starts');

test.pending(entry.token);
if (!options[0].classes.has(hidden) || options[0].classes.has(fallback))
    throw new Error('stock QR is visible while custom SVG is loading');

test.failed(entry.token);
if (options[0].classes.has(hidden) || !options[0].classes.has(fallback))
    throw new Error('stock fallback was not restored after SVG failure');

rowSids = [ 'wifi0' ];
options = [ makeOption('wifinet1') ];
test.setCatalog('ready', { wifi0: entry });
test.hide();
if (!options[0].classes.has(hidden) || options[0].classes.has(fallback))
    throw new Error('new browser-only Wi-Fi section exposes a stock QR');

rowSids = [ 'wifi0', 'wifi2' ];
options = [ makeOption('wifi2') ];
test.hide();
if (!options[0].classes.has(hidden) || options[0].classes.has(fallback))
    throw new Error('disabled or unsupported network exposes a stock QR');

test.setCatalog('failed', null);
test.hide();
if (options[0].classes.has(hidden) || !options[0].classes.has(fallback))
    throw new Error('committed network fallback stayed hidden after catalog failure');

rowSids = [ 'wifi0' ];
options = [ makeOption(null) ];
test.hide();
if (!options[0].classes.has(hidden) || options[0].classes.has(fallback))
    throw new Error('sectionless Add/Join modal exposes a stock QR');
EOF
fi

printf '%s\n' 'test-stock-qr-hiding: ok'
