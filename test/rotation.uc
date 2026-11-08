/*
 * SPDX-License-Identifier: GPL-2.0-only
 */

'use strict';

/*
 * Display rotation on the DRM panel.
 *
 * For every rotation, draws a red square into the logical top left corner
 * and reads the scanout buffer back: the square has to land where LVGL's
 * pointer transform expects that corner, or touch and picture disagree.
 * Takes DRM master, so stop whatever owns the panel first:
 *
 *	/etc/init.d/glinet-panel-ui stop
 *	ucode /tmp/rotation.uc
 *	/etc/init.d/glinet-panel-ui start
 */

import * as lv from 'lv';

const RED = 0xff0000;
const BLACK = 0x000000;
const BOX = 20;
const PROBE = 5;

let failures = 0;
let checks = 0;

function check(what, got, want) {
	let ok = (sprintf('%J', got) == sprintf('%J', want));

	checks++;

	if (!ok)
		failures++;

	printf('%-44s %-12J %s\n', what, got,
	       ok ? 'ok' : sprintf('want %J', want));
}

function raises(what, fn) {
	checks++;

	try {
		fn();
	} catch (e) {
		printf('%-44s %-12s ok\n', what, 'raises');

		return;
	}

	failures++;
	printf('%-44s DID NOT RAISE\n', what);
}

/* RGB565 keeps 5 or 6 bits a channel; compare what survives of them. */
function colour(rgb) {
	return rgb == null ? null : (rgb & 0xf8fcf8);
}

if (!lv.init())
	die('cannot initialise LVGL');

if (!lv.display_drm(getenv('PANEL_DRM_DEVICE') ?? '/dev/dri/card0', -1))
	die('cannot open the DRM display');

check('starts unrotated', lv.display_rotation(), 0);
raises('refuses 45 degrees', () => lv.display_rotation(45));

/*
 * Physical corner the logical top left lands on, from the inverse of
 * indev_pointer_proc() in LVGL: 90 is bottom left, 180 bottom right, 270 top
 * right, on the 320x240 scanout.
 */
const PW = 320, PH = 240;
const CORNER = {
	'0':   [ PROBE,          PROBE ],
	'90':  [ PROBE,          PH - 1 - PROBE ],
	'180': [ PW - 1 - PROBE, PH - 1 - PROBE ],
	'270': [ PW - 1 - PROBE, PROBE ]
};
const OPPOSITE = {
	'0':   CORNER['180'],
	'90':  CORNER['270'],
	'180': CORNER['0'],
	'270': CORNER['90']
};

for (let deg in [ 0, 90, 180, 270, 0 ]) {
	printf('\n== %d degrees ==\n', deg);

	check('rotation is set', lv.display_rotation(deg), deg);

	let screen = lv.screen_create();

	screen.style({ bg_color: BLACK, bg_opa: lv.OPA_COVER, border_width: 0,
		       pad_all: 0, radius: 0 });
	screen.scrollable(false);

	let box = lv.obj(screen);

	box.style({ bg_color: RED, bg_opa: lv.OPA_COVER, border_width: 0,
		    radius: 0, pad_all: 0 });
	box.set({ x: 0, y: 0, w: BOX, h: BOX });

	lv.screen_load(screen);
	lv.refresh();

	let portrait = (deg == 90 || deg == 270);

	check('logical width', screen.width(), portrait ? PH : PW);
	check('logical height', screen.height(), portrait ? PW : PH);

	let at = CORNER[deg], away = OPPOSITE[deg];

	check(sprintf('red at physical %d,%d', at[0], at[1]),
	      colour(lv.scanout_pixel(at[0], at[1])), colour(RED));
	check(sprintf('black at physical %d,%d', away[0], away[1]),
	      colour(lv.scanout_pixel(away[0], away[1])), colour(BLACK));
}

check('outside the scanout reads null', lv.scanout_pixel(PW, PH), null);

printf('\n%s: %d of %d checks failed\n', failures ? 'FAIL' : 'PASS', failures,
       checks);

lv.drm_drop_master();

exit(failures ? 1 : 0);
