# ucode-mode-lvgl

An LVGL binding for [ucode](https://github.com/jow-/ucode), so a user interface
for a small DRM display can be written in ucode rather than in C. It builds one
file, lv.so, which ucode loads as the module lv.

It carries the widgets, the DRM backend and the evdev input. Beside the binding
sits a panel library in ucode, shared by the applications built on it, with the
Inter faces and the icons that library draws.

## The panel library

`ucode/lvgl/` installs to `/usr/share/ucode/lvgl/` and is imported through the
default search path, as `lvgl.<name>`:

* `theme`, `assets`, `layout`, `widget`, `threshold`, `rate` and
  `component.*`: the design, the faces, the geometry and the drawing.
* `page`, `loader`, `runtime`: the page framework, the page loader, and the
  backlight, idle lock and settings. An application names its uci config and its
  page directory with `runtime_init()` and `loader_init()`.
* `sampler` and `sources`: the source framework, and the clock, cpu, sysinfo,
  temp and weather sources. An application hands its own sources to
  `sampler_init()` beside these.

`assets/fonts/` and `assets/icons/` install to `/usr/share/lvgl/`. Application
specific artwork stays with the application.

## What it gives ucode

* Widgets: object, label, bar, chart, arc, line, tileview, image, qrcode. Each
  answers a handle carrying the methods in widget_fns[].
* A DRM display and an evdev pointer, both opened by path.
* Up to four evdev keypads with lv.indev_keypad(path, keymap), which maps
  input event codes onto LVGL keys, and lv.on_key(handler), which sees every
  key before the keymap does. Keys go to the focused widget of the active
  lv.group().
* lv.font_load(path) for an LVGL binary font, and lv.image_load(path, alpha)
  for a PNG as RGB565 or as an A8 coverage mask. Both answer an index and
  remember the paths they have already been given.
* lv.timer_handler() to drive from a uloop timer, and lv.refresh(), which
  draws and then waits for the panel to take the frame.
* lv.screenshot(path), so a page can be looked at without standing in front
  of it.

Every function a caller can reach carries a kernel-doc header in the source.

## Packaging

The OpenWrt package is ucode-mod-lvgl in
[feed-blogic](https://github.com/blogic/feed-blogic). It fetches LVGL, applies
the DRM patch, and builds this repository inside it.

## Licence

GPL-2.0-only, except the faces in `assets/fonts/`, which are Inter under the
SIL Open Font License 1.1 (`assets/fonts/OFL.txt`).
