const std = @import("std");
const c = @cImport({
    @cInclude("xcb/xcb.h");
});

pub const UIEvent = enum { Nop, Exit };

const XCBUI = struct {
    connection: *c.struct_xcb_connection_t,
    wm_delete_window_atom: u32,

    pub fn poll(self: XCBUI) ?UIEvent {
        const event: *c.xcb_generic_event_t = c.xcb_poll_for_event(self.connection) orelse return null;

        // Check event type
        const response_type = event.response_type & 0x7F;
        switch (response_type) {
            c.XCB_CLIENT_MESSAGE => {
                const client_message: *const c.xcb_client_message_event_t = @ptrCast(event);
                if (client_message.data.data32[0] == self.wm_delete_window_atom) {
                    return UIEvent.Exit;
                }
            },
            else => {
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

    // Get the first screen connected to the display
    const setup = c.xcb_get_setup(connection);
    const iter = c.xcb_setup_roots_iterator(setup);
    const screen = iter.data.*;

    // Generate an ID for the window
    const window = c.xcb_generate_id(connection);
    // Create the window
    _ = c.xcb_create_window(connection, // X server connection
        c.XCB_COPY_FROM_PARENT, // Use the same depth as the root window
        window, // The ID of the window to create
        screen.root, // Parent window ID, usually the root window of the screen
        0, 0, // x, y position of the top-left corner of the window
        200, 200, // width, height of the window
        10, // border width
        c.XCB_WINDOW_CLASS_INPUT_OUTPUT, // Type of the window
        screen.root_visual, // Visual type
        0, null // Masks and values for window attributes (not used here)
    );

    // Make the window visible on the screen
    _ = c.xcb_map_window(connection, window);

    // Set up window close event handling
    const wm_protocols_str = "WM_PROTOCOLS";
    const wm_delete_window_str = "WM_DELETE_WINDOW";
    // Obtain atoms for WM protocols and delete window
    const wm_protocols_atom = intern_atom(connection, 1, wm_protocols_str);
    const wm_delete_window_atom = intern_atom(connection, 0, wm_delete_window_str);
    var wm_protocol_atoms: [1]c.xcb_atom_t = .{wm_delete_window_atom};
    // Change window property to listen for WM_DELETE_WINDOW messages
    _ = c.xcb_change_property(connection, c.XCB_PROP_MODE_REPLACE, window, wm_protocols_atom, c.XCB_ATOM_ATOM, 32, 1, &wm_protocol_atoms);
    // Flush commands to the X server
    _ = c.xcb_flush(connection);

    return XCBUI{ .connection = connection, .wm_delete_window_atom = wm_delete_window_atom };
}

/// Helper function to obtain an XCB atom identifier.
fn intern_atom(connection: *c.xcb_connection_t, only_if_exists: u8, name: []const u8) c.xcb_atom_t {
    const cookie = c.xcb_intern_atom(connection, only_if_exists, @intCast(name.len), name.ptr);
    const reply = c.xcb_intern_atom_reply(connection, cookie, null);
    const atom = reply.*.atom;
    return atom;
}
