# Phase 3 — Single-Pass Traversal and Typed Results

Back to plan: [README](./README.md)

- [ ] 3 Phase - Execute the native plan in one complete document-order walk
  and produce transactional typed scalar slots without constructing BEAM terms.

  This phase implements the core On-Demand query engine below the NIF boundary.
  Objects and arrays advance once, common prefixes and duplicate paths share
  work, unselected content is consumed without materialization, and malformed
  JSON anywhere fails the operation. C and Zig harnesses inspect native slots;
  threaded BEAM result conversion arrives in Phase 4.

  Contract focus:

  - `simd_json.projection_engine.declaration_order_independence`
  - `simd_json.projection_engine.single_guided_traversal`
  - `simd_json.projection_engine.complete_source_validation`
  - `simd_json.projection_engine.duplicate_json_key_policy`
  - `simd_json.projection_engine.scalar_only_materialization`
  - `simd_json.projection_engine.typed_result_slots`
  - `simd_json.projection_engine.transactional_conversion`
  - `simd_json.projection_engine.shared_prefix_and_order`
  - `simd_json.projection_engine.object_array_walk`
  - `simd_json.projection_engine.invalid_unselected_content`
  - `simd_json.projection_engine.duplicate_object_keys`
  - `simd_json.projection_engine.transactional_slot_failure`

## 3.1 Section — Guided Object Traversal

- [x] 3.1 Section - Walk requested and unrequested object fields once in source
  order while matching all relevant projection-tree edges.

  This section makes JSON field order independent from caller declaration order
  and defines repeated-key behavior at every depth.

  - [x] 3.1.1 Task - Match object edges without cursor rewind.

    The task uses the plan's object-child index to dispatch fields encountered
    by the On-Demand iterator and recurses only into matching projection nodes.

    - [x] 3.1.1.1 Subtask - Iterate every source object field exactly once and match its decoded key bytes against the current plan node without converting that key to an atom.
    - [x] 3.1.1.2 Subtask - Descend through one shared child node for every requested prefix and fan a completed terminal value into all terminal output slots.
    - [x] 3.1.1.3 Subtask - Skip and structurally consume unrequested field values through simdjson without allocating plan nodes, result slots, strings, maps, or lists for them.
    - [x] 3.1.1.4 Subtask - Track requested children not satisfied by object end and report the deterministic first missing slot according to caller slot order, not hash or source enumeration order.

  - [x] 3.1.2 Task - Enforce the duplicate JSON key policy.

    The task makes repeated requested keys deterministic while still validating
    the complete object.

    - [x] 3.1.2.1 Subtask - Mark a requested object edge satisfied after its first occurrence in document order and prevent later occurrences from overwriting its terminal or descendant slots.
    - [x] 3.1.2.2 Subtask - Continue consuming and structurally validating every later duplicate value even after its requested slots are complete.
    - [x] 3.1.2.3 Subtask - Apply the same first-occurrence rule independently in nested objects and document it in native conformance fixtures.

## 3.2 Section — Array Traversal and Scalar Extraction

- [x] 3.2 Section - Advance arrays monotonically to requested indexes and fill
  correctly typed scalar result slots.

  This section completes mixed object/array paths, exact scalar typing, missing
  index behavior, and scalar-only output bounds.

  - [x] 3.2.1 Task - Traverse requested array indexes in source order.

    The task consumes each array element at most once regardless of projection
    declaration order or how many paths share an indexed prefix.

    - [x] 3.2.1.1 Subtask - Use ascending plan edges to advance the On-Demand array cursor once, sharing a selected element among all descendant paths at the same index.
    - [x] 3.2.1.2 Subtask - Structurally skip every unrequested lower, intervening, and trailing element without BEAM materialization.
    - [x] 3.2.1.3 Subtask - Return `index_out_of_bounds` for the deterministic first unsatisfied requested index when array end is reached.
    - [x] 3.2.1.4 Subtask - Return `incorrect_type` when an object edge targets a non-object, an index edge targets a non-array, or a terminal resolves to an object or array.

  - [x] 3.2.2 Task - Preserve every supported scalar type.

    The task translates simdjson On-Demand values into native tagged slots
    without premature BEAM allocation or numeric coercion.

    - [x] 3.2.2.1 Subtask - Store signed and unsigned 64-bit integers in distinct slots and defer exact BEAM-integer construction to Zig.
    - [x] 3.2.2.2 Subtask - Store valid finite floating-point values without converting integer syntax to float and map unsupported numeric range or representation to `number_out_of_range`.
    - [x] 3.2.2.3 Subtask - Store booleans and null as closed scalar tags requiring no source-backed allocation.
    - [x] 3.2.2.4 Subtask - Store string pointer and logical length as a borrowed view valid only through the retained document lifetime; never append padding or a terminator to logical value length.

## 3.3 Section — Complete Validation, Transactionality, and Diagnostics

- [ ] 3.3 Section - Validate the whole logical source and make every native
  result all-or-nothing across errors, cancellation, and allocation failure.

  This section distinguishes skipping materialization from skipping parser
  validation and prepares bounded internal evidence for Phase 4 conversion and
  Phase 6 qualification.

  - [ ] 3.3.1 Task - Consume the complete JSON source.

    The task continues traversal after requested slots fill so a successful
    result always implies valid complete JSON.

    - [ ] 3.3.1.1 Subtask - Traverse or structurally skip every unselected object, array, and scalar branch to the end of the top-level value.
    - [ ] 3.3.1.2 Subtask - Reject extra trailing non-whitespace data and malformed syntax before, inside, after, and structurally nested outside every selected path.
    - [ ] 3.3.1.3 Subtask - Preserve simdjson logical byte offsets and stable parse categories without ever reporting padding positions or source excerpts.
    - [ ] 3.3.1.4 Subtask - Respect the pinned parser depth and numeric bounds with stable errors rather than native recursion overflow, assertion, or exception leakage.

  - [ ] 3.3.2 Task - Make slot production transactional and cancellable.

    The task ensures native callers see either a complete validated slot set or
    one failure with all intermediate state reclaimed.

    - [ ] 3.3.2.1 Subtask - Initialize every result slot to an explicit unset state and publish success only when all terminals are filled and the complete document has validated.
    - [ ] 3.3.2.2 Subtask - On missing, index, type, range, parse, allocation, internal, or cancellation failure, clear borrowed views and release auxiliary traversal state before returning one stable status.
    - [ ] 3.3.2.3 Subtask - Check a testable cancellation flag between bounded object fields, array elements, scalar extractions, and structural skip units without freeing state inside an uninterruptible simdjson call.
    - [ ] 3.3.2.4 Subtask - Record bounded redacted plan-compilation and traversal durations plus visited-node, shared-prefix, and filled-slot counts in test/diagnostic builds only.

  - [ ] 3.3.3 Task - Freeze the single-execution boundary.

    The task proves the complete plan is evaluated by one ABI execution call and
    prevents helper design from degrading into per-path execution.

    - [ ] 3.3.3.1 Subtask - Implement the ABI v2 projection execution function over one document, one plan, and one complete caller-owned slot array.
    - [ ] 3.3.3.2 Subtask - Count execution entries and assert one call handles all paths, prefixes, array indexes, and scalar slots in a projection.
    - [ ] 3.3.3.3 Subtask - Keep slot inspection inside C/Zig native harnesses; expose no NIF or Elixir function per slot, field, segment, cursor, or native pointer.

## 3.4 Section — Phase 3 Integration Tests

- [ ] 3.4 Section - Prove one-pass traversal, full validation, typed slots,
  duplicate policy, cancellation, and cleanup through ordinary and sanitizer
  native harnesses.

  This section closes the complete native engine before it can operate on a
  public or threaded BEAM resource.

  - [ ] 3.4.1 Task - Run the functional traversal corpus.

    The task covers path topology, source-order variation, Unicode and escapes,
    scalar types, missing values, and very large skipped content.

    - [ ] 3.4.1.1 Subtask - Execute shared and disjoint object paths, identical paths, nested arrays, low/high indexes, declaration order opposite source order, and all scalar terminals.
    - [ ] 3.4.1.2 Subtask - Exercise empty and Unicode keys, escaped keys and values, duplicate keys at multiple depths, empty containers, deep valid nesting, and large unselected subtrees.
    - [ ] 3.4.1.3 Subtask - Verify stable missing-field, index, container-type, scalar-leaf, numeric-range, invalid UTF-8, unexpected EOF, invalid JSON, and logical-offset behavior.
    - [ ] 3.4.1.4 Subtask - Assert shared-prefix/terminal counters equal the expected topology and one execution entry handles every fixture.

  - [ ] 3.4.2 Task - Run full-validation and failure-cleanup gates.

    The task attacks every point where early slots could otherwise escape or
    borrowed input could outlive its document.

    - [ ] 3.4.2.1 Subtask - Place malformed syntax before, inside, and after selected paths and in large unselected branches; require failure and no published slots for every case.
    - [ ] 3.4.2.2 Subtask - Inject cancellation and allocation failure after every plan, traversal, skip, and slot step and require deterministic status plus baseline recovery.
    - [ ] 3.4.2.3 Subtask - Run ordinary, AddressSanitizer, and UndefinedBehaviorSanitizer projection engine suites with guard-page and borrowed-string lifetime fixtures.
    - [ ] 3.4.2.4 Subtask - Run the ABI v2, Zig resource, and all Milestone 1 regression suites, `mix spec.next`, and the reported `mix spec.check --base ...` command before marking Phase 3 complete.
