const c = @import("clibs");

const std = @import("std");

const Vec2 = @import("math3d.zig").Vec2;

pub const ScanCode = enum(c_int) {
    Unknown = 0,
    A = 4,
    B = 5,
    C = 6,
    D = 7,
    E = 8,
    F = 9,
    G = 10,
    H = 11,
    I = 12,
    J = 13,
    K = 14,
    L = 15,
    M = 16,
    N = 17,
    O = 18,
    P = 19,
    Q = 20,
    R = 21,
    S = 22,
    T = 23,
    U = 24,
    V = 25,
    W = 26,
    X = 27,
    Y = 28,
    Z = 29,
    Num1 = 30,
    Num2 = 31,
    Num3 = 32,
    Num4 = 33,
    Num5 = 34,
    Num6 = 35,
    Num7 = 36,
    Num8 = 37,
    Num9 = 38,
    Num0 = 39,
    Return = 40,
    Escape = 41,
    Backspace = 42,
    Tab = 43,
    Space = 44,
    Minus = 45,
    Equals = 46,
    LeftBracket = 47,
    RightBracket = 48,
    Backslash = 49,
    Nonushash = 50,
    Semicolon = 51,
    Apostrophe = 52,
    Grave = 53,
    Comma = 54,
    Period = 55,
    Slash = 56,
    Capslock = 57,
    F1 = 58,
    F2 = 59,
    F3 = 60,
    F4 = 61,
    F5 = 62,
    F6 = 63,
    F7 = 64,
    F8 = 65,
    F9 = 66,
    F10 = 67,
    F11 = 68,
    F12 = 69,
    PrintScreen = 70,
    ScrollLock = 71,
    Pause = 72,
    Insert = 73,
    Home = 74,
    PageUp = 75,
    Delete = 76,
    End = 77,
    PageDown = 78,
    Right = 79,
    Left = 80,
    Down = 81,
    Up = 82,
    NumlockClear = 83,
    KeyPadDivide = 84,
    KeypadMultiply = 85,
    KeypadMinus = 86,
    KeypadPlus = 87,
    KeypadEnter = 88,
    Keypad1 = 89,
    Keypad2 = 90,
    Keypad3 = 91,
    Keypad4 = 92,
    Keypad5 = 93,
    Keypad6 = 94,
    Keypad7 = 95,
    Keypad8 = 96,
    Keypad9 = 97,
    Keypad0 = 98,
    KeypadPeriod = 99,
    Nonusbackslash = 100,
    Application = 101,
    Power = 102,
    KeypadEquals = 103,
    F13 = 104,
    F14 = 105,
    F15 = 106,
    F16 = 107,
    F17 = 108,
    F18 = 109,
    F19 = 110,
    F20 = 111,
    F21 = 112,
    F22 = 113,
    F23 = 114,
    F24 = 115,
    Execute = 116,
    Help = 117,
    Menu = 118,
    Select = 119,
    Stop = 120,
    Again = 121,
    Undo = 122,
    Cut = 123,
    Copy = 124,
    Paste = 125,
    Find = 126,
    Mute = 127,
    VolumeUp = 128,
    VolumeDown = 129,
    KP_COMMA = 133,
    KP_EQUALSAS400 = 134,
    International1 = 135,
    International2 = 136,
    International3 = 137,
    International4 = 138,
    International5 = 139,
    International6 = 140,
    International7 = 141,
    International8 = 142,
    International9 = 143,
    Lang1 = 144,
    Lang2 = 145,
    Lang3 = 146,
    Lang4 = 147,
    Lang5 = 148,
    Lang6 = 149,
    Lang7 = 150,
    Lang8 = 151,
    Lang9 = 152,
    Alterase = 153,
    Sysreq = 154,
    Cancel = 155,
    Clear = 156,
    Prior = 157,
    Return2 = 158,
    Separator = 159,
    Out = 160,
    Oper = 161,
    Clearagain = 162,
    Crsel = 163,
    Exsel = 164,
    Keypad00 = 176,
    Keypad000 = 177,
    ThousandsSeparator = 178,
    Decimalseparator = 179,
    Currencyunit = 180,
    Currencysubunit = 181,
    KeypadLeftParen = 182,
    KeypadRightParen = 183,
    KeypadLeftBrace = 184,
    KeypadRightBrace = 185,
    KeypadTab = 186,
    KeypadBackspace = 187,
    KeypadA = 188,
    KeypadB = 189,
    KeypadC = 190,
    KeypadD = 191,
    KeypadE = 192,
    KeypadF = 193,
    KeypadXor = 194,
    KeypadPower = 195,
    KeypadPercent = 196,
    KeypadLess = 197,
    KeypadGreater = 198,
    KeypadAmpersand = 199,
    KeypadDoubleAmpersand = 200,
    KeypadVerticalBar = 201,
    KeypadDoubleVerticalbar = 202,
    KeypadColon = 203,
    KeypadHash = 204,
    KeypadSpace = 205,
    KeypadAt = 206,
    KeypadExclam = 207,
    KeypadMemStore = 208,
    KeypadMemRecall = 209,
    KeypadMemClear = 210,
    KeypadMemAdd = 211,
    KeypadMemSubtract = 212,
    KeypadMemMultiply = 213,
    KeypadMemDivide = 214,
    KeypadPlusMinus = 215,
    KeypadClear = 216,
    KeypadClearentry = 217,
    KeypadBinary = 218,
    KeypadOctal = 219,
    KeypadDecimal = 220,
    KeypadHexadecimal = 221,
    LeftCtrl = 224,
    LeftShift = 225,
    LeftAlt = 226,
    LeftGui = 227,
    RightCtrl = 228,
    RightShift = 229,
    RightAlt = 230,
    RightGui = 231,
    Mode = 257,
    Audionext = 258,
    Audioprev = 259,
    Audiostop = 260,
    Audioplay = 261,
    Audiomute = 262,
    Mediaselect = 263,
    Www = 264,
    Mail = 265,
    Calculator = 266,
    Computer = 267,
    AcSearch = 268,
    AcHome = 269,
    AcBack = 270,
    AcForward = 271,
    AcStop = 272,
    AcRefresh = 273,
    AcBookmarks = 274,
    BrightnessDown = 275,
    BrightnessUp = 276,
    DisplaySwitch = 277,
    KeyboardIlluminationToggle = 278,
    KeyboardIlluminationDown = 279,
    KeyboardIlluminationUp = 280,
    Eject = 281,
    Sleep = 282,
    App1 = 283,
    App2 = 284,
    AudioRewind = 285,
    AudioFastforward = 286,
    SoftLeft = 287,
    SoftRight = 288,
    Call = 289,
    EndCall = 290,
};

pub const MouseButton = enum {
    Left,
    Middle,
    Right,
};

pub const KeyState = enum(u1) {
    Up,
    Down,
};

pub const InputContext = struct {
    const Self = @This();
    const ScancodeStates = [c.SDL_NUM_SCANCODES]KeyState;
    const MouseButtonStates = [3]KeyState; // Assuming left, middle, and right mouse buttons

    by_scancode: ScancodeStates = std.mem.zeroes(ScancodeStates),
    by_mouse_button: MouseButtonStates = std.mem.zeroes(MouseButtonStates),
    mouse_wheel: Vec2 = Vec2.ZERO,
    mouse_pos: Vec2 = Vec2.ZERO,
    mouse_delta: Vec2 = Vec2.ZERO,

    pub fn clear(self: *Self) void {
        self.mouse_wheel = Vec2.ZERO;
        self.mouse_delta = Vec2.ZERO;
    }

    pub fn push(self: *Self, e: *c.SDL_Event) void {
        switch (e.type) {
            c.SDL_EVENT_KEY_DOWN => {
                self.by_scancode[e.key.keysym.scancode] = KeyState.Down;
            },
            c.SDL_EVENT_KEY_UP => {
                self.by_scancode[e.key.keysym.scancode] = KeyState.Up;
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
                self.by_mouse_button[button_idx] = KeyState.Down;
            },
            c.SDL_EVENT_MOUSE_BUTTON_UP => {
                const button_idx: usize = switch (e.button.button) {
                    c.SDL_BUTTON_LEFT => 0,
                    c.SDL_BUTTON_MIDDLE => 1,
                    c.SDL_BUTTON_RIGHT => 2,
                    else => return,
                };
                self.by_mouse_button[button_idx] = KeyState.Up;
            },
            c.SDL_EVENT_MOUSE_MOTION => {
                const new_mouse_pos = Vec2.make(e.motion.x, e.motion.y);
                self.mouse_delta = new_mouse_pos.sub(self.mouse_pos);
                self.mouse_pos = new_mouse_pos;
            },
            else => {},
        }
    }

    pub inline fn isKeyDown(self: *Self, scancode: ScanCode) bool {
        return self.stateOf(scancode) == KeyState.Down;
    }

    pub inline fn isMouseButtonDown(self: *Self, button: MouseButton) bool {
        const button_idx = switch (button) {
            MouseButton.Left => 0,
            MouseButton.Middle => 1,
            MouseButton.Right => 2,
        };
        return self.by_mouse_button[button_idx] == KeyState.Down;
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

    pub inline fn stateOf(self: *Self, scancode: ScanCode) KeyState {
        return self.by_scancode[@intFromEnum(scancode)];
    }
};

// singleton global context
var context: ?InputContext = null;

pub fn init() error{AlreadyInitialized}!*InputContext {
    if (context != null) {
        return error.AlreadyInitialized;
    }

    context = .{};
    return &context.?;
}

pub fn isKeyDown(scancode: ScanCode) bool {
    return context.stateOf(scancode) == KeyState.Down;
}

pub fn mouseWheel() Vec2 {
    return context.mouseWheel();
}

pub fn stateOf(scancode: ScanCode) KeyState {
    return context.by_scancode[@intFromEnum(scancode)];
}
