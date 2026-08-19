'use strict';

import * as ubus from 'ubus';
import * as uloop from 'uloop';
import { readfile } from 'fs';

export const state = {};

let sources = {};
let watchers = [];
let awake;

/**
 * monotonic - seconds from a clock that does not step
 *
 * Return: a float. For measuring an interval, never for a wall time.
 */
export function monotonic() {
	let now = clock(true);

	return now[0] + now[1] / 1000000000.0;
};

/**
 * file_read - a file's contents, trimmed
 * @path: the file
 *
 * Return: the string, or null when it cannot be read.
 */
export function file_read(path) {
	let data = readfile(path);

	return data ? trim(data) : null;
};

/**
 * words - split a line on runs of blanks
 * @line: the line
 *
 * Return: the fields, with no empty ones.
 */
export function words(line) {
	return filter(split(replace(trim(line), /[ \t]+/g, ' '), ' '),
		      part => part != '');
};

const UCI_TRUE = [ '1', 'on', 'true', 'yes', 'enabled' ];

/**
 * truish - whether a uci value spells a set flag
 * @value: the value, or null
 *
 * Return: true for any spelling uci accepts for on.
 */
export function truish(value) {
	return index(UCI_TRUE, lc(value ?? '')) >= 0;
};

/**
 * ubus_call - a ubus call that answers null rather than throwing
 * @object: the object name
 * @method: the method
 * @data: the arguments, or null
 *
 * Return: the reply, or null.
 */
export function ubus_call(object, method, data) {
	try {
		return ubus.call({ object, method, data: data ?? {} });
	}
	catch (e) {
		return null;
	}
};

/**
 * source_notify - tell the watchers that a source has a new sample
 * @name: the source name
 * @broadcast: true to reach every page that declared it, not only the one shown
 *
 * For a source whose answer arrives after its read() returned.
 */
export function source_notify(name, broadcast) {
	for (let fn in watchers)
		fn(name, broadcast);
};

function source_fire(src) {
	src.read();

	source_notify(src.name, src.broadcast);
}

function source_timer_new(src) {
	return uloop.interval(0, () => source_fire(src));
}

function source_wanted(src) {
	return src.retain || (awake && src.users > 0);
}

function source_sync(src) {
	let want = source_wanted(src);

	if (want == src.armed)
		return;

	src.armed = want;

	if (want)
		src.read();

	/* Zero is the disarm: cancel() would free the callback binding. */
	src.timer.set(want ? src.ms : 0);
}

/**
 * sampler_init - build the source table and its timers
 * @decls: the sources, each of name, ms, read and optionally retain and
 *	   broadcast
 * @defaults: what state holds before the first read
 *
 * Every source starts disarmed. Call once, before any page is built.
 */
export function sampler_init(decls, defaults) {
	for (let key, value in defaults)
		state[key] = value;

	for (let decl in decls) {
		let src = { ...decl, users: 0, armed: false };

		src.timer = source_timer_new(src);
		sources[src.name] = src;
	}
};

/**
 * source_watch - register a handler for a sample
 * @fn: called with the source name and its broadcast flag
 */
export function source_watch(fn) {
	push(watchers, fn);
};

/**
 * source_seed - read a source once without arming it
 * @names: source names, in the order they should be read
 *
 * Fills state so a page can be drawn before it has ever been shown. An already
 * armed source is skipped, and no watcher is called.
 */
export function source_seed(names) {
	for (let name in names) {
		let src = sources[name];

		if (!src || src.armed)
			continue;

		src.read();
	}
};

/**
 * source_subscribe - claim sources for a page that is being entered
 * @names: the page's needs, in the order they should be armed
 *
 * A source arms on its first user and is read once immediately, so a page whose
 * source depends on another lists that one first.
 */
export function source_subscribe(names) {
	for (let name in names) {
		let src = sources[name];

		if (!src)
			continue;

		src.users++;
		source_sync(src);
	}
};

/**
 * source_release - drop a page's claim on its sources
 * @names: the page's needs
 *
 * A source with no users left and no retain flag stops sampling.
 */
export function source_release(names) {
	for (let name in names) {
		let src = sources[name];

		if (!src || --src.users > 0)
			continue;

		source_sync(src);
	}
};

/**
 * sampler_awake - whether the subscribed sources should sample
 * @flag: false once the panel is idle
 *
 * A retained source keeps running either way.
 */
export function sampler_awake(flag) {
	awake = flag;

	for (let name, src in sources)
		source_sync(src);
};
