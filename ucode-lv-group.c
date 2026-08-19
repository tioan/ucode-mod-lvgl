/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2026 John Crispin <john@phrozen.org>
 */

#include "ucode-lv.h"

static lv_group_t *
uclv_group_this(uc_vm_t *vm)
{
	lv_group_t *group = _uc_fn_thisval(vm, UCLV_GROUP_TYPE);

	if (!group)
		uc_vm_raise_exception(vm, EXCEPTION_TYPE, "expecting a group");

	return group;
}

static lv_obj_t *
uclv_group_member(uc_vm_t *vm, uc_value_t *val)
{
	uclv_widget_t *w = ucv_resource_data(val, UCLV_WIDGET_TYPE);

	if (!w || !w->obj) {
		uc_vm_raise_exception(vm, EXCEPTION_TYPE,
				      "expecting a live widget");
		return NULL;
	}

	return w->obj;
}

static void
uclv_group_free(void *ptr)
{
	lv_group_t *group = ptr;

	if (uclv_keypad_group() == group)
		uclv_keypad_group_set(NULL);

	uclv_widget_mute(true);
	lv_group_delete(group);
	uclv_widget_mute(false);
}

/**
 * uclv_group_new() - lv.group()
 *
 * A focus ring for the keypads. It lives as long as ucode holds it, and a
 * widget leaves it by itself when it is deleted.
 *
 * Return: a group, empty and inactive.
 */
uc_value_t *
uclv_group_new(uc_vm_t *vm, size_t nargs)
{
	lv_group_t *group = lv_group_create();

	if (!group)
		return NULL;

	return ucv_resource_create(vm, UCLV_GROUP_TYPE, group);
}

/**
 * uc_lv_group_add() - g.add(widget)
 * @widget: the widget to append to the focus order
 *
 * A widget belongs to one group at a time, so this takes it out of any other.
 *
 * Return: true.
 */
static uc_value_t *
uc_lv_group_add(uc_vm_t *vm, size_t nargs)
{
	lv_group_t *group = uclv_group_this(vm);
	lv_obj_t *obj;

	if (!group)
		return NULL;

	obj = uclv_group_member(vm, uc_fn_arg(0));

	if (!obj)
		return NULL;

	lv_group_add_obj(group, obj);

	return ucv_boolean_new(true);
}

/**
 * uc_lv_group_remove() - g.remove(widget)
 * @widget: the widget to take out of the focus order
 *
 * Return: false when the widget is not in this group.
 */
static uc_value_t *
uc_lv_group_remove(uc_vm_t *vm, size_t nargs)
{
	lv_group_t *group = uclv_group_this(vm);
	lv_obj_t *obj;

	if (!group)
		return NULL;

	obj = uclv_group_member(vm, uc_fn_arg(0));

	if (!obj)
		return NULL;

	if (lv_obj_get_group(obj) != group)
		return ucv_boolean_new(false);

	lv_group_remove_obj(obj);

	return ucv_boolean_new(true);
}

/**
 * uc_lv_group_clear() - g.clear()
 *
 * Return: true.
 */
static uc_value_t *
uc_lv_group_clear(uc_vm_t *vm, size_t nargs)
{
	lv_group_t *group = uclv_group_this(vm);

	if (!group)
		return NULL;

	lv_group_remove_all_objs(group);

	return ucv_boolean_new(true);
}

/**
 * uc_lv_group_focus() - g.focus(widget)
 * @widget: a member of this group
 *
 * Return: false when the widget is not in this group.
 */
static uc_value_t *
uc_lv_group_focus(uc_vm_t *vm, size_t nargs)
{
	lv_group_t *group = uclv_group_this(vm);
	lv_obj_t *obj;

	if (!group)
		return NULL;

	obj = uclv_group_member(vm, uc_fn_arg(0));

	if (!obj)
		return NULL;

	if (lv_obj_get_group(obj) != group)
		return ucv_boolean_new(false);

	lv_group_focus_obj(obj);

	return ucv_boolean_new(true);
}

/**
 * uc_lv_group_next() - g.next()
 *
 * Return: true.
 */
static uc_value_t *
uc_lv_group_next(uc_vm_t *vm, size_t nargs)
{
	lv_group_t *group = uclv_group_this(vm);

	if (!group)
		return NULL;

	lv_group_focus_next(group);

	return ucv_boolean_new(true);
}

/**
 * uc_lv_group_prev() - g.prev()
 *
 * Return: true.
 */
static uc_value_t *
uc_lv_group_prev(uc_vm_t *vm, size_t nargs)
{
	lv_group_t *group = uclv_group_this(vm);

	if (!group)
		return NULL;

	lv_group_focus_prev(group);

	return ucv_boolean_new(true);
}

/**
 * uc_lv_group_focused() - g.focused()
 *
 * Return: the focused widget, or null when the group is empty.
 */
static uc_value_t *
uc_lv_group_focused(uc_vm_t *vm, size_t nargs)
{
	lv_group_t *group = uclv_group_this(vm);

	if (!group)
		return NULL;

	return uclv_widget_wrap(vm, lv_group_get_focused(group));
}

/**
 * uc_lv_group_count() - g.count()
 *
 * Return: how many widgets the group holds.
 */
static uc_value_t *
uc_lv_group_count(uc_vm_t *vm, size_t nargs)
{
	lv_group_t *group = uclv_group_this(vm);

	if (!group)
		return NULL;

	return ucv_uint64_new(lv_group_get_obj_count(group));
}

/**
 * uc_lv_group_wrap() - g.wrap(on)
 * @on: whether next on the last widget focuses the first, LVGL's default
 *
 * Return: true.
 */
static uc_value_t *
uc_lv_group_wrap(uc_vm_t *vm, size_t nargs)
{
	lv_group_t *group = uclv_group_this(vm);

	if (!group)
		return NULL;

	lv_group_set_wrap(group, ucv_is_truish(uc_fn_arg(0)));

	return ucv_boolean_new(true);
}

/**
 * uc_lv_group_activate() - g.activate()
 *
 * Gives every keypad to this group, including one opened later. One group is
 * active at a time, so a dialog activates its own and the page activates its
 * group again when the dialog closes.
 *
 * Return: true.
 */
static uc_value_t *
uc_lv_group_activate(uc_vm_t *vm, size_t nargs)
{
	lv_group_t *group = uclv_group_this(vm);

	if (!group)
		return NULL;

	uclv_keypad_group_set(group);

	return ucv_boolean_new(true);
}

static const uc_function_list_t group_fns[] = {
	{ "add",		uc_lv_group_add },
	{ "remove",		uc_lv_group_remove },
	{ "clear",		uc_lv_group_clear },
	{ "focus",		uc_lv_group_focus },
	{ "next",		uc_lv_group_next },
	{ "prev",		uc_lv_group_prev },
	{ "focused",		uc_lv_group_focused },
	{ "count",		uc_lv_group_count },
	{ "wrap",		uc_lv_group_wrap },
	{ "activate",		uc_lv_group_activate },
};

void
uclv_group_register(uc_vm_t *vm)
{
	uc_type_declare(vm, UCLV_GROUP_TYPE, group_fns, uclv_group_free);
}
