(function() {
    'use strict';

    // Inject Wi-Fi QR controls into LuCI without modifying LuCI's own sources.

    var isWirelessPage = /\/admin\/network\/wireless/.test(location.pathname);

    // Mark the page before a modal can be opened, allowing CSS to suppress the
    // stock QR on its very first frame. JavaScript later opts real fallbacks in.
    if (isWirelessPage && document.documentElement && window.MutationObserver)
        document.documentElement.classList.add('wifi-qr-stock-managed');

    var wifiEntryBySid     = null,
        wifiEntriesBySsid  = null,
        luciUi             = null;

    // SVG content is fetched through authenticated RPC and exposed only as
    // browser-local blob URLs, never as a public web path.
    var callGetQrCatalog = null,
        callGetQrSvg = null,
        qrUrlPromises = Object.create(null),
        qrObjectUrls = [],
        customQrStateByToken = Object.create(null),
        qrCatalogState = 'pending';

    function hasWirelessOverviewRow(sid) {
        if (!sid)
            return false;

        var rows = document.querySelectorAll('.cbi-section-table-row[data-sid]');

        for (var i = 0; i < rows.length; i++) {
            if (rows[i].getAttribute('data-sid') === sid)
                return true;
        }

        return false;
    }

    // Hide LuCI's stock control before the first paint. Restore it only when
    // the catalog itself fails, or when a catalogued network's custom SVG
    // fails. A successful catalog omission means that the network is disabled
    // or unsupported, while a missing overview row denotes browser-only Add.
    function hideStockQrOptions() {
        if (!isWirelessPage)
            return;

        var options = document.querySelectorAll('.cbi-value[data-name="_qrops"]');

        options.forEach(function(option) {
            var section = option.closest('[data-section-id]');
            var sid = section && section.getAttribute('data-section-id');
            var entry = wifiEntryBySid && sid && wifiEntryBySid[sid];
            var state = entry && customQrStateByToken[entry.token];
            var uncommitted = !hasWirelessOverviewRow(sid);

            if (qrCatalogState === 'pending' ||
                uncommitted ||
                (qrCatalogState === 'ready' &&
                 (!entry || state !== 'failed'))) {
                option.classList.add('wifi-qr-stock-hidden');
                option.classList.remove('wifi-qr-stock-fallback');
            }
            else {
                option.classList.remove('wifi-qr-stock-hidden');
                option.classList.add('wifi-qr-stock-fallback');
            }
        });
    }

    function markCustomQrPending(token) {
        if (!token || customQrStateByToken[token] === 'pending' ||
            customQrStateByToken[token] === 'ready')
            return;

        customQrStateByToken[token] = 'pending';
        hideStockQrOptions();
    }

    function markCustomQrReady(token) {
        if (!token || customQrStateByToken[token] === 'ready')
            return;

        customQrStateByToken[token] = 'ready';
        hideStockQrOptions();
    }

    function markCustomQrFailed(token) {
        if (!token || customQrStateByToken[token] === 'failed')
            return;

        customQrStateByToken[token] = 'failed';
        hideStockQrOptions();
    }

    function loadQrUrl(token) {
        if (!callGetQrSvg)
            return Promise.reject(new Error('Wi-Fi QR RPC is unavailable'));

        if (qrUrlPromises[token])
            return qrUrlPromises[token];

        qrUrlPromises[token] = callGetQrSvg(token).then(function(svg) {
            if (typeof svg !== 'string' || !svg.length)
                throw new Error('Wi-Fi QR RPC returned an empty SVG');

            var url = URL.createObjectURL(new Blob([svg], {
                type: 'image/svg+xml'
            }));

            qrObjectUrls.push(url);
            return url;
        }).catch(function(err) {
            delete qrUrlPromises[token];
            throw err;
        });

        return qrUrlPromises[token];
    }

    window.addEventListener('beforeunload', function() {
        for (var i = 0; i < qrObjectUrls.length; i++)
            URL.revokeObjectURL(qrObjectUrls[i]);

        qrObjectUrls = [];
        qrUrlPromises = Object.create(null);
    });

    function showQrModal(src, ssid) {
        if (!luciUi)
            return false;

        var label = ssid ? 'QR "' + ssid + '"' : 'QR';

        var img = document.createElement('img');
        img.className = 'wifi-qr-img wifi-qr-img-large';
        img.src = src;
        img.alt = label;

        var content = document.createElement('div');
        content.className = 'wifi-qr-modal-content';
        content.appendChild(img);

        var close = document.createElement('button');
        close.type = 'button';
        close.className = 'btn cbi-button';
        close.textContent = (typeof _ === 'function') ? _('Close') : 'Close';

        var actions = document.createElement('div');
        actions.className = 'right wifi-qr-modal-actions';
        actions.hidden = true;
        actions.appendChild(close);

        var dlg = luciUi.showModal(null, [ content, actions ], 'wifi-qr-modal');
        var overlay = dlg.parentNode;

        dlg.setAttribute('aria-label', label);

        function dismissModal() {
            overlay.removeEventListener('click', dismissOnBackdrop);
            luciUi.hideModal();
        }

        function dismissOnBackdrop(ev) {
            if (ev.target === overlay)
                close.click();
        }

        close.addEventListener('click', dismissModal);
        overlay.addEventListener('click', dismissOnBackdrop);

        return true;
    }

    function extractSsidFromLabelNode(labelNode) {
        if (!labelNode)
            return null;

        var n = labelNode.nextSibling;

        while (n && n.nodeType === 3 && !(n.textContent || '').trim())
            n = n.nextSibling;

        if (!n)
            return null;

        var text = (n.textContent || '').trim();
        return text || null;
    }

    function normalizeSsidKey(ssid) {
        // Match browser-rendered whitespace while retaining the committed raw
        // UCI value in the catalog entry used for labels and rendering.
        var s = String(ssid || '');
        s = s.replace(/\s+/g, ' ');
        return s.trim();
    }

    function restoreQrLinkTransition(link) {
        var nextFrame = function(callback) {
            if (typeof window.requestAnimationFrame === 'function')
                window.requestAnimationFrame(callback);
            else
                window.setTimeout(callback, 0);
        };

        // LuCI replaces status widgets while polling. Keep the native :hover
        // state, but skip its transition for the replacement's first paint so
        // the highlight does not visibly disappear and return under the cursor.
        nextFrame(function() {
            nextFrame(function() {
                link.classList.remove('wifi-qr-link-initial');
            });
        });
    }

    function createQrImg(ssid, compact, token) {
        var link = document.createElement('a');
        var img  = document.createElement('img');

        img.setAttribute('data-wifi-qr', '1');
        img.setAttribute('data-ssid', ssid);
        img.setAttribute('data-token', token);

        if (compact) {
            img.className = 'wifi-qr-img wifi-qr-img-small';
            link.className = 'btn wifi-qr-link wifi-qr-link-small';
        }
        else {
            img.className = 'wifi-qr-img wifi-qr-img-medium';
            link.className = 'btn wifi-qr-link wifi-qr-link-medium';
        }

        link.classList.add('wifi-qr-link-initial');

        var label = 'QR "' + ssid + '"';
        var svgUrl = null;

        img.alt   = label;
        img.title = label;

        link.setAttribute('aria-label', label);
        link.hidden = true;
        link.appendChild(img);

        markCustomQrPending(token);

        img.addEventListener('load', function() {
            markCustomQrReady(token);
        });

        img.addEventListener('error', function() {
            link.hidden = true;
            markCustomQrFailed(token);
        });

        loadQrUrl(token).then(function(url) {
            svgUrl = url;
            img.src = url;
            link.href = url;
            link.hidden = false;
            restoreQrLinkTransition(link);
        }).catch(function() {
            link.hidden = true;
            markCustomQrFailed(token);
        });

        link.addEventListener('click', function(ev) {
            if (ev.button !== 0)
                return;

            if (svgUrl && (ev.ctrlKey || ev.metaKey || ev.shiftKey || ev.altKey))
                return;

            if (!luciUi)
                return;

            ev.preventDefault();

            loadQrUrl(token).then(function(url) {
                showQrModal(url, ssid);
            }).catch(function() {
            });
        });

        return link;
    }

    function addQrToWirelessOverview() {
        // Network -> Wireless rows carry stable UCI section identifiers.
        if (!/\/admin\/network\/wireless/.test(location.pathname))
            return;

        if (!wifiEntryBySid ||
            !Object.keys(wifiEntryBySid).length)
            return;

        var rows = document.querySelectorAll('.cbi-section-table-row[data-sid]');

        rows.forEach(function (tr) {
            var sid = tr.getAttribute('data-sid') || '';

            if (/^radio/.test(sid))
                return;

            var entry = null;
            if (Object.prototype.hasOwnProperty.call(wifiEntryBySid, sid))
                entry = wifiEntryBySid[sid];

            if (!entry)
                return;

            var infoCell = tr.querySelector('td[data-name="_stat"]') || (tr.cells && tr.cells[1]);
            if (!infoCell)
                return;

            var wrap = infoCell.querySelector('.wifi-qr-wrap');
            var ssid = entry.ssid;
            var token = entry.token;

            var qrNode;

            if (!wrap) {
                var originalHTML = infoCell.innerHTML;

                wrap = document.createElement('div');
                wrap.className = 'wifi-qr-wrap';

                var textDiv = document.createElement('div');
                textDiv.innerHTML = originalHTML;

                qrNode = createQrImg(ssid, false, token);

                wrap.appendChild(textDiv);
                wrap.appendChild(qrNode);

                infoCell.innerHTML = '';
                infoCell.appendChild(wrap);
            }
            else {
                var existingImg  = wrap.querySelector('img[data-wifi-qr="1"]');

                if (!existingImg) {
                    qrNode = createQrImg(ssid, false, token);
                    wrap.appendChild(qrNode);
                }
                else {
                    var cur = existingImg.getAttribute('data-ssid') || '';
                    var curToken = existingImg.getAttribute('data-token') || '';
                    if (cur !== ssid || curToken !== token) {
                        var oldNode = existingImg.parentNode;
                        var newNode = createQrImg(ssid, false, token);
                        if (oldNode && oldNode.parentNode)
                            oldNode.parentNode.replaceChild(newNode, oldNode);
                    }
                }
            }
        });
    }

    function addQrToStatusWireless() {
        // Status cards lack section identifiers, so duplicate SSIDs are matched
        // to committed catalog entries in DOM order.
        if (!wifiEntriesBySsid ||
            !Object.keys(wifiEntriesBySsid).length)
            return;

        var boxes = document.querySelectorAll('.ifacebox');

        var ssidPos = Object.create(null);

        boxes.forEach(function (box) {
            var badges = box.querySelectorAll('.ifacebadge');

            badges.forEach(function (badge) {
                var spans = badge.querySelectorAll('span');
                var labelSpan = null;

                for (var i = 0; i < spans.length; i++) {
                    if (spans[i].querySelector('strong')) {
                        labelSpan = spans[i];
                        break;
                    }
                }

                if (!labelSpan)
                    return;

                var labels = labelSpan.querySelectorAll('strong');

                var existingQr = badge.querySelector('img[data-wifi-qr="1"]');

                if (labels.length < 3) {
                    if (existingQr && existingQr.parentNode) {
                        var qrWrapper = existingQr.parentNode;
                        if (qrWrapper && qrWrapper.parentNode) {
                            qrWrapper.parentNode.removeChild(qrWrapper);
                        }
                    }
                    return;
                }

                var signalImg = badge.querySelector('img:not([data-wifi-qr])');
                if (!signalImg)
                    return;

                var src = signalImg.getAttribute('src') || '';

                if (src.indexOf('signal-') === -1)
                    return;

                var lbl = labels[0];
                var ssid = extractSsidFromLabelNode(lbl);

                if (!ssid)
                    return;

                var entry = null;
                var ssidKey = normalizeSsidKey(ssid);
                var list    = wifiEntriesBySsid[ssidKey];
                if (list && list.length) {
                    var pos  = ssidPos[ssidKey] || 0;  // 0,1,2,...
                    ssidPos[ssidKey] = pos + 1;

                    if (pos < list.length)
                        entry = list[pos];
                    else
                        entry = list[list.length - 1];
                }

                if (!entry)
                    return;

                if (existingQr) {
                    var curSsid = existingQr.getAttribute('data-ssid') || '';
                    var curToken = existingQr.getAttribute('data-token') || '';
                    if (curSsid === entry.ssid && curToken === entry.token)
                        return;
                }

                var iconWrap = badge.querySelector('.wifi-qr-icon-wrap');
                if (!iconWrap) {
                    iconWrap = document.createElement('span');
                    iconWrap.className = 'wifi-qr-icon-wrap';

                    badge.insertBefore(iconWrap, badge.firstChild);
                }

                if (signalImg.parentNode !== iconWrap)
                    iconWrap.insertBefore(signalImg, iconWrap.firstChild);

                var qrNode = createQrImg(entry.ssid, true, entry.token);

                var cs = window.getComputedStyle(signalImg);
                if (cs) {
                    var w = parseFloat(cs.width)  || 0;
                    var h = parseFloat(cs.height) || 0;

                    if (w > 2)
                        qrNode.style.setProperty('width', (w - 2) + 'px', 'important');
                    if (h > 2)
                        qrNode.style.height = (h - 2) + 'px';
                }

                if (existingQr && existingQr.parentNode) {
                    var oldNode = existingQr.parentNode;
                    if (oldNode && oldNode.parentNode)
                        oldNode.parentNode.replaceChild(qrNode, oldNode);
                }
                else {
                    iconWrap.appendChild(qrNode);
                }
            });
        });
    }

    function startQrObserver(onWireless, onStatus) {
        // LuCI creates wireless dialogs dynamically; reapply idempotent DOM
        // changes whenever it inserts new nodes.
        if (onWireless) {
            addQrToWirelessOverview();
            hideStockQrOptions();
        }
        if (onStatus)
            addQrToStatusWireless();

        var target = document.body;
        if (!window.MutationObserver)
            return;

        var observer = new MutationObserver(function(mutations) {
            for (var i = 0; i < mutations.length; i++) {
                if (mutations[i].type === 'childList') {
                    if (onWireless) {
                        addQrToWirelessOverview();
                        hideStockQrOptions();
                    }
                    if (onStatus)
                        addQrToStatusWireless();
                    break;
                }
            }
        });

        observer.observe(target, { childList: true, subtree: true });
    }

    function indexWifiCatalog(networks) {
        var bySid      = Object.create(null);
        var bySsid     = Object.create(null);
        var seenBySsid = Object.create(null);

        if (!Array.isArray(networks))
            networks = [];

        for (var i = 0; i < networks.length; i++) {
            var network = networks[i];

            if (!network || typeof network !== 'object')
                continue;

            var sid   = network.sid;
            var ssid  = network.ssid;
            var token = network.token;

            if (typeof sid !== 'string' || !sid.length ||
                typeof ssid !== 'string' || !ssid.length ||
                typeof token !== 'string' || token.length > 256 ||
                !/^id[0-9]+_[A-Za-z0-9._-]+\.svg$/.test(token))
                continue;

            var ssidKey = normalizeSsidKey(ssid);
            if (!ssidKey)
                continue;

            var entry = {
                sid: sid,
                ssid: ssid,
                token: token
            };

            bySid[sid] = entry;

            if (!bySsid[ssidKey]) {
                bySsid[ssidKey] = [];
                seenBySsid[ssidKey] = Object.create(null);
            }

            if (!seenBySsid[ssidKey][token]) {
                seenBySsid[ssidKey][token] = true;
                bySsid[ssidKey].push(entry);
            }
        }

        return {
            bySid: bySid,
            bySsid: bySsid
        };
    }

    function buildWifiCatalog(done) {
        if (!window.L || typeof L.require !== 'function') {
            qrCatalogState = 'failed';
            done();
            return;
        }

        Promise.all([
            L.require('rpc'),
            L.require('ui')
        ]).then(function(modules) {
            var rpc = modules[0];
            luciUi = modules[1];

            callGetQrCatalog = rpc.declare({
                object: 'luci.wifi-qr',
                method: 'get_catalog',
                expect: { networks: [] },
                reject: true
            });

            callGetQrSvg = rpc.declare({
                object: 'luci.wifi-qr',
                method: 'get_svg',
                params: [ 'token' ],
                expect: { svg: '' },
                reject: true
            });

            return callGetQrCatalog().then(function(networks) {
                var catalog = indexWifiCatalog(networks);

                wifiEntryBySid = catalog.bySid;
                wifiEntriesBySsid = catalog.bySsid;
                qrCatalogState = 'ready';

                done();
            });
        }).catch(function() {
            qrCatalogState = 'failed';
            done();
        });
    }

    function initQrObserver() {
        var path = location.pathname;

        var onWireless = isWirelessPage;
        var onStatus   = /\/admin\/status\/overview/.test(path) ||
                         /\/cgi-bin\/luci\/?$/.test(path);

        if (!onWireless && !onStatus)
            return;

        // Observe modal insertion immediately. Waiting for the catalog RPC
        // would allow LuCI's stock QR to flash before our control is ready.
        startQrObserver(onWireless, onStatus);

        buildWifiCatalog(function() {
            if (onWireless) {
                addQrToWirelessOverview();
                hideStockQrOptions();
            }
            if (onStatus)
                addQrToStatusWireless();
        });
    }

    if (document.readyState === 'loading')
        document.addEventListener('DOMContentLoaded', initQrObserver);
    else
        initQrObserver();
})();
