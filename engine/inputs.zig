const c = @import("clibs");

const std = @import("std");

const Vec2 = @import("math3d.zig").Vec2;

pub const ScanCode = enum(c_int) {
    unknown = 0,
    a = 4,
    b = 5,
    c = 6,
    d = 7,
    e = 8,
    f = 9,
    g = 10,
    h = 11,
    i = 12,
    j = 13,
    k = 14,
    l = 15,
    m = 16,
    n = 17,
    o = 18,
    p = 19,
    q = 20,
    r = 21,
    s = 22,
    t = 23,
    u = 24,
    v = 25,
    w = 26,
    x = 27,
    y = 28,
    z = 29,
    num1 = 30,
    num2 = 31,
    num3 = 32,
    num4 = 33,
    num5 = 34,
    num6 = 35,
    num7 = 36,
    num8 = 37,
    num9 = 38,
    num0 = 39,
    enter = 40,
    escape = 41,
    backspace = 42,
    tab = 43,
    space = 44,
    minus = 45,
    equals = 46,
    left_bracket = 47,
    right_bracket = 48,
    backslash = 49,
    nonushash = 50,
    semicolon = 51,
    apostrophe = 52,
    grave = 53,
    comma = 54,
    period = 55,
    slash = 56,
    capslock = 57,
    f1 = 58,
    f2 = 59,
    f3 = 60,
    f4 = 61,
    f5 = 62,
    f6 = 63,
    f7 = 64,
    f8 = 65,
    f9 = 66,
    f10 = 67,
    f11 = 68,
    f12 = 69,
    print_screen = 70,
    scroll_lock = 71,
    pause = 72,
    insert = 73,
    home = 74,
    page_up = 75,
    delete = 76,
    end = 77,
    page_down = 78,
    right = 79,
    left = 80,
    down = 81,
    up = 82,
    numlock_clear = 83,
    keypad_divide = 84,
    keypad_multiply = 85,
    keypad_minus = 86,
    keypad_plus = 87,
    keypad_enter = 88,
    keypad1 = 89,
    keypad2 = 90,
    keypad3 = 91,
    keypad4 = 92,
    keypad5 = 93,
    keypad6 = 94,
    keypad7 = 95,
    keypad8 = 96,
    keypad9 = 97,
    keypad0 = 98,
    keypad_period = 99,
    nonusbackslash = 100,
    application = 101,
    power = 102,
    keypad_equals = 103,
    f13 = 104,
    f14 = 105,
    f15 = 106,
    f16 = 107,
    f17 = 108,
    f18 = 109,
    f19 = 110,
    f20 = 111,
    f21 = 112,
    f22 = 113,
    f23 = 114,
    f24 = 115,
    execute = 116,
    help = 117,
    menu = 118,
    select = 119,
    stop = 120,
    again = 121,
    undo = 122,
    cut = 123,
    copy = 124,
    paste = 125,
    find = 126,
    mute = 127,
    volume_up = 128,
    volume_down = 129,
    kP_COMMA = 133,
    kP_EQUALSAS400 = 134,
    international1 = 135,
    international2 = 136,
    international3 = 137,
    international4 = 138,
    international5 = 139,
    international6 = 140,
    international7 = 141,
    international8 = 142,
    international9 = 143,
    lang1 = 144,
    lang2 = 145,
    lang3 = 146,
    lang4 = 147,
    lang5 = 148,
    lang6 = 149,
    lang7 = 150,
    lang8 = 151,
    lang9 = 152,
    alterase = 153,
    sysreq = 154,
    cancel = 155,
    clear = 156,
    prior = 157,
    return2 = 158,
    separator = 159,
    out = 160,
    oper = 161,
    clearagain = 162,
    crsel = 163,
    exsel = 164,
    keypad00 = 176,
    keypad000 = 177,
    thousands_separator = 178,
    decimalseparator = 179,
    currencyunit = 180,
    currencysubunit = 181,
    keypad_left_paren = 182,
    keypad_right_paren = 183,
    keypad_left_brace = 184,
    keypad_right_brace = 185,
    keypad_tab = 186,
    keypad_backspace = 187,
    keypad_a = 188,
    keypad_b = 189,
    keypad_c = 190,
    keypad_d = 191,
    keypad_e = 192,
    keypad_f = 193,
    keypad_xor = 194,
    keypad_power = 195,
    keypad_percent = 196,
    keypad_less = 197,
    keypad_greater = 198,
    keypad_ampersand = 199,
    keypad_double_ampersand = 200,
    keypad_vertical_bar = 201,
    keypad_double_verticalbar = 202,
    keypad_colon = 203,
    keypad_hash = 204,
    keypad_space = 205,
    keypad_at = 206,
    keypad_exclam = 207,
    keypad_mem_store = 208,
    keypad_mem_recall = 209,
    keypad_mem_clear = 210,
    keypad_mem_add = 211,
    keypad_mem_subtract = 212,
    keypad_mem_multiply = 213,
    keypad_mem_divide = 214,
    keypad_plus_minus = 215,
    keypad_clear = 216,
    keypad_clearentry = 217,
    keypad_binary = 218,
    keypad_octal = 219,
    keypad_decimal = 220,
    keypad_hexadecimal = 221,
    left_ctrl = 224,
    left_shift = 225,
    left_alt = 226,
    left_gui = 227,
    right_ctrl = 228,
    right_shift = 229,
    right_alt = 230,
    right_gui = 231,
    mode = 257,
    audionext = 258,
    audioprev = 259,
    audiostop = 260,
    audioplay = 261,
    audiomute = 262,
    mediaselect = 263,
    www = 264,
    mail = 265,
    calculator = 266,
    computer = 267,
    ac_search = 268,
    ac_home = 269,
    ac_back = 270,
    ac_forward = 271,
    ac_stop = 272,
    ac_refresh = 273,
    ac_bookmarks = 274,
    brightness_down = 275,
    brightness_up = 276,
    display_switch = 277,
    keyboard_illumination_toggle = 278,
    keyboard_illumination_down = 279,
    keyboard_illumination_up = 280,
    eject = 281,
    sleep = 282,
    app1 = 283,
    app2 = 284,
    audio_rewind = 285,
    audio_fastforward = 286,
    soft_left = 287,
    soft_right = 288,
    call = 289,
    end_call = 290,
};

pub const MouseButton = enum {
    left,
    middle,
    right,
};

pub const KeyState = enum(u2) {
    up,
    pressed,
    down,
};

pub const InputContext = struct {
    const Self = @This();
    const ScancodeStates = [c.SDL_SCANCODE_COUNT]KeyState;
    const MouseButtonStates = [3]KeyState; // Assuming left, middle, and right mouse buttons

    window: *c.SDL_Window,

    by_scancode: ScancodeStates = std.mem.zeroes(ScancodeStates),
    by_mouse_button: MouseButtonStates = std.mem.zeroes(MouseButtonStates),
    mouse_wheel: Vec2 = Vec2.ZERO,
    mouse_pos: Vec2 = Vec2.ZERO,
    mouse_delta: Vec2 = Vec2.ZERO,
    mouse_rel: Vec2 = Vec2.ZERO,

    pub fn clear(self: *Self) void {
        self.mouse_wheel = Vec2.ZERO;
        self.mouse_delta = Vec2.ZERO;

        // SDL doesn't repeat mouse buttons?
        for (0..self.by_mouse_button.len) |i| {
            if (self.by_mouse_button[i] == .pressed) {
                self.by_mouse_button[i] = .down;
            }
        }
    }

    pub fn push(self: *Self, e: *c.SDL_Event) void {
        switch (e.type) {
            c.SDL_EVENT_KEY_DOWN => {
                self.by_scancode[e.key.scancode] =
                    if (self.by_scancode[e.key.scancode] == .up) .pressed else .down;
            },
            c.SDL_EVENT_KEY_UP => {
                self.by_scancode[e.key.scancode] = .up;
            },
            c.SDL_EVENT_MOUSE_WHEEL => {
                self.mouse_wheel = Vec2.make(e.wheel.x, e.wheel.y);
            },
            c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                const button_idx: usize = switch (e.button.button) {
                    c.SDL_BUTTON_LEFT => 0,
                    c.SDL_BUTTON_MIDDLE => 1,
                    c.SDL_BUTTON_RIGHT => 2,
                    else => return,
                };

                self.by_mouse_button[button_idx] =
                    if (self.by_mouse_button[button_idx] == .up) .pressed else .down;
            },
            c.SDL_EVENT_MOUSE_BUTTON_UP => {
                const button_idx: usize = switch (e.button.button) {
                    c.SDL_BUTTON_LEFT => 0,
                    c.SDL_BUTTON_MIDDLE => 1,
                    c.SDL_BUTTON_RIGHT => 2,
                    else => return,
                };
                self.by_mouse_button[button_idx] = .up;
            },
            c.SDL_EVENT_MOUSE_MOTION => {
                const new_mouse_pos = Vec2.make(e.motion.x, e.motion.y);
                self.mouse_delta = new_mouse_pos.sub(self.mouse_pos);
                self.mouse_pos = new_mouse_pos;

                if (c.SDL_GetWindowRelativeMouseMode(self.window)) {
                    self.mouse_rel = Vec2.make(e.motion.xrel, e.motion.yrel);
                }
            },
            else => {},
        }
    }

    pub inline fn isKeyDown(self: *Self, scancode: ScanCode) bool {
        return switch (self.stateOf(scancode)) {
            inline .down, .pressed => true,
            else => false,
        };
    }

    pub inline fn inKeyUp(self: *Self, scancode: ScanCode) bool {
        return self.stateOf(scancode) == .up;
    }

    pub inline fn inKeyPressed(self: *Self, scancode: ScanCode) bool {
        return self.stateOf(scancode) == .pressed;
    }

    pub inline fn isMouseButtonDown(self: *Self, button: MouseButton) bool {
        return switch (self.by_mouse_button[mouseIx(button)]) {
            inline .down, .pressed => true,
            else => false,
        };
    }

    pub inline fn isMouseButtonUp(self: *Self, button: MouseButton) bool {
        return self.by_mouse_button[mouseIx(button)] == .up;
    }

    pub inline fn isMouseButtonPressed(self: *Self, button: MouseButton) bool {
        return self.by_mouse_button[mouseIx(button)] == .pressed;
    }

    pub inline fn mouseWheel(self: *Self) Vec2 {
        return self.mouse_wheel;
    }

    pub inline fn mousePos(self: *Self) Vec2 {
        return self.mouse_pos;
    }

    pub inline fn mouseDelta(self: *Self) Vec2 {
        return self.mouse_delta;
    }

    pub inline fn mouseRelative(self: *Self) Vec2 {
        _ = self;
        var xrel: f32 = 0;
        var yrel: f32 = 0;
        _ = c.SDL_GetRelativeMouseState(&xrel, &yrel);
        const speed = (xrel * xrel) + (yrel * yrel);
        if (speed <= 1) {
            xrel = 0;
            yrel = 0;
        }

        return Vec2.make(xrel, yrel);
    }

    pub inline fn stateOf(self: *Self, scancode: ScanCode) KeyState {
        return self.by_scancode[@intCast(@intFromEnum(scancode))];
    }

    pub inline fn setRelativeMouseMode(self: *Self, enabled: bool) void {
        if (!c.SDL_GetWindowRelativeMouseMode(self.window)) {
            _ = c.SDL_GetRelativeMouseState(null, null);
        }
        _ = c.SDL_SetWindowRelativeMouseMode(self.window, enabled);
    }
};

// singleton global context
var context: ?InputContext = null;

pub fn init(window: *c.SDL_Window) error{AlreadyInitialized}!*InputContext {
    if (context != null) {
        return error.AlreadyInitialized;
    }

    context = .{ .window = window };
    return &context.?;
}

pub fn isKeyDown(scancode: ScanCode) bool {
    return context.stateOf(scancode) == .down;
}

pub fn mouseWheel() Vec2 {
    return context.mouseWheel();
}

pub fn stateOf(scancode: ScanCode) KeyState {
    return context.by_scancode[@intFromEnum(scancode)];
}

inline fn mouseIx(btn: MouseButton) usize {
    return switch (btn) {
        .left => 0,
        .middle => 1,
        .right => 2,
    };
}
