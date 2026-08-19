'use strict';

import * as lv from 'lv';

/*
 * A screen stack for a key driven panel, the counterpart to page.uc for a board
 * with no touchscreen. page.uc pages between roots with a tileview and a finger;
 * here a screen is pushed and popped, and the keys reach it through a focus
 * group.
 *
 * A screen is an object of:
 *   obj:	the lv screen, from lv.screen_create()
 *   group:	its focus group, or null for a screen that takes no focus
 *   enter:	called after the screen is shown, optional
 *   leave:	called before it is left, optional
 *   key:	called with an lv key for a key the focused widget did not use,
 *		optional; return true to swallow it
 *   root:	true for a screen Esc does not leave, such as the idle screen
 *
 * LVGL already sends a mapped key to the focused widget of the active group, so
 * a screen only has to put its widgets in its group. This holds Esc for back
 * and routes the unhandled keys to the screen's own key handler.
 */

let stack = [];
let on_exit;
let on_key;
let empty_group;

function top() {
	return stack[-1];
}

function activate(entry) {
	/* A screen with no group of its own must not leave the previous screen's
	   group active, or its focusable widgets would still take mapped keys. An
	   empty group parks the focus so those keys reach nothing. */
	if (entry.group)
		entry.group.activate();
	else
		empty_group.activate();

	lv.screen_load(entry.obj);

	if (entry.enter)
		entry.enter();
}

/**
 * nav_key - the global key handler, wired to lv.on_key by nav_init
 * @code: the input event code
 * @value: 1 for a press, 0 for a release, 2 for autorepeat
 *
 * Return: true to keep the key from LVGL.
 */
function nav_key(code, value) {
	/* The global handler sees every key, press and release, so a board can
	   act on its hook, its cancel key and its volume keys from one place. */
	if (on_key && on_key(code, value))
		return true;

	if (value != 1)
		return false;

	let entry = top();

	if (!entry)
		return false;

	if (entry.key && entry.key(code))
		return true;

	return false;
}

/**
 * nav_init - start the navigator with the first screen
 * @first: the screen to show, which should be a root
 * @opts: on_exit, called when the last screen is popped; on_key(code, value),
 *	  a global key handler that sees every key first, both optional
 *
 * Call after lv.display_drm() and after a keypad is open.
 */
export function nav_init(first, opts) {
	on_exit = opts?.on_exit;
	on_key = opts?.on_key;

	empty_group = lv.group();

	lv.on_key(nav_key);

	stack = [ first ];
	activate(first);
};

/**
 * nav_push - show a screen over the current one
 * @entry: the screen
 */
export function nav_push(entry) {
	let cur = top();

	if (cur?.leave)
		cur.leave();

	push(stack, entry);
	activate(entry);
};

/**
 * nav_pop - leave the top screen and show the one beneath
 *
 * A root is not left. With nothing beneath and no root, on_exit runs.
 *
 * Return: false when the top screen is a root, so nothing happened.
 */
export function nav_pop() {
	let cur = top();

	if (!cur || cur.root)
		return false;

	if (cur.leave)
		cur.leave();

	pop(stack);

	let below = top();

	/* Load the screen beneath before deleting this one, or LVGL has no
	   active screen for a moment and warns. */
	if (below) {
		activate(below);
		cur.obj.delete();

		return true;
	}

	cur.obj.delete();

	if (on_exit)
		on_exit();

	return true;
};

/**
 * nav_replace - swap the top screen for another, without growing the stack
 * @entry: the new screen
 *
 * For a state change that is not navigation, such as a call going from ringing
 * to connected.
 */
export function nav_replace(entry) {
	let cur = top();

	if (cur && cur.leave)
		cur.leave();

	if (cur)
		pop(stack);

	push(stack, entry);
	activate(entry);

	/* Delete the old screen after the new one is on, not before. */
	if (cur)
		cur.obj.delete();
};

/**
 * nav_reset - drop every screen above the root and show the root
 *
 * For waking to idle, or ending a call. The root is entry 0.
 */
export function nav_reset() {
	let doomed = [];

	while (length(stack) > 1) {
		let entry = pop(stack);

		if (entry.leave)
			entry.leave();

		push(doomed, entry);
	}

	let root = top();

	/* Load the root before deleting the screens above it. */
	if (root)
		activate(root);

	for (let entry in doomed)
		entry.obj.delete();
};

/**
 * nav_depth - how many screens are on the stack
 *
 * Return: 1 at the root.
 */
export function nav_depth() {
	return length(stack);
};

/**
 * nav_top - the screen now showing
 *
 * Return: the entry, or null.
 */
export function nav_top() {
	return top();
};
