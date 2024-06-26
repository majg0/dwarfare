const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("xcb/xcb.h");
    @cInclude("xcb/xkb.h");
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("xkbcommon/xkbcommon-x11.h");
});
// const Input = @import("input.zig").Input;
const platform = @import("platform");

// TODO: check replies across function calls in this file, no _ =

const assert = std.debug.assert;

// DOCS: https://www.x.org/releases/X11R7.5/doc/x11proto/proto.pdf
// DOCS: https://specifications.freedesktop.org/wm-spec/1.4/ar01s05.html

const int_invalid = 0xDEAD;

pub const InputEvent = struct {
    pub const Type = enum(u8) {
        key_press,
        // key_release,
        // button_press,
        // button_release,
        // mouse_move,
        // mouse_enter,
        // mouse_leave,
        // focus_in,
        // focus_out,
        // resize,
        // visibility,
    };

    pub const KeyPress = struct {
        /// platform-dependent
        physical_key: u32,
        virtual_key: u32,
        text_size: u32,
        /// gathered at input time, as a state change in e.g. shift key could alter it before processing
        text_utf8: [64:0]u8,
        // NOTE: we could get these at any time
        // virtual_key_name_size: u32,
        // virtual_key_name: [64:0]u8,
    };

    pub const KeyRelease = struct {
        /// platform-dependent
        physical_key: u32,
    };
};

fn key_code_translate(keycode: u8) platform.KeyCode {
    return switch (keycode) {
        9 => .escape,
        10 => .num1,
        11 => .num2,
        12 => .num3,
        13 => .num4,
        14 => .num5,
        15 => .num6,
        16 => .num7,
        17 => .num8,
        18 => .num9,
        19 => .num0,
        20 => .minus,
        21 => .equal,
        22 => .backspace,
        23 => .tab,
        24 => .q,
        25 => .w,
        26 => .e,
        27 => .r,
        28 => .t,
        29 => .y,
        30 => .u,
        31 => .i,
        32 => .o,
        33 => .p,
        34 => .bracket_left,
        35 => .bracket_right,
        36 => .enter,
        37 => .control_left,
        38 => .a,
        39 => .s,
        40 => .d,
        41 => .f,
        42 => .g,
        43 => .h,
        44 => .j,
        45 => .k,
        46 => .l,
        47 => .semicolon,
        48 => .apostrophe,
        49 => .grave,
        50 => .shift_left,
        51 => .backslash,
        52 => .z,
        53 => .x,
        54 => .c,
        55 => .v,
        56 => .b,
        57 => .n,
        58 => .m,
        59 => .comma,
        60 => .period,
        61 => .slash,
        62 => .shift_right,
        63 => .numpad_mul,
        64 => .alt_left,
        65 => .space,
        66 => .caps_lock,
        67 => .f1,
        68 => .f2,
        69 => .f3,
        70 => .f4,
        71 => .f5,
        72 => .f6,
        73 => .f7,
        74 => .f8,
        75 => .f9,
        76 => .f10,
        77 => .num_lock,
        78 => .scroll_lock,
        79 => .numpad_7,
        80 => .numpad_8,
        81 => .numpad_9,
        82 => .numpad_sub,
        83 => .numpad_4,
        84 => .numpad_5,
        85 => .numpad_6,
        86 => .numpad_add,
        87 => .numpad_1,
        88 => .numpad_2,
        89 => .numpad_3,
        90 => .numpad_0,
        91 => .numpad_delete,
        // ?
        94 => .less,
        95 => .f11,
        96 => .f12,
        // ?
        104 => .numpad_enter,
        105 => .control_right,
        106 => .numpad_div,
        107 => .print_screen,
        108 => .alt_right,
        // ?
        110 => .home,
        111 => .up,
        112 => .page_up,
        113 => .left,
        114 => .right,
        115 => .end,
        116 => .down,
        117 => .page_down,
        118 => .insert,
        119 => .delete,
        // ?
        127 => .pause_break,
        // ?
        133 => .gui_left,
        // ?
        135 => .menu,
        else => .unknown,
    };
}

pub const XcbUi = struct {
    connection: *c.struct_xcb_connection_t = @ptrFromInt(int_invalid),
    window: c.xcb_window_t = int_invalid,
    wm_delete_window_atom: c.xcb_atom_t = int_invalid,
    xkb_context: *c.xkb_context,
    xkb_keymap: *c.xkb_keymap,
    xkb_state: *c.xkb_state,
    xkb_base_event: u8,
    xkb_base_error: u8,
    xkb_device_id: i32,

    pub fn virtualKeyName(_: *const XcbUi, virtual_key: u32, slice: []u8) u32 {
        const size = c.xkb_keysym_get_name(virtual_key, slice.ptr, slice.len);
        assert(size >= 0);
        return @intCast(size);
    }

    pub fn eventsPoll(self: *XcbUi) ?platform.Event {
        for (0..100) |_| {
            const generic_event: *c.xcb_generic_event_t = c.xcb_poll_for_event(self.connection) orelse return null;
            defer c.free(generic_event);

            const response_type = generic_event.response_type & 0x7F;
            switch (response_type) {
                c.XCB_NONE => {
                    const e: *c.xcb_generic_error_t = @ptrCast(generic_event);
                    std.debug.print("XCB error code {}", .{e.error_code});
                },
                c.XCB_KEY_PRESS => {
                    const e: *c.xcb_key_press_event_t = @ptrCast(generic_event);

                    var out = InputEvent.KeyPress{
                        .physical_key = e.detail,
                        .virtual_key = c.xkb_state_key_get_one_sym(self.xkb_state, e.detail),
                        .text_size = 0,
                        .text_utf8 = std.mem.zeroes([64:0]u8),
                    };

                    const size = c.xkb_state_key_get_utf8(self.xkb_state, e.detail, &out.text_utf8, out.text_utf8.len);
                    assert(size >= 0);
                    out.text_size = @intCast(size);

                    std.debug.print("0x{X} KeyPress {} state:0b{b} ({},{}) root:({},{})\n", .{ e.event, e.detail, e.state, e.event_x, e.event_y, e.root_x, e.root_y });

                    return platform.Event{
                        .tag = .key_down,
                        .data = .{
                            .key_down = .{
                                .key_code = key_code_translate(e.detail),
                            },
                        },
                    };
                },
                c.XCB_KEY_RELEASE => {
                    const e: *c.xcb_key_release_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} KeyRelease {} state:0b{b} ({},{}) root:({},{})\n", .{ e.event, e.detail, e.state, e.event_x, e.event_y, e.root_x, e.root_y });
                    return platform.Event{
                        .tag = .key_up,
                        .data = .{
                            .key_up = .{
                                .key_code = key_code_translate(e.detail),
                            },
                        },
                    };
                },
                c.XCB_BUTTON_PRESS => {
                    const e: *c.xcb_button_press_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} ButtonPress {} state:0b{b} ({},{}) root:({},{})\n", .{ e.event, e.detail, e.state, e.event_x, e.event_y, e.root_x, e.root_y });
                },
                c.XCB_BUTTON_RELEASE => {
                    const e: *c.xcb_button_release_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} ButtonRelease {} state:0b{b} ({},{}) root:({},{})\n", .{ e.event, e.detail, e.state, e.event_x, e.event_y, e.root_x, e.root_y });
                },
                c.XCB_MOTION_NOTIFY => {
                    const e: *c.xcb_motion_notify_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} MotionNotify state:0b{b} ({},{}) root:({},{})\n", .{ e.event, e.state, e.event_x, e.event_y, e.root_x, e.root_y });
                },
                c.XCB_ENTER_NOTIFY => {
                    const e: *c.xcb_enter_notify_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} EnterNotify ({},{}) root:({},{})\n", .{ e.event, e.event_x, e.event_y, e.root_x, e.root_y });
                },
                c.XCB_LEAVE_NOTIFY => {
                    const e: *c.xcb_leave_notify_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} LeaveNotify ({},{}) root:({},{})\n", .{ e.event, e.event_x, e.event_y, e.root_x, e.root_y });
                },
                c.XCB_FOCUS_IN => {
                    const e: *c.xcb_focus_in_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} FocusIn\n", .{e.event});
                },
                c.XCB_FOCUS_OUT => {
                    const e: *c.xcb_focus_out_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} FocusOut\n", .{e.event});
                },
                c.XCB_EXPOSE => {
                    const e: *c.xcb_expose_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} Expose ({},{},{},{})\n", .{ e.window, e.x, e.y, e.width, e.height });
                },
                c.XCB_VISIBILITY_NOTIFY => {
                    const e: *c.xcb_visibility_notify_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} VisibilityNotify {s}\n", .{
                        e.window,
                        switch (e.state) {
                            c.XCB_VISIBILITY_UNOBSCURED => "Unobscured",
                            c.XCB_VISIBILITY_PARTIALLY_OBSCURED => "PartiallyObscured",
                            c.XCB_VISIBILITY_FULLY_OBSCURED => "FullyObscured",
                            else => "?",
                        },
                    });
                },
                c.XCB_MAP_NOTIFY => {
                    const e: *c.xcb_map_notify_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} MapNotify force:{}\n", .{ e.window, e.override_redirect });
                },
                c.XCB_REPARENT_NOTIFY => {
                    const e: *c.xcb_reparent_notify_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} ReparentNotify 0x{X} ({},{}) force:{}\n", .{ e.window, e.parent, e.x, e.y, e.override_redirect });
                },
                c.XCB_PROPERTY_NOTIFY => {
                    const e: *c.xcb_property_notify_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} PropertyNotify {s}", .{ e.window, if (e.state != 0) "-" else "" });

                    var err: [*c]c.xcb_generic_error_t = undefined;

                    const name_cookie = c.xcb_get_atom_name(self.connection, e.atom);
                    const name_reply: ?*c.xcb_get_atom_name_reply_t = c.xcb_get_atom_name_reply(self.connection, name_cookie, &err);
                    if (name_reply) |atom| {
                        defer c.free(name_reply);
                        if (c.xcb_get_atom_name_name(atom)) |raw_name| {
                            const name = raw_name[0..atom.name_len];

                            std.debug.print("({s}", .{name});
                        }
                    } else {
                        defer c.free(err);
                        std.debug.print("XCB resource {} error code {}", .{ err.*.resource_id, err.*.error_code });
                    }

                    if (e.state == c.XCB_PROPERTY_NEW_VALUE) {
                        const prop_cookie = c.xcb_get_property(self.connection, 0, e.window, e.atom, c.XCB_GET_PROPERTY_TYPE_ANY, 0, 1024);
                        const prop_reply: ?*c.xcb_get_property_reply_t = c.xcb_get_property_reply(self.connection, prop_cookie, &err);
                        if (prop_reply) |prop| {
                            defer c.free(prop_reply);
                            const maybe_opaque_ptr = c.xcb_get_property_value(prop);
                            if (maybe_opaque_ptr) |opaque_ptr| {
                                switch (prop.format) {
                                    8 => {
                                        const typed_ptr: [*]u8 = @ptrCast(opaque_ptr);
                                        const value = typed_ptr[0..prop.value_len];
                                        std.debug.print("={s})\n", .{value});
                                    },
                                    16 => {
                                        const typed_ptr: [*]u16 = @alignCast(@ptrCast(opaque_ptr));
                                        const value = typed_ptr[0..prop.value_len];
                                        std.debug.print("={any})\n", .{value});
                                    },
                                    32 => {
                                        const typed_ptr: [*]u32 = @alignCast(@ptrCast(opaque_ptr));
                                        const value = typed_ptr[0..prop.value_len];
                                        std.debug.print("={any})\n", .{value});
                                    },
                                    else => {},
                                }
                            }
                        } else {
                            defer c.free(err);
                            std.debug.print("XCB resource {} error code {}", .{ err.*.resource_id, err.*.error_code });
                        }
                    } else {
                        std.debug.assert(e.state == c.XCB_PROPERTY_DELETE);
                        std.debug.print("-)\n", .{});
                    }
                },
                c.XCB_CONFIGURE_NOTIFY => {
                    const e: *c.xcb_configure_notify_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} ConfigureNotify ({},{},{},{}) border:{} above:0x{X} force:{}\n", .{
                        e.window,
                        e.x,
                        e.y,
                        e.width,
                        e.height,
                        e.border_width,
                        e.above_sibling,
                        e.override_redirect,
                    });
                },
                c.XCB_MAPPING_NOTIFY => {
                    const e: *c.xcb_mapping_notify_event_t = @ptrCast(generic_event);
                    std.debug.print("MappingNotify {s} first_keycode:{} count:{}\n", .{
                        switch (e.request) {
                            c.XCB_MAPPING_MODIFIER => "Modifier",
                            c.XCB_MAPPING_KEYBOARD => "Keyboard",
                            c.XCB_MAPPING_POINTER => "Pointer",
                            else => "?",
                        },
                        e.first_keycode,
                        e.count,
                    });
                },
                c.XCB_CLIENT_MESSAGE => {
                    const e: *const c.xcb_client_message_event_t = @ptrCast(generic_event);
                    switch (e.format) {
                        8 => {},
                        16 => {},
                        32 => if (e.data.data32[0] == self.wm_delete_window_atom) {},
                        else => {},
                    }
                },
                else => {
                    if (response_type == self.xkb_base_event + c.XCB_XKB_NEW_KEYBOARD_NOTIFY) {
                        const e: *const c.xcb_xkb_new_keyboard_notify_event_t = @ptrCast(generic_event);
                        std.debug.print("XkbNewKeyboardNotify {}\n", .{e.deviceID});
                        // TODO: no catch
                        self.xkb_recreate() catch {};
                    } else if (response_type == self.xkb_base_event + c.XCB_XKB_MAP_NOTIFY) {
                        const e: *const c.xcb_xkb_map_notify_event_t = @ptrCast(generic_event);
                        std.debug.print("XkbMapNotify {}\n", .{e.deviceID});
                        // TODO: no catch
                        self.xkb_recreate() catch {};
                    } else if (response_type == self.xkb_base_event + c.XCB_XKB_STATE_NOTIFY) {
                        const e: *const c.xcb_xkb_state_notify_event_t = @ptrCast(generic_event);
                        std.debug.print("XkbStateNotify {}\n", .{e.deviceID});
                        _ = c.xkb_state_update_mask(
                            self.xkb_state,
                            e.mods,
                            e.latchedMods,
                            e.lockedMods,
                            @intCast(e.baseGroup),
                            @intCast(e.latchedGroup),
                            @intCast(e.lockedGroup),
                        );
                    } else {
                        std.debug.print("WARNING: unhandled event {}\n", .{response_type});
                    }
                },
            }
        }
        return null;
    }

    fn xkb_recreate(self: *XcbUi) error{ XkbKeymapNewError, XkbStateNewError }!void {
        c.xkb_keymap_unref(self.xkb_keymap);
        c.xkb_state_unref(self.xkb_state);

        self.xkb_keymap = c.xkb_x11_keymap_new_from_device(
            self.xkb_context,
            self.connection,
            self.xkb_device_id,
            c.XKB_KEYMAP_COMPILE_NO_FLAGS,
        ) orelse return error.XkbKeymapNewError;

        self.xkb_state = c.xkb_x11_state_new_from_device(
            self.xkb_keymap,
            self.connection,
            self.xkb_device_id,
        ) orelse return error.XkbStateNewError;
    }

    pub fn kill(self: XcbUi) void {
        c.xcb_disconnect(self.connection);
        {
            c.xkb_state_unref(self.xkb_state);
            c.xkb_keymap_unref(self.xkb_keymap);
            c.xkb_context_unref(self.xkb_context);
        }
    }

    pub fn init(self: *XcbUi) !void {
        std.debug.print("\n=== XCB ===\n", .{});

        self.connection = c.xcb_connect(null, null) orelse
            return error.XcbConnectionMissing;

        std.debug.assert(self.connection != @as(*c.xcb_connection_t, @ptrFromInt(int_invalid)));

        if (c.xcb_connection_has_error(self.connection) != 0) {
            return error.XcbConnectionError;
        }

        const setup: *const c.xcb_setup_t = c.xcb_get_setup(self.connection) orelse return error.XcbSetup;
        var iter = c.xcb_setup_roots_iterator(setup);
        const first_screen = iter.data.*;
        // NOTE: rem is confusingly 1 on the last iterator element, when there is 0 remaining
        while (iter.rem != 0) {
            const screen = iter.data.*;
            std.debug.print("Screen {} ({} x {} px / {} x {} mm)\n", .{
                iter.index,
                screen.width_in_pixels,
                screen.height_in_pixels,
                screen.width_in_millimeters,
                screen.height_in_millimeters,
            });
            c.xcb_screen_next(&iter);
        }

        self.window = c.xcb_generate_id(self.connection);
        std.debug.assert(self.window != int_invalid);
        const value_mask: u32 = c.XCB_CW_EVENT_MASK;
        const value_list = [_]u32{
            c.XCB_EVENT_MASK_KEY_PRESS |
                c.XCB_EVENT_MASK_KEY_RELEASE |
                c.XCB_EVENT_MASK_BUTTON_PRESS |
                c.XCB_EVENT_MASK_BUTTON_RELEASE |
                c.XCB_EVENT_MASK_ENTER_WINDOW |
                c.XCB_EVENT_MASK_LEAVE_WINDOW |
                c.XCB_EVENT_MASK_POINTER_MOTION |
                c.XCB_EVENT_MASK_EXPOSURE |
                c.XCB_EVENT_MASK_VISIBILITY_CHANGE |
                c.XCB_EVENT_MASK_STRUCTURE_NOTIFY |
                c.XCB_EVENT_MASK_FOCUS_CHANGE |
                c.XCB_EVENT_MASK_PROPERTY_CHANGE,
        };

        _ = c.xcb_create_window(
            self.connection,
            c.XCB_COPY_FROM_PARENT,
            self.window,
            first_screen.root,
            0,
            0,
            200,
            200,
            0,
            c.XCB_WINDOW_CLASS_INPUT_OUTPUT,
            first_screen.root_visual,
            value_mask,
            &value_list,
        );

        const title = "dwarven";
        _ = c.xcb_change_property(
            self.connection,
            c.XCB_PROP_MODE_REPLACE,
            self.window,
            c.XCB_ATOM_WM_NAME,
            c.XCB_ATOM_STRING,
            8,
            title.len,
            title,
        );

        // TODO: how to use?
        const title_icon = "dwarven\x00";
        _ = c.xcb_change_property(
            self.connection,
            c.XCB_PROP_MODE_REPLACE,
            self.window,
            c.XCB_ATOM_WM_ICON_NAME,
            c.XCB_ATOM_STRING,
            8,
            title_icon.len,
            title_icon,
        );

        _ = c.xcb_map_window(self.connection, self.window);

        const wm_protocols_str = "WM_PROTOCOLS";
        const wm_protocols_cookie = c.xcb_intern_atom(
            self.connection,
            1,
            @intCast(wm_protocols_str.len),
            wm_protocols_str.ptr,
        );

        const wm_delete_window_str = "WM_DELETE_WINDOW";
        const wm_delete_window_cookie = c.xcb_intern_atom(
            self.connection,
            0,
            @intCast(wm_delete_window_str.len),
            wm_delete_window_str.ptr,
        );

        const wm_protocols_atom = try intern_atom_reply(self.connection, wm_protocols_cookie);
        self.wm_delete_window_atom = try intern_atom_reply(self.connection, wm_delete_window_cookie);

        _ = c.xcb_change_property(
            self.connection,
            c.XCB_PROP_MODE_REPLACE,
            self.window,
            wm_protocols_atom,
            c.XCB_ATOM_ATOM,
            32,
            1,
            &self.wm_delete_window_atom,
        );

        _ = c.xcb_flush(self.connection);

        {
            self.xkb_context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS) orelse
                return error.XkbContextNewError;

            {
                const result = c.xkb_x11_setup_xkb_extension(
                    self.connection,
                    c.XKB_X11_MIN_MAJOR_XKB_VERSION,
                    c.XKB_X11_MIN_MINOR_XKB_VERSION,
                    c.XKB_X11_SETUP_XKB_EXTENSION_NO_FLAGS,
                    null,
                    null,
                    &self.xkb_base_event,
                    &self.xkb_base_error,
                );
                assert(result == 1);
            }

            self.xkb_device_id = c.xkb_x11_get_core_keyboard_device_id(self.connection);
            if (self.xkb_device_id == -1) {
                return error.XkbKeyboardDeviceError;
            }

            self.xkb_keymap = c.xkb_x11_keymap_new_from_device(
                self.xkb_context,
                self.connection,
                self.xkb_device_id,
                c.XKB_KEYMAP_COMPILE_NO_FLAGS,
            ) orelse return error.XkbKeymapNewError;

            self.xkb_state = c.xkb_x11_state_new_from_device(
                self.xkb_keymap,
                self.connection,
                self.xkb_device_id,
            ) orelse return error.XkbStateNewError;

            const mask = c.XCB_XKB_EVENT_TYPE_NEW_KEYBOARD_NOTIFY | c.XCB_XKB_EVENT_TYPE_MAP_NOTIFY | c.XCB_XKB_EVENT_TYPE_STATE_NOTIFY;
            _ = c.xcb_xkb_select_events_aux(
                self.connection,
                @intCast(self.xkb_device_id),
                mask,
                0,
                mask,
                0,
                0,
                null,
            );
        }
    }
};

fn intern_atom_reply(connection: *c.xcb_connection_t, cookie: c.xcb_intern_atom_cookie_t) !c.xcb_atom_t {
    var err: [*c]c.xcb_generic_error_t = undefined;
    const reply: ?*c.xcb_intern_atom_reply_t = c.xcb_intern_atom_reply(connection, cookie, &err);
    if (reply) |r| {
        defer c.free(r);
        return reply.?.atom;
    } else {
        defer c.free(err);
        std.debug.print("XCB resource {} error code {}", .{ err.*.resource_id, err.*.error_code });
        return error.XCBError;
    }
}
