const std = @import("std");
pub fn Implementation(comptime beam: type, comptime e: type) type {
    return struct {
        pub const JobKind = enum(u8) { fixture };
        pub const JobState = enum(u8) { queued, running, completed, cancelled };
        pub const SubmitStatus = enum(u8) { accepted, busy, stopped, out_of_memory, input_too_large };
        pub const SubmitResult = struct { status: SubmitStatus, request_id: u64 };

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
                job.* = .{ .allocator = allocator, .request_id = request_id, .kind = .fixture, .state = .init(@intFromEnum(JobState.queued)), .cancelled = .init(false), .enqueued_at = e.enif_monotonic_time(e.ERL_NIF_USEC), .bytes = bytes, .next = null };
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
            queued_jobs: usize,
            running_jobs: usize,
            completed_jobs: usize,
            rejected_jobs: usize,
            retained_bytes: usize,
            last_dequeued_request: u64,
            dequeue_order_hash: u64,
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
            queue_head: ?*Job,
            queue_tail: ?*Job,
            queued_jobs: usize,
            running_jobs: usize,
            completed_jobs: usize,
            completed_checksum: u64,
            rejected_jobs: usize,
            retained_bytes: usize,
            next_request_id: u64,
            last_dequeued_request: u64,
            pause_workers: bool,
            dequeue_order_hash: u64,

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
                runtime.* = .{ .allocator = allocator, .mutex = mutex, .condition = condition, .threads = threads, .queue_capacity = queue_capacity, .live_workers = .init(0), .accepting = .init(true), .stopping = false, .queue_head = null, .queue_tail = null, .queued_jobs = 0, .running_jobs = 0, .completed_jobs = 0, .completed_checksum = 0, .rejected_jobs = 0, .retained_bytes = 0, .next_request_id = 1, .last_dequeued_request = 0, .pause_workers = false, .dequeue_order_hash = 0 };
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

            pub fn enqueueOwned(self: *Runtime, job: *Job) bool {
                e.enif_mutex_lock(self.mutex);
                defer e.enif_mutex_unlock(self.mutex);
                if (self.stopping or !self.accepting.load(.acquire)) return false;
                job.next = null;
                if (self.queue_tail) |tail| tail.next = job else self.queue_head = job;
                self.queue_tail = job;
                self.queued_jobs += 1;
                e.enif_cond_signal(self.condition);
                return true;
            }

            pub fn submit(self: *Runtime, input: []const u8) SubmitResult {
                if (input.len > 1_048_576) return .{ .status = .input_too_large, .request_id = 0 };
                e.enif_mutex_lock(self.mutex);
                defer e.enif_mutex_unlock(self.mutex);
                if (self.stopping or !self.accepting.load(.acquire)) return .{ .status = .stopped, .request_id = 0 };
                if (self.queued_jobs >= self.queue_capacity) {
                    self.rejected_jobs += 1;
                    return .{ .status = .busy, .request_id = 0 };
                }
                const request_id = self.next_request_id;
                self.next_request_id +%= 1;
                const job = Job.create(self.allocator, request_id, input) catch return .{ .status = .out_of_memory, .request_id = 0 };
                self.retained_bytes += input.len;
                if (self.queue_tail) |tail| tail.next = job else self.queue_head = job;
                self.queue_tail = job;
                self.queued_jobs += 1;
                e.enif_cond_signal(self.condition);
                return .{ .status = .accepted, .request_id = request_id };
            }

            pub fn setPaused(self: *Runtime, paused: bool) void {
                e.enif_mutex_lock(self.mutex);
                self.pause_workers = paused;
                if (!paused) e.enif_cond_broadcast(self.condition);
                e.enif_mutex_unlock(self.mutex);
            }

            fn pop(self: *Runtime) ?*Job {
                const job = self.queue_head orelse return null;
                self.queue_head = job.next;
                if (self.queue_head == null) self.queue_tail = null;
                job.next = null;
                self.queued_jobs -= 1;
                self.running_jobs += 1;
                self.last_dequeued_request = job.request_id;
                self.dequeue_order_hash = self.dequeue_order_hash *% 131 +% job.request_id;
                job.state.store(@intFromEnum(JobState.running), .release);
                return job;
            }

            pub fn snapshot(self: *Runtime) Snapshot {
                e.enif_mutex_lock(self.mutex);
                defer e.enif_mutex_unlock(self.mutex);
                return .{ .worker_count = self.threads.len, .queue_capacity = self.queue_capacity, .live_workers = self.live_workers.load(.acquire), .accepting = self.accepting.load(.acquire), .queued_jobs = self.queued_jobs, .running_jobs = self.running_jobs, .completed_jobs = self.completed_jobs, .rejected_jobs = self.rejected_jobs, .retained_bytes = self.retained_bytes, .last_dequeued_request = self.last_dequeued_request, .dequeue_order_hash = self.dequeue_order_hash };
            }
        };

        fn workerMain(raw: ?*anyopaque) callconv(.c) ?*anyopaque {
            const runtime: *Runtime = @ptrCast(@alignCast(raw.?));
            _ = runtime.live_workers.fetchAdd(1, .acq_rel);
            e.enif_mutex_lock(runtime.mutex);
            while (true) {
                while (runtime.queue_head == null and !runtime.stopping) e.enif_cond_wait(runtime.condition, runtime.mutex);
                const job = runtime.pop();
                if (job == null and runtime.stopping) {
                    e.enif_mutex_unlock(runtime.mutex);
                    break;
                }
                while (runtime.pause_workers and !runtime.stopping) e.enif_cond_wait(runtime.condition, runtime.mutex);
                e.enif_mutex_unlock(runtime.mutex);
                var checksum: u64 = 0;
                for (job.?.bytes) |byte| checksum +%= byte;
                const retained = job.?.bytes.len;
                job.?.state.store(@intFromEnum(JobState.completed), .release);
                job.?.destroy();
                e.enif_mutex_lock(runtime.mutex);
                runtime.running_jobs -= 1;
                runtime.completed_jobs += 1;
                runtime.retained_bytes -= retained;
                runtime.completed_checksum +%= checksum;
                e.enif_cond_broadcast(runtime.condition);
            }
            _ = runtime.live_workers.fetchSub(1, .acq_rel);
            return null;
        }
    };
}
