'use strict';

import { popen } from 'fs';
import { cursor } from 'uci';

const renderer = '/usr/lib/wi-fi-qr/wi-fi-qr-render';
const cataloger = '/usr/lib/wi-fi-qr/wi-fi-qr-catalog';
const maxTokenLength = 256;
const maxResponseLength = 256 * 1024;
const uci = cursor();

function validToken(token) {
	return type(token) == 'string' &&
	       length(token) &&
	       length(token) <= maxTokenLength &&
	       match(token, /^[A-Za-z0-9._-]+$/) != null;
}

function getSvg(request) {
	const token = request.args.token;

	if (!validToken(token))
		exit(UBUS_STATUS_INVALID_ARGUMENT);

	// OpenWrt 25.12 fs.popen() uses a shell command string. The fixed renderer
	// path and ASCII allowlist above make this concatenation safe.
	const proc = popen(renderer + ' ' + token, 'r');

	if (!proc)
		exit(UBUS_STATUS_UNKNOWN_ERROR);

	const svg = proc.read('all');
	const status = proc.close();

	if (status == 2)
		exit(UBUS_STATUS_INVALID_ARGUMENT);

	if (status == 3)
		exit(UBUS_STATUS_NOT_FOUND);

	if (status != 0 || type(svg) != 'string' || !length(svg) || length(svg) > maxResponseLength)
		exit(UBUS_STATUS_UNKNOWN_ERROR);

	return { svg };
}

function readCatalogTokens() {
	const proc = popen(cataloger, 'r');

	if (!proc)
		exit(UBUS_STATUS_UNKNOWN_ERROR);

	const output = proc.read('all');
	const status = proc.close();

	if (status != 0 || type(output) != 'string' || length(output) > maxResponseLength)
		exit(UBUS_STATUS_UNKNOWN_ERROR);

	const tokens = {};
	const lines = split(output, '\n');
	let count = 0;

	for (let i = 0; i < length(lines); i++) {
		if (!length(lines[i]))
			continue;

		const fields = split(lines[i], '\t');

		if (length(fields) != 2 ||
		    match(fields[0], /^(0|[1-9][0-9]*)$/) == null ||
		    !validToken(fields[1]) ||
		    tokens[fields[0]] != null)
			exit(UBUS_STATUS_UNKNOWN_ERROR);

		tokens[fields[0]] = fields[1];
		count++;
	}

	return { tokens, count };
}

function getCatalog() {
	const catalog = readCatalogTokens();
	const networks = [];
	let index = 0;
	let matched = 0;

	// A direct libuci cursor reads the committed configuration rather than the
	// browser session's pending LuCI changes.
	uci.unload('wireless');
	uci.foreach('wireless', 'wifi-iface', function(section) {
		const token = catalog.tokens[index++];

		if (token == null)
			return;

		const sid = section['.name'];
		const ssid = section.ssid;

		if (type(sid) != 'string' || !length(sid) ||
		    type(ssid) != 'string' || !length(ssid))
			exit(UBUS_STATUS_UNKNOWN_ERROR);

		push(networks, { sid, ssid, token });
		matched++;
	});
	uci.unload('wireless');

	if (matched != catalog.count)
		exit(UBUS_STATUS_UNKNOWN_ERROR);

	return { networks };
}

return {
	'luci.wifi-qr': {
		get_catalog: {
			args: {},
			call: getCatalog
		},
		get_svg: {
			args: { token: '' },
			call: getSvg
		}
	}
};
