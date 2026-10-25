# Independent Claude review and final decision protocol

This is a comparison worksheet, not approval to implement the Codex council's proposal. The user intends to obtain Claude's independent audit, compare both, then make the final release decision.

## Neutral brief for Claude

> Audit the current Sidefolk application for a public v1 release. Use eight explicitly simulated reviewer seats: Maya (nontechnical operations manager, black box first), Leo (senior multi-session developer, user first then source), Priya (product positioning, official competitor research and scope), Jun (Mac UI, light/dark and approved designs), Sam (usability and accessibility), Elena (architecture and reliability), Omar (security and distribution), and Ines (creative identity and animation). Independently inspect what actually exists. Review tasks and failure/recovery behavior, not just screenshots. Follow repository safety rules: no native desktop capture, global configuration edits, product model calls or implementation changes; avoid disturbing the running app or user data. Browser preview sample data is not native integration evidence. Do not read the Codex council findings in `docs/audit-2026-10-25/` or its output artifacts before freezing your initial conclusions; shared STATUS contains only an audit handoff, not adopted decisions. Evaluate a focused everyday companion, a developer-first companion and a broader assistant without assuming the answer. State what should ship, what should be reworked/deferred, whether a rewrite is justified, and the measurable release gates. Cite source locations and distinguish reproduced defects, source inferences, subjective judgments and unverified native behavior. Preserve each seat's dissent. Save your independent report separately. After the initial report is frozen, compare with the Codex audit and write an addendum correcting either review where evidence warrants it. Do not start implementation until the user makes the final joint decision.

## Compare claims before comparing roadmaps

| Question | Codex evidence/conclusion | Claude evidence/conclusion | Resolution and evidence still needed |
|---|---|---|---|
| What is the first audience and the one recurring job? | Fill after Claude freezes its report | Pending | Prefer observed repeated usefulness over persona votes |
| Which failures are reproduced in current source or native app? | Fill after independent review | Pending | Reproduce on the same revision and input |
| Which findings depend on preview fixtures or historical docs? | Fill after independent review | Pending | Reclassify unsupported claims; do not count them as product bugs |
| Are reminders correct, recoverable and dependable under the promised conditions? | Fill after independent review | Pending | Run shared fixed-clock and native matrix |
| Is the notebook destination predictable, and can data be recovered? | Fill after independent review | Pending | Use ambiguous notebooks and isolated damaged files |
| What is each tool's actual monitoring/approval/reopen capability? | Fill after independent review | Pending | One capability matrix with actual CLI/host/version evidence |
| What authority can users grant and revoke, with what guarantees? | Fill after independent review | Pending | Review full raw operation flow and native tool semantics |
| Does keyboard/native accessibility work for core tasks? | Fill after independent review | Pending | Native assistive-technology observation; browser semantics alone insufficient |
| Does existing architecture need replacement, and where specifically? | Fill after independent review | Pending | Tie replacement to a failure that bounded rework cannot reasonably address |
| Is the release artifact installable, maintainable and removable? | Fill after independent review | Pending | Clean signed download/update/uninstall test |
| What will make us continue, switch direction, or stop? | Fill after independent review | Pending | Predeclared beta tasks and real participant counts |

## How to resolve disagreement

1. Keep an evidence register: claim, exact revision, reproduction, observed result, consequence, uncertainty. Two AI reviewers agreeing is not independent customer validation.
2. Fix or remove exposure to confirmed data-loss and authority defects before asking participants to rely on the app. Preference disputes do not outrank those failures.
3. Re-run disputed technical claims with the same source and inputs. Update the reports if one used old code, assumed sample behavior was real, or overstated a trust boundary.
4. For positioning, run a small beta with both plausible audiences and an existing-tool baseline. For visual preferences, show the smallest relevant prototypes in actual tasks. Do not average incompatible product directions into a broad release.
5. Write one final release contract: audience, promise, stable/beta/deferred features, supported platforms/tools/hosts, privacy and authority boundaries, acceptance evidence, remaining limitations and release owner.
6. Have the user approve that contract once. Only then revise the canonical plan and execute the agreed roadmap. Existing approved artwork/logo are preserved unless the final decision explicitly changes them.

## Decisions to record after both reports

- Primary audience and one-sentence v1 promise.
- Reminder recurrence, snooze and missed-occurrence semantics.
- Stable developer capabilities and exact supported tools/hosts.
- Approval model, defaults, authority duration and revocation.
- Advanced capabilities retained in beta versus deferred from distribution.
- Minimum macOS version, CPU architectures and direct-distribution/update strategy.
- Release gates and participant evidence that have actually passed.
- Explicit reasons for every proposed rewrite or deletion.

Until that final decision, these reports remain proposals; they do not supersede `docs/PLAN-V2.md` or authorize a product reset.
