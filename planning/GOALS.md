# Project Goals (`planning/GOALS.md`)

Last Updated: 2026-11-08
Source State: `STATE_1.md` and the architecture review discussed with the user.

## Intent and constraints

- User approved all three architecture suggestions as work on top of stable 0.2.0, not changes to the running orchestration.
- Prioritize correctness and locality, then downstream leverage. No performance target is assumed.
- Stable 0.2.0 is a prerequisite, not yet verified complete by this goal-selection session.
- Reassess the final 0.2.0 revision before planning implementation; do not duplicate corrections or shared index extraction already delivered there.
- Do not modify `EXECUTION_PLAN_1.md`, `STATE_1.md`, or active worker tasks for this follow-up.
- Preserve established behavior during refactoring. Separate any geographic correction or adaptive-estimator change from behavior-preserving work.
- No new adapter abstraction or proposed interface is approved by this goal graph.
- This file records goals and a future plan-wave handoff; it does not authorize execution or start another orchestration.

## Circled Goal (Active Focus)

- **[G1] Independent behavioral tests establish geodesic neighborhood correctness for fixed and adaptive KDE.**
  - Depends on: G0.
  - Status: selected follow-up focus; execution waits for G0.
  - Why now: an independent correctness oracle distinguishes intended geographic behavior from existing output and gives leverage to neighborhood consolidation, corrections, and adaptive verification. Regression fingerprints alone cannot do this.
  - Exit criteria: small all-points reference calculations exercise high latitude, dateline crossing, index-cell edges, and the three-bandwidth cutoff through the existing calculation interface. Fixed and adaptive comparisons are evaluated; discrepancies are explicitly classified rather than silently accepted or hidden by widened tolerances.
  - Policy constraint: reference comparisons for adaptive evaluation use explicitly stated local bandwidth assumptions; they do not settle or canonize the unresolved adaptive policy in G3. Full adaptive-policy acceptance belongs to G4.
  - First action: after G0 completes, inspect the recorded final revision, final diff, and tests against the architecture review; identify which correctness cases remain uncovered.
  - Files in scope for planning: `inst/tinytest/test_geodensity.R`, focused test fixtures/helpers as justified, and read-only tracing of `R/geodensity.R` and `src/rust/src/lib.rs`. Exact edits and reference-calculation placement remain for plan-wave.
  - Critical path:
    1. Confirm G0 revision and verification evidence.
    2. Reconcile completed changes with the review.
    3. Establish an independently calculated reference and justified numerical tolerance.
    4. Exercise fixed KDE neighborhood behavior.
    5. Exercise adaptive neighborhood behavior without deciding scaling policy implicitly.
    6. Record discrepancies and route behavior changes separately from refactoring.
  - Handoff: plan-wave, after G0; draft a bounded execution plan for user approval before implementation.

## Sequenced Goals (Dependency DAG)

- **[G0] Stable 0.2.0 is complete, with its final revision and verification recorded.**
  - Depends on: the existing orchestration in `EXECUTION_PLAN_1.md`.
  - Owner: existing orchestration; this goal graph does not take over its work.
  - Exit criteria: its orchestrator records completion and release-check results, with unresolved warnings or findings explicitly identified and dispositioned under the approved acceptance criteria.

- **[G2] One deep neighborhood module owns candidate discovery, wrapping, cutoff, and accumulation for both KDE paths.**
  - Depends on: G1.
  - Exit criteria: fixed and adaptive KDE share ownership of these invariants and pass the independent neighborhood tests. Behavior-preserving consolidation is verified separately from any intentional correctness correction.
  - Scope: `src/rust/src/lib.rs` and relevant tests.
  - Locality: geographic knowledge and corrections concentrate in one implementation behind the existing seam.
  - Existing-work constraint: build on the shared index extraction delivered by G0 rather than repeating it.

- **[G3] Adaptive bandwidth policy is explicitly decided, including reference-density and template dependence.**
  - Depends on: G0.
  - Exit criteria: the user resolves the documented-versus-implemented scaling discrepancy and establishes expected behavior at zero and maximum pilot density, under template expansion, and under uniform duplication of observations.
  - Unresolved: preserve the implemented policy and correct its documentation, or deliberately change the estimator to an agreed policy. Neither path is selected here.
  - Scope: adaptive policy discussion grounded in `R/geodensity.R`, `src/rust/src/lib.rs`, and adaptive documentation.

- **[G4] Adaptive implementation, documentation, and behavioral tests agree with the established policy.**
  - Depends on: G3, G2.
  - Exit criteria: tests establish dense/sparse smoothing, zero-density behavior, intended template dependence, and equality of default versus explicit 10% minimum bandwidth. Documentation and implementation describe the same rule.
  - Scope: adaptive orchestration, relevant tests, and source documentation with generated documentation updated through existing tooling.
  - Locality: pilot density, reference-density selection, scaling, and final evaluation have coherent ownership inside the adaptive module.
  - Constraint: any estimator change is explicit and separate from behavior-preserving consolidation.

- **[G5] Behavioral tests establish coordinate pairing, raster placement, template preservation, and supported input equivalence.**
  - Depends on: G0.
  - Exit criteria: tests compare equivalent `sf` and `SpatVector` results when the optional dependency is available; establish asymmetric cell placement, unchanged input templates, adaptive extent/resolution/CRS preservation, and consistent geographic-input rejection.
  - Scope: existing exported R interface and relevant tests.

- **[G6] Geographic preparation and raster assembly have shared ownership without changing established behavior.**
  - Depends on: G5.
  - Exit criteria: the three R calculations share point-preparation responsibility; fixed and adaptive density share raster-preparation/assembly responsibility; G5 tests pass and validation order is preserved unless a change is explicitly approved.
  - Scope: `R/geodensity.R` and relevant tests; retain generated R–Rust adapters and calculation-specific bandwidth rules.
  - Leverage: three callers share point preparation; two share raster coordination without expanding the exported interface.

Dependency edges (an arrow means prerequisite → downstream goal):

```text
G0 -> [G1, G3, G5]
G1 -> [G2]
G2 -> [G4]
G3 -> [G4]
G5 -> [G6]
```

G3 and G5 are independent follow-up branches after G0; this graph does not request parallel execution. G1 remains the selected focus because it unlocks safe neighborhood work.

## Independent Backlog

None added. All three architecture suggestions are represented in the sequenced goals.

## Deferred

- Execution planning and implementation of G1–G6.
  - Trigger: G0 completion is verified against the final revision. Plan-wave then reassesses remaining scope and seeks approval for its execution plan.

## Blocked / Pruned

- Duplicate proposals for Haversine consolidation or shared index extraction.
  - Status: Pruned from the follow-up graph.
  - Reason: already assigned to the running 0.2.0 orchestration; inspect its delivered result rather than schedule the same work twice.
- Choosing adaptive-estimator semantics without user agreement.
  - Status: Blocked pending G3.
  - Reason: the review establishes a documentation/implementation mismatch, not which scientific policy should be authoritative.
