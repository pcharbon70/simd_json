const std = @import("std");
const beam = @import("beam");
const e = @import("erl_nif");
const c = @import("simd_json_abi");
const document_resource = @import("document_resource").Implementation(c);
const projection_plan = @import("projection_plan").Implementation(c);
const stream_cursor = @import("stream_cursor").Implementation(c, projection_plan);
const worker_pool = @import("worker_pool").Implementation(beam, e, root, @This());
const root = @import("root");

pub const PoolRequestResource = worker_pool.RequestResource;
pub const PoolSerializationResource = worker_pool.SerializationResource;

extern fn simd_json_build_smoke_version() callconv(.c) u32;
extern fn simd_json_build_smoke_padding() callconv(.c) u32;
extern fn simd_json_build_smoke_runtime_implementation() callconv(.c) [*:0]const u8;

const DocumentControl = struct {
    allocator: std.mem.Allocator,
    native: document_resource.DocumentState,
    owner: beam.pid,
    module_generation: u64,
    accounted: std.atomic.Value(bool),
    cleanup_next: ?*DocumentControl,
};

const DocumentResourcePayload = struct {
    control: ?*DocumentControl,
};

const DocumentResourceCallbacks = struct {
    pub fn dtor(payload: *DocumentResourcePayload) void {
        const control = payload.control orelse return;
        payload.control = null;
        _ = control.native.detachForDeferredCleanup();
        enqueueDetachedDocument(control);
    }
};

pub const DocumentResource = beam.Resource(
    DocumentResourcePayload,
    root,
    .{ .Callbacks = DocumentResourceCallbacks },
);

const StreamCursorControl = struct {
    allocator: std.mem.Allocator,
    native: stream_cursor.OwnedCursor,
    parent: ?DocumentResource,
    owner: beam.pid,
    parent_generation: u64,
    demand_state: std.atomic.Value(u8),
    next_sequence: std.atomic.Value(u64),
    stream_reservation: ?document_resource.StreamReservation,
    owned_document: document_resource.DocumentState,
};

const StreamDemandState = enum(u8) { ready, running, done, cancelled, closed };

const StreamFixtureStatus = enum(u8) {
    ok,
    cancelled,
    not_owner,
    closed,
    cursor_consumed,
    execution_unavailable,
    out_of_memory,
    invalid_target,
    native_failure,
    cursor_state,
    invalid_json,
    invalid_utf8,
    unexpected_eof,
    missing_field,
    index_out_of_bounds,
    incorrect_type,
    number_out_of_range,
    batch_too_large,
};

const StreamSetupFixtureResult = struct {
    status: StreamFixtureStatus,
    kind: OperationKind,
    generation: u64,
    worker_context: ExecutionContext,
    cursor: ?StreamCursorResource,
    ready_for_delivery: bool,
};

const StreamBatchFixtureResult = struct {
    status: StreamFixtureStatus,
    kind: OperationKind,
    generation: u64,
    worker_context: ExecutionContext,
    sequence: u64,
    produced_rows: usize,
    encoded_bytes: u64,
    done: bool,
    rows: ?JoinCopiedTerm,
    native_code: ?i32,
    byte_offset: ?u64,
    output_slot: ?u32,
    array_index: ?u64,
    ready_for_delivery: bool,
};

const StreamCursorResourcePayload = struct {
    control: ?*StreamCursorControl,
};

const StreamCursorResourceCallbacks = struct {
    pub fn dtor(payload: *StreamCursorResourcePayload) void {
        const control = payload.control orelse return;
        payload.control = null;
        destroyStreamCursorControl(control);
    }
};

pub const StreamCursorResource = beam.Resource(
    StreamCursorResourcePayload,
    root,
    .{ .Callbacks = StreamCursorResourceCallbacks },
);

pub const OperationKind = enum(u8) {
    document_open,
    document_cleanup,
    threaded_smoke,
    projection,
    stream_setup,
    stream_batch,
};

pub const ProjectionSourceKind = enum(u8) {
    binary,
    document,
};

pub const OperationState = enum(u8) {
    queued,
    running,
    cancelling,
    delivering,
    completed,
    discarded,
};

pub const OperationOutcome = enum(u8) {
    delivered,
    discarded,
};

const OperationBoundary = enum(u8) {
    none,
    before_copy,
    before_parse,
    after_parse,
    before_publication,
    before_plan_compilation,
    before_cursor_access,
    during_traversal,
    before_term_construction,
    during_term_construction,
    before_delivery,
};

pub const ExecutionContext = enum(u8) {
    synchronous,
    threaded,
    dirty,
    callback,
    unsupported,
};

const ExecutionAccounting = struct {
    var live_operations = std.atomic.Value(usize).init(0);
    var retained_inputs = std.atomic.Value(usize).init(0);
    var queued_operations = std.atomic.Value(usize).init(0);
    var queued_cleanup = std.atomic.Value(usize).init(0);
    var running_operations = std.atomic.Value(usize).init(0);
    var delivered_results = std.atomic.Value(usize).init(0);
    var discarded_results = std.atomic.Value(usize).init(0);
    var worker_entries = std.atomic.Value(usize).init(0);
    var live_documents = std.atomic.Value(usize).init(0);
    var completed_document_cleanup = std.atomic.Value(usize).init(0);
    var live_document_controls = std.atomic.Value(usize).init(0);
    var dispatcher_queued_cleanup = std.atomic.Value(usize).init(0);
    var dispatcher_active_cleanup = std.atomic.Value(usize).init(0);
    var dispatcher_completed_cleanup = std.atomic.Value(usize).init(0);
    var retained_failed_cleanup = std.atomic.Value(usize).init(0);
    var cleanup_submission_failures = std.atomic.Value(usize).init(0);
    var projection_operation_count = std.atomic.Value(usize).init(0);
    var retained_projection_binaries = std.atomic.Value(usize).init(0);
    var retained_projection_documents = std.atomic.Value(usize).init(0);
    var projection_environment_count = std.atomic.Value(usize).init(0);
    var projection_plan_count = std.atomic.Value(usize).init(0);
    var projection_slot_count = std.atomic.Value(usize).init(0);
    var temporary_document_graph_count = std.atomic.Value(usize).init(0);
    var completed_projection_deliveries = std.atomic.Value(usize).init(0);
    var discarded_projection_deliveries = std.atomic.Value(usize).init(0);
    var projection_worker_count = std.atomic.Value(usize).init(0);
    var projection_boundary_count = std.atomic.Value(usize).init(0);
    var live_stream_cursor_resources = std.atomic.Value(usize).init(0);
    var retained_stream_cursor_parents = std.atomic.Value(usize).init(0);
    var live_stream_setup_operations = std.atomic.Value(usize).init(0);
    var live_stream_batch_operations = std.atomic.Value(usize).init(0);
    var stream_setup_worker_entries = std.atomic.Value(usize).init(0);
    var stream_batch_worker_entries = std.atomic.Value(usize).init(0);
    var stream_deliveries = std.atomic.Value(usize).init(0);
    var stream_discards = std.atomic.Value(usize).init(0);
};

const Runtime = struct {
    allocator: std.mem.Allocator,
    mutex: *e.ErlNifMutex,
    condition: *e.ErlNifCond,
    thread: beam.tid,
    generation: std.atomic.Value(u64),
    accepting: std.atomic.Value(bool),
    shutdown_requested: bool,
    worker_running: bool,
    reject_cleanup_submission: bool,
    queue_head: ?*DocumentControl,
    queue_tail: ?*DocumentControl,
    failed_head: ?*DocumentControl,
    failed_tail: ?*DocumentControl,

    fn create(allocator: std.mem.Allocator, generation: u64) !*Runtime {
        const runtime = try allocator.create(Runtime);
        errdefer allocator.destroy(runtime);

        const mutex = e.enif_mutex_create(@constCast("simd_json_cleanup_mutex")) orelse
            return error.cleanup_mutex_unavailable;
        errdefer e.enif_mutex_destroy(mutex);

        const condition = e.enif_cond_create(@constCast("simd_json_cleanup_condition")) orelse
            return error.cleanup_condition_unavailable;
        errdefer e.enif_cond_destroy(condition);

        runtime.* = .{
            .allocator = allocator,
            .mutex = mutex,
            .condition = condition,
            .thread = undefined,
            .generation = .init(generation),
            .accepting = .init(true),
            .shutdown_requested = false,
            .worker_running = true,
            .reject_cleanup_submission = false,
            .queue_head = null,
            .queue_tail = null,
            .failed_head = null,
            .failed_tail = null,
        };

        if (e.enif_thread_create(
            @constCast("simd_json_cleanup"),
            &runtime.thread,
            cleanupWorkerMain,
            runtime,
            null,
        ) != 0) return error.cleanup_thread_unavailable;

        return runtime;
    }

    fn append(
        head: *?*DocumentControl,
        tail: *?*DocumentControl,
        control: *DocumentControl,
    ) void {
        control.cleanup_next = null;
        if (tail.*) |last| {
            last.cleanup_next = control;
        } else {
            head.* = control;
        }
        tail.* = control;
    }

    fn enqueue(self: *Runtime, control: *DocumentControl) bool {
        e.enif_mutex_lock(self.mutex);
        defer e.enif_mutex_unlock(self.mutex);

        if (!self.worker_running or self.reject_cleanup_submission) {
            append(&self.failed_head, &self.failed_tail, control);
            _ = ExecutionAccounting.retained_failed_cleanup.fetchAdd(1, .acq_rel);
            _ = ExecutionAccounting.cleanup_submission_failures.fetchAdd(1, .acq_rel);
            return false;
        }

        append(&self.queue_head, &self.queue_tail, control);
        _ = ExecutionAccounting.dispatcher_queued_cleanup.fetchAdd(1, .acq_rel);
        e.enif_cond_signal(self.condition);
        return true;
    }

    fn setCleanupRejection(self: *Runtime, reject: bool) void {
        e.enif_mutex_lock(self.mutex);
        defer e.enif_mutex_unlock(self.mutex);

        self.reject_cleanup_submission = reject;
        if (reject or self.failed_head == null or !self.worker_running) return;

        if (self.queue_tail) |tail| {
            tail.cleanup_next = self.failed_head;
        } else {
            self.queue_head = self.failed_head;
        }
        self.queue_tail = self.failed_tail;

        const retained = ExecutionAccounting.retained_failed_cleanup.swap(0, .acq_rel);
        _ = ExecutionAccounting.dispatcher_queued_cleanup.fetchAdd(retained, .acq_rel);
        self.failed_head = null;
        self.failed_tail = null;
        e.enif_cond_broadcast(self.condition);
    }

    fn pop(self: *Runtime) ?*DocumentControl {
        const control = self.queue_head orelse return null;
        self.queue_head = control.cleanup_next;
        if (self.queue_head == null) self.queue_tail = null;
        control.cleanup_next = null;
        return control;
    }

    fn requestShutdownAndJoin(self: *Runtime) void {
        self.accepting.store(false, .release);
        self.setCleanupRejection(false);

        e.enif_mutex_lock(self.mutex);
        self.shutdown_requested = true;
        e.enif_cond_broadcast(self.condition);
        e.enif_mutex_unlock(self.mutex);

        var ignored: ?*anyopaque = null;
        _ = e.enif_thread_join(self.thread, &ignored);

        e.enif_cond_destroy(self.condition);
        e.enif_mutex_destroy(self.mutex);
        self.allocator.destroy(self);
    }
};

var runtime_ref = std.atomic.Value(?*Runtime).init(null);
var pool_ref = std.atomic.Value(?*worker_pool.Runtime).init(null);

pub const PoolStartStatus = enum(u8) { ok, already_started, conflicting_configuration, startup_failed };

pub fn native_pool_start(workers: usize, queue_capacity: usize) PoolStartStatus {
    if (pool_ref.load(.acquire)) |pool| {
        const current = pool.snapshot();
        return if (current.worker_count == workers and current.queue_capacity == queue_capacity)
            .already_started
        else
            .conflicting_configuration;
    }
    const pool = worker_pool.Runtime.create(beam.allocator, workers, queue_capacity) catch return .startup_failed;
    if (pool_ref.cmpxchgStrong(null, pool, .acq_rel, .acquire) != null) {
        pool.destroy();
        return .conflicting_configuration;
    }
    return .ok;
}

pub fn native_pool_snapshot() ?worker_pool.Snapshot {
    const pool = pool_ref.load(.acquire) orelse return null;
    return pool.snapshot();
}

pub fn native_pool_stop() bool {
    const pool = pool_ref.swap(null, .acq_rel) orelse return false;
    pool.destroy();
    return true;
}

pub fn native_pool_start_with_failure(workers: usize, queue_capacity: usize, fail_after: usize) PoolStartStatus {
    if (pool_ref.load(.acquire) != null) return .conflicting_configuration;
    const pool = worker_pool.Runtime.createWithFailure(beam.allocator, workers, queue_capacity, fail_after) catch return .startup_failed;
    pool_ref.store(pool, .release);
    return .ok;
}

pub fn native_pool_submit_fixture(input: []const u8) worker_pool.SubmitResult {
    const pool = pool_ref.load(.acquire) orelse return .{ .status = .stopped, .request_id = 0 };
    return pool.submit(input);
}

pub fn native_pool_submit_monitored_fixture(input: []const u8) !worker_pool.MonitoredSubmission {
    const pool = pool_ref.load(.acquire) orelse return error.pool_stopped;
    return pool.submitMonitored(input);
}

pub fn native_pool_cancel_fixture(request: PoolRequestResource) bool {
    const pool = pool_ref.load(.acquire) orelse return false;
    return pool.cancelRequest(request);
}

pub fn native_pool_request_state_fixture(request: PoolRequestResource) worker_pool.TerminalState {
    return @enumFromInt(request.__payload.*.terminal.load(.acquire));
}

pub fn native_pool_abandon_monitor_fixture(request: PoolRequestResource) bool {
    const pool = pool_ref.load(.acquire) orelse return false;
    pool.abandonMonitor(request);
    return true;
}

pub fn native_pool_serialization_fixture() !PoolSerializationResource {
    return PoolSerializationResource.create(.{ .state = .init(@intFromEnum(worker_pool.SerializationState.ready)) }, .{});
}

pub fn native_pool_submit_serialized_fixture(
    input: []const u8,
    resource: PoolSerializationResource,
) !worker_pool.MonitoredSubmission {
    const pool = pool_ref.load(.acquire) orelse return error.pool_stopped;
    return pool.submitSerialized(input, resource);
}

pub fn native_pool_submit_open(operation: OperationResource) !worker_pool.MonitoredSubmission {
    const pool = pool_ref.load(.acquire) orelse return error.pool_stopped;
    return pool.submitOperation(.document_open, operation, null, null, null, null, 0, 0, 0);
}

pub fn native_pool_submit_cleanup(
    operation: OperationResource,
    document: DocumentResource,
) !worker_pool.MonitoredSubmission {
    const pool = pool_ref.load(.acquire) orelse return error.pool_stopped;
    return pool.submitOperation(.document_cleanup, operation, document, null, null, null, 0, 0, 0);
}

pub fn native_pool_submit_projection(operation: OperationResource) !worker_pool.MonitoredSubmission {
    const pool = pool_ref.load(.acquire) orelse return error.pool_stopped;
    return pool.submitOperation(.projection, operation, null, null, null, null, 0, 0, 0);
}

pub fn native_pool_submit_stream_binary_setup(
    operation: OperationResource,
    projection: beam.term,
    target: beam.term,
    row_limit: u64,
    byte_limit: u64,
) !worker_pool.MonitoredSubmission {
    const pool = pool_ref.load(.acquire) orelse return error.pool_stopped;
    return pool.submitOperation(.stream_binary_setup, operation, null, null, projection, target, row_limit, byte_limit, 0);
}

pub fn native_pool_submit_stream_document_setup(
    operation: OperationResource,
    document: DocumentResource,
    projection: beam.term,
    target: beam.term,
    row_limit: u64,
    byte_limit: u64,
) !worker_pool.MonitoredSubmission {
    const pool = pool_ref.load(.acquire) orelse return error.pool_stopped;
    return pool.submitOperation(.stream_document_setup, operation, document, null, projection, target, row_limit, byte_limit, 0);
}

pub fn native_pool_submit_stream_batch(
    operation: OperationResource,
    cursor: StreamCursorResource,
    projection: beam.term,
    sequence: u64,
) !worker_pool.MonitoredSubmission {
    const pool = pool_ref.load(.acquire) orelse return error.pool_stopped;
    return pool.submitOperation(.stream_batch, operation, null, cursor, projection, null, 0, 0, sequence);
}

pub fn native_pool_close_serialization_fixture(resource: PoolSerializationResource) worker_pool.CloseStatus {
    return resource.__payload.close();
}

pub fn native_pool_serialization_state_fixture(resource: PoolSerializationResource) worker_pool.SerializationState {
    return @enumFromInt(resource.__payload.state.load(.acquire));
}

pub fn native_pool_pause_workers(paused: bool) bool {
    const pool = pool_ref.load(.acquire) orelse return false;
    pool.setPaused(paused);
    return true;
}

const JoinCopiedTermPayload = struct {
    term: beam.term,
};

/// Zigler 0.16 stores a threaded return value in the worker environment and
/// encodes it later in the generated join NIF. A raw `beam.term` field would
/// therefore belong to the wrong environment at join time. This deliberately
/// resource-shaped adapter selects Zigler's custom `make` dispatch and copies
/// the completed term into the join environment. Its registered resource type
/// is only a compile-time integration requirement; no instance is allocated.
pub const JoinCopiedTerm = struct {
    pub const __is_zigler_resource = true;

    __payload: *JoinCopiedTermPayload,
    __should_release: bool = false,

    pub fn init(comptime module: []const u8, init_opts: anytype) *e.ErlNifResourceType {
        var init_struct = e.ErlNifResourceTypeInit{
            .dtor = null,
            .stop = null,
            .down = null,
            .dyncall = null,
            .members = 0,
        };
        return e.enif_init_resource_type(
            init_opts.env,
            @typeName(JoinCopiedTermPayload) ++ "-" ++ module,
            &init_struct,
            e.ERL_NIF_RT_CREATE,
            null,
        ).?;
    }

    pub fn make(self: JoinCopiedTerm, make_opts: anytype) beam.term {
        return beam.copy(make_opts.env, self.__payload.term);
    }

    pub fn release(_: JoinCopiedTerm) void {}
};

const OperationRecord = struct {
    allocator: std.mem.Allocator,
    private_env: beam.env,
    input_term: beam.term,
    projection_term: ?beam.term,
    projection_source_kind: ?ProjectionSourceKind,
    projection_document: ?*DocumentControl,
    projection_reservation: ?document_resource.ProjectionReservation,
    projection_reservation_active: std.atomic.Value(bool),
    projection_committed: std.atomic.Value(bool),
    projection_boundaries: std.atomic.Value(usize),
    projection_failure_after: std.atomic.Value(usize),
    projection_result_payload: JoinCopiedTermPayload,
    request_ref: beam.term,
    owner: beam.pid,
    kind: OperationKind,
    generation: u64,
    state: std.atomic.Value(u8),
    cancelled: std.atomic.Value(bool),
    pause_boundary: std.atomic.Value(u8),
    pause_released: std.atomic.Value(bool),
    pause_observer: ?beam.pid,

    fn currentState(self: *const OperationRecord) OperationState {
        return @enumFromInt(self.state.load(.acquire));
    }

    fn accountDequeued(self: *const OperationRecord) void {
        const queued = ExecutionAccounting.queued_operations.fetchSub(1, .acq_rel);
        std.debug.assert(queued > 0);
        if (self.kind == .document_cleanup) {
            const cleanup = ExecutionAccounting.queued_cleanup.fetchSub(1, .acq_rel);
            std.debug.assert(cleanup > 0);
        }
    }

    fn beginRunning(self: *OperationRecord) bool {
        if (self.cancelled.load(.acquire)) {
            if (self.state.cmpxchgStrong(
                @intFromEnum(OperationState.queued),
                @intFromEnum(OperationState.cancelling),
                .acq_rel,
                .acquire,
            ) == null) {
                self.accountDequeued();
            }
            return false;
        }

        if (self.state.cmpxchgStrong(
            @intFromEnum(OperationState.queued),
            @intFromEnum(OperationState.running),
            .acq_rel,
            .acquire,
        ) != null) return false;

        self.accountDequeued();
        _ = ExecutionAccounting.running_operations.fetchAdd(1, .acq_rel);
        _ = ExecutionAccounting.worker_entries.fetchAdd(1, .acq_rel);
        if (self.kind == .projection)
            _ = ExecutionAccounting.projection_worker_count.fetchAdd(1, .acq_rel);
        if (self.kind == .stream_setup)
            _ = ExecutionAccounting.stream_setup_worker_entries.fetchAdd(1, .acq_rel);
        if (self.kind == .stream_batch)
            _ = ExecutionAccounting.stream_batch_worker_entries.fetchAdd(1, .acq_rel);
        return true;
    }

    fn markReadyForDelivery(self: *OperationRecord) bool {
        const running = ExecutionAccounting.running_operations.fetchSub(1, .acq_rel);
        std.debug.assert(running > 0);

        if (self.cancelled.load(.acquire)) {
            self.state.store(@intFromEnum(OperationState.cancelling), .release);
            return false;
        }

        self.state.store(@intFromEnum(OperationState.delivering), .release);
        return true;
    }

    fn abortRunning(self: *OperationRecord) void {
        const state = self.currentState();
        if (state != .running and state != .cancelling) return;

        const running = ExecutionAccounting.running_operations.fetchSub(1, .acq_rel);
        std.debug.assert(running > 0);
        self.state.store(@intFromEnum(OperationState.cancelling), .release);
    }

    fn cancel(self: *OperationRecord) void {
        self.cancelled.store(true, .release);

        while (true) {
            const state = self.currentState();
            switch (state) {
                .queued, .running, .delivering => {
                    if (self.state.cmpxchgWeak(
                        @intFromEnum(state),
                        @intFromEnum(OperationState.cancelling),
                        .acq_rel,
                        .acquire,
                    ) == null) {
                        if (state == .queued) {
                            self.accountDequeued();
                        }
                        return;
                    }
                },
                .cancelling, .completed, .discarded => return,
            }
        }
    }

    fn finish(self: *OperationRecord, outcome: OperationOutcome) bool {
        while (true) {
            const state = self.currentState();
            switch (state) {
                .completed, .discarded => return false,
                .queued => {
                    if (self.state.cmpxchgWeak(
                        @intFromEnum(OperationState.queued),
                        @intFromEnum(OperationState.discarded),
                        .acq_rel,
                        .acquire,
                    ) == null) {
                        self.accountDequeued();
                        _ = ExecutionAccounting.discarded_results.fetchAdd(1, .acq_rel);
                        if (self.kind == .projection)
                            _ = ExecutionAccounting.discarded_projection_deliveries.fetchAdd(1, .acq_rel);
                        if (self.kind == .stream_setup or self.kind == .stream_batch)
                            _ = ExecutionAccounting.stream_discards.fetchAdd(1, .acq_rel);
                        return true;
                    }
                },
                .running => return false,
                .cancelling, .delivering => {
                    const terminal: OperationState = if (outcome == .delivered and state == .delivering)
                        .completed
                    else
                        .discarded;
                    if (self.state.cmpxchgWeak(
                        @intFromEnum(state),
                        @intFromEnum(terminal),
                        .acq_rel,
                        .acquire,
                    ) == null) {
                        if (terminal == .completed) {
                            _ = ExecutionAccounting.delivered_results.fetchAdd(1, .acq_rel);
                            if (self.kind == .projection)
                                _ = ExecutionAccounting.completed_projection_deliveries.fetchAdd(1, .acq_rel);
                            if (self.kind == .stream_setup or self.kind == .stream_batch)
                                _ = ExecutionAccounting.stream_deliveries.fetchAdd(1, .acq_rel);
                        } else {
                            _ = ExecutionAccounting.discarded_results.fetchAdd(1, .acq_rel);
                            if (self.kind == .projection)
                                _ = ExecutionAccounting.discarded_projection_deliveries.fetchAdd(1, .acq_rel);
                            if (self.kind == .stream_setup or self.kind == .stream_batch)
                                _ = ExecutionAccounting.stream_discards.fetchAdd(1, .acq_rel);
                        }
                        return true;
                    }
                },
            }
        }
    }

    fn inputLength(self: *const OperationRecord) !usize {
        var binary: e.ErlNifBinary = undefined;
        if (e.enif_inspect_binary(self.private_env, self.input_term.v, &binary) == 0)
            return error.invalid_retained_input;
        return binary.size;
    }

    fn inputBytes(self: *const OperationRecord) ![]const u8 {
        var binary: e.ErlNifBinary = undefined;
        if (e.enif_inspect_binary(self.private_env, self.input_term.v, &binary) == 0)
            return error.invalid_retained_input;
        return binary.data[0..binary.size];
    }

    fn projectionTerm(self: *const OperationRecord) !beam.term {
        return self.projection_term orelse error.invalid_projection_payload;
    }

    fn rollbackProjectionReservation(self: *OperationRecord) bool {
        if (!self.projection_reservation_active.load(.acquire) or
            self.projection_committed.load(.acquire))
            return false;
        const control = self.projection_document orelse return false;
        const reservation = self.projection_reservation orelse return false;
        if (self.projection_reservation_active.cmpxchgStrong(
            true,
            false,
            .acq_rel,
            .acquire,
        ) != null) return false;
        return control.native.rollbackProjection(reservation);
    }

    fn commitProjectionReservation(self: *OperationRecord) bool {
        if (!self.projection_reservation_active.load(.acquire) or
            self.projection_committed.load(.acquire))
            return false;
        const control = self.projection_document orelse return false;
        const reservation = self.projection_reservation orelse return false;
        if (control.module_generation != self.generation) return false;
        if (!control.native.commitProjection(reservation)) return false;
        self.projection_committed.store(true, .release);
        return true;
    }

    fn projectionDocumentHandle(self: *OperationRecord) ?*c.simd_json_document {
        const control = self.projection_document orelse return null;
        const reservation = self.projection_reservation orelse return null;
        if (!self.projection_reservation_active.load(.acquire) or
            !self.projection_committed.load(.acquire))
            return null;
        return control.native.projectionDocument(reservation);
    }

    fn releaseProjectionReservation(self: *OperationRecord) bool {
        if (self.projection_source_kind != .document or
            !self.projection_reservation_active.swap(false, .acq_rel))
            return false;
        const control = self.projection_document orelse return false;
        const reservation = self.projection_reservation orelse return false;
        if (self.projection_committed.load(.acquire)) {
            control.native.releaseCommittedProjection(reservation);
            return true;
        }
        return control.native.rollbackProjection(reservation);
    }

    fn pauseAt(self: *OperationRecord, boundary: OperationBoundary) void {
        if (self.pause_boundary.load(.acquire) != @intFromEnum(boundary)) return;
        if (self.pause_released.load(.acquire) or self.cancelled.load(.acquire)) return;

        if (self.pause_observer) |observer| {
            const request_ref = beam.copy(beam.context.env, self.request_ref);
            beam.send(
                observer,
                .{ .simd_json_native_boundary, request_ref, self.kind, self.generation, boundary },
                .{},
            ) catch {};
        }

        while (!self.pause_released.load(.acquire) and
            !self.cancelled.load(.acquire))
        {
            beam.context.io.sleep(.{ .nanoseconds = 1_000_000 }, .awake) catch {};
            if (beam.context.mode == .threaded) beam.yield() catch break;
        }
    }
};

const DecodedProjection = struct {
    allocator: std.mem.Allocator,
    entries: []projection_plan.NormalizedEntry,
    paths: []projection_plan.NormalizedPath,
    output_keys: []beam.term,

    fn deinit(self: *DecodedProjection) void {
        for (self.paths) |path| {
            if (path.segments.len != 0) self.allocator.free(path.segments);
        }
        self.allocator.free(self.output_keys);
        self.allocator.free(self.paths);
        self.allocator.free(self.entries);
        self.* = undefined;
    }

    fn normalized(self: *const DecodedProjection) projection_plan.NormalizedProjection {
        return .{ .entries = self.entries, .paths = self.paths };
    }
};

const ProjectionDecodeError = error{ OutOfMemory, InvalidProjection };

fn tupleElements(
    env: beam.env,
    term: beam.term,
    expected_arity: c_int,
) ?[*c]const e.ErlNifTerm {
    var arity: c_int = 0;
    var elements: [*c]const e.ErlNifTerm = undefined;
    if (e.enif_get_tuple(env, term.v, &arity, &elements) == 0 or
        arity != expected_arity)
        return null;
    return elements;
}

fn properListLength(env: beam.env, term: beam.term) ?usize {
    var length: c_uint = 0;
    if (e.enif_get_list_length(env, term.v, &length) == 0) return null;
    return @intCast(length);
}

fn uint64Term(env: beam.env, term: e.ErlNifTerm) ?u64 {
    var value: u64 = 0;
    if (e.enif_get_uint64(env, term, &value) == 0) return null;
    return value;
}

fn decodeProjectionTerm(env: beam.env, projection: beam.term) ProjectionDecodeError!DecodedProjection {
    const root_elements = tupleElements(env, projection, 3) orelse
        return error.InvalidProjection;
    const expected_tag = beam.make_into_atom("simd_json_projection_v1", .{ .env = env });
    if (e.enif_compare(root_elements[0], expected_tag.v) != 0)
        return error.InvalidProjection;

    const entries_term = beam.term{ .v = root_elements[1] };
    const paths_term = beam.term{ .v = root_elements[2] };
    const entry_count = properListLength(env, entries_term) orelse
        return error.InvalidProjection;
    const path_count = properListLength(env, paths_term) orelse
        return error.InvalidProjection;
    if (entry_count == 0 or path_count == 0) return error.InvalidProjection;

    const allocator = beam.allocator;
    const entries = allocator.alloc(projection_plan.NormalizedEntry, entry_count) catch
        return error.OutOfMemory;
    errdefer allocator.free(entries);
    const paths = allocator.alloc(projection_plan.NormalizedPath, path_count) catch
        return error.OutOfMemory;
    errdefer allocator.free(paths);
    for (paths) |*path| path.* = .{ .path_slot = 0, .segments = &.{} };
    errdefer for (paths) |path| {
        if (path.segments.len != 0) allocator.free(path.segments);
    };
    const output_keys = allocator.alloc(beam.term, entry_count) catch
        return error.OutOfMemory;
    errdefer allocator.free(output_keys);
    const seen_slots = allocator.alloc(bool, entry_count) catch
        return error.OutOfMemory;
    defer allocator.free(seen_slots);
    @memset(seen_slots, false);

    var list = entries_term.v;
    for (entries) |*entry| {
        var head: e.ErlNifTerm = undefined;
        var tail: e.ErlNifTerm = undefined;
        if (e.enif_get_list_cell(env, list, &head, &tail) == 0)
            return error.InvalidProjection;
        list = tail;
        const fields = tupleElements(env, .{ .v = head }, 3) orelse
            return error.InvalidProjection;
        const output_slot = uint64Term(env, fields[0]) orelse
            return error.InvalidProjection;
        const path_slot = uint64Term(env, fields[2]) orelse
            return error.InvalidProjection;
        const slot_index = std.math.cast(usize, output_slot) orelse
            return error.InvalidProjection;
        if (slot_index >= output_keys.len or seen_slots[slot_index])
            return error.InvalidProjection;
        if (e.enif_is_atom(env, fields[1]) == 0 and
            e.enif_is_binary(env, fields[1]) == 0)
            return error.InvalidProjection;

        seen_slots[slot_index] = true;
        output_keys[slot_index] = .{ .v = fields[1] };
        entry.* = .{ .output_slot = output_slot, .path_slot = path_slot };
    }

    list = paths_term.v;
    for (paths) |*path| {
        var head: e.ErlNifTerm = undefined;
        var tail: e.ErlNifTerm = undefined;
        if (e.enif_get_list_cell(env, list, &head, &tail) == 0)
            return error.InvalidProjection;
        list = tail;
        const fields = tupleElements(env, .{ .v = head }, 2) orelse
            return error.InvalidProjection;
        const path_slot = uint64Term(env, fields[0]) orelse
            return error.InvalidProjection;
        const segments_term = beam.term{ .v = fields[1] };
        const segment_count = properListLength(env, segments_term) orelse
            return error.InvalidProjection;
        if (segment_count == 0) return error.InvalidProjection;
        const segments = allocator.alloc(projection_plan.Segment, segment_count) catch
            return error.OutOfMemory;
        path.* = .{ .path_slot = path_slot, .segments = segments };

        var segment_list = segments_term.v;
        for (segments) |*segment| {
            var segment_head: e.ErlNifTerm = undefined;
            var segment_tail: e.ErlNifTerm = undefined;
            if (e.enif_get_list_cell(
                env,
                segment_list,
                &segment_head,
                &segment_tail,
            ) == 0) return error.InvalidProjection;
            segment_list = segment_tail;

            var binary: e.ErlNifBinary = undefined;
            if (e.enif_inspect_binary(env, segment_head, &binary) != 0) {
                segment.* = .{ .object_key = binary.data[0..binary.size] };
            } else {
                const index = uint64Term(env, segment_head) orelse
                    return error.InvalidProjection;
                segment.* = .{ .array_index = index };
            }
        }
    }

    for (seen_slots) |seen| if (!seen) return error.InvalidProjection;
    return .{
        .allocator = allocator,
        .entries = entries,
        .paths = paths,
        .output_keys = output_keys,
    };
}

fn decodeProjection(record: *const OperationRecord) ProjectionDecodeError!DecodedProjection {
    return decodeProjectionTerm(
        record.private_env,
        record.projectionTerm() catch return error.InvalidProjection,
    );
}

fn decodeTargetTerm(env: beam.env, target: beam.term) ProjectionDecodeError![]stream_cursor.Segment {
    const count = properListLength(env, target) orelse return error.InvalidProjection;
    const segments = beam.allocator.alloc(stream_cursor.Segment, count) catch
        return error.OutOfMemory;
    errdefer beam.allocator.free(segments);
    var list = target.v;
    for (segments) |*segment| {
        var head: e.ErlNifTerm = undefined;
        var tail: e.ErlNifTerm = undefined;
        if (e.enif_get_list_cell(env, list, &head, &tail) == 0)
            return error.InvalidProjection;
        list = tail;
        var binary: e.ErlNifBinary = undefined;
        if (e.enif_inspect_binary(env, head, &binary) != 0)
            segment.* = .{ .object_key = binary.data[0..binary.size] }
        else
            segment.* = .{ .array_index = uint64Term(env, head) orelse return error.InvalidProjection };
    }
    return segments;
}

const OperationResourceCallbacks = struct {
    pub fn dtor(payload: **OperationRecord) void {
        const operation = payload.*;
        _ = operation.finish(.discarded);
        _ = operation.releaseProjectionReservation();
        beam.free_env(operation.private_env);

        if (operation.kind == .projection) {
            const environments = ExecutionAccounting.projection_environment_count.fetchSub(1, .acq_rel);
            std.debug.assert(environments > 0);
            const projections = ExecutionAccounting.projection_operation_count.fetchSub(1, .acq_rel);
            std.debug.assert(projections > 0);
            switch (operation.projection_source_kind orelse unreachable) {
                .binary => {
                    const retained = ExecutionAccounting.retained_projection_binaries.fetchSub(1, .acq_rel);
                    std.debug.assert(retained > 0);
                },
                .document => {
                    const retained = ExecutionAccounting.retained_projection_documents.fetchSub(1, .acq_rel);
                    std.debug.assert(retained > 0);
                },
            }
        }
        if (operation.kind == .stream_setup) {
            const live = ExecutionAccounting.live_stream_setup_operations.fetchSub(1, .acq_rel);
            std.debug.assert(live > 0);
        }
        if (operation.kind == .stream_batch) {
            const live = ExecutionAccounting.live_stream_batch_operations.fetchSub(1, .acq_rel);
            std.debug.assert(live > 0);
        }
        operation.allocator.destroy(operation);

        const retained = ExecutionAccounting.retained_inputs.fetchSub(1, .acq_rel);
        std.debug.assert(retained > 0);
        const live = ExecutionAccounting.live_operations.fetchSub(1, .acq_rel);
        std.debug.assert(live > 0);
    }
};

pub const OperationResource = beam.Resource(
    *OperationRecord,
    root,
    .{ .Callbacks = OperationResourceCallbacks },
);

const ExecutionSnapshot = struct {
    live_operations: usize,
    retained_inputs: usize,
    queued_operations: usize,
    queued_cleanup: usize,
    running_operations: usize,
    delivered_results: usize,
    discarded_results: usize,
    worker_entries: usize,
    live_documents: usize,
    completed_document_cleanup: usize,
    live_document_controls: usize,
    dispatcher_queued_cleanup: usize,
    dispatcher_active_cleanup: usize,
    dispatcher_completed_cleanup: usize,
    retained_failed_cleanup: usize,
    cleanup_submission_failures: usize,
    live_projection_operations: usize,
    retained_projection_binaries: usize,
    retained_projection_documents: usize,
    live_projection_environments: usize,
    live_projection_plans: usize,
    live_projection_slots: usize,
    live_projection_temporary_document_graphs: usize,
    completed_projection_deliveries: usize,
    discarded_projection_deliveries: usize,
    projection_worker_entries: usize,
    projection_boundary_entries: usize,
    live_stream_cursor_resources: usize,
    retained_stream_cursor_parents: usize,
    live_stream_setup_operations: usize,
    live_stream_batch_operations: usize,
    stream_setup_worker_entries: usize,
    stream_batch_worker_entries: usize,
    stream_deliveries: usize,
    stream_discards: usize,
};

const ThreadedSmokeResult = struct {
    context: ExecutionContext,
    owner_matches: bool,
    kind: OperationKind,
    generation: u64,
    input_length: usize,
    ready_for_delivery: bool,
};

pub const DocumentOpenStatus = enum(u8) {
    ok,
    cancelled,
    execution_unavailable,
    invalid_json,
    invalid_utf8,
    unexpected_eof,
    out_of_memory,
    invalid_argument,
    internal_failure,
};

pub const DocumentOpenResult = struct {
    status: DocumentOpenStatus,
    kind: OperationKind,
    generation: u64,
    worker_context: ExecutionContext,
    native_code: ?i32,
    byte_offset: ?u64,
    document: ?DocumentResource,
};

pub const DocumentCleanupResult = struct {
    status: enum(u8) { closed, execution_unavailable, internal_failure },
    kind: OperationKind,
    generation: u64,
    worker_context: ExecutionContext,
};

const DocumentProbeStatus = enum(u8) {
    ok,
    closed,
    not_owner,
    execution_unavailable,
    test_unavailable,
    internal_failure,
};

const DocumentProbeResult = struct {
    status: DocumentProbeStatus,
    kind: OperationKind,
    generation: u64,
    worker_context: ExecutionContext,
    uses_owned_input: bool,
    valid: bool,
    ready_for_delivery: bool,
};

pub const DocumentOwnerState = enum(u8) {
    open,
    closing,
    closed,
    not_owner,
};

const DocumentProjectionOwnerState = enum(u8) {
    fresh,
    selecting,
    streaming,
    consumed,
    closing,
    closed,
    not_owner,
};

pub const ProjectionAdmissionStatus = enum(u8) {
    ok,
    invalid_source,
    invalid_projection,
    not_owner,
    closed,
    cursor_consumed,
    execution_unavailable,
};

pub const ProjectionAdmissionResult = struct {
    status: ProjectionAdmissionStatus,
    operation: ?OperationResource,
};

pub const ProjectionStatus = enum(u8) {
    ok,
    cancelled,
    execution_unavailable,
    invalid_projection,
    invalid_json,
    invalid_utf8,
    unexpected_eof,
    out_of_memory,
    invalid_argument,
    internal_failure,
    missing_field,
    index_out_of_bounds,
    incorrect_type,
    number_out_of_range,
    cursor_consumed,
};

pub const ProjectionResult = struct {
    status: ProjectionStatus,
    kind: OperationKind,
    generation: u64,
    worker_context: ExecutionContext,
    native_code: ?i32,
    byte_offset: ?u64,
    output_slot: ?u32,
    result: ?JoinCopiedTerm,
    ready_for_delivery: bool,
    compilation_nanoseconds: u64,
    traversal_nanoseconds: u64,
    term_construction_nanoseconds: u64,
    boundary_count: usize,
};

pub fn pool_encode_projection_result(env: beam.env, result: ProjectionResult) beam.term {
    return beam.make(.{
        .status = result.status,
        .kind = result.kind,
        .generation = result.generation,
        .worker_context = result.worker_context,
        .native_code = result.native_code,
        .byte_offset = result.byte_offset,
        .output_slot = result.output_slot,
        .result = if (result.result) |value| beam.copy(env, value.__payload.term) else null,
        .ready_for_delivery = result.ready_for_delivery,
        .compilation_nanoseconds = result.compilation_nanoseconds,
        .traversal_nanoseconds = result.traversal_nanoseconds,
        .term_construction_nanoseconds = result.term_construction_nanoseconds,
        .boundary_count = result.boundary_count,
    }, .{ .env = env });
}

var module_loaded = std.atomic.Value(bool).init(false);
var module_generation = std.atomic.Value(u64).init(0);

fn executionContext() ExecutionContext {
    return switch (beam.context.mode) {
        .synchronous => .synchronous,
        .threaded => .threaded,
        .dirty, .dirty_yield => .dirty,
        .callback => .callback,
        .yielding => .unsupported,
        // The library-owned pool installs an independent environment on each
        // fixed worker before entering the same operation implementations.
        .independent => .threaded,
    };
}

fn pidsEqual(left: beam.pid, right: beam.pid) bool {
    beam.ignore_when_sema();
    return e.enif_compare(left.pid, right.pid) == 0;
}

fn operationCancelled(context: ?*anyopaque) bool {
    const operation: *OperationRecord = @ptrCast(@alignCast(context.?));
    return operation.cancelled.load(.acquire);
}

fn projectionBoundary(record: *OperationRecord, boundary: OperationBoundary) void {
    _ = record.projection_boundaries.fetchAdd(1, .acq_rel);
    _ = ExecutionAccounting.projection_boundary_count.fetchAdd(1, .acq_rel);
    record.pauseAt(boundary);
}

fn projectionCheckpointFails(record: *OperationRecord) bool {
    while (true) {
        const remaining = record.projection_failure_after.load(.acquire);
        if (remaining == std.math.maxInt(usize)) return false;
        if (remaining == 0) {
            return record.projection_failure_after.cmpxchgWeak(
                0,
                std.math.maxInt(usize),
                .acq_rel,
                .acquire,
            ) == null;
        }
        if (record.projection_failure_after.cmpxchgWeak(
            remaining,
            remaining - 1,
            .acq_rel,
            .acquire,
        ) == null) return false;
    }
}

fn projectionCancellation(context: ?*anyopaque) callconv(.c) u32 {
    const record: *OperationRecord = @ptrCast(@alignCast(context.?));
    projectionBoundary(record, .during_traversal);
    const stale = !module_loaded.load(.acquire) or
        record.generation != module_generation.load(.acquire);
    return @intFromBool(stale or record.cancelled.load(.acquire));
}

fn operationBoundary(
    context: ?*anyopaque,
    boundary: document_resource.CancellationBoundary,
) void {
    const operation: *OperationRecord = @ptrCast(@alignCast(context.?));
    operation.pauseAt(switch (boundary) {
        .before_copy => .before_copy,
        .before_parse => .before_parse,
        .after_parse => .after_parse,
        .before_publication => .before_publication,
    });
}

fn documentOpenResult(
    status: DocumentOpenStatus,
    operation: *const OperationRecord,
    diagnostics: ?document_resource.Diagnostics,
    document: ?DocumentResource,
) DocumentOpenResult {
    return .{
        .status = status,
        .kind = operation.kind,
        .generation = operation.generation,
        .worker_context = executionContext(),
        .native_code = if (diagnostics) |value| value.native_code else null,
        .byte_offset = if (diagnostics) |value| value.byte_offset else null,
        .document = document,
    };
}

fn failedDocumentOpen(
    status: document_resource.NativeStatus,
    operation: *const OperationRecord,
) DocumentOpenResult {
    return switch (status) {
        .ok => unreachable,
        .invalid_json => |diagnostics| documentOpenResult(.invalid_json, operation, diagnostics, null),
        .invalid_utf8 => |diagnostics| documentOpenResult(.invalid_utf8, operation, diagnostics, null),
        .unexpected_eof => |diagnostics| documentOpenResult(.unexpected_eof, operation, diagnostics, null),
        .out_of_memory => |diagnostics| documentOpenResult(.out_of_memory, operation, diagnostics, null),
        .invalid_argument => |diagnostics| documentOpenResult(.invalid_argument, operation, diagnostics, null),
        .internal_failure => |diagnostics| documentOpenResult(.internal_failure, operation, diagnostics, null),
    };
}

fn finishDocumentProbe(
    record: *OperationRecord,
    status: DocumentProbeStatus,
    uses_owned_input: bool,
    valid: bool,
) DocumentProbeResult {
    const ready = record.markReadyForDelivery();
    return .{
        .status = if (ready) status else .internal_failure,
        .kind = record.kind,
        .generation = record.generation,
        .worker_context = executionContext(),
        .uses_owned_input = uses_owned_input,
        .valid = valid,
        .ready_for_delivery = ready,
    };
}

fn finishDocumentAccounting(control: *DocumentControl) void {
    if (control.accounted.swap(false, .acq_rel)) {
        const live = ExecutionAccounting.live_documents.fetchSub(1, .acq_rel);
        std.debug.assert(live > 0);
        _ = ExecutionAccounting.completed_document_cleanup.fetchAdd(1, .acq_rel);
    }
}

fn destroyDocumentControl(control: *DocumentControl) void {
    const allocator = control.allocator;
    allocator.destroy(control);
    const live = ExecutionAccounting.live_document_controls.fetchSub(1, .acq_rel);
    std.debug.assert(live > 0);
}

fn cleanupDetachedDocument(control: *DocumentControl) void {
    if (control.native.lifecycleState() == .open)
        _ = control.native.beginClose();

    while (!control.native.completeCleanup()) std.atomic.spinLoopHint();
    finishDocumentAccounting(control);
    destroyDocumentControl(control);
}

fn completeThreadedDocumentCleanup(control: *DocumentControl) bool {
    switch (control.native.beginClose()) {
        .cleanup_owner, .closing => while (!control.native.completeCleanup()) std.atomic.spinLoopHint(),
        .closed => return true,
    }
    return control.native.lifecycleState() == .closed;
}

fn cleanupWorkerMain(raw_runtime: ?*anyopaque) callconv(.c) ?*anyopaque {
    const runtime: *Runtime = @ptrCast(@alignCast(raw_runtime.?));

    while (true) {
        e.enif_mutex_lock(runtime.mutex);
        while (runtime.queue_head == null and !runtime.shutdown_requested) {
            e.enif_cond_wait(runtime.condition, runtime.mutex);
        }

        const control = runtime.pop();
        if (control == null and runtime.shutdown_requested) {
            runtime.worker_running = false;
            e.enif_cond_broadcast(runtime.condition);
            e.enif_mutex_unlock(runtime.mutex);
            return null;
        }

        const queued = ExecutionAccounting.dispatcher_queued_cleanup.fetchSub(1, .acq_rel);
        std.debug.assert(queued > 0);
        _ = ExecutionAccounting.dispatcher_active_cleanup.fetchAdd(1, .acq_rel);
        e.enif_mutex_unlock(runtime.mutex);

        cleanupDetachedDocument(control.?);

        e.enif_mutex_lock(runtime.mutex);
        const active = ExecutionAccounting.dispatcher_active_cleanup.fetchSub(1, .acq_rel);
        std.debug.assert(active > 0);
        _ = ExecutionAccounting.dispatcher_completed_cleanup.fetchAdd(1, .acq_rel);
        e.enif_cond_broadcast(runtime.condition);
        e.enif_mutex_unlock(runtime.mutex);
    }
}

fn enqueueDetachedDocument(control: *DocumentControl) void {
    const runtime = runtime_ref.load(.acquire) orelse {
        _ = ExecutionAccounting.retained_failed_cleanup.fetchAdd(1, .acq_rel);
        _ = ExecutionAccounting.cleanup_submission_failures.fetchAdd(1, .acq_rel);
        return;
    };
    _ = runtime.enqueue(control);
}

fn createDocumentControl(owner: beam.pid, generation: u64) !*DocumentControl {
    const allocator = beam.allocator;
    const control = try allocator.create(DocumentControl);
    control.* = .{
        .allocator = allocator,
        .native = document_resource.DocumentState.empty(),
        .owner = owner,
        .module_generation = generation,
        .accounted = .init(false),
        .cleanup_next = null,
    };
    _ = ExecutionAccounting.live_document_controls.fetchAdd(1, .acq_rel);
    return control;
}

fn operationAdmissionAvailable(generation: u64) bool {
    const runtime = runtime_ref.load(.acquire) orelse return false;
    return module_loaded.load(.acquire) and
        runtime.accepting.load(.acquire) and
        generation != 0 and
        generation == module_generation.load(.acquire);
}

fn validProjectionEnvelope(projection: beam.term) bool {
    var arity: c_int = 0;
    var elements: [*c]const e.ErlNifTerm = undefined;
    if (e.enif_get_tuple(beam.context.env, projection.v, &arity, &elements) == 0 or
        arity != 3)
        return false;
    const expected = beam.make_into_atom("simd_json_projection_v1", .{});
    return e.enif_compare(elements[0], expected.v) == 0;
}

fn createOperation(
    input: beam.term,
    projection: ?beam.term,
    owner: beam.pid,
    kind: OperationKind,
    generation: u64,
    projection_source_kind: ?ProjectionSourceKind,
    projection_document: ?*DocumentControl,
    projection_reservation: ?document_resource.ProjectionReservation,
) !OperationResource {
    const private_env = beam.alloc_env();
    errdefer beam.free_env(private_env);

    const allocator = beam.allocator;
    const operation = try allocator.create(OperationRecord);
    errdefer allocator.destroy(operation);

    const request_ref = beam.make_ref(.{});
    operation.* = .{
        .allocator = allocator,
        .private_env = private_env,
        .input_term = beam.copy(private_env, input),
        .projection_term = if (projection) |term| beam.copy(private_env, term) else null,
        .projection_source_kind = projection_source_kind,
        .projection_document = projection_document,
        .projection_reservation = projection_reservation,
        .projection_reservation_active = .init(projection_reservation != null),
        .projection_committed = .init(false),
        .projection_boundaries = .init(0),
        .projection_failure_after = .init(std.math.maxInt(usize)),
        .projection_result_payload = .{ .term = beam.make(null, .{ .env = private_env }) },
        .request_ref = beam.copy(private_env, request_ref),
        .owner = owner,
        .kind = kind,
        .generation = generation,
        .state = .init(@intFromEnum(OperationState.queued)),
        .cancelled = .init(false),
        .pause_boundary = .init(@intFromEnum(OperationBoundary.none)),
        .pause_released = .init(false),
        .pause_observer = null,
    };

    const resource = try OperationResource.create(operation, .{});
    _ = ExecutionAccounting.live_operations.fetchAdd(1, .acq_rel);
    _ = ExecutionAccounting.retained_inputs.fetchAdd(1, .acq_rel);
    _ = ExecutionAccounting.queued_operations.fetchAdd(1, .acq_rel);
    if (kind == .document_cleanup)
        _ = ExecutionAccounting.queued_cleanup.fetchAdd(1, .acq_rel);
    if (kind == .projection) {
        _ = ExecutionAccounting.projection_operation_count.fetchAdd(1, .acq_rel);
        _ = ExecutionAccounting.projection_environment_count.fetchAdd(1, .acq_rel);
        switch (projection_source_kind orelse unreachable) {
            .binary => _ = ExecutionAccounting.retained_projection_binaries.fetchAdd(1, .acq_rel),
            .document => _ = ExecutionAccounting.retained_projection_documents.fetchAdd(1, .acq_rel),
        }
    }
    if (kind == .stream_setup)
        _ = ExecutionAccounting.live_stream_setup_operations.fetchAdd(1, .acq_rel);
    if (kind == .stream_batch)
        _ = ExecutionAccounting.live_stream_batch_operations.fetchAdd(1, .acq_rel);
    return resource;
}

/// Bounded admission retains a private-env reference to the binary; it does
/// not copy caller bytes. The worker later performs the sole owned JSON copy.
pub fn operation_admit(
    input: beam.term,
    owner: beam.pid,
    kind: OperationKind,
    generation: u64,
) !OperationResource {
    if (!operationAdmissionAvailable(generation))
        return error.execution_unavailable;

    var inspected: e.ErlNifBinary = undefined;
    if (e.enif_inspect_binary(beam.context.env, input.v, &inspected) == 0)
        return error.invalid_input;

    return createOperation(input, null, owner, kind, generation, null, null, null);
}

/// Bounded projection admission retains the normalized descriptor and source
/// term in the operation's private environment. Document sources validate the
/// registered resource and immutable owner before reserving one projection.
pub fn projection_operation_admit(
    source: beam.term,
    projection: beam.term,
    owner: beam.pid,
    source_kind: ProjectionSourceKind,
    generation: u64,
) !ProjectionAdmissionResult {
    if (!operationAdmissionAvailable(generation)) return .{
        .status = .execution_unavailable,
        .operation = null,
    };
    if (!validProjectionEnvelope(projection)) return .{
        .status = .invalid_projection,
        .operation = null,
    };

    var control: ?*DocumentControl = null;
    var reservation: ?document_resource.ProjectionReservation = null;

    switch (source_kind) {
        .binary => {
            var inspected: e.ErlNifBinary = undefined;
            if (e.enif_inspect_binary(beam.context.env, source.v, &inspected) == 0)
                return .{ .status = .invalid_source, .operation = null };
        },
        .document => {
            var document: DocumentResource = undefined;
            document.get(source, .{ .released = false }) catch
                return .{ .status = .invalid_source, .operation = null };
            control = document.__payload.control orelse
                return .{ .status = .closed, .operation = null };

            // Ownership is deliberately checked before lifecycle, generation,
            // or one-shot state so another process learns nothing about them.
            if (!pidsEqual(owner, control.?.owner))
                return .{ .status = .not_owner, .operation = null };
            if (control.?.module_generation != generation)
                return .{ .status = .execution_unavailable, .operation = null };

            switch (control.?.native.reserveProjection()) {
                .reserved => |value| reservation = value,
                .cursor_consumed => return .{
                    .status = .cursor_consumed,
                    .operation = null,
                },
                .closed => return .{ .status = .closed, .operation = null },
            }
        },
    }

    errdefer if (reservation) |value| {
        _ = control.?.native.rollbackProjection(value);
    };

    const operation = try createOperation(
        source,
        projection,
        owner,
        .projection,
        generation,
        source_kind,
        control,
        reservation,
    );
    return .{ .status = .ok, .operation = operation };
}

pub fn projection_operation_rollback(operation: OperationResource) bool {
    const record = operation.unpack();
    if (record.kind != .projection) return false;
    return record.rollbackProjectionReservation();
}

pub fn projection_operation_release(operation: OperationResource) bool {
    const record = operation.unpack();
    if (record.kind != .projection) return false;
    if (record.projection_source_kind == .binary) return true;
    return record.releaseProjectionReservation();
}

pub fn projection_operation_inject_failure(
    operation: OperationResource,
    successful_checkpoints: usize,
) bool {
    const record = operation.unpack();
    if (record.kind != .projection or record.currentState() != .queued) return false;
    record.projection_failure_after.store(successful_checkpoints, .release);
    return true;
}

pub fn operation_metadata(operation: OperationResource) beam.term {
    const record = operation.unpack();
    return beam.make(.{
        beam.copy(beam.context.env, record.request_ref),
        record.kind,
        record.generation,
        record.currentState(),
    }, .{});
}

pub fn operation_pool_env(operation: OperationResource) beam.env {
    return operation.unpack().private_env;
}

pub fn operation_cancel(operation: OperationResource) bool {
    const record = operation.unpack();
    record.cancel();
    return true;
}

pub fn operation_finish(operation: OperationResource, outcome: OperationOutcome) bool {
    return operation.unpack().finish(outcome);
}

pub fn operation_configure_pause(
    operation: OperationResource,
    boundary: OperationBoundary,
    observer: beam.pid,
) bool {
    const record = operation.unpack();
    if (boundary == .none or record.currentState() != .queued) return false;
    record.pause_observer = observer;
    record.pause_released.store(false, .release);
    record.pause_boundary.store(@intFromEnum(boundary), .release);
    return true;
}

pub fn operation_release_pause(operation: OperationResource) bool {
    operation.unpack().pause_released.store(true, .release);
    return true;
}

pub fn admission_context() ExecutionContext {
    return executionContext();
}

pub fn operation_owner_matches(operation: OperationResource) !bool {
    return pidsEqual(try beam.self(.{}), operation.unpack().owner);
}

pub fn operation_owner_is(operation: OperationResource, owner: beam.pid) bool {
    return pidsEqual(owner, operation.unpack().owner);
}

/// Pinned Zigler `:threaded` smoke operation. The operation resource retains
/// its private input environment until the generated join and payload cleanup.
pub fn threaded_context_smoke(operation: OperationResource) !ThreadedSmokeResult {
    const record = operation.unpack();
    if (!record.beginRunning()) return error.operation_cancelled;
    var worker_finished = false;
    defer if (!worker_finished) record.abortRunning();

    record.pauseAt(.before_copy);
    if (record.cancelled.load(.acquire)) return error.operation_cancelled;
    if (beam.context.mode == .threaded) try beam.yield();
    const input_length = try record.inputLength();
    if (beam.context.mode == .threaded) try beam.yield();

    record.pauseAt(.before_delivery);
    const result = ThreadedSmokeResult{
        .context = executionContext(),
        .owner_matches = pidsEqual(try beam.self(.{}), record.owner),
        .kind = record.kind,
        .generation = record.generation,
        .input_length = input_length,
        .ready_for_delivery = record.markReadyForDelivery(),
    };
    worker_finished = true;
    return result;
}

fn projectionResult(
    status: ProjectionStatus,
    record: *const OperationRecord,
    ready_for_delivery: bool,
) ProjectionResult {
    return .{
        .status = status,
        .kind = record.kind,
        .generation = record.generation,
        .worker_context = executionContext(),
        .native_code = null,
        .byte_offset = null,
        .output_slot = null,
        .result = null,
        .ready_for_delivery = ready_for_delivery,
        .compilation_nanoseconds = 0,
        .traversal_nanoseconds = 0,
        .term_construction_nanoseconds = 0,
        .boundary_count = record.projection_boundaries.load(.acquire),
    };
}

fn elapsedNanoseconds(start: std.Io.Timestamp) u64 {
    const elapsed = start.untilNow(beam.context.io, .awake).nanoseconds;
    if (elapsed <= 0) return 0;
    if (elapsed > std.math.maxInt(u64)) return std.math.maxInt(u64);
    return @intCast(elapsed);
}

fn finishProjectionResult(
    record: *OperationRecord,
    result: ProjectionResult,
) ProjectionResult {
    var finished = result;
    const ready = record.markReadyForDelivery();
    finished.ready_for_delivery = ready;
    finished.boundary_count = record.projection_boundaries.load(.acquire);
    if (!ready) {
        finished.status = .cancelled;
        finished.result = null;
    }
    return finished;
}

fn projectionFailureResult(
    record: *const OperationRecord,
    failure: projection_plan.Failure,
    compilation_nanoseconds: u64,
    traversal_nanoseconds: u64,
) ProjectionResult {
    var result = projectionResult(switch (failure.code) {
        .invalid_json => .invalid_json,
        .invalid_utf8 => .invalid_utf8,
        .unexpected_eof => .unexpected_eof,
        .out_of_memory => .out_of_memory,
        .invalid_argument => .invalid_argument,
        .internal_failure => .internal_failure,
        .missing_field => .missing_field,
        .index_out_of_bounds => .index_out_of_bounds,
        .incorrect_type => .incorrect_type,
        .number_out_of_range => .number_out_of_range,
        .cursor_consumed => .cursor_consumed,
        .cancelled => .cancelled,
    }, record, false);
    result.native_code = failure.native_code;
    result.byte_offset = failure.byte_offset;
    result.output_slot = failure.output_slot;
    result.compilation_nanoseconds = compilation_nanoseconds;
    result.traversal_nanoseconds = traversal_nanoseconds;
    return result;
}

fn projectionOpenFailureResult(
    record: *const OperationRecord,
    status: document_resource.NativeStatus,
    compilation_nanoseconds: u64,
) ProjectionResult {
    var result = projectionResult(.internal_failure, record, false);
    const diagnostics: ?document_resource.Diagnostics = switch (status) {
        .ok => null,
        .invalid_json => |value| blk: {
            result.status = .invalid_json;
            break :blk value;
        },
        .invalid_utf8 => |value| blk: {
            result.status = .invalid_utf8;
            break :blk value;
        },
        .unexpected_eof => |value| blk: {
            result.status = .unexpected_eof;
            break :blk value;
        },
        .out_of_memory => |value| blk: {
            result.status = .out_of_memory;
            break :blk value;
        },
        .invalid_argument => |value| blk: {
            result.status = .invalid_argument;
            break :blk value;
        },
        .internal_failure => |value| blk: {
            result.status = .internal_failure;
            break :blk value;
        },
    };
    if (diagnostics) |value| {
        result.native_code = value.native_code;
        result.byte_offset = value.byte_offset;
    }
    result.compilation_nanoseconds = compilation_nanoseconds;
    return result;
}

const ProjectionConversionError = error{ OutOfMemory, InvalidSlot, Cancelled };

fn scalarTerm(
    env: beam.env,
    scalar: projection_plan.Scalar,
) ProjectionConversionError!beam.term {
    return switch (scalar) {
        .signed_integer => |value| beam.make(value, .{ .env = env }),
        .unsigned_integer => |value| beam.make(value, .{ .env = env }),
        .floating_point => |value| beam.make(value, .{ .env = env }),
        .boolean => |value| beam.make(value, .{ .env = env }),
        .null => beam.make(null, .{ .env = env }),
        .string => |value| beam.make(value, .{ .env = env }),
    };
}

fn constructProjectionMap(
    record: *OperationRecord,
    decoded: *const DecodedProjection,
    results: *const projection_plan.OwnedResults,
) ProjectionConversionError!beam.term {
    const env = record.private_env;
    if (projectionCheckpointFails(record)) return error.OutOfMemory;
    var map = beam.term{ .v = e.enif_make_new_map(env) };

    for (decoded.output_keys, 0..) |key, output_slot| {
        if (output_slot % 64 == 0) {
            projectionBoundary(record, .during_term_construction);
            if (record.cancelled.load(.acquire)) return error.Cancelled;
        }
        if (projectionCheckpointFails(record)) return error.OutOfMemory;

        const scalar = results.scalar(output_slot) orelse return error.InvalidSlot;
        const value = try scalarTerm(env, scalar);
        var next: e.ErlNifTerm = undefined;
        if (e.enif_make_map_put(env, map.v, key.v, value.v, &next) == 0)
            return error.OutOfMemory;
        map = .{ .v = next };
    }

    return map;
}

pub fn threaded_projection_execute(operation: OperationResource) ProjectionResult {
    const record = operation.unpack();
    if (!record.beginRunning()) return projectionResult(.cancelled, record, false);
    var worker_finished = false;
    defer if (!worker_finished) record.abortRunning();

    if (!module_loaded.load(.acquire) or
        record.generation != module_generation.load(.acquire))
    {
        worker_finished = true;
        return finishProjectionResult(
            record,
            projectionResult(.execution_unavailable, record, false),
        );
    }

    projectionBoundary(record, .before_plan_compilation);
    if (record.cancelled.load(.acquire)) {
        worker_finished = true;
        return finishProjectionResult(
            record,
            projectionResult(.cancelled, record, false),
        );
    }

    if (projectionCheckpointFails(record)) {
        worker_finished = true;
        return finishProjectionResult(
            record,
            projectionResult(.out_of_memory, record, false),
        );
    }

    const compilation_started = std.Io.Timestamp.now(beam.context.io, .awake);
    var decoded = decodeProjection(record) catch |err| {
        var failed = projectionResult(switch (err) {
            error.OutOfMemory => .out_of_memory,
            error.InvalidProjection => .invalid_projection,
        }, record, false);
        failed.compilation_nanoseconds = elapsedNanoseconds(compilation_started);
        worker_finished = true;
        return finishProjectionResult(record, failed);
    };
    defer decoded.deinit();

    if (projectionCheckpointFails(record)) {
        var failed = projectionResult(.out_of_memory, record, false);
        failed.compilation_nanoseconds = elapsedNanoseconds(compilation_started);
        worker_finished = true;
        return finishProjectionResult(record, failed);
    }

    var plan = projection_plan.OwnedPlan.init(
        beam.allocator,
        decoded.normalized(),
    ) catch |err| {
        var failed = projectionResult(switch (err) {
            error.OutOfMemory => .out_of_memory,
            error.InvalidProjection => .invalid_projection,
            error.NativeFailure => .internal_failure,
        }, record, false);
        failed.compilation_nanoseconds = elapsedNanoseconds(compilation_started);
        worker_finished = true;
        return finishProjectionResult(record, failed);
    };
    _ = ExecutionAccounting.projection_plan_count.fetchAdd(1, .acq_rel);
    defer {
        plan.deinit();
        const live = ExecutionAccounting.projection_plan_count.fetchSub(1, .acq_rel);
        std.debug.assert(live > 0);
    }
    const compilation_nanoseconds = elapsedNanoseconds(compilation_started);

    var temporary_document = document_resource.DocumentState.empty();
    const binary_source = record.projection_source_kind == .binary;
    var temporary_graph_accounted = false;
    defer if (binary_source) {
        _ = temporary_document.closeAndDestroy();
        if (temporary_graph_accounted) {
            const live = ExecutionAccounting.temporary_document_graph_count.fetchSub(1, .acq_rel);
            std.debug.assert(live > 0);
        }
    };

    var document: ?*c.simd_json_document = null;
    if (binary_source) {
        if (projectionCheckpointFails(record)) {
            var failed = projectionResult(.out_of_memory, record, false);
            failed.compilation_nanoseconds = compilation_nanoseconds;
            worker_finished = true;
            return finishProjectionResult(record, failed);
        }
        const input = record.inputBytes() catch {
            var failed = projectionResult(.invalid_argument, record, false);
            failed.compilation_nanoseconds = compilation_nanoseconds;
            worker_finished = true;
            return finishProjectionResult(record, failed);
        };
        const open_status = temporary_document.openOwnedProjectionCancellable(
            beam.allocator,
            input,
            .{
                .context = record,
                .is_cancelled = operationCancelled,
                .at_boundary = operationBoundary,
            },
        );
        if (open_status != .ok) {
            worker_finished = true;
            return finishProjectionResult(
                record,
                projectionOpenFailureResult(record, open_status, compilation_nanoseconds),
            );
        }
        _ = ExecutionAccounting.temporary_document_graph_count.fetchAdd(1, .acq_rel);
        temporary_graph_accounted = true;
        document = temporary_document.ownedOperationDocument();
    }

    projectionBoundary(record, .before_cursor_access);
    if (record.cancelled.load(.acquire)) {
        worker_finished = true;
        return finishProjectionResult(
            record,
            projectionResult(.cancelled, record, false),
        );
    }

    if (!binary_source) {
        if (!record.commitProjectionReservation()) {
            worker_finished = true;
            return finishProjectionResult(
                record,
                projectionResult(.execution_unavailable, record, false),
            );
        }
        document = record.projectionDocumentHandle();
    }

    const native_document = document orelse {
        var failed = projectionResult(.execution_unavailable, record, false);
        failed.compilation_nanoseconds = compilation_nanoseconds;
        worker_finished = true;
        return finishProjectionResult(record, failed);
    };

    if (projectionCheckpointFails(record)) {
        var failed = projectionResult(.out_of_memory, record, false);
        failed.compilation_nanoseconds = compilation_nanoseconds;
        worker_finished = true;
        return finishProjectionResult(record, failed);
    }

    const traversal_started = std.Io.Timestamp.now(beam.context.io, .awake);
    c.simd_json_nif_projection_set_cancellation(
        native_document,
        record,
        projectionCancellation,
    );
    const execute_outcome = plan.execute(beam.allocator, native_document);
    c.simd_json_nif_projection_clear_cancellation(native_document);
    const traversal_nanoseconds = elapsedNanoseconds(traversal_started);

    switch (execute_outcome) {
        .failure => |failure| {
            worker_finished = true;
            return finishProjectionResult(
                record,
                projectionFailureResult(
                    record,
                    failure,
                    compilation_nanoseconds,
                    traversal_nanoseconds,
                ),
            );
        },
        .success => |owned| {
            var results = owned;
            const slot_count = results.native_slots.len;
            _ = ExecutionAccounting.projection_slot_count.fetchAdd(slot_count, .acq_rel);
            defer {
                results.deinit();
                const live = ExecutionAccounting.projection_slot_count.fetchSub(slot_count, .acq_rel);
                std.debug.assert(live >= slot_count);
            }

            projectionBoundary(record, .before_term_construction);
            if (record.cancelled.load(.acquire)) {
                var failed = projectionResult(.cancelled, record, false);
                failed.compilation_nanoseconds = compilation_nanoseconds;
                failed.traversal_nanoseconds = traversal_nanoseconds;
                worker_finished = true;
                return finishProjectionResult(record, failed);
            }

            const construction_started = std.Io.Timestamp.now(beam.context.io, .awake);
            const private_map = constructProjectionMap(record, &decoded, &results) catch |err| {
                var failed = projectionResult(switch (err) {
                    error.OutOfMemory => .out_of_memory,
                    error.InvalidSlot => .internal_failure,
                    error.Cancelled => .cancelled,
                }, record, false);
                failed.compilation_nanoseconds = compilation_nanoseconds;
                failed.traversal_nanoseconds = traversal_nanoseconds;
                failed.term_construction_nanoseconds = elapsedNanoseconds(construction_started);
                worker_finished = true;
                return finishProjectionResult(record, failed);
            };
            const construction_nanoseconds = elapsedNanoseconds(construction_started);

            if (projectionCheckpointFails(record)) {
                var failed = projectionResult(.out_of_memory, record, false);
                failed.compilation_nanoseconds = compilation_nanoseconds;
                failed.traversal_nanoseconds = traversal_nanoseconds;
                failed.term_construction_nanoseconds = construction_nanoseconds;
                worker_finished = true;
                return finishProjectionResult(record, failed);
            }

            projectionBoundary(record, .before_delivery);
            const stale = !module_loaded.load(.acquire) or
                record.generation != module_generation.load(.acquire) or
                (!binary_source and record.projectionDocumentHandle() == null);
            if (stale or record.cancelled.load(.acquire)) {
                var failed = projectionResult(
                    if (record.cancelled.load(.acquire)) .cancelled else .execution_unavailable,
                    record,
                    false,
                );
                failed.compilation_nanoseconds = compilation_nanoseconds;
                failed.traversal_nanoseconds = traversal_nanoseconds;
                failed.term_construction_nanoseconds = construction_nanoseconds;
                worker_finished = true;
                return finishProjectionResult(record, failed);
            }

            var completed = projectionResult(.ok, record, false);
            record.projection_result_payload.term = private_map;
            completed.result = .{ .__payload = &record.projection_result_payload };
            completed.compilation_nanoseconds = compilation_nanoseconds;
            completed.traversal_nanoseconds = traversal_nanoseconds;
            completed.term_construction_nanoseconds = construction_nanoseconds;
            worker_finished = true;
            return finishProjectionResult(record, completed);
        },
    }
}

pub fn execution_snapshot() ExecutionSnapshot {
    return .{
        .live_operations = ExecutionAccounting.live_operations.load(.acquire),
        .retained_inputs = ExecutionAccounting.retained_inputs.load(.acquire),
        .queued_operations = ExecutionAccounting.queued_operations.load(.acquire),
        .queued_cleanup = ExecutionAccounting.queued_cleanup.load(.acquire),
        .running_operations = ExecutionAccounting.running_operations.load(.acquire),
        .delivered_results = ExecutionAccounting.delivered_results.load(.acquire),
        .discarded_results = ExecutionAccounting.discarded_results.load(.acquire),
        .worker_entries = ExecutionAccounting.worker_entries.load(.acquire),
        .live_documents = ExecutionAccounting.live_documents.load(.acquire),
        .completed_document_cleanup = ExecutionAccounting.completed_document_cleanup.load(.acquire),
        .live_document_controls = ExecutionAccounting.live_document_controls.load(.acquire),
        .dispatcher_queued_cleanup = ExecutionAccounting.dispatcher_queued_cleanup.load(.acquire),
        .dispatcher_active_cleanup = ExecutionAccounting.dispatcher_active_cleanup.load(.acquire),
        .dispatcher_completed_cleanup = ExecutionAccounting.dispatcher_completed_cleanup.load(.acquire),
        .retained_failed_cleanup = ExecutionAccounting.retained_failed_cleanup.load(.acquire),
        .cleanup_submission_failures = ExecutionAccounting.cleanup_submission_failures.load(.acquire),
        .live_projection_operations = ExecutionAccounting.projection_operation_count.load(.acquire),
        .retained_projection_binaries = ExecutionAccounting.retained_projection_binaries.load(.acquire),
        .retained_projection_documents = ExecutionAccounting.retained_projection_documents.load(.acquire),
        .live_projection_environments = ExecutionAccounting.projection_environment_count.load(.acquire),
        .live_projection_plans = ExecutionAccounting.projection_plan_count.load(.acquire),
        .live_projection_slots = ExecutionAccounting.projection_slot_count.load(.acquire),
        .live_projection_temporary_document_graphs = ExecutionAccounting.temporary_document_graph_count.load(.acquire),
        .completed_projection_deliveries = ExecutionAccounting.completed_projection_deliveries.load(.acquire),
        .discarded_projection_deliveries = ExecutionAccounting.discarded_projection_deliveries.load(.acquire),
        .projection_worker_entries = ExecutionAccounting.projection_worker_count.load(.acquire),
        .projection_boundary_entries = ExecutionAccounting.projection_boundary_count.load(.acquire),
        .live_stream_cursor_resources = ExecutionAccounting.live_stream_cursor_resources.load(.acquire),
        .retained_stream_cursor_parents = ExecutionAccounting.retained_stream_cursor_parents.load(.acquire),
        .live_stream_setup_operations = ExecutionAccounting.live_stream_setup_operations.load(.acquire),
        .live_stream_batch_operations = ExecutionAccounting.live_stream_batch_operations.load(.acquire),
        .stream_setup_worker_entries = ExecutionAccounting.stream_setup_worker_entries.load(.acquire),
        .stream_batch_worker_entries = ExecutionAccounting.stream_batch_worker_entries.load(.acquire),
        .stream_deliveries = ExecutionAccounting.stream_deliveries.load(.acquire),
        .stream_discards = ExecutionAccounting.stream_discards.load(.acquire),
    };
}

/// The only Phase 4 document constructor. The operation's private environment
/// retains caller bytes; copying, padding, C parser creation, and parsing all
/// happen in this Zigler worker context.
pub fn threaded_document_open(operation: OperationResource) !DocumentOpenResult {
    const record = operation.unpack();
    if (!record.beginRunning())
        return documentOpenResult(.cancelled, record, null, null);

    var worker_finished = false;
    defer if (!worker_finished) record.abortRunning();

    if (!module_loaded.load(.acquire) or
        record.generation != module_generation.load(.acquire))
    {
        const ready = record.markReadyForDelivery();
        worker_finished = true;
        return documentOpenResult(
            if (ready) .execution_unavailable else .cancelled,
            record,
            null,
            null,
        );
    }

    if (record.cancelled.load(.acquire))
        return documentOpenResult(.cancelled, record, null, null);

    const input = try record.inputBytes();
    if (record.cancelled.load(.acquire))
        return documentOpenResult(.cancelled, record, null, null);

    const control = try createDocumentControl(record.owner, record.generation);
    const document = DocumentResource.create(.{ .control = control }, .{}) catch |err| {
        destroyDocumentControl(control);
        return err;
    };
    var publish_document = false;
    defer if (!publish_document) document.release();

    const native_status = control.native.openOwnedCancellable(
        beam.allocator,
        input,
        .{
            .context = record,
            .is_cancelled = operationCancelled,
            .at_boundary = operationBoundary,
        },
    );

    // Cancellation immediately after the uninterruptible simdjson call and
    // before any result term/resource is published uses worker-owned rollback.
    if (record.cancelled.load(.acquire)) {
        _ = control.native.closeAndDestroy();
        return documentOpenResult(.cancelled, record, null, null);
    }

    if (native_status != .ok) {
        const ready = record.markReadyForDelivery();
        worker_finished = true;
        return if (ready)
            failedDocumentOpen(native_status, record)
        else
            documentOpenResult(.cancelled, record, null, null);
    }

    if (beam.context.mode == .threaded) try beam.yield();
    record.pauseAt(.before_delivery);
    if (record.cancelled.load(.acquire)) {
        _ = control.native.closeAndDestroy();
        return documentOpenResult(.cancelled, record, null, null);
    }

    // Final cancellation/delivery claim occurs before the resource can be
    // encoded by the generated bounded join entry.
    if (!record.markReadyForDelivery()) {
        _ = control.native.closeAndDestroy();
        worker_finished = true;
        return documentOpenResult(.cancelled, record, null, null);
    }

    control.accounted.store(true, .release);
    _ = ExecutionAccounting.live_documents.fetchAdd(1, .acq_rel);
    publish_document = true;
    worker_finished = true;
    return documentOpenResult(.ok, record, null, document);
}

/// Explicit and orphan-result cleanup use a Zigler worker. GC cleanup is
/// attached to the callback-safe dispatcher in Section 4.3.
pub fn threaded_document_cleanup(
    operation: OperationResource,
    document: DocumentResource,
) DocumentCleanupResult {
    const record = operation.unpack();
    if (!record.beginRunning()) {
        return .{
            .status = .execution_unavailable,
            .kind = record.kind,
            .generation = record.generation,
            .worker_context = executionContext(),
        };
    }

    const control = document.__payload.control orelse {
        _ = record.markReadyForDelivery();
        return .{
            .status = .internal_failure,
            .kind = record.kind,
            .generation = record.generation,
            .worker_context = executionContext(),
        };
    };

    const available = module_loaded.load(.acquire) and
        record.generation == module_generation.load(.acquire) and
        control.module_generation == record.generation;

    const cleaned = if (available) completeThreadedDocumentCleanup(control) else false;
    if (cleaned) finishDocumentAccounting(control);
    const ready = record.markReadyForDelivery();

    return .{
        .status = if (!available)
            .execution_unavailable
        else if (cleaned and ready)
            .closed
        else
            .internal_failure,
        .kind = record.kind,
        .generation = record.generation,
        .worker_context = executionContext(),
    };
}

/// Test conformance entry for the complete public-document lifetime. The
/// generated join is threaded, document admission blocks concurrent cleanup,
/// and a hidden NIF-internal C function traverses the existing On-Demand
/// document again. The high-level Elixir helper is compiled only in tests;
/// production imports no failure-injection or native-accounting hooks.
pub fn threaded_document_probe(
    operation: OperationResource,
    document: DocumentResource,
) DocumentProbeResult {
    const record = operation.unpack();
    if (!record.beginRunning()) {
        return .{
            .status = .execution_unavailable,
            .kind = record.kind,
            .generation = record.generation,
            .worker_context = executionContext(),
            .uses_owned_input = false,
            .valid = false,
            .ready_for_delivery = false,
        };
    }

    var worker_finished = false;
    defer if (!worker_finished) record.abortRunning();

    const control = document.__payload.control orelse {
        const result = finishDocumentProbe(record, .internal_failure, false, false);
        worker_finished = true;
        return result;
    };

    // The operation owner is captured synchronously from the probing caller.
    // Check it before reading lifecycle state, matching every document entry.
    if (!pidsEqual(record.owner, control.owner)) {
        const result = finishDocumentProbe(record, .not_owner, false, false);
        worker_finished = true;
        return result;
    }

    if (!module_loaded.load(.acquire) or
        record.generation != module_generation.load(.acquire) or
        control.module_generation != record.generation)
    {
        const result = finishDocumentProbe(record, .execution_unavailable, false, false);
        worker_finished = true;
        return result;
    }

    const admission = control.native.tryAdmit() orelse {
        const result = finishDocumentProbe(record, .closed, false, false);
        worker_finished = true;
        return result;
    };
    defer control.native.releaseAdmission(admission);

    if (comptime @hasDecl(c, "simd_json_nif_document_revalidate")) {
        const uses_owned_input = control.native.cDocumentUsesOwnedInputForProbe();
        const valid = control.native.revalidateForProbe() == .ok;
        const status: DocumentProbeStatus = if (uses_owned_input and valid)
            .ok
        else
            .internal_failure;
        const result = finishDocumentProbe(record, status, uses_owned_input, valid);
        worker_finished = true;
        return result;
    } else {
        const result = finishDocumentProbe(record, .test_unavailable, false, false);
        worker_finished = true;
        return result;
    }
}

pub fn document_lifecycle(document: DocumentResource) document_resource.Lifecycle {
    const control = document.__payload.control orelse return .closed;
    return control.native.lifecycleState();
}

/// Public wrappers use this bounded entry before admitting cleanup. Ownership
/// is deliberately checked before lifecycle so another process cannot learn
/// whether the document has already been closed.
pub fn document_owner_state(document: DocumentResource) !DocumentOwnerState {
    const control = document.__payload.control orelse return .closed;
    if (!pidsEqual(try beam.self(.{}), control.owner)) return .not_owner;

    return switch (control.native.lifecycleState()) {
        .open => .open,
        .closing => .closing,
        .closed => .closed,
    };
}

pub fn document_projection_owner_state(
    document: DocumentResource,
) !DocumentProjectionOwnerState {
    const control = document.__payload.control orelse return .closed;
    if (!pidsEqual(try beam.self(.{}), control.owner)) return .not_owner;

    return switch (control.native.projectionState()) {
        .selecting => .selecting,
        .streaming => .streaming,
        .consumed => .consumed,
        .fresh => switch (control.native.lifecycleState()) {
            .open => .fresh,
            .closing => .closing,
            .closed => .closed,
        },
    };
}

/// Test-only bounded proof for the shared select/stream one-shot state. A
/// rejected setup rolls back; cursor access commits permanently.
pub fn document_stream_reservation_probe(
    document: DocumentResource,
    commit: bool,
) !DocumentProjectionOwnerState {
    const control = document.__payload.control orelse return .closed;
    if (!pidsEqual(try beam.self(.{}), control.owner)) return .not_owner;
    const reservation = switch (control.native.reserveStream()) {
        .reserved => |value| value,
        .cursor_consumed => return .consumed,
        .closed => return .closed,
    };
    if (!commit) {
        _ = control.native.rollbackStream(reservation);
        return .fresh;
    }
    if (!control.native.commitStream(reservation)) {
        _ = control.native.rollbackStream(reservation);
        return .closed;
    }
    control.native.releaseCommittedStream(reservation);
    return .consumed;
}

/// Coordinator-only bounded close reservation. Public ownership has already
/// been checked by the ordinary owner-state entry; this transition prevents
/// later projection reservations while threaded cleanup performs teardown.
pub fn document_prepare_cleanup(document: DocumentResource) DocumentOwnerState {
    const control = document.__payload.control orelse return .closed;

    return switch (control.native.beginClose()) {
        .cleanup_owner, .closing => .closing,
        .closed => .closed,
    };
}

pub fn execution_generation() u64 {
    return module_generation.load(.acquire);
}

pub fn execution_begin_shutdown() u64 {
    const runtime = runtime_ref.load(.acquire) orelse return 0;
    runtime.accepting.store(false, .release);
    const generation = runtime.generation.fetchAdd(1, .acq_rel) + 1;
    module_generation.store(generation, .release);
    return generation;
}

pub fn execution_resume() !u64 {
    const runtime = runtime_ref.load(.acquire) orelse
        return error.execution_unavailable;
    if (!module_loaded.load(.acquire)) return error.execution_unavailable;

    const generation = runtime.generation.fetchAdd(1, .acq_rel) + 1;
    module_generation.store(generation, .release);
    runtime.accepting.store(true, .release);
    return generation;
}

pub fn execution_set_cleanup_rejection(reject: bool) bool {
    const runtime = runtime_ref.load(.acquire) orelse return false;
    runtime.setCleanupRejection(reject);
    return true;
}

pub fn simdjson_version() u32 {
    return simd_json_build_smoke_version();
}

pub fn simdjson_padding() u32 {
    return simd_json_build_smoke_padding();
}

pub fn runtime_implementation() []const u8 {
    return std.mem.span(simd_json_build_smoke_runtime_implementation());
}

pub fn target_triple() []const u8 {
    return "x86_64-linux-gnu";
}

/// A bounded internal fixture: it allocates and releases one empty resource
/// record without copying or parsing caller input.
pub fn document_resource_registration_smoke() !bool {
    if (!module_loaded.load(.acquire)) return false;

    const owner = try beam.self(.{});
    const control = try createDocumentControl(owner, module_generation.load(.acquire));
    const fixture = DocumentResource.create(.{ .control = control }, .{ .released = false }) catch |err| {
        destroyDocumentControl(control);
        return err;
    };
    defer fixture.release();

    return !control.native.hasOwnedNativeState();
}

/// Produces only an opaque reference for a bounded resource-registration test.
/// It is internal to the build module and is not a public document constructor.
pub fn document_resource_fixture() !DocumentResource {
    const owner = try beam.self(.{});
    const control = try createDocumentControl(owner, module_generation.load(.acquire));
    return DocumentResource.create(.{ .control = control }, .{}) catch |err| {
        destroyDocumentControl(control);
        return err;
    };
}

fn streamSetupFixtureResult(
    status: StreamFixtureStatus,
    record: *OperationRecord,
    cursor: ?StreamCursorResource,
    ready: bool,
) StreamSetupFixtureResult {
    return .{
        .status = status,
        .kind = record.kind,
        .generation = record.generation,
        .worker_context = executionContext(),
        .cursor = cursor,
        .ready_for_delivery = ready,
    };
}

pub fn threaded_stream_binary_setup_fixture(
    operation: OperationResource,
    projection: beam.term,
    target: beam.term,
    row_limit: u64,
    byte_limit: u64,
) StreamSetupFixtureResult {
    const record = operation.unpack();
    if (record.kind != .stream_setup or !record.beginRunning())
        return streamSetupFixtureResult(.cancelled, record, null, false);
    var worker_finished = false;
    defer if (!worker_finished) record.abortRunning();

    const input = record.inputBytes() catch {
        worker_finished = true;
        return streamSetupFixtureResult(.invalid_target, record, null, record.markReadyForDelivery());
    };
    var owned_document = document_resource.DocumentState.empty();
    var transferred = false;
    defer if (!transferred) {
        _ = owned_document.closeAndDestroy();
    };
    const opened = owned_document.openOwnedProjectionCancellable(
        beam.allocator,
        input,
        .{ .context = record, .is_cancelled = operationCancelled, .at_boundary = operationBoundary },
    );
    if (opened != .ok) {
        worker_finished = true;
        return streamSetupFixtureResult(.native_failure, record, null, record.markReadyForDelivery());
    }

    var decoded = decodeProjectionTerm(beam.context.env, projection) catch |err| {
        worker_finished = true;
        return streamSetupFixtureResult(if (err == error.OutOfMemory) .out_of_memory else .invalid_target, record, null, record.markReadyForDelivery());
    };
    defer decoded.deinit();
    const target_segments = decodeTargetTerm(beam.context.env, target) catch |err| {
        worker_finished = true;
        return streamSetupFixtureResult(if (err == error.OutOfMemory) .out_of_memory else .invalid_target, record, null, record.markReadyForDelivery());
    };
    defer beam.allocator.free(target_segments);
    var plan = projection_plan.OwnedPlan.init(beam.allocator, decoded.normalized()) catch |err| {
        worker_finished = true;
        return streamSetupFixtureResult(
            if (err == error.OutOfMemory) .out_of_memory else .native_failure,
            record,
            null,
            record.markReadyForDelivery(),
        );
    };
    defer plan.deinit();
    const parent_generation = owned_document.generation.load(.acquire);
    var cursor = stream_cursor.OwnedCursor.init(
        beam.allocator,
        owned_document.ownedOperationDocument(),
        &plan,
        .{ .segments = target_segments },
        .{ .rows = row_limit, .encoded_bytes = byte_limit },
        parent_generation,
    ) catch |err| {
        worker_finished = true;
        return streamSetupFixtureResult(
            switch (err) {
                error.OutOfMemory => .out_of_memory,
                error.InvalidTarget, error.InvalidPlan => .invalid_target,
                error.NativeFailure => .native_failure,
            },
            record,
            null,
            record.markReadyForDelivery(),
        );
    };
    errdefer cursor.deinit();
    const control = beam.allocator.create(StreamCursorControl) catch {
        cursor.deinit();
        worker_finished = true;
        return streamSetupFixtureResult(.out_of_memory, record, null, record.markReadyForDelivery());
    };
    control.* = .{
        .allocator = beam.allocator,
        .native = cursor,
        .parent = null,
        .owner = record.owner,
        .parent_generation = parent_generation,
        .demand_state = .init(@intFromEnum(StreamDemandState.ready)),
        .next_sequence = .init(0),
        .stream_reservation = null,
        .owned_document = owned_document,
    };
    _ = ExecutionAccounting.live_stream_cursor_resources.fetchAdd(1, .acq_rel);
    const resource = StreamCursorResource.create(.{ .control = control }, .{}) catch {
        destroyStreamCursorControl(control);
        worker_finished = true;
        return streamSetupFixtureResult(.out_of_memory, record, null, record.markReadyForDelivery());
    };
    transferred = true;
    worker_finished = true;
    return streamSetupFixtureResult(.ok, record, resource, record.markReadyForDelivery());
}

/// Private Phase 4 integration seam. It builds a real root-array cursor with
/// one `value` field plan and transfers the committed document reservation to
/// the returned child resource.
pub fn threaded_stream_setup_fixture(
    operation: OperationResource,
    document: DocumentResource,
    projection: beam.term,
    target: beam.term,
    row_limit: u64,
    byte_limit: u64,
) StreamSetupFixtureResult {
    const record = operation.unpack();
    if (record.kind != .stream_setup or !record.beginRunning())
        return streamSetupFixtureResult(.cancelled, record, null, false);
    var worker_finished = false;
    defer if (!worker_finished) record.abortRunning();

    const parent_control = document.__payload.control orelse {
        worker_finished = true;
        return streamSetupFixtureResult(.closed, record, null, record.markReadyForDelivery());
    };
    if (!pidsEqual(record.owner, parent_control.owner)) {
        worker_finished = true;
        return streamSetupFixtureResult(.not_owner, record, null, record.markReadyForDelivery());
    }
    if (record.generation != module_generation.load(.acquire) or
        parent_control.module_generation != record.generation)
    {
        worker_finished = true;
        return streamSetupFixtureResult(.execution_unavailable, record, null, record.markReadyForDelivery());
    }

    const reservation = switch (parent_control.native.reserveStream()) {
        .reserved => |value| value,
        .cursor_consumed => {
            worker_finished = true;
            return streamSetupFixtureResult(.cursor_consumed, record, null, record.markReadyForDelivery());
        },
        .closed => {
            worker_finished = true;
            return streamSetupFixtureResult(.closed, record, null, record.markReadyForDelivery());
        },
    };
    var committed = false;
    var transferred = false;
    defer if (!transferred) {
        if (committed)
            parent_control.native.releaseCommittedStream(reservation)
        else
            _ = parent_control.native.rollbackStream(reservation);
    };

    var decoded = decodeProjectionTerm(beam.context.env, projection) catch |err| {
        worker_finished = true;
        return streamSetupFixtureResult(if (err == error.OutOfMemory) .out_of_memory else .invalid_target, record, null, record.markReadyForDelivery());
    };
    defer decoded.deinit();
    const target_segments = decodeTargetTerm(beam.context.env, target) catch |err| {
        worker_finished = true;
        return streamSetupFixtureResult(if (err == error.OutOfMemory) .out_of_memory else .invalid_target, record, null, record.markReadyForDelivery());
    };
    defer beam.allocator.free(target_segments);
    var plan = projection_plan.OwnedPlan.init(beam.allocator, decoded.normalized()) catch |err| {
        worker_finished = true;
        return streamSetupFixtureResult(
            if (err == error.OutOfMemory) .out_of_memory else .native_failure,
            record,
            null,
            record.markReadyForDelivery(),
        );
    };
    defer plan.deinit();

    if (!parent_control.native.commitStream(reservation)) {
        worker_finished = true;
        return streamSetupFixtureResult(.execution_unavailable, record, null, record.markReadyForDelivery());
    }
    committed = true;
    const native_document = parent_control.native.streamDocument(reservation) orelse {
        worker_finished = true;
        return streamSetupFixtureResult(.execution_unavailable, record, null, record.markReadyForDelivery());
    };
    var cursor = stream_cursor.OwnedCursor.init(
        beam.allocator,
        native_document,
        &plan,
        .{ .segments = target_segments },
        .{ .rows = row_limit, .encoded_bytes = byte_limit },
        reservation.generation,
    ) catch |err| {
        worker_finished = true;
        return streamSetupFixtureResult(
            switch (err) {
                error.OutOfMemory => .out_of_memory,
                error.InvalidTarget, error.InvalidPlan => .invalid_target,
                error.NativeFailure => .native_failure,
            },
            record,
            null,
            record.markReadyForDelivery(),
        );
    };
    errdefer cursor.deinit();

    const control = beam.allocator.create(StreamCursorControl) catch {
        cursor.deinit();
        worker_finished = true;
        return streamSetupFixtureResult(.out_of_memory, record, null, record.markReadyForDelivery());
    };
    retainParent(document);
    _ = ExecutionAccounting.retained_stream_cursor_parents.fetchAdd(1, .acq_rel);
    control.* = .{
        .allocator = beam.allocator,
        .native = cursor,
        .parent = document,
        .owner = record.owner,
        .parent_generation = reservation.generation,
        .demand_state = .init(@intFromEnum(StreamDemandState.ready)),
        .next_sequence = .init(0),
        .stream_reservation = reservation,
        .owned_document = document_resource.DocumentState.empty(),
    };
    _ = ExecutionAccounting.live_stream_cursor_resources.fetchAdd(1, .acq_rel);
    const resource = StreamCursorResource.create(.{ .control = control }, .{}) catch {
        destroyStreamCursorControl(control);
        worker_finished = true;
        return streamSetupFixtureResult(.out_of_memory, record, null, record.markReadyForDelivery());
    };
    transferred = true;
    worker_finished = true;
    return streamSetupFixtureResult(.ok, record, resource, record.markReadyForDelivery());
}

pub fn threaded_stream_batch_fixture(
    operation: OperationResource,
    cursor: StreamCursorResource,
    projection: beam.term,
    sequence: u64,
) StreamBatchFixtureResult {
    const record = operation.unpack();
    var result = StreamBatchFixtureResult{
        .status = .cursor_state,
        .kind = record.kind,
        .generation = record.generation,
        .worker_context = executionContext(),
        .sequence = sequence,
        .produced_rows = 0,
        .encoded_bytes = 0,
        .done = false,
        .rows = null,
        .native_code = null,
        .byte_offset = null,
        .output_slot = null,
        .array_index = null,
        .ready_for_delivery = false,
    };
    if (record.kind != .stream_batch or !record.beginRunning()) {
        result.status = .cancelled;
        return result;
    }
    var worker_finished = false;
    defer if (!worker_finished) record.abortRunning();
    const control = cursor.__payload.control orelse {
        worker_finished = true;
        result.status = .closed;
        result.ready_for_delivery = record.markReadyForDelivery();
        return result;
    };
    if (!pidsEqual(record.owner, control.owner)) {
        worker_finished = true;
        result.status = .not_owner;
        result.ready_for_delivery = record.markReadyForDelivery();
        return result;
    }
    if (!stream_cursor_demand_reserve(cursor, sequence)) {
        worker_finished = true;
        result.status = .cursor_state;
        result.ready_for_delivery = record.markReadyForDelivery();
        return result;
    }
    var batch = stream_cursor.OwnedBatch.init(beam.allocator, &control.native) catch |err| {
        _ = stream_cursor_demand_cancel(cursor);
        worker_finished = true;
        result.status = if (err == error.OutOfMemory) .out_of_memory else .native_failure;
        result.ready_for_delivery = record.markReadyForDelivery();
        return result;
    };
    defer batch.deinit();
    if (batch.next(&control.native)) |failure| {
        _ = stream_cursor_demand_cancel(cursor);
        worker_finished = true;
        result.status = switch (failure.code) {
            .invalid_json => .invalid_json,
            .invalid_utf8 => .invalid_utf8,
            .unexpected_eof => .unexpected_eof,
            .out_of_memory => .out_of_memory,
            .missing_field => .missing_field,
            .index_out_of_bounds => .index_out_of_bounds,
            .incorrect_type, .invalid_argument => .incorrect_type,
            .number_out_of_range => .number_out_of_range,
            .cursor_consumed, .cursor_state => .cursor_state,
            .cancelled => .cancelled,
            .batch_too_large => .batch_too_large,
            .internal_failure => .native_failure,
        };
        result.native_code = failure.native_code;
        result.byte_offset = failure.byte_offset;
        result.output_slot = failure.output_slot;
        result.array_index = failure.array_index;
        result.ready_for_delivery = record.markReadyForDelivery();
        return result;
    }
    var decoded = decodeProjectionTerm(beam.context.env, projection) catch {
        _ = stream_cursor_demand_cancel(cursor);
        worker_finished = true;
        result.status = .native_failure;
        result.ready_for_delivery = record.markReadyForDelivery();
        return result;
    };
    defer decoded.deinit();
    var rows = beam.make_empty_list(.{ .env = record.private_env });
    var row_index = batch.produced_rows;
    while (row_index > 0) {
        row_index -= 1;
        const row = batch.rows[row_index];
        const slot_index = std.math.cast(usize, row.slot_offset) orelse {
            _ = stream_cursor_demand_cancel(cursor);
            worker_finished = true;
            result.status = .native_failure;
            result.ready_for_delivery = record.markReadyForDelivery();
            return result;
        };
        var map = beam.term{ .v = e.enif_make_new_map(record.private_env) };
        for (decoded.output_keys, 0..) |source_key, field_index| {
            const scalar = projection_plan.OwnedResults.scalarFromSlot(batch.slots[slot_index + field_index]) orelse {
                _ = stream_cursor_demand_cancel(cursor);
                worker_finished = true;
                result.status = .native_failure;
                result.ready_for_delivery = record.markReadyForDelivery();
                return result;
            };
            const value = scalarTerm(record.private_env, scalar) catch {
                _ = stream_cursor_demand_cancel(cursor);
                worker_finished = true;
                result.status = .out_of_memory;
                result.ready_for_delivery = record.markReadyForDelivery();
                return result;
            };
            const key = beam.copy(record.private_env, source_key);
            var next_map: e.ErlNifTerm = undefined;
            if (e.enif_make_map_put(record.private_env, map.v, key.v, value.v, &next_map) == 0) {
                _ = stream_cursor_demand_cancel(cursor);
                worker_finished = true;
                result.status = .out_of_memory;
                result.ready_for_delivery = record.markReadyForDelivery();
                return result;
            }
            map = .{ .v = next_map };
        }
        if (row.slot_count != decoded.output_keys.len) {
            _ = stream_cursor_demand_cancel(cursor);
            worker_finished = true;
            result.status = .native_failure;
            result.ready_for_delivery = record.markReadyForDelivery();
            return result;
        }
        rows = .{ .v = e.enif_make_list_cell(record.private_env, map.v, rows.v) };
    }
    record.projection_result_payload.term = rows;
    _ = stream_cursor_demand_complete(cursor, sequence, batch.done);
    result.status = .ok;
    result.produced_rows = batch.produced_rows;
    result.encoded_bytes = batch.encoded_bytes;
    result.done = batch.done;
    result.rows = .{ .__payload = &record.projection_result_payload };
    result.ready_for_delivery = record.markReadyForDelivery();
    worker_finished = true;
    return result;
}

/// Registers the private Phase 2 child-resource shape and retains one genuine
/// owner document before any future cursor handle can dereference it. Native
/// target and batch execution remain unavailable through this fixture.
pub fn stream_cursor_resource_fixture(
    document: DocumentResource,
) !StreamCursorResource {
    const parent_control = document.__payload.control orelse
        return error.closed_document;
    const owner = try beam.self(.{});

    // Owner validation deliberately precedes lifecycle and generation detail.
    if (!pidsEqual(owner, parent_control.owner)) return error.not_owner;
    if (parent_control.native.lifecycleState() != .open)
        return error.closed_document;
    if (parent_control.module_generation != module_generation.load(.acquire))
        return error.stale_generation;
    const parent_generation = parent_control.native.generation.load(.acquire);
    if (parent_generation == 0) return error.stale_generation;

    const control = try beam.allocator.create(StreamCursorControl);
    retainParent(document);
    _ = ExecutionAccounting.retained_stream_cursor_parents.fetchAdd(1, .acq_rel);
    control.* = .{
        .allocator = beam.allocator,
        .native = stream_cursor.OwnedCursor.empty(),
        .parent = document,
        .owner = owner,
        .parent_generation = parent_generation,
        .demand_state = .init(@intFromEnum(StreamDemandState.ready)),
        .next_sequence = .init(0),
        .stream_reservation = null,
        .owned_document = document_resource.DocumentState.empty(),
    };
    _ = ExecutionAccounting.live_stream_cursor_resources.fetchAdd(1, .acq_rel);

    return StreamCursorResource.create(.{ .control = control }, .{}) catch |err| {
        destroyStreamCursorControl(control);
        return err;
    };
}

/// Test-only deterministic release for the otherwise GC-owned fixture.
pub fn stream_cursor_resource_close(cursor: StreamCursorResource) bool {
    const control = cursor.__payload.control orelse return true;
    cursor.__payload.control = null;
    destroyStreamCursorControl(control);
    return true;
}

pub fn stream_cursor_demand_reserve(cursor: StreamCursorResource, sequence: u64) bool {
    const control = cursor.__payload.control orelse return false;
    if (control.next_sequence.load(.acquire) != sequence) return false;
    return control.demand_state.cmpxchgStrong(
        @intFromEnum(StreamDemandState.ready),
        @intFromEnum(StreamDemandState.running),
        .acq_rel,
        .acquire,
    ) == null;
}

pub fn stream_cursor_demand_complete(
    cursor: StreamCursorResource,
    sequence: u64,
    done: bool,
) bool {
    const control = cursor.__payload.control orelse return false;
    if (control.next_sequence.load(.acquire) != sequence) return false;
    const next: StreamDemandState = if (done) .done else .ready;
    if (control.demand_state.cmpxchgStrong(
        @intFromEnum(StreamDemandState.running),
        @intFromEnum(next),
        .acq_rel,
        .acquire,
    ) != null) return false;
    _ = control.next_sequence.fetchAdd(1, .acq_rel);
    return true;
}

pub fn stream_cursor_demand_cancel(cursor: StreamCursorResource) bool {
    const control = cursor.__payload.control orelse return true;
    while (true) {
        const current: StreamDemandState = @enumFromInt(control.demand_state.load(.acquire));
        switch (current) {
            .done, .cancelled, .closed => return true,
            .ready, .running => if (control.demand_state.cmpxchgWeak(
                @intFromEnum(current),
                @intFromEnum(StreamDemandState.cancelled),
                .acq_rel,
                .acquire,
            ) == null) return true,
        }
    }
}

pub fn stream_cursor_demand_snapshot(cursor: StreamCursorResource) beam.term {
    const control = cursor.__payload.control orelse
        return beam.make(.{ StreamDemandState.closed, @as(u64, 0) }, .{});
    return beam.make(.{
        @as(StreamDemandState, @enumFromInt(control.demand_state.load(.acquire))),
        control.next_sequence.load(.acquire),
    }, .{});
}

fn destroyStreamCursorControl(control: *StreamCursorControl) void {
    control.demand_state.store(@intFromEnum(StreamDemandState.closed), .release);
    control.native.deinit();
    _ = control.owned_document.closeAndDestroy();
    if (control.parent) |parent| {
        if (control.stream_reservation) |reservation| {
            if (parent.__payload.control) |parent_control|
                parent_control.native.releaseCommittedStream(reservation);
            control.stream_reservation = null;
        }
        control.parent = null;
        releaseParent(parent);
        const retained = ExecutionAccounting.retained_stream_cursor_parents.fetchSub(1, .acq_rel);
        std.debug.assert(retained > 0);
    }
    const live = ExecutionAccounting.live_stream_cursor_resources.fetchSub(1, .acq_rel);
    std.debug.assert(live > 0);
    const allocator = control.allocator;
    allocator.destroy(control);
}

fn retainParent(parent: DocumentResource) void {
    parent.keep();
    document_resource.noteParentRetained();
}

fn releaseParent(parent: DocumentResource) void {
    document_resource.noteParentReleased();
    parent.release();
}

pub fn resource_on_load(
    env: beam.env,
    private_data: ?*?*anyopaque,
    load_info: e.ErlNifTerm,
) callconv(.c) c_int {
    _ = env;
    _ = load_info;

    const slot = private_data orelse return -1;
    const runtime = Runtime.create(beam.allocator, 1) catch return -1;
    slot.* = @ptrCast(runtime);
    runtime_ref.store(runtime, .release);
    module_loaded.store(true, .release);
    module_generation.store(1, .release);
    return 0;
}

pub fn resource_on_upgrade(
    env: beam.env,
    private_data: ?*?*anyopaque,
    old_private_data: ?*?*anyopaque,
    load_info: e.ErlNifTerm,
) callconv(.c) c_int {
    _ = env;
    _ = load_info;

    const slot = private_data orelse return -1;
    const old_runtime: ?*Runtime = if (old_private_data) |old_slot|
        if (old_slot.*) |raw_old_runtime| @ptrCast(@alignCast(raw_old_runtime)) else null
    else
        null;

    const generation = if (old_runtime) |old| blk: {
        old.accepting.store(false, .release);
        break :blk old.generation.load(.acquire) + 1;
    } else module_generation.load(.acquire) + 1;

    const runtime = Runtime.create(beam.allocator, generation) catch return -1;
    slot.* = @ptrCast(runtime);
    runtime_ref.store(runtime, .release);
    module_generation.store(generation, .release);
    module_loaded.store(true, .release);
    return 0;
}

pub fn resource_on_unload(env: beam.env, private_data: ?*anyopaque) callconv(.c) void {
    _ = env;
    module_loaded.store(false, .release);
    _ = module_generation.fetchAdd(1, .acq_rel);

    const runtime: *Runtime = @ptrCast(@alignCast(private_data orelse return));
    runtime.accepting.store(false, .release);
    runtime_ref.store(null, .release);
    _ = native_pool_stop();
    runtime.requestShutdownAndJoin();
}

// covers: simd_json.document_resource.opaque_handle simd_json.document_resource.complete_ownership simd_json.document_resource.lifecycle simd_json.document_resource.reverse_destruction simd_json.document_resource.parent_retention
