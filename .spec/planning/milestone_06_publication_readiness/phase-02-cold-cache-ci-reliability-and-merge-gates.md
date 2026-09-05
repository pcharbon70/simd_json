# Phase 2 — Cold-Cache CI Reliability and Merge Gates

Back to plan: [README](./README.md)

- [ ] 2 Phase - Make release qualification deterministic on clean GitHub
  runners and prevent red revisions from being treated as accepted.

## 2.1 Section — Reproduce and Specify the Formatter Failure

- [ ] 2.1 Section - Turn the current red CI symptom into a deterministic test.
  - [ ] 2.1.1 Task - Reproduce without developer caches.
    - [ ] 2.1.1.1 Subtask - Run the aggregate qualifier in an isolated build directory after dependency retrieval.
    - [ ] 2.1.1.2 Subtask - Demonstrate that `mix format` cannot resolve `Zig.Formatter` after the preceding clean native steps.
    - [ ] 2.1.1.3 Subtask - Record Mix environment, code paths, cache key, and command order without leaking runner state.
  - [ ] 2.1.2 Task - Add a regression contract.
    - [ ] 2.1.2.1 Subtask - Require formatter-plugin compilation before every strict formatting gate.
    - [ ] 2.1.2.2 Subtask - Require success with both an empty cache and a restored cache.

## 2.2 Section — Deterministic Tool Bootstrap

- [ ] 2.2 Section - Fix qualification ordering and eliminate hidden cache dependencies.
  - [ ] 2.2.1 Task - Bootstrap exact build tools.
    - [ ] 2.2.1.1 Subtask - Compile the pinned Zigler dependency before `mix format --check-formatted`.
    - [ ] 2.2.1.2 Subtask - Pin or record Hex/Rebar versions used by qualification when their behavior affects archives.
    - [ ] 2.2.1.3 Subtask - Verify Zig 0.16.0 from the intended cache/download path before native compilation.
  - [ ] 2.2.2 Task - Preserve deterministic environments.
    - [ ] 2.2.2.1 Subtask - Make MIX_ENV transitions explicit and prevent one phase from invalidating another phase's plugin paths.
    - [ ] 2.2.2.2 Subtask - Ensure temporary sanitizer, symbol, and offline builds cannot mutate canonical build inputs.
    - [ ] 2.2.2.3 Subtask - Fail with a concise diagnostic identifying the missing tool and recovery command.

## 2.3 Section — Workflow Safety and Evidence Retention

- [ ] 2.3 Section - Make CI suitable as a release gate.
  - [ ] 2.3.1 Task - Harden workflow behavior.
    - [ ] 2.3.1.1 Subtask - Add workflow concurrency cancellation for superseded PR revisions without cancelling `main` qualification.
    - [ ] 2.3.1.2 Subtask - Add job and expensive-step timeouts above measured clean-run duration.
    - [ ] 2.3.1.3 Subtask - Keep actions commit-pinned and permissions read-only outside the future protected release job.
  - [ ] 2.3.2 Task - Retain actionable failure evidence.
    - [ ] 2.3.2.1 Subtask - Upload partial evidence on every failure and complete checksummed evidence on success.
    - [ ] 2.3.2.2 Subtask - Add a compact summary naming the failed gate, revision, tree, and evidence path.
    - [ ] 2.3.2.3 Subtask - Prevent generated SpecLed state, build products, and qualification evidence from dirtying source.

## 2.4 Section — Required Checks and Cold-Cache Proof

- [ ] 2.4 Section - Prove the repaired workflow before declaring release readiness.
  - [ ] 2.4.1 Task - Execute the CI matrix.
    - [ ] 2.4.1.1 Subtask - Pass one pull-request run with a deliberately cold dependency/native cache.
    - [ ] 2.4.1.2 Subtask - Pass one repeat run with restored caches and compare qualification identities.
    - [ ] 2.4.1.3 Subtask - Pass the resulting `main` push run at the exact merge commit.
  - [ ] 2.4.2 Task - Establish merge policy.
    - [ ] 2.4.2.1 Subtask - Document the required CI check and prohibit merging release-preparation PRs while it is pending or red.
    - [ ] 2.4.2.2 Subtask - Configure branch protection only with explicit repository-owner authorization.
    - [ ] 2.4.2.3 Subtask - Preserve local qualification as supporting evidence, not a substitute for green GitHub CI.
