# ADR-001: Project Scope and Feature Governance

## Status

Accepted

## Context

PitchforkLauncher is a personal fork of FLauncher, an open-source Android TV launcher whose last upstream commit was approximately 5 years old. The primary motivation for forking was not to build a "better" launcher for a market, but to solve a concrete, personal problem: **eliminating unmaintained, potentially vulnerable dependencies and toolchain components from a device on my home network**.

The project has been developed rapidly (4 days, 4 releases) using Claude (Anthropic's AI) as a coding assistant, with personal design decisions and real-device testing on a Google TV Streamer 4K. The development velocity has been high, and the resulting product already resolves the fundamental irritations that prompted the fork.

The risk now is **scope creep**: the temptation to continue adding features because the tooling and process make it easy, rather than because they serve the original purpose.

## Decision

We will **cap active feature development** and shift focus to **maintaining a robust, upgradeable pipeline**. New features are only accepted if they pass a strict governance filter.

### The Five-Question Gate

Any proposed feature must answer "yes" to at least one of the following, and "no" to none of the disqualifiers:

| Question | Rationale |
|----------|-----------|
| **1. Does this solve an irritation I personally experience?** | The project exists for my use case. Features for hypothetical users are out of scope. |
| **2. Does this improve the pipeline (faster testing, easier upgrades, lower maintenance burden)?** | Infrastructure improvements compound. Runtime features do not. |
| **3. Is the added runtime complexity minimal (no new services, permissions, or UI states)?** | Every new surface is a new trust boundary and potential bug source. |
| **4. Is it fully reversible without data loss?** | If a feature turns out to be wrong, it must be removable without migration headaches. |
| **5. Can I explain it in DRIFT.md without apologising or justifying?** | If the rationale feels defensive, the feature is suspect. |

**Disqualifier:** If a feature cost for a background element that never changes (e.g., per-frame image filtering), it is rejected regardless of other merits. Bake once, display flat.

## Consequences

### Positive

- **Security posture remains the primary driver.** The project stays lean, which reduces attack surface and makes dependency audits tractable.
- **Upgrade velocity is preserved.** A small, stable feature set means `UPGRADE_PLAN.md`-style toolchain bumps remain low-friction.
- **Cognitive load is bounded.** There is no growing backlog of "wouldn't it be cool if..." items competing for attention.
- **The fork stays honest.** It remains a personal tool shared incidentally, not a product aspiring to a user base.

### Negative / Accepted Trade-offs

- **Some users may find the launcher too minimal.** Accepted: this is not their launcher.
- **Features that are "technically elegant" but scope-expanding will be rejected.** Examples: universal client-side wallpaper filters (GPU cost, transforms "pick" into "edit"), additional telemetry alternatives, cloud sync.
- **The "no new features" stance may feel restrictive during periods of high motivation.** Accepted: channel that energy into toolchain hygiene, documentation, or testing.

## Related Documents

- `DRIFT.md` — Detailed history of what changed and why
- `TODO.md` — Open items, known issues, and deliberately rejected ideas
- `UPGRADE_PLAN.md` — Phased toolchain modernisation strategy

## Superseded work

- **`feature/unsplash-reenable`** (branch, never merged) — pre-dates this ADR: an in-progress
  effort to bring the dormant Unsplash wallpaper source back with a user-supplied API key
  (`vendor/unsplash_client` vendoring, Settings UI for the key). Doesn't clear Question 1 (no
  personal irritation it solves — Picsum's key-less random-photo source already covers that need)
  and adds exactly the kind of new UI state/runtime surface Question 3 exists to filter out.
  Closed as wontfix (2026-07-24) rather than merged or continued; the Unsplash source itself was
  removed entirely the same day (PR #23).

## Notes

> "The project isn't published on the Play Store; anyone sideloading it who hits [an edge case] is an accepted edge case, not worth building around."
> — `TODO.md`, Back-button decision, 2026-07-20

