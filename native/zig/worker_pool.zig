const std = @import("std");
pub fn Implementation(comptime beam: type, comptime e: type) type {
    return struct {
        pub const JobKind = enum(u8) { fixture };
        pub const JobState = enum(u8) { queued, running, completed, cancelled };

        pub const Job = struct {
            allocator: std.mem.Allocator,
            request_id: u64,
            kind: JobKind,
            state: std.atomic.Value(u8),
            cancelled: std.atomic.Value(bool),
            enqueued_at: i64,
            bytes: []u8,
            next: ?*Job,

            pub fn create(allocator: std.mem.Allocator, request_id: u64, input: []const u8) !*Job {
                const job = try allocator.create(Job);
                errdefer allocator.destroy(job);
                const bytes = try allocator.dupe(u8, input);
                job.* = .{ .allocator = allocator, .request_id = request_id, .kind = .fixture, .state = .init(@intFromEnum(JobState.queued)), .cancelled = .init(false), .enqueued_at = std.time.nanoTimestamp(), .bytes = bytes, .next = null };
                return job;
            }

            pub fn destroy(self: *Job) void {
                const allocator = self.allocator;
                allocator.free(self.bytes);
                allocator.destroy(self);
            }
        };

        pub const Snapshot = struct {
            worker_count: usize,
            queue_capacity: usize,
            live_workers: usize,
            accepting: bool,
        };

        pub const Runtime = struct {
            allocator: std.mem.Allocator,
            mutex: *e.ErlNifMutex,
            condition: *e.ErlNifCond,
            threads: []beam.tid,
            queue_capacity: usize,
            live_workers: std.atomic.Value(usize),
            accepting: std.atomic.Value(bool),
            stopping: bool,

            pub fn create(allocator: std.mem.Allocator, workers: usize, queue_capacity: usize) !*Runtime {
                return createWithFailure(allocator, workers, queue_capacity, null);
            }

            pub fn createWithFailure(allocator: std.mem.Allocator, workers: usize, queue_capacity: usize, fail_after: ?usize) !*Runtime {
                if (workers == 0 or workers > 64 or queue_capacity == 0 or queue_capacity > 4096)
                    return error.invalid_configuration;
                const runtime = try allocator.create(Runtime);
                errdefer allocator.destroy(runtime);
                const mutex = e.enif_mutex_create(@constCast("simd_json_pool_mutex")) orelse return error.mutex_unavailable;
                errdefer e.enif_mutex_destroy(mutex);
                const condition = e.enif_cond_create(@constCast("simd_json_pool_condition")) orelse return error.condition_unavailable;
                errdefer e.enif_cond_destroy(condition);
                const threads = try allocator.alloc(beam.tid, workers);
                errdefer allocator.free(threads);
                runtime.* = .{ .allocator = allocator, .mutex = mutex, .condition = condition, .threads = threads, .queue_capacity = queue_capacity, .live_workers = .init(0), .accepting = .init(true), .stopping = false };
                var started: usize = 0;
                errdefer runtime.rollback(started);
                while (started < workers) : (started += 1) {
                    if (fail_after != null and started == fail_after.?) return error.injected_thread_failure;
                    if (e.enif_thread_create(@constCast("simd_json_pool_worker"), &threads[started], workerMain, runtime, null) != 0)
                        return error.thread_unavailable;
                }
                while (runtime.live_workers.load(.acquire) != workers) std.atomic.spinLoopHint();
                return runtime;
            }

            fn rollback(self: *Runtime, started: usize) void {
                e.enif_mutex_lock(self.mutex);
                self.stopping = true;
                e.enif_cond_broadcast(self.condition);
                e.enif_mutex_unlock(self.mutex);
                for (self.threads[0..started]) |thread| {
                    var ignored: ?*anyopaque = null;
                    _ = e.enif_thread_join(thread, &ignored);
                }
            }

            pub fn destroy(self: *Runtime) void {
                self.accepting.store(false, .release);
                self.rollback(self.threads.len);
                e.enif_cond_destroy(self.condition);
                e.enif_mutex_destroy(self.mutex);
                const allocator = self.allocator;
                allocator.free(self.threads);
                allocator.destroy(self);
            }

            pub fn snapshot(self: *Runtime) Snapshot {
                return .{ .worker_count = self.threads.len, .queue_capacity = self.queue_capacity, .live_workers = self.live_workers.load(.acquire), .accepting = self.accepting.load(.acquire) };
            }
        };

        fn workerMain(raw: ?*anyopaque) callconv(.c) ?*anyopaque {
            const runtime: *Runtime = @ptrCast(@alignCast(raw.?));
            _ = runtime.live_workers.fetchAdd(1, .acq_rel);
            e.enif_mutex_lock(runtime.mutex);
            while (!runtime.stopping) e.enif_cond_wait(runtime.condition, runtime.mutex);
            e.enif_mutex_unlock(runtime.mutex);
            _ = runtime.live_workers.fetchSub(1, .acq_rel);
            return null;
        }
    };
}
