const std = @import("std");

// /// NOTE: this is not a complete list
// const MouseButton = enum(u8) {
//     left = 1,
//     mid = 2,
//     right = 3,
//     scroll_up = 4,
//     scroll_down = 5,
// };

// /// NOTE: this is not a complete list
// const Keycode = enum(u16) {
//     // ?
//     escape = 9,
//     digit1 = 10,
//     digit2 = 11,
//     digit3 = 12,
//     digit4 = 13,
//     digit5 = 14,
//     digit6 = 15,
//     digit7 = 16,
//     digit8 = 17,
//     digit9 = 18,
//     digit0 = 19,
//     minus = 20,
//     equal = 21,
//     backspace = 22,
//     tab = 23,
//     q = 24,
//     w = 25,
//     e = 26,
//     r = 27,
//     t = 28,
//     y = 29,
//     u = 30,
//     i = 31,
//     o = 32,
//     p = 33,
//     bracket_left = 34,
//     bracket_right = 35,
//     enter = 36,
//     ctrl_left = 37,
//     a = 38,
//     s = 39,
//     d = 40,
//     f = 41,
//     g = 42,
//     h = 43,
//     j = 44,
//     k = 45,
//     l = 46,
//     semicolon = 47,
//     quote_single = 48,
//     quote_back = 49,
//     shift_left = 50,
//     slash_back = 51,
//     z = 52,
//     x = 53,
//     c = 54,
//     v = 55,
//     b = 56,
//     n = 57,
//     m = 58,
//     comma = 59,
//     period = 60,
//     slash_forward = 61,
//     shift_right = 62,
//     numpad_multiply = 63,
//     alt_left = 64,
//     space = 65,
//     caps_lock = 66,
//     f1 = 67,
//     f2 = 68,
//     f3 = 69,
//     f4 = 70,
//     f5 = 71,
//     f6 = 72,
//     f7 = 73,
//     f8 = 74,
//     f9 = 75,
//     f10 = 76,
//     num_lock = 77,
//     scroll_lock = 78,
//     numpad_7 = 79,
//     numpad_8 = 80,
//     numpad_9 = 81,
//     numpad_subtract = 82,
//     numpad_4 = 83,
//     numpad_5 = 84,
//     numpad_6 = 85,
//     numpad_add = 86,
//     numpad_1 = 87,
//     numpad_2 = 88,
//     numpad_3 = 89,
//     numpad_0 = 90,
//     numpad_decimal = 91,
//     // ?
//     less = 94,
//     f11 = 95,
//     f12 = 96,
//     // ?
//     numpad_enter = 104,
//     ctrl_right = 105,
//     numpad_divide = 106,
//     print = 107,
//     alt_right = 108,
//     // ?
//     home = 110,
//     arrow_up = 111,
//     page_up = 112,
//     arrow_left = 113,
//     arrow_right = 114,
//     end = 115,
//     arrow_down = 116,
//     page_down = 117,
//     insert = 118,
//     delete = 119,
//     // ?
//     pause = 127,
//     // ?
//     super_left = 133,
//     // ?
//     menu = 135,
//     // ?
//     xf86_calculator = 148,
//     // ?
//     xf86_explorer = 152,
//     // ?
//     xf86_mail = 163,
//     xf86_favorites = 164,
//     // ?
//     xf86_audio_next = 171,
//     xf86_audio_play = 172,
//     xf86_audio_prev = 173,
//     // ?
//     xf86_tools = 179,
//     xf86_home_page = 180,
//     // ?
//     xf86_search = 225,
// };

// key strokes, mouse moves, controller input, wm close, etc
const PhysicalInputEvent = union(enum) {
    key_press: struct { keycode: u8 },
};

// axes, states, etc
const LogicalInputEvent = struct {};

// logical input -> action
const Binding = struct {};

// what bindings are active
const UserContext = struct {};

// what's important to the user
const UserActionStanding = enum {
    jump,
    crouch,
};

const UserActionCrouching = enum {
    stand_up,
};

const UserActionAirborne = enum {};

const UserState = enum {
    standing,
    crouching,
    airborne,
};

test "input" {
    const t = std.testing;

    // var state = .standing;

    // const keycode_a = 0;
    // const keycode_b = 1;

    // // press space to jump
    // const jump: u8 = 0;
    // const space: u8 = 10;

    // 1. gather physical input (out of scope)
    // 2. set logical input

    try t.expect(true);
}
