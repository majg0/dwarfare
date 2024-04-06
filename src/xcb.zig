const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("xcb/xcb.h");
});

pub const UIEvent = enum { Nop, Exit };

const modifiers = [_][]const u8{ "Shift", "Lock", "Ctrl", "Alt", "Mod2", "Mod3", "Mod4", "Mod5", "Button1", "Button2", "Button3", "Button4", "Button5" };

fn print_modifiers(mask: u16) void {
    inline for (modifiers, 0..modifiers.len) |mod, index| {
        if ((mask & (1 << index)) != 0) std.debug.print("{s} ", .{mod});
    }
}

const XCBUI = struct {
    connection: *c.struct_xcb_connection_t,
    wm_delete_window_atom: u32,

    pub fn poll(self: XCBUI) ?UIEvent {
        const generic_event: *c.xcb_generic_event_t = c.xcb_poll_for_event(self.connection) orelse return null;
        defer c.free(generic_event);

        const response_type = generic_event.response_type & 0x7F;
        switch (response_type) {
            c.XCB_BUTTON_PRESS => {
                const e: *c.xcb_button_press_event_t = @ptrCast(generic_event);

                print_modifiers(e.state);

                std.debug.print("Button{} pressed in window {} at ({}, {})\n", .{ e.detail, e.event, e.event_x, e.event_y });
            },
            c.XCB_BUTTON_RELEASE => {
                const e: *c.xcb_button_release_event_t = @ptrCast(generic_event);

                // NOTE: the released button is part of the mask, so we mask it out of the mask for a prettier print :)
                print_modifiers(e.state & ~std.math.shl(u16, 1, 7 + e.detail));

                std.debug.print("Button{} released in window {}, at coordinates ({}, {})\n", .{ e.detail, e.event, e.event_x, e.event_y });
            },
            c.XCB_CLIENT_MESSAGE => {
                const client_message: *const c.xcb_client_message_event_t = @ptrCast(generic_event);
                if (client_message.data.data32[0] == self.wm_delete_window_atom) {
                    return UIEvent.Exit;
                }
            },
            else => {
                std.debug.print("unhandled event {}\n", .{generic_event.response_type});
                return UIEvent.Nop;
            },
        }

        return UIEvent.Nop;
    }

    pub fn kill(self: XCBUI) void {
        c.xcb_disconnect(self.connection);
    }
};

pub fn init() !XCBUI {
    const connection: *c.struct_xcb_connection_t = c.xcb_connect(null, null) orelse {
        return error.XcbConnectionMissing;
    };

    if (c.xcb_connection_has_error(connection) != 0) {
        return error.XcbConnectionError;
    }

    const setup = c.xcb_get_setup(connection);
    const iter = c.xcb_setup_roots_iterator(setup);
    const screen = iter.data.*;

    const window = c.xcb_generate_id(connection);
    const value_mask: u32 = c.XCB_CW_EVENT_MASK;
    const value_list = [_]u32{0xFFFF};

    _ = c.xcb_create_window(connection, c.XCB_COPY_FROM_PARENT, window, screen.root, 0, 0, 200, 200, 0, c.XCB_WINDOW_CLASS_INPUT_OUTPUT, screen.root_visual, value_mask, &value_list);

    _ = c.xcb_map_window(connection, window);

    const wm_protocols_str = "WM_PROTOCOLS";
    const wm_delete_window_str = "WM_DELETE_WINDOW";
    const wm_protocols_atom = intern_atom(connection, 1, wm_protocols_str);
    const wm_delete_window_atom = intern_atom(connection, 0, wm_delete_window_str);
    var wm_protocol_atoms: [1]c.xcb_atom_t = .{wm_delete_window_atom};
    _ = c.xcb_change_property(connection, c.XCB_PROP_MODE_REPLACE, window, wm_protocols_atom, c.XCB_ATOM_ATOM, 32, 1, &wm_protocol_atoms);
    _ = c.xcb_flush(connection);

    return XCBUI{ .connection = connection, .wm_delete_window_atom = wm_delete_window_atom };
}

/// Helper function to obtain an XCB atom identifier.
fn intern_atom(connection: *c.xcb_connection_t, only_if_exists: u8, name: []const u8) c.xcb_atom_t {
    const cookie = c.xcb_intern_atom(connection, only_if_exists, @intCast(name.len), name.ptr);
    const reply = c.xcb_intern_atom_reply(connection, cookie, null);
    const atom = reply.*.atom;
    c.free(reply);
    return atom;
}
