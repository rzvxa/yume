// TODO(zig): <https://github.com/ziglang/zig/issues/20682>
const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.Watch);

const Self = @This();

pub const supported_platform = Impl != void;
pub fn WatchCallback(comptime CTX: type) type {
    return *const fn (*CTX, Event) void;
}
pub const Event = union(enum) {
    const Path = []u8;

    add: Path,
    remove: Path,
    modify: Path,
    rename_old: Path,
    rename_new: Path,

    pub inline fn path(e: *const Event) []const u8 {
        return switch (e.*) {
            inline .add, .remove, .modify, .rename_old, .rename_new => |s| s,
        };
    }

    fn deinit(e: *const Event, allocator: std.mem.Allocator) void {
        return switch (e.*) {
            .add, .remove, .modify, .rename_old, .rename_new => |s| allocator.free(s),
        };
    }

    fn clone(e: *const Event, allocator: std.mem.Allocator) !Event {
        return switch (e.*) {
            .add => |s| .{ .add = try allocator.dupe(u8, s) },
            .remove => |s| .{ .remove = try allocator.dupe(u8, s) },
            .modify => |s| .{ .modify = try allocator.dupe(u8, s) },
            .rename_old => |s| .{ .rename_old = try allocator.dupe(u8, s) },
            .rename_new => |s| .{ .rename_new = try allocator.dupe(u8, s) },
        };
    }
};

allocator: std.mem.Allocator,

impl: Impl,

mutex: std.Thread.Mutex = .{},
events: std.ArrayListUnmanaged(Event) = .{},
last_error: ?anyerror = null,

const Impl = switch (builtin.os.tag) {
    .windows => struct {
        const fs = std.fs;
        const w = std.os.windows;
        const kernel32 = w.kernel32;

        callback: WatchCallback(anyopaque),
        callback_ctx: *anyopaque,

        dir_handle: w.HANDLE,
        event_handle: w.HANDLE,

        overlapped: w.OVERLAPPED,

        alive: std.atomic.Value(bool),
        thread: std.Thread,

        fn init(ptr: *Impl, path: []const u8, callback: WatchCallback(anyopaque), callback_ctx: *anyopaque) !void {
            const event_handle = kernel32.CreateEventExW(
                null,
                null,
                w.CREATE_EVENT_MANUAL_RESET,
                w.EVENT_ALL_ACCESS,
            ) orelse return error.CreateEventFailure;

            ptr.* = Impl{
                .callback = callback,
                .callback_ctx = callback_ctx,

                .dir_handle = try openDir(path),
                .event_handle = event_handle,
                .overlapped = std.mem.zeroInit(w.OVERLAPPED, .{ .hEvent = event_handle }),

                .alive = std.atomic.Value(bool).init(true),
                .thread = undefined,
            };

            ptr.thread = try std.Thread.spawn(.{}, threadFn, .{ptr});
        }

        fn deinit(impl: *Impl) void {
            impl.alive.store(false, .unordered);
            _ = kernel32.CancelIoEx(impl.dir_handle, &impl.overlapped);
            _ = kernel32.CloseHandle(impl.event_handle);
            impl.thread.join();
            _ = kernel32.CloseHandle(impl.dir_handle);
        }

        fn threadFn(impl: *Impl) !void {
            var buffer: [1024]u8 align(4) = undefined;
            var bytes_returned: u32 = 0;

            if (!impl.alive.load(.unordered)) {
                return;
            }
            while (true) {
                const read_res = kernel32.ReadDirectoryChangesW(
                    impl.dir_handle,
                    &buffer,
                    buffer.len,
                    w.TRUE, // watch subdirectories
                    w.FILE_NOTIFY_CHANGE_FILE_NAME | w.FILE_NOTIFY_CHANGE_LAST_WRITE,
                    null, // lpBytesReturned is not used in overlapped mode.
                    &impl.overlapped,
                    null, // no completion routine.
                );

                if (read_res == w.FALSE) {
                    const err = kernel32.GetLastError();
                    if (err != .IO_PENDING) {
                        log.err("ReadDirectoryChangesW failed with error: {}", .{err});
                        break;
                    }
                }

                // wait for the asynchronous I/O to signal completion.
                const wait_res = kernel32.WaitForSingleObject(impl.event_handle, w.INFINITE);
                switch (wait_res) {
                    w.WAIT_OBJECT_0 => {},
                    else => |err| {
                        log.err("WaitForSingleObject failed: {}", .{err});
                        break;
                    },
                }

                // retrieve the overlapped result.
                const get_res = kernel32.GetOverlappedResult(
                    impl.dir_handle,
                    &impl.overlapped,
                    &bytes_returned,
                    w.FALSE, // do not wait, since we've already waited.
                );
                if (get_res == w.FALSE) {
                    const err = kernel32.GetLastError();
                    if (err != .OPERATION_ABORTED) {
                        log.err("GetOverlappedResult failed with error: {}", .{err});
                    }
                    break;
                }

                if (bytes_returned > 0) {
                    impl.emitEventsFromInfoBuf(buffer[0..@intCast(bytes_returned)]) catch |e| log.warn("Dropped Watch event {}", .{e});
                }

                if (!impl.alive.load(.unordered)) {
                    break;
                }

                // only reset if alive to avoid race conditions on deinitialization
                _ = ResetEvent(impl.event_handle);
                impl.overlapped = std.mem.zeroes(w.OVERLAPPED);
                impl.overlapped.hEvent = impl.event_handle;
            }
        }

        fn openDir(sub_path: []const u8) !w.HANDLE {
            var buf: [w.MAX_PATH]u8 = undefined;
            const full_path = try std.fs.cwd().realpath(sub_path, &buf);

            var path_w: w.PathSpace = undefined;
            path_w.len = try std.unicode.wtf8ToWtf16Le(&path_w.data, full_path);
            path_w.data[path_w.len] = 0;

            // open the directory with the correct flags.
            const handle = kernel32.CreateFileW(
                path_w.span(),
                w.FILE_LIST_DIRECTORY,
                w.FILE_SHARE_READ | w.FILE_SHARE_WRITE | w.FILE_SHARE_DELETE,
                null,
                w.OPEN_EXISTING,
                w.FILE_FLAG_BACKUP_SEMANTICS | w.FILE_FLAG_OVERLAPPED,
                null,
            );
            if (handle == w.INVALID_HANDLE_VALUE) {
                return error.AccessDenied;
            }
            return handle;
        }

        extern "kernel32" fn ResetEvent(hEvent: w.HANDLE) callconv(w.WINAPI) w.BOOL;

        fn emitEventsFromInfoBuf(impl: *Impl, buffer: []const u8) !void {
            const FILE_NOTIFY_INFORMATION = extern struct {
                NextEntryOffset: w.DWORD,
                Action: w.DWORD,
                FileNameLength: w.DWORD,
                FileName: [1]w.WCHAR,
            };

            var offset: usize = 0;
            var info_ptr: *const FILE_NOTIFY_INFORMATION = undefined;

            while (offset < buffer.len) : ({
                // move to the next record. the NextEntryOffset field tells us the distance to advance.
                if (info_ptr.NextEntryOffset == 0) break;
                offset += info_ptr.NextEntryOffset;
            }) {
                info_ptr = @ptrCast(@alignCast(buffer.ptr + offset));
                // calculate how many UTF-16 code units the FileName field has.
                const numUTF16Units = info_ptr.FileNameLength / 2;

                const file_name_ptr: *const u16 = &info_ptr.FileName[0];
                const file_name_slice = @as([*]const u16, @ptrCast(file_name_ptr))[0..numUTF16Units];

                var utf8_name_buf: [w.MAX_PATH]u8 = undefined;
                const utf8_name_len = try std.unicode.utf16LeToUtf8(&utf8_name_buf, file_name_slice);
                const utf8_name = utf8_name_buf[0..utf8_name_len];

                impl.callback(impl.callback_ctx, switch (info_ptr.Action) {
                    w.FILE_ACTION_ADDED => .{ .add = utf8_name },
                    w.FILE_ACTION_REMOVED => .{ .remove = utf8_name },
                    w.FILE_ACTION_MODIFIED => .{ .modify = utf8_name },
                    w.FILE_ACTION_RENAMED_OLD_NAME => .{ .rename_old = utf8_name },
                    w.FILE_ACTION_RENAMED_NEW_NAME => .{ .rename_new = utf8_name },
                    else => unreachable,
                });
            }
        }
    },
    else => void,
};

pub fn init(allocator: std.mem.Allocator, path: []const u8) !*Self {
    const self = try allocator.create(Self);
    self.* = .{ .allocator = allocator, .impl = undefined };
    Impl.init(&self.impl, path, @ptrCast(&Self.collectEvent), self) catch |e| {
        log.err("failed to init implementation: {}", .{e});
        return e;
    };
    return self;
}

pub fn deinit(self: *Self) void {
    const allocator = self.allocator;
    self.impl.deinit();
    {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.events.items) |e| {
            e.deinit(allocator);
        }
        self.events.deinit(allocator);
        if (self.last_error) |e| {
            log.warn("unhandled watch error: {}", .{e});
        }
    }
    allocator.destroy(self);
}

// dispatches events collected from the last dispatch in the current thread
pub fn dispatch(self: *Self, comptime CTX: type, callback: WatchCallback(CTX), callback_ctx: *CTX) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    if (self.last_error) |err| {
        self.last_error = null;
        return err;
    }

    for (self.events.items) |e| {
        callback(callback_ctx, e);
        e.deinit(self.allocator);
    }
    self.events.clearRetainingCapacity();
}

fn collectEvent(self: *Self, event: Event) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const cloned = event.clone(self.allocator) catch |err| {
        self.last_error = err;
        return;
    };
    errdefer cloned.deinit(self.allocator);

    self.events.append(self.allocator, cloned) catch |err| {
        self.last_error = err;
        return;
    };
}
