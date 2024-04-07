const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("xcb/xcb.h");
});

// DOCS: https://www.x.org/releases/X11R7.5/doc/x11proto/proto.pdf

pub const UIEvent = enum { Nop, KeysChanged, Exit };

pub const Keys = struct {
    state: [32]u8,
    prev: [32]u8,

    pub fn set(self: *Keys, index: u8) void {
        self.state[index >> 3] |= std.math.shl(u8, 1, index & 7);
    }

    pub fn unset(self: *Keys, index: u8) void {
        self.state[index >> 3] &= ~std.math.shl(u8, 1, index & 7);
    }

    pub fn down(self: *Keys, index: u8) bool {
        return (self.state[index >> 3] & std.math.shl(u8, 1, index & 7)) != 0;
    }

    pub fn up(self: *Keys, index: u8) bool {
        return (self.state[index >> 3] & std.math.shl(u8, 1, index & 7)) == 0;
    }

    pub fn pressed(self: *Keys, index: u8) bool {
        return (self.prev[index >> 3] & std.math.shl(u8, 1, index & 7)) == 0 and self.down(index);
    }

    pub fn released(self: *Keys, index: u8) bool {
        return (self.prev[index >> 3] & std.math.shl(u8, 1, index & 7)) != 0 and self.up(index);
    }

    pub fn nextFrame(self: *Keys) void {
        std.mem.copyForwards(u8, &self.prev, &self.state);
    }
};

const XCBUI = struct {
    connection: *c.struct_xcb_connection_t,
    wm_delete_window_atom: u32,
    keys: Keys,

    pub fn update(self: *XCBUI) void {
        self.keys.nextFrame();
    }

    pub fn poll(self: *XCBUI) ?UIEvent {
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
                std.debug.print("0x{X} KeyPress {} (0b{b}) ({},{}) root:({},{})\n", .{ e.event, e.detail, e.state, e.event_x, e.event_y, e.root_x, e.root_y });
                self.keys.set(e.detail);
                return UIEvent.KeysChanged;
            },
            c.XCB_KEY_RELEASE => {
                const e: *c.xcb_key_release_event_t = @ptrCast(generic_event);
                std.debug.print("0x{X} KeyRelease {} (0b{b}) ({},{}) root:({},{})\n", .{ e.event, e.detail, e.state, e.event_x, e.event_y, e.root_x, e.root_y });
                self.keys.unset(e.detail);
                return UIEvent.KeysChanged;
            },
            c.XCB_BUTTON_PRESS => {
                const e: *c.xcb_button_press_event_t = @ptrCast(generic_event);
                std.debug.print("0x{X} ButtonPress {} (0b{b}) ({},{}) root:({},{})\n", .{ e.event, e.detail, e.state, e.event_x, e.event_y, e.root_x, e.root_y });
                self.keys.set(e.detail);
                return UIEvent.KeysChanged;
            },
            c.XCB_BUTTON_RELEASE => {
                const e: *c.xcb_button_release_event_t = @ptrCast(generic_event);
                std.debug.print("0x{X} ButtonRelease {} (0b{b}) ({},{}) root:({},{})\n", .{ e.event, e.detail, e.state, e.event_x, e.event_y, e.root_x, e.root_y });
                self.keys.unset(e.detail);
                return UIEvent.KeysChanged;
            },
            c.XCB_MOTION_NOTIFY => {
                const e: *c.xcb_motion_notify_event_t = @ptrCast(generic_event);
                std.debug.print("0x{X} MotionNotify (0b{b}) ({},{}) root:({},{})\n", .{ e.event, e.state, e.event_x, e.event_y, e.root_x, e.root_y });
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
            // pub const XCB_VISIBILITY_NOTIFY = @as(c_int, 15);
            // pub const XCB_MAP_NOTIFY = @as(c_int, 19);
            // pub const XCB_REPARENT_NOTIFY = @as(c_int, 21);
            // pub const XCB_CONFIGURE_NOTIFY = @as(c_int, 22);
            // pub const XCB_PROPERTY_NOTIFY = @as(c_int, 28);
            c.XCB_MAPPING_NOTIFY => {
                const e: *c.xcb_mapping_notify_event_t = @ptrCast(generic_event);
                // pub const XCB_MAPPING_MODIFIER: c_int = 0;
                // pub const XCB_MAPPING_KEYBOARD: c_int = 1;
                // pub const XCB_MAPPING_POINTER: c_int = 2;
                std.debug.print("MappingNotify {} {} {}\n", .{ e.request, e.first_keycode, e.count });
            },
            c.XCB_CLIENT_MESSAGE => {
                const e: *const c.xcb_client_message_event_t = @ptrCast(generic_event);
                switch (e.format) {
                    8 => {},
                    16 => {},
                    32 => if (e.data.data32[0] == self.wm_delete_window_atom) {
                        return UIEvent.Exit;
                    },
                    else => {},
                }
            },
            else => {
                std.debug.print("unhandled event {}\n", .{generic_event.response_type});
            },
        }

        return UIEvent.Nop;
    }

    pub fn kill(self: XCBUI) void {
        c.xcb_disconnect(self.connection);
    }
};

pub fn init() !XCBUI {
    std.debug.print("\n=== XCB ===\n", .{});

    const connection: *c.struct_xcb_connection_t = c.xcb_connect(null, null) orelse {
        return error.XcbConnectionMissing;
    };

    if (c.xcb_connection_has_error(connection) != 0) {
        return error.XcbConnectionError;
    }

    const setup = c.xcb_get_setup(connection);
    var iter = c.xcb_setup_roots_iterator(setup);
    const first_screen = iter.data.*;
    // NOTE: rem is confusingly 1 on the last iterator element, when there is 0 remaining
    while (iter.rem != 0) {
        const screen = iter.data.*;
        std.debug.print("Screen {} ({} x {} px / {} x {} mm)\n", .{ iter.index, screen.width_in_pixels, screen.height_in_pixels, screen.width_in_millimeters, screen.height_in_millimeters });
        c.xcb_screen_next(&iter);
    }

    const window = c.xcb_generate_id(connection);
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

    _ = c.xcb_create_window(connection, c.XCB_COPY_FROM_PARENT, window, first_screen.root, 0, 0, 200, 200, 0, c.XCB_WINDOW_CLASS_INPUT_OUTPUT, first_screen.root_visual, value_mask, &value_list);

    const title = "dwarfare";
    _ = c.xcb_change_property(connection, c.XCB_PROP_MODE_REPLACE, window, c.XCB_ATOM_WM_NAME, c.XCB_ATOM_STRING, 8, title.len, title);

    // TODO: how to use?
    const title_icon = "dwarfare (icon)";
    _ = c.xcb_change_property(connection, c.XCB_PROP_MODE_REPLACE, window, c.XCB_ATOM_WM_ICON_NAME, c.XCB_ATOM_STRING, 8, title_icon.len, title_icon);

    _ = c.xcb_map_window(connection, window);

    const wm_protocols_str = "WM_PROTOCOLS";
    const wm_protocols_cookie = c.xcb_intern_atom(connection, 1, @intCast(wm_protocols_str.len), wm_protocols_str.ptr);

    const wm_delete_window_str = "WM_DELETE_WINDOW";
    const wm_delete_window_cookie = c.xcb_intern_atom(connection, 0, @intCast(wm_delete_window_str.len), wm_delete_window_str.ptr);

    const wm_protocols_atom = try intern_atom_reply(connection, wm_protocols_cookie);
    const wm_delete_window_atom = try intern_atom_reply(connection, wm_delete_window_cookie);

    var wm_protocol_atoms: [1]c.xcb_atom_t = .{wm_delete_window_atom};
    _ = c.xcb_change_property(connection, c.XCB_PROP_MODE_REPLACE, window, wm_protocols_atom, c.XCB_ATOM_ATOM, 32, 1, &wm_protocol_atoms);

    _ = c.xcb_flush(connection);

    return XCBUI{ .connection = connection, .wm_delete_window_atom = wm_delete_window_atom, .keys = Keys{ .state = [_]u8{0} ** 32, .prev = [_]u8{0} ** 32 } };
}

fn intern_atom_reply(connection: *c.xcb_connection_t, cookie: c.xcb_intern_atom_cookie_t) !c.xcb_atom_t {
    var err: [*c]c.xcb_generic_error_t = undefined;
    const reply = c.xcb_intern_atom_reply(connection, cookie, &err) orelse {
        std.debug.print("XCB resource {} error code {}", .{ err.*.resource_id, err.*.error_code });
        c.free(err);
        return error.XCBError;
    };
    const atom = reply.*.atom;
    c.free(reply);
    return atom;
}
