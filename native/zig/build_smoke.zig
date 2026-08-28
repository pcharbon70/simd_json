const std = @import("std");
const beam = @import("beam");
const e = @import("erl_nif");
const c = @import("simd_json_abi");
const document_resource = @import("document_resource").Implementation(c);
const root = @import("root");

extern fn simd_json_build_smoke_version() callconv(.c) u32;
extern fn simd_json_build_smoke_padding() callconv(.c) u32;
extern fn simd_json_build_smoke_runtime_implementation() callconv(.c) [*:0]const u8;

const DocumentResourcePayload = struct {
    native: document_resource.DocumentState,
    owner: beam.pid,
};

const DocumentResourceCallbacks = struct {
    pub fn dtor(payload: *DocumentResourcePayload) void {
        // Phase 3 deliberately publishes no resource containing parse state.
        // The callback therefore performs no input-dependent work or native
        // destruction. Phase 4 will attach the off-scheduler cleanup queue.
        _ = payload.native.detachForDeferredCleanup();
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
};

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
};

pub const ThreadedSmokeResult = struct {
    context: ExecutionContext,
    owner_matches: bool,
    kind: OperationKind,
    generation: u64,
    input_length: usize,
    ready_for_delivery: bool,
};

var module_loaded = std.atomic.Value(bool).init(false);

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

/// Bounded admission retains a private-env reference to the binary; it does
/// not copy caller bytes. The worker later performs the sole owned JSON copy.
pub fn operation_admit(
    input: beam.term,
    owner: beam.pid,
    kind: OperationKind,
    generation: u64,
) !OperationResource {
    if (!module_loaded.load(.acquire) or generation == 0)
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

pub fn admission_context() ExecutionContext {
    return executionContext();
}

pub fn operation_owner_matches(operation: OperationResource) !bool {
    return pidsEqual(try beam.self(.{}), operation.unpack().owner);
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
    };
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
    const fixture = try DocumentResource.create(.{
        .native = document_resource.DocumentState.empty(),
        .owner = owner,
    }, .{ .released = false });
    defer fixture.release();

    return !fixture.__payload.native.hasOwnedNativeState();
}

/// Produces only an opaque reference for a bounded resource-registration test.
/// It is internal to the build module and is not a public document constructor.
pub fn document_resource_fixture() !DocumentResource {
    const owner = try beam.self(.{});
    return DocumentResource.create(.{
        .native = document_resource.DocumentState.empty(),
        .owner = owner,
    }, .{});
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
    _ = private_data;
    _ = load_info;
    module_loaded.store(true, .release);
    return 0;
}

pub fn resource_on_upgrade(
    env: beam.env,
    private_data: ?*?*anyopaque,
    old_private_data: ?*?*anyopaque,
    load_info: e.ErlNifTerm,
) callconv(.c) c_int {
    _ = env;
    _ = private_data;
    _ = old_private_data;
    _ = load_info;
    module_loaded.store(true, .release);
    return 0;
}

pub fn resource_on_unload(env: beam.env, private_data: ?*anyopaque) callconv(.c) void {
    _ = env;
    _ = private_data;
    module_loaded.store(false, .release);
}

// covers: simd_json.document_resource.opaque_handle simd_json.document_resource.complete_ownership simd_json.document_resource.lifecycle simd_json.document_resource.reverse_destruction simd_json.document_resource.parent_retention
