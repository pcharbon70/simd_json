# Phase 1 — Configuration and Admission Contract

Back to plan: [README](./README.md)

- [ ] 1 Phase - Establish one closed, bounded configuration and admission
  vocabulary before native worker or queue implementation begins.

  This phase validates runtime configuration at application startup, freezes
  finite defaults and maxima, reserves the stable saturation error, and exposes
  an honest redacted snapshot. The current Zigler-threaded executor remains in
  place and explicitly pre-production.

## 1.1 Section — Pool Terms and Fixed Configuration

- [x] 1.1 Section - Define the typed normalized representation, exact keys,
  defaults, bounds, and source identity consumed by later native phases.

  - [x] 1.1.1 Task - Freeze the configuration grammar.
    - [x] 1.1.1.1 Subtask - Accept only application keys `:native_workers` and `:native_queue_size` as integers.
    - [x] 1.1.1.2 Subtask - Default workers to half online schedulers rounded up and capped at 32; default queue capacity to 256.
    - [x] 1.1.1.3 Subtask - Enforce exact ranges `1..64` and `1..4096` without coercion or clamping.
    - [x] 1.1.1.4 Subtask - Record whether each normalized value was explicit without retaining raw application terms.
  - [x] 1.1.2 Task - Establish current-truth ownership.
    - [x] 1.1.2.1 Subtask - Add the accepted configuration/admission ADR and planned native-pool spec.
    - [x] 1.1.2.2 Subtask - Add the ordered six-phase Milestone 4 plan and preserve all earlier contracts.

## 1.2 Section — Startup Preflight and Effective Snapshot

- [x] 1.2 Section - Validate configuration once before the coordinator accepts
  operations and retain one immutable effective snapshot.

  - [x] 1.2.1 Task - Implement deterministic preflight.
    - [x] 1.2.1.1 Subtask - Normalize defaults from a bounded scheduler count and validate explicit values completely.
    - [x] 1.2.1.2 Subtask - Fail startup with controlled `ArgumentError` messages before any operation admission.
    - [x] 1.2.1.3 Subtask - Pass the normalized value through the supervision boundary without rereading mutable application configuration.
  - [x] 1.2.2 Task - Expose honest bounded diagnostics.
    - [x] 1.2.2.1 Subtask - Snapshot effective workers, queue capacity, explicit flags, and executor phase only.
    - [x] 1.2.2.2 Subtask - Keep the phase marker `:preproduction_threaded` until real pool routing is qualified.
    - [x] 1.2.2.3 Subtask - Prove no request, allocation, generation, or native worker state changes during pure normalization.

## 1.3 Section — Saturation Error and Redaction

- [x] 1.3 Section - Reserve the public `:busy` reason and stable redacted
  meaning without pretending saturation can occur before the queue exists.

  - [x] 1.3.1 Task - Extend the common error contract.
    - [x] 1.3.1.1 Subtask - Add `:busy` to the closed reason type and safe inspector allowlist.
    - [x] 1.3.1.2 Subtask - Define `:busy` as immediate global-capacity rejection with all unrelated metadata nil.
    - [x] 1.3.1.3 Subtask - Preserve every existing error reason, message, and redaction behavior.
  - [x] 1.3.2 Task - Bound configuration inspection.
    - [x] 1.3.2.1 Subtask - Omit raw environment/application terms, PIDs, references, paths, inputs, and native identities.
    - [x] 1.3.2.2 Subtask - Ensure forged configuration structs cannot render unbounded or sensitive content.

## 1.4 Section — Phase 1 Integration Tests

- [ ] 1.4 Section - Prove defaults, boundaries, invalid startup, immutable
  snapshot behavior, redaction, and unchanged Milestone 1–3 execution.

  - [ ] 1.4.1 Task - Execute the configuration matrix.
    - [ ] 1.4.1.1 Subtask - Test defaults, both valid boundaries, representative interiors, and every invalid term class.
    - [ ] 1.4.1.2 Subtask - Test deterministic normalization and explicit-source flags across scheduler counts.
    - [ ] 1.4.1.3 Subtask - Test supervisor wiring consumes one normalized value and rejects invalid startup before coordinator admission.
  - [ ] 1.4.2 Task - Run safety and regression gates.
    - [ ] 1.4.2.1 Subtask - Test bounded redacted inspection and the stable busy error.
    - [ ] 1.4.2.2 Subtask - Prove the executor marker remains pre-production and public pool controls remain absent.
    - [ ] 1.4.2.3 Subtask - Run focused tests, full regression, formatting, `mix spec.next`, and the reported `mix spec.check` command.
