pub const UpdateResult = enum(i32) {
    keep_running,
    stop_running,
};

pub const KeyCode = enum(i32) {
    unknown,

    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,

    num1,
    num2,
    num3,
    num4,
    num5,
    num6,
    num7,
    num8,
    num9,
    num0,

    enter,
    escape,
    backspace,
    tab,
    space,

    minus, // -
    equal, // =
    bracket_left, // [
    bracket_right, // ]
    backslash, // \
    semicolon, // ;
    apostrophe, // '
    grave, // `
    comma, // ,
    period, // .
    slash, // /
    less, // <

    caps_lock,

    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,

    print_screen,
    scroll_lock,
    pause_break,

    insert,
    delete,
    home,
    end,
    page_up,
    page_down,

    right,
    left,
    up,
    down,

    num_lock,
    numpad_div,
    numpad_mul,
    numpad_sub,
    numpad_add,
    numpad_enter,
    numpad_1,
    numpad_2,
    numpad_3,
    numpad_4,
    numpad_5,
    numpad_6,
    numpad_7,
    numpad_8,
    numpad_9,
    numpad_0,
    numpad_delete,

    menu,

    control_left,
    shift_left,
    alt_left,
    gui_left,
    control_right,
    shift_right,
    alt_right,
    gui_right,
};

pub const Event = extern struct {
    tag: enum(i32) {
        key_down,
        key_up,
    },
    data: extern union {
        key_down: extern struct {
            key_code: KeyCode,
        },
        key_up: extern struct {
            key_code: KeyCode,
        },
    },
};
