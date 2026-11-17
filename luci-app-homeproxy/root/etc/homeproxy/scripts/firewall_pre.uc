#!/usr/bin/ucode

'use strict';

import { writefile } from 'fs';
import { connect } from 'ubus';
import { cursor } from 'uci';
import { isEmpty, RUN_DIR } from 'homeproxy';

const cfgname = 'homeproxy';
const uci = cursor();
uci.load(cfgname);

/* MIPSLE core builds intentionally omit with_ebpf. Keep the firewall setup
   consistent with generate_client.uc and firewall_post.ut when a config is
   imported from an eBPF-capable router. */
const ubus = connect();
const sing_features = ubus.call('luci.homeproxy', 'singbox_get_features', {}) || {};
const routing_mode = uci.get(cfgname, 'config', 'routing_mode') || 'bypass_mainland_china';
let proxy_mode = uci.get(cfgname, 'config', 'proxy_mode') || 'redirect_tproxy';
if (match(proxy_mode, /^ebpf(?:_|$)/) && !sing_features.with_ebpf)
	proxy_mode = 'redirect_tproxy';

let outbound_node, tun_name;
if (match(proxy_mode, /tun/)) {
	if (routing_mode === 'custom')
		outbound_node = uci.get(cfgname, 'routing', 'default_outbound') || 'nil';
	else
		outbound_node = uci.get(cfgname, 'config', 'main_node') || 'nil';

	if (outbound_node !== 'nil')
		tun_name = uci.get(cfgname, 'infra', 'tun_name') || 'singtun0';
}

const server_enabled = uci.get(cfgname, 'server', 'enabled');

let forward = [],
    input = [];

if (tun_name) {
	push(forward, `oifname ${tun_name} counter accept comment "!${cfgname}: accept tun forward"`);
	push(input ,`iifname ${tun_name} counter accept comment "!${cfgname}: accept tun input"`);
}

if (server_enabled === '1') {
	uci.foreach(cfgname, 'server', (s) => {
		if (s.enabled !== '1' || s.firewall !== '1')
			return;

		let proto = s.network || '{ tcp, udp }';
		push(input, `meta l4proto ${proto} th dport ${s.port} counter accept comment "!${cfgname}: accept server ${s['.name']}"`);
	});
}

if (!isEmpty(forward))
	writefile(RUN_DIR + '/fw4_forward.nft', join('\n', forward) + '\n');

if (!isEmpty(input))
	writefile(RUN_DIR + '/fw4_input.nft', join('\n', input) + '\n');
