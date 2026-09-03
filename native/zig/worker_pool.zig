const std = @import("std");
pub fn Implementation(comptime beam: type, comptime e: type, comptime root: type) type {
    return struct {
        pub const JobKind = enum(u8) { fixture };
        pub const JobState = enum(u8) { queued, running, completed, cancelled };
        pub const SubmitStatus = enum(u8) { accepted, busy, stopped, out_of_memory, input_too_large };
        pub const SubmitResult = struct { status: SubmitStatus, request_id: u64 };
        pub const TerminalState = enum(u8) { pending, delivering, delivered, discarded, cancelled };
        const DeliveryOutcome = enum(u8) { delivered, discarded, cancelled };

        pub const RequestControl = struct {
            allocator: std.mem.Allocator,
            references: std.atomic.Value(usize),
            cancelled: std.atomic.Value(bool),
            monitored: std.atomic.Value(bool),
            resource_object: std.atomic.Value(?*anyopaque),
            monitor: beam.monitor,
            caller: beam.pid,
            private_env: beam.env,
            request_ref: e.ErlNifTerm,
            terminal: std.atomic.Value(u8),

            fn create(allocator: std.mem.Allocator, caller: beam.pid) !*RequestControl {
                const control = try allocator.create(RequestControl);
                const private_env = e.enif_alloc_env() orelse {
                    allocator.destroy(control);
                    return error.out_of_memory;
                };
                control.* = .{
                    .allocator = allocator,
                    .references = .init(1),
                    .cancelled = .init(false),
                    .monitored = .init(false),
                    .resource_object = .init(null),
                    .monitor = undefined,
                    .caller = caller,
                    .private_env = private_env,
                    .request_ref = e.enif_make_ref(private_env),
                    .terminal = .init(@intFromEnum(TerminalState.pending)),
                };
                return control;
            }

            fn retain(self: *RequestControl) void {
                _ = self.references.fetchAdd(1, .acq_rel);
            }

            fn release(self: *RequestControl) void {
                const previous = self.references.fetchSub(1, .acq_rel);
                std.debug.assert(previous > 0);
                if (previous == 1) {
                    e.enif_free_env(self.private_env);
                    self.allocator.destroy(self);
                }
            }

            fn cancel(self: *RequestControl) bool {
                if (self.terminal.load(.acquire) != @intFromEnum(TerminalState.pending))
                    return false;
                return !self.cancelled.swap(true, .acq_rel);
            }

            fn deliver(self: *RequestControl, checksum: u64) DeliveryOutcome {
                if (self.cancelled.load(.acquire)) {
                    _ = self.terminal.cmpxchgStrong(
                        @intFromEnum(TerminalState.pending),
                        @intFromEnum(TerminalState.cancelled),
                        .acq_rel,
                        .acquire,
                    );
                    return .cancelled;
                }
                if (self.terminal.cmpxchgStrong(
                    @intFromEnum(TerminalState.pending),
                    @intFromEnum(TerminalState.delivering),
                    .acq_rel,
                    .acquire,
                ) != null) return .cancelled;

                const env = self.private_env;
                const ok_parts = [_]e.ErlNifTerm{
                    e.enif_make_atom(env, "ok"),
                    e.enif_make_uint64(env, checksum),
                };
                const ok = e.enif_make_tuple_from_array(env, &ok_parts, ok_parts.len);
                const message_parts = [_]e.ErlNifTerm{
                    e.enif_make_atom(env, "Elixir.SimdJson.Native"),
                    self.request_ref,
                    ok,
                };
                const message = e.enif_make_tuple_from_array(env, &message_parts, message_parts.len);
                var caller = self.caller;
                const delivered = e.enif_send(null, &caller, env, message) != 0;
                self.terminal.store(
                    @intFromEnum(if (delivered) TerminalState.delivered else TerminalState.discarded),
                    .release,
                );
                return if (delivered) .delivered else .discarded;
            }

            fn demonitor(self: *RequestControl) void {
                if (!self.monitored.swap(false, .acq_rel)) return;
                const resource_object = self.resource_object.load(.acquire) orelse return;
                _ = e.enif_demonitor_process(null, resource_object, &self.monitor);
            }
        };

        pub const RequestResource = struct {
            pub const __is_zigler_resource = true;
            __payload: **RequestControl,
            __should_release: bool = true,

            pub fn init(comptime module: []const u8, init_opts: anytype) *e.ErlNifResourceType {
                var callbacks = e.ErlNifResourceTypeInit{
                    .dtor = resourceDtor,
                    .stop = null,
                    .down = resourceDown,
                    .dyncall = null,
                    .members = 3,
                };
                return e.enif_init_resource_type(
                    init_opts.env,
                    "PoolRequestResource-" ++ module,
                    &callbacks,
                    e.ERL_NIF_RT_CREATE,
                    null,
                ).?;
            }

            pub fn resource_type(_: @This()) *e.ErlNifResourceType {
                var resource_type_value: *e.ErlNifResourceType = undefined;
                root.set_resource(@This(), &resource_type_value);
                return resource_type_value;
            }

            pub fn create(control: *RequestControl, _: anytype) !@This() {
                var probe: @This() = undefined;
                const raw = e.enif_alloc_resource(probe.resource_type(), @sizeOf(*RequestControl)) orelse
                    return error.out_of_memory;
                const payload: **RequestControl = @ptrCast(@alignCast(raw));
                payload.* = control;
                return .{ .__payload = payload };
            }

            pub fn release(self: @This()) void {
                e.enif_release_resource(@ptrCast(self.__payload));
            }

            pub fn maybe_release(self: @This()) void {
                if (self.__should_release) self.release();
            }

            pub fn keep(self: @This()) void {
                _ = e.enif_keep_resource(@ptrCast(self.__payload));
            }

            pub fn get(self: *@This(), src: beam.term, _: anytype) !void {
                const target: *?*anyopaque = @ptrCast(&self.__payload);
                if (e.enif_get_resource(
                    beam.context.env,
                    src.v,
                    self.resource_type(),
                    target,
                ) == 0) return error.incorrect_resource_type;
            }

            pub fn make(self: @This(), _: anytype) beam.term {
                defer self.maybe_release();
                return .{ .v = e.enif_make_resource(beam.context.env, @ptrCast(self.__payload)) };
            }

            fn resourceDtor(_: beam.env, raw: ?*anyopaque) callconv(.c) void {
                const payload: **RequestControl = @ptrCast(@alignCast(raw.?));
                payload.*.release();
            }

            fn resourceDown(
                _: beam.env,
                raw: ?*anyopaque,
                _: [*c]const beam.pid,
                _: [*c]const beam.monitor,
            ) callconv(.c) void {
                const payload: **RequestControl = @ptrCast(@alignCast(raw.?));
                _ = payload.*.cancel();
                payload.*.monitored.store(false, .release);
            }
        };

        pub const MonitoredSubmission = struct {
            request_id: u64,
            request_ref: beam.term,
            request: RequestResource,
        };

        pub const SerializationState = enum(u8) { ready, reserved, closing, closed };
        pub const CloseStatus = enum(u8) { closed, closing, already_closed };

        pub const ResourceControl = struct {
            state: std.atomic.Value(u8),

            fn reserve(self: *ResourceControl) !void {
                const current: SerializationState = @enumFromInt(self.state.load(.acquire));
                if (current != .ready) return if (current == .reserved)
                    error.resource_busy
                else
                    error.resource_closed;
                if (self.state.cmpxchgStrong(
                    @intFromEnum(SerializationState.ready),
                    @intFromEnum(SerializationState.reserved),
                    .acq_rel,
                    .acquire,
                ) != null) return error.resource_busy;
            }

            fn releaseReservation(self: *ResourceControl) void {
                while (true) {
                    const current: SerializationState = @enumFromInt(self.state.load(.acquire));
                    const next = switch (current) {
                        .reserved => SerializationState.ready,
                        .closing => SerializationState.closed,
                        .ready, .closed => return,
                    };
                    if (self.state.cmpxchgWeak(
                        @intFromEnum(current),
                        @intFromEnum(next),
                        .acq_rel,
                        .acquire,
                    ) == null) return;
                }
            }

            pub fn close(self: *ResourceControl) CloseStatus {
                while (true) {
                    const current: SerializationState = @enumFromInt(self.state.load(.acquire));
                    const next, const result = switch (current) {
                        .ready => .{ SerializationState.closed, CloseStatus.closed },
                        .reserved => .{ SerializationState.closing, CloseStatus.closing },
                        .closing => return .closing,
                        .closed => return .already_closed,
                    };
                    if (self.state.cmpxchgWeak(
                        @intFromEnum(current),
                        @intFromEnum(next),
                        .acq_rel,
                        .acquire,
                    ) == null) return result;
                }
            }
        };

        pub const SerializationResource = beam.Resource(ResourceControl, root, .{});

        pub const Job = struct {
            allocator: std.mem.Allocator,
            request_id: u64,
            kind: JobKind,
            state: std.atomic.Value(u8),
            cancelled: std.atomic.Value(bool),
            enqueued_at: i64,
            bytes: []u8,
            request: ?*RequestControl,
            serialization: ?SerializationResource,
            next: ?*Job,

            pub fn create(allocator: std.mem.Allocator, request_id: u64, input: []const u8) !*Job {
                const job = try allocator.create(Job);
                errdefer allocator.destroy(job);
                const bytes = try allocator.dupe(u8, input);
                job.* = .{ .allocator = allocator, .request_id = request_id, .kind = .fixture, .state = .init(@intFromEnum(JobState.queued)), .cancelled = .init(false), .enqueued_at = e.enif_monotonic_time(e.ERL_NIF_USEC), .bytes = bytes, .request = null, .serialization = null, .next = null };
                return job;
            }

            fn attachRequest(self: *Job, request: *RequestControl) void {
                request.retain();
                self.request = request;
            }

            fn isCancelled(self: *Job) bool {
                return self.cancelled.load(.acquire) or
                    if (self.request) |request| request.cancelled.load(.acquire) else false;
            }

            fn attachSerialization(self: *Job, resource: SerializationResource) void {
                resource.keep();
                self.serialization = resource;
            }

            pub fn destroy(self: *Job) void {
                const allocator = self.allocator;
                if (self.request) |request| request.release();
                if (self.serialization) |resource| {
                    resource.__payload.releaseReservation();
                    resource.release();
                }
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
            cancelled_jobs: usize,
            delivered_jobs: usize,
            discarded_jobs: usize,
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
            cancelled_jobs: usize,
            delivered_jobs: usize,
            discarded_jobs: usize,
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
                runtime.* = .{ .allocator = allocator, .mutex = mutex, .condition = condition, .threads = threads, .queue_capacity = queue_capacity, .live_workers = .init(0), .accepting = .init(true), .stopping = false, .queue_head = null, .queue_tail = null, .queued_jobs = 0, .running_jobs = 0, .completed_jobs = 0, .cancelled_jobs = 0, .delivered_jobs = 0, .discarded_jobs = 0, .completed_checksum = 0, .rejected_jobs = 0, .retained_bytes = 0, .next_request_id = 1, .last_dequeued_request = 0, .pause_workers = false, .dequeue_order_hash = 0 };
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

            pub fn submitMonitored(self: *Runtime, input: []const u8) !MonitoredSubmission {
                if (input.len > 1_048_576) return error.input_too_large;
                const owner = try beam.self(.{});
                const control = try RequestControl.create(self.allocator, owner);
                const request = RequestResource.create(control, .{}) catch |reason| {
                    control.release();
                    return reason;
                };
                errdefer request.release();
                control.resource_object.store(@ptrCast(request.__payload), .release);
                var monitored_owner = owner;
                if (e.enif_monitor_process(beam.context.env, @ptrCast(request.__payload), &monitored_owner, &control.monitor) != 0)
                    return error.monitor_failed;
                control.monitored.store(true, .release);

                e.enif_mutex_lock(self.mutex);
                defer e.enif_mutex_unlock(self.mutex);
                if (self.stopping or !self.accepting.load(.acquire)) return error.pool_stopped;
                if (self.queued_jobs >= self.queue_capacity) {
                    self.rejected_jobs += 1;
                    return error.pool_busy;
                }
                const request_id = self.next_request_id;
                self.next_request_id +%= 1;
                const job = try Job.create(self.allocator, request_id, input);
                job.attachRequest(control);
                self.retained_bytes += input.len;
                if (self.queue_tail) |tail| tail.next = job else self.queue_head = job;
                self.queue_tail = job;
                self.queued_jobs += 1;
                e.enif_cond_signal(self.condition);
                return .{
                    .request_id = request_id,
                    .request_ref = beam.copy(beam.context.env, .{ .v = control.request_ref }),
                    .request = request,
                };
            }

            pub fn submitSerialized(
                self: *Runtime,
                input: []const u8,
                resource: SerializationResource,
            ) !MonitoredSubmission {
                try resource.__payload.reserve();
                errdefer resource.__payload.releaseReservation();
                if (input.len > 1_048_576) return error.input_too_large;
                const owner = try beam.self(.{});
                const control = try RequestControl.create(self.allocator, owner);
                const request = RequestResource.create(control, .{}) catch |reason| {
                    control.release();
                    return reason;
                };
                errdefer request.release();
                control.resource_object.store(@ptrCast(request.__payload), .release);
                var monitored_owner = owner;
                if (e.enif_monitor_process(beam.context.env, @ptrCast(request.__payload), &monitored_owner, &control.monitor) != 0)
                    return error.monitor_failed;
                control.monitored.store(true, .release);

                e.enif_mutex_lock(self.mutex);
                defer e.enif_mutex_unlock(self.mutex);
                if (self.stopping or !self.accepting.load(.acquire)) return error.pool_stopped;
                if (self.queued_jobs >= self.queue_capacity) {
                    self.rejected_jobs += 1;
                    return error.pool_busy;
                }
                const request_id = self.next_request_id;
                self.next_request_id +%= 1;
                const job = try Job.create(self.allocator, request_id, input);
                job.attachRequest(control);
                job.attachSerialization(resource);
                self.retained_bytes += input.len;
                if (self.queue_tail) |tail| tail.next = job else self.queue_head = job;
                self.queue_tail = job;
                self.queued_jobs += 1;
                e.enif_cond_signal(self.condition);
                return .{
                    .request_id = request_id,
                    .request_ref = beam.copy(beam.context.env, .{ .v = control.request_ref }),
                    .request = request,
                };
            }

            pub fn cancelRequest(_: *Runtime, request: RequestResource) bool {
                return request.__payload.*.cancel();
            }

            pub fn abandonMonitor(_: *Runtime, request: RequestResource) void {
                request.__payload.*.demonitor();
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
                return .{ .worker_count = self.threads.len, .queue_capacity = self.queue_capacity, .live_workers = self.live_workers.load(.acquire), .accepting = self.accepting.load(.acquire), .queued_jobs = self.queued_jobs, .running_jobs = self.running_jobs, .completed_jobs = self.completed_jobs, .cancelled_jobs = self.cancelled_jobs, .delivered_jobs = self.delivered_jobs, .discarded_jobs = self.discarded_jobs, .rejected_jobs = self.rejected_jobs, .retained_bytes = self.retained_bytes, .last_dequeued_request = self.last_dequeued_request, .dequeue_order_hash = self.dequeue_order_hash };
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
                if (!job.?.isCancelled()) {
                    for (job.?.bytes) |byte| checksum +%= byte;
                }
                const retained = job.?.bytes.len;
                var cancelled = job.?.isCancelled();
                var delivery: ?DeliveryOutcome = null;
                if (job.?.request) |request| {
                    delivery = request.deliver(checksum);
                    cancelled = delivery.? == .cancelled;
                }
                job.?.state.store(@intFromEnum(if (cancelled) JobState.cancelled else JobState.completed), .release);
                if (job.?.request) |request| request.demonitor();
                job.?.destroy();
                e.enif_mutex_lock(runtime.mutex);
                runtime.running_jobs -= 1;
                if (cancelled) runtime.cancelled_jobs += 1 else runtime.completed_jobs += 1;
                if (delivery) |outcome| switch (outcome) {
                    .delivered => runtime.delivered_jobs += 1,
                    .discarded => runtime.discarded_jobs += 1,
                    .cancelled => {},
                };
                runtime.retained_bytes -= retained;
                runtime.completed_checksum +%= checksum;
                e.enif_cond_broadcast(runtime.condition);
            }
            _ = runtime.live_workers.fetchSub(1, .acq_rel);
            return null;
        }
    };
}
