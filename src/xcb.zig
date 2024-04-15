const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("xcb/xcb.h");
});
const Input = @import("input.zig").Input;

// DOCS: https://www.x.org/releases/X11R7.5/doc/x11proto/proto.pdf
// DOCS: https://specifications.freedesktop.org/wm-spec/1.4/ar01s05.html

const int_invalid = 0xDEAD;

pub const XcbUi = struct {
    connection: *c.struct_xcb_connection_t = @ptrFromInt(int_invalid),
    window: c.xcb_window_t = int_invalid,
    wm_delete_window_atom: c.xcb_atom_t = int_invalid,

    pub fn frameConsume(self: *XcbUi, input: *Input) void {
        for (0..100) |_| {
            const generic_event: *c.xcb_generic_event_t = c.xcb_poll_for_event(self.connection) orelse return;
            defer c.free(generic_event);

            const response_type = generic_event.response_type & 0x7F;
            switch (response_type) {
                c.XCB_NONE => {
                    const e: *c.xcb_generic_error_t = @ptrCast(generic_event);
                    std.debug.print("XCB error code {}", .{e.error_code});
                },
                c.XCB_KEY_PRESS => {
                    const e: *c.xcb_key_press_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} KeyPress {} state:0b{b} ({},{}) root:({},{})\n", .{ e.event, e.detail, e.state, e.event_x, e.event_y, e.root_x, e.root_y });
                    input.keys.set(e.detail);
                },
                c.XCB_KEY_RELEASE => {
                    const e: *c.xcb_key_release_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} KeyRelease {} state:0b{b} ({},{}) root:({},{})\n", .{ e.event, e.detail, e.state, e.event_x, e.event_y, e.root_x, e.root_y });
                    input.keys.unset(e.detail);
                },
                c.XCB_BUTTON_PRESS => {
                    const e: *c.xcb_button_press_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} ButtonPress {} state:0b{b} ({},{}) root:({},{})\n", .{ e.event, e.detail, e.state, e.event_x, e.event_y, e.root_x, e.root_y });
                    input.keys.set(e.detail);
                },
                c.XCB_BUTTON_RELEASE => {
                    const e: *c.xcb_button_release_event_t = @ptrCast(generic_event);
                    std.debug.print("0x{X} ButtonRelease {} state:0b{b} ({},{}) root:({},{})\n", .{ e.event, e.detail, e.state, e.event_x, e.event_y, e.root_x, e.root_y });
                    input.keys.unset(e.detail);
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
                    input.wm.flags |= @intFromEnum(Input.Wm.Event.resize);
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
                        32 => if (e.data.data32[0] == self.wm_delete_window_atom) {
                            input.wm.flags |= @intFromEnum(Input.Wm.Event.delete);
                        },
                        else => {},
                    }
                },
                else => {
                    std.debug.print("WARNING: unhandled event {}\n", .{generic_event.response_type});
                },
            }
        }
    }

    pub fn kill(self: XcbUi) void {
        c.xcb_disconnect(self.connection);
    }

    pub fn init(self: *XcbUi) !void {
        std.debug.print("\n=== XCB ===\n", .{});

        self.connection = c.xcb_connect(null, null) orelse {
            return error.XcbConnectionMissing;
        };
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

        const title = "dwarfare";
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
        const title_icon = "dwarfare (icon)";
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
            const first_keycode = setup.min_keycode;
            const count = setup.max_keycode - setup.min_keycode;

            // TODO: get mapping on MappingNotify

            const keyboard_mapping = c.xcb_get_keyboard_mapping(
                self.connection,
                first_keycode,
                count,
            );
            const reply: *c.xcb_get_keyboard_mapping_reply_t = c.xcb_get_keyboard_mapping_reply(
                self.connection,
                keyboard_mapping,
                null,
            ) orelse return error.XcbKeyMap;
            defer c.free(reply);

            const keysyms_per_keycode = reply.keysyms_per_keycode;
            const keysyms = c.xcb_get_keyboard_mapping_keysyms(reply);

            // TODO: use global preallocated memory with max size
            var keysym_map = std.AutoArrayHashMap(u32, []const u8).init(std.heap.page_allocator);

            // TODO: fill keysym map with, don't hardcode
            // xkb_keysym_to_utf8(xkb_keysym_t keysym, char *buffer, size_t size)
            try keysym_map.putNoClobber(0xff1b, "Escape");

            for (first_keycode..(first_keycode + count)) |keycode| {
                std.debug.print("Keycode {d} -> (", .{keycode});
                const offset = (keycode - first_keycode) * keysyms_per_keycode;
                for (0..keysyms_per_keycode) |i| {
                    const index = offset + i;
                    const keysym = keysyms[index];
                    if (keysym == 0) {
                        break;
                    } else if (i != 0) {
                        std.debug.print(" ", .{});
                    }

                    if (keysym_map.get(keysym)) |name| {
                        std.debug.print("{s}", .{name});
                    } else {
                        std.debug.print("{x}", .{keysym});
                    }
                }
                std.debug.print(")\n", .{});
            }
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
