const std = @import("std");
const builtin = @import("builtin");

const assert = std.debug.assert;

const win = @cImport({
    // HACK: workaround zig failing to resolve mingw's name macro (just the A vs W suffix based on UNICODE)
    @cDefine("MAKEINTRESOURCE", "MAKEINTRESOURCEA");
    // TODO: use 16-bit unicode
    // @cDefine("UNICODE", "1");
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("Windows.h");
});

const dwarven = @cImport({
    @cInclude("dwarven.h");
});

// LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);

fn wndProc(h_wnd: win.HWND, message: win.UINT, w_param: win.WPARAM, l_param: win.LPARAM) callconv(std.os.windows.WINAPI) win.LRESULT {
    switch (message) {
        // NOTE: when Alt is held while pressing another key, we end up in the sys key space
        // win.WM_SYSKEYDOWN => {},

        win.WM_KEYDOWN => {
            switch (w_param) {
                win.VK_ESCAPE => {
                    std.debug.print("can't escape, teehee!\n", .{});
                },
                else => {},
            }
        },
        // win.WM_SYSCHAR => {
        //     // NOTE: Windows plays a system notification sound when pressing Alt+Enter unless this message is handled. :)
        // },
        win.WM_DESTROY => {
            win.PostQuitMessage(0);
        },

        else => {
            return win.DefWindowProcA(h_wnd, message, w_param, l_param);
        },
    }

    return 0;
}

// h_inst_prev, lp_cmd_line, n_cmd_show
pub export fn main(h_inst: win.HINSTANCE, _: win.HINSTANCE, _: win.PWSTR, _: c_int) callconv(std.os.windows.WINAPI) c_int {
    dwarven.init();

    // NOTE: Allows the client area of the window to achieve 100% scaling while allowing non-client window content in a DPI sensitive fashion.
    _ = win.SetThreadDpiAwarenessContext(win.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    const window_title: [*c]const u8 = "Dwarven\x00";

    const screen_width = win.GetSystemMetrics(win.SM_CXSCREEN);
    const screen_height = win.GetSystemMetrics(win.SM_CYSCREEN);
    const window_class = win.WNDCLASSEXA{
        .cbClsExtra = 0,
        .cbSize = @sizeOf(win.WNDCLASSEXA),
        .cbWndExtra = 0,
        .hbrBackground = (win.COLOR_WINDOW + 1),
        // TODO: can we get load cursor working?
        .hCursor = win.LoadCursorA(0, win.IDC_ARROW),
        .hIcon = win.LoadIconA(h_inst, 0),
        .hIconSm = win.LoadIconA(h_inst, 0),
        .hInstance = h_inst,
        .lpfnWndProc = &wndProc,
        .lpszClassName = window_title,
        .lpszMenuName = 0,
        .style = win.CS_HREDRAW | win.CS_VREDRAW,
    };
    const atom = win.RegisterClassExA(&window_class);
    assert(atom != 0);

    const h_wnd = win.CreateWindowExA(
        0,
        window_title,
        window_title,
        win.WS_OVERLAPPEDWINDOW,
        screen_width >> 2,
        screen_height >> 2,
        screen_width >> 1,
        screen_height >> 1,
        0,
        0,
        h_inst,
        null,
    );
    assert(h_wnd != 0);

    var window_rect = win.struct_tagRECT{};
    _ = win.GetWindowRect(h_wnd, &window_rect);

    _ = win.ShowWindow(h_wnd, win.SW_SHOW);

    var msg = win.MSG{};
    while (msg.message != win.WM_QUIT) {
        if (win.PeekMessageA(&msg, 0, 0, 0, win.PM_REMOVE) != 0) {
            _ = win.TranslateMessage(&msg);
            _ = win.DispatchMessageA(&msg);
        }
    }

    dwarven.kill();

    return 0;
}
