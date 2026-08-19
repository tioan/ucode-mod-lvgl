/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2026 John Crispin <john@phrozen.org>
 */

'use strict';

/*
 * Keypad smoke test for the lv module.
 *
 * Draws four rows in a focus group on every keypad found under /dev/input.
 * Up and down move the focus, OK clicks the focused row, and every other key
 * is shown in the status line together with its input event code. The hook
 * switch is taken by lv.on_key() and never reaches LVGL. Takes DRM master, so
 * stop whatever owns the panel first:
 *
 *	ucode /tmp/keypad.uc
 *
 * Ends on SIGINT or SIGTERM.
 */

import * as lv from 'lv';
import * as uloop from 'uloop';
import { glob } from 'fs';

const C_SCREEN = 0x000000;
const C_SURFACE = 0x1c1c1e;
const C_FOCUS = 0x0a84ff;
const C_TXT = 0xffffff;
const C_TXT_DIM = 0x9a9aa2;

const ROW_H = 40;
const ROW_W = 300;
const ROWS = [ 'Line 1', 'Line 2', 'Call log', 'Settings' ];

const EV_KEY_ESC = 1;
const EV_KEY_UP = 103;
const EV_KEY_LEFT = 105;
const EV_KEY_RIGHT = 106;
const EV_KEY_DOWN = 108;
const EV_KEY_PHONE = 169;
const EV_KEY_OK = 0x160;
const EV_KEY_NUMERIC_0 = 0x200;
const EV_KEY_NUMERIC_STAR = 0x20a;
const EV_KEY_NUMERIC_POUND = 0x20b;

let status;
let timer;

function keymap_build() {
	let map = {
		[EV_KEY_UP]: lv.KEY_PREV,
		[EV_KEY_DOWN]: lv.KEY_NEXT,
		[EV_KEY_LEFT]: lv.KEY_LEFT,
		[EV_KEY_RIGHT]: lv.KEY_RIGHT,
		[EV_KEY_OK]: lv.KEY_ENTER,
		[EV_KEY_ESC]: lv.KEY_ESC,
		[EV_KEY_NUMERIC_STAR]: ord('*'),
		[EV_KEY_NUMERIC_POUND]: ord('#'),
	};

	for (let i = 0; i <= 9; i++)
		map[EV_KEY_NUMERIC_0 + i] = ord('0') + i;

	return map;
}

function status_set(text) {
	status.text(text);
}

function key_name(key) {
	if (key >= 0x20 && key < 0x7f)
		return sprintf("'%s'", chr(key));

	return sprintf('lv key %d', key);
}

function row_handlers(row, name) {
	row.on(lv.EVENT_CLICKED, () => status_set(`clicked ${name}`));
	row.on(lv.EVENT_KEY, (code, key) => status_set(`${name}: ${key_name(key)}`));
}

function row_new(parent, group, index) {
	let row = lv.obj(parent);
	let label = lv.label(row);

	row.set({ x: 10, y: 34 + index * (ROW_H + 4), w: ROW_W, h: ROW_H });
	row.style({ bg_color: C_SURFACE, bg_opa: lv.OPA_COVER, radius: 9,
		    border_width: 0, pad_all: 0 });
	row.style({ bg_color: C_FOCUS }, lv.PART_MAIN | lv.STATE_FOCUSED);
	row.scrollable(false);

	label.text(ROWS[index]);
	label.style({ text_color: C_TXT });
	label.set({ align: lv.ALIGN_LEFT_MID, align_x: 12 });

	row_handlers(row, ROWS[index]);
	group.add(row);

	return row;
}

function screen_build(group) {
	let screen = lv.screen();
	let title = lv.label(screen);

	screen.style({ bg_color: C_SCREEN, bg_opa: lv.OPA_COVER });
	screen.scrollable(false);

	title.text('Keypad test');
	title.style({ text_color: C_TXT });
	title.set({ x: 10, y: 8 });

	for (let i = 0; i < length(ROWS); i++)
		row_new(screen, group, i);

	status = lv.label(screen);
	status.style({ text_color: C_TXT_DIM });
	status.set({ x: 10, y: 214, w: ROW_W });
	status.long_mode(lv.LABEL_LONG_CLIP);
	status.text('press a key');
}

function key_raw(code, value) {
	if (value == 2)
		return false;

	warn(sprintf('key %d %s\n', code, value ? 'down' : 'up'));

	if (code != EV_KEY_PHONE)
		return false;

	status_set(value ? 'hook: off hook' : 'hook: on hook');

	return true;
}

function keypads_open(map) {
	let count = 0;

	for (let path in glob('/dev/input/event*')) {
		if (count == 4)
			break;

		if (!lv.indev_keypad(path, map))
			continue;

		warn(`keypad ${path}\n`);
		count++;
	}

	return count;
}

function lv_tick() {
	let delay = lv.timer_handler();

	if (delay == null) {
		uloop.end();
		return;
	}

	timer.set(min(max(delay, 5), 200));
}

lv.init();

if (!lv.display_drm())
	die('cannot open /dev/dri/card0\n');

let group = lv.group();

screen_build(group);
group.activate();

lv.on_key(key_raw);

if (!keypads_open(keymap_build()))
	die('no input device opened\n');

uloop.init();
timer = uloop.timer(1, lv_tick);
uloop.signal('SIGINT', () => uloop.end());
uloop.signal('SIGTERM', () => uloop.end());
uloop.run();
