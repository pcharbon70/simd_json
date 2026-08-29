const std = @import("std");
const beam = @import("beam");
const e = @import("erl_nif");
const c = @import("simd_json_abi");
const document_resource = @import("document_resource").Implementation(c);
const projection_plan = @import("projection_plan").Implementation(c);
const root = @import("root");

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

pub const OperationKind = enum(u8) {
    document_open,
    document_cleanup,
    threaded_smoke,
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

pub const OperationBoundary = enum(u8) {
    none,
    before_copy,
    before_parse,
    after_parse,
    before_publication,
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

const OperationRecord = struct {
    allocator: std.mem.Allocator,
    private_env: beam.env,
    input_term: beam.term,
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
                        } else {
                            _ = ExecutionAccounting.discarded_results.fetchAdd(1, .acq_rel);
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

    fn pauseAt(self: *OperationRecord, boundary: OperationBoundary) void {
        if (self.pause_boundary.load(.acquire) != @intFromEnum(boundary)) return;

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
            beam.yield() catch break;
        }
    }
};

const OperationResourceCallbacks = struct {
    pub fn dtor(payload: **OperationRecord) void {
        const operation = payload.*;
        _ = operation.finish(.discarded);
        beam.free_env(operation.private_env);
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

pub const ExecutionSnapshot = struct {
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
};

pub const ThreadedSmokeResult = struct {
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

pub const DocumentProbeStatus = enum(u8) {
    ok,
    closed,
    not_owner,
    execution_unavailable,
    test_unavailable,
    internal_failure,
};

pub const DocumentProbeResult = struct {
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

var module_loaded = std.atomic.Value(bool).init(false);
var module_generation = std.atomic.Value(u64).init(0);

fn executionContext() ExecutionContext {
    return switch (beam.context.mode) {
        .synchronous => .synchronous,
        .threaded => .threaded,
        .dirty, .dirty_yield => .dirty,
        .callback => .callback,
        .yielding, .independent => .unsupported,
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
        .cleanup_owner => {
            while (!control.native.completeCleanup()) std.atomic.spinLoopHint();
        },
        .closing => {
            while (control.native.lifecycleState() != .closed) std.atomic.spinLoopHint();
        },
        .closed => {},
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

/// Bounded admission retains a private-env reference to the binary; it does
/// not copy caller bytes. The worker later performs the sole owned JSON copy.
pub fn operation_admit(
    input: beam.term,
    owner: beam.pid,
    kind: OperationKind,
    generation: u64,
) !OperationResource {
    const runtime = runtime_ref.load(.acquire) orelse
        return error.execution_unavailable;
    if (!module_loaded.load(.acquire) or
        !runtime.accepting.load(.acquire) or
        generation == 0 or
        generation != module_generation.load(.acquire))
        return error.execution_unavailable;

    var inspected: e.ErlNifBinary = undefined;
    if (e.enif_inspect_binary(beam.context.env, input.v, &inspected) == 0)
        return error.invalid_input;

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
    return resource;
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

    try beam.yield();
    const input_length = try record.inputLength();
    try beam.yield();

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

    try beam.yield();
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
    runtime.requestShutdownAndJoin();
}

// covers: simd_json.document_resource.opaque_handle simd_json.document_resource.complete_ownership simd_json.document_resource.lifecycle simd_json.document_resource.reverse_destruction simd_json.document_resource.parent_retention
