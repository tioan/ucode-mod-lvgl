'use strict';

import * as uci from 'uci';
import * as uloop from 'uloop';
import { readfile } from 'fs';
import { state, monotonic, file_read, words, ubus_call,
	 source_notify } from 'lvgl.sampler';

const MS_LOAD	= 2000;
const MS_SLOW	= 5000;
const MS_CLOCK	= 1000;

const STAT_IDLE	= 4;
const STAT_IOWAIT = 5;

let app_config;

export const DEFAULTS = {
	cpu: 0,
	mem: 0,
	flash: 0,
	temp: null,
	cpu_busy: null,
	cpu_total: null,
	clock_12: '',
	clock_24: '',
	meridiem: '',
	date: '',
	weather: null
};

function cpu_read() {
	let stat = file_read('/proc/stat');

	if (!stat)
		return;

	let field = words(split(stat, '\n')[0]);
	let total = 0;

	for (let i = 1; i < length(field); i++)
		total += +field[i];

	let idle = +field[STAT_IDLE] +
		   (length(field) > STAT_IOWAIT ? +field[STAT_IOWAIT] : 0);
	let busy = total - idle;

	if (state.cpu_total != null && total > state.cpu_total)
		state.cpu = int((busy - state.cpu_busy) * 100.0 /
				(total - state.cpu_total));

	state.cpu_busy = busy;
	state.cpu_total = total;
}

function sysinfo_read() {
	let info = ubus_call('system', 'info');

	if (!info)
		return;

	let mem = info.memory;

	if (mem?.total > 0)
		state.mem = int((mem.total - mem.available) * 100 / mem.total);

	let root = info.root;

	if (root?.total > 0)
		state.flash = int(root.used * 100 / root.total);
}

function temp_read() {
	let milli = file_read('/sys/class/thermal/thermal_zone0/temp');

	if (milli != null)
		state.temp = int(+milli / 1000);
}

/* ucode counts wday from one and starts it at Monday, not at Sunday. */
const WEEKDAYS = [ 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
		   'Saturday', 'Sunday' ];
const MONTHS = [ 'January', 'February', 'March', 'April', 'May', 'June',
		 'July', 'August', 'September', 'October', 'November',
		 'December' ];

function clock_read() {
	let now = localtime(time());
	let hour = now.hour % 12;

	state.clock_12 = sprintf('%d:%02d', hour == 0 ? 12 : hour, now.min);
	state.clock_24 = sprintf('%02d:%02d', now.hour, now.min);
	state.meridiem = now.hour < 12 ? 'AM' : 'PM';
	state.date = sprintf('%s, %d %s', WEEKDAYS[now.wday - 1], now.mday,
			     MONTHS[now.mon - 1]);
}

const WX_HOST	= 'https://api.open-meteo.com/v1/forecast';
const WX_CURRENT = 'temperature_2m,apparent_temperature,weather_code,is_day';
const WX_DAILY	= 'weather_code,temperature_2m_max,temperature_2m_min';
const WX_DAYS	= 5;

const WX_FETCH	= '/usr/bin/wget';
const WX_TMP	= '/tmp/lvgl-weather.json';
const WX_TIMEOUT = 15;

const WX_TTL	= 3600;
const MS_WX	= 300000;

const WX_LAT_MAX = 90;
const WX_LON_MAX = 180;

let wx_busy, wx_ts;

function wx_config() {
	let cursor = uci.cursor();

	if (!cursor.load(app_config))
		return null;

	let lat = cursor.get(app_config, '@panel[0]', 'latitude');
	let lon = cursor.get(app_config, '@panel[0]', 'longitude');

	/* Absent is refused here and not by the range test: +null is 0 and 0 is a
	   latitude, which would put an unset panel in the Gulf of Guinea. */
	if (lat == null || lat == '' || lon == null || lon == '')
		return null;

	lat = +lat;
	lon = +lon;

	if (!(lat >= -WX_LAT_MAX && lat <= WX_LAT_MAX))
		return null;
	if (!(lon >= -WX_LON_MAX && lon <= WX_LON_MAX))
		return null;

	return { lat, lon };
}

const WX_CODES = [
	[ [ 0 ],			'clear',  'Clear' ],
	[ [ 1 ],			'partly', 'Mainly clear' ],
	[ [ 2 ],			'partly', 'Partly cloudy' ],
	[ [ 3 ],			'cloud',  'Overcast' ],
	[ [ 45, 48 ],			'cloud',  'Fog' ],
	[ [ 51, 53, 55, 56, 57 ],	'rain',   'Drizzle' ],
	[ [ 61, 63, 65, 66, 67 ],	'rain',   'Rain' ],
	[ [ 80, 81, 82 ],		'rain',   'Showers' ],
	[ [ 71, 73, 75, 77 ],		'snow',   'Snow' ],
	[ [ 85, 86 ],			'snow',   'Snow showers' ],
	[ [ 95, 96, 99 ],		'storm',  'Thunderstorm' ]
];

function wx_code(code) {
	for (let row in WX_CODES)
		if (index(row[0], code) >= 0)
			return { glyph: row[1], text: row[2] };

	return { glyph: 'cloud', text: '—' };
}

function wx_round(value) {
	if (type(value) != 'double' && type(value) != 'int')
		return null;

	return int(value + (value < 0 ? -0.5 : 0.5));
}

function wx_days(daily) {
	let out = [];
	let today = localtime(time()).wday - 1;

	for (let i = 0; i < WX_DAYS; i++) {
		let code = daily.weather_code?.[i];

		if (code == null)
			break;

		push(out, {
			name: substr(WEEKDAYS[(today + i) % 7], 0, 3),
			glyph: wx_code(code).glyph,
			hi: wx_round(daily.temperature_2m_max?.[i]),
			lo: wx_round(daily.temperature_2m_min?.[i])
		});
	}

	return out;
}

function wx_parse(raw) {
	let doc;

	try {
		doc = json(raw);
	}
	catch (e) {
		return false;
	}

	if (!doc || doc.error || !doc.current || !doc.daily)
		return false;

	let now = doc.current;
	let sky = wx_code(now.weather_code);

	state.weather = {
		temp: wx_round(now.temperature_2m),
		feels: wx_round(now.apparent_temperature),
		glyph: sky.glyph,
		text: sky.text,
		day: now.is_day != 0,
		days: wx_days(doc.daily)
	};

	return true;
}

function weather_read() {
	if (wx_busy)
		return;
	if (state.weather && wx_ts != null && monotonic() - wx_ts < WX_TTL)
		return;

	let cfg = wx_config();

	if (!cfg)
		return;

	let url = sprintf('%s?latitude=%.4f&longitude=%.4f&current=%s&daily=%s' +
			  '&timezone=auto&forecast_days=%d',
			  WX_HOST, cfg.lat, cfg.lon, WX_CURRENT, WX_DAILY, WX_DAYS);

	wx_busy = true;

	let proc = uloop.process(WX_FETCH,
				 [ '-q', '-O', WX_TMP,
				   '-T', sprintf('%d', WX_TIMEOUT), url ],
				 null, function(code) {
		wx_busy = false;

		if (code != 0)
			return;

		if (wx_parse(readfile(WX_TMP))) {
			wx_ts = monotonic();
			source_notify('weather', true);
		}
	});

	if (!proc)
		wx_busy = false;
}

/**
 * sources_new - the sources every panel can use
 * @opts: config, the uci config whose panel section holds the latitude and
 *	  longitude for the forecast
 *
 * Return: clock, cpu, sysinfo, temp and weather, for sampler_init().
 */
export function sources_new(opts) {
	app_config = opts.config;

	return [
		{ name: 'clock',   ms: MS_CLOCK, read: clock_read },
		{ name: 'cpu',     ms: MS_LOAD,  read: cpu_read },
		{ name: 'sysinfo', ms: MS_LOAD,  read: sysinfo_read },
		{ name: 'temp',    ms: MS_SLOW,  read: temp_read },
		{ name: 'weather', ms: MS_WX,    retain: true, broadcast: true,
		  read: weather_read }
	];
};
