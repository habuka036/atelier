# ATELIER Stage 2 — experiment report

> Fill one copy per run. Record **actual observed values**, not expectations.
> A command exiting `0` is not sufficient evidence of success — judge each
> criterion. Follow the procedure in `README.md`. Keep the independent eval
> suite, the target, and all sources unmodified during the run.

## Run identification

| Field | Value |
|---|---|
| Date / time (UTC) | `__________` |
| Operator | `__________` |
| Target | `jsonl-summary` |
| Goal text (verbatim) | `__________` |
| NAVETTE task id | `__________` |
| NAVETTE run id | `run-__________` |

## Environment (step 1)

| Field | Value |
|---|---|
| `~/.atelier-versions` (recorded) | `__________` |
| `go version` (live) | `__________` (expect `go1.26.0`) |
| `mise --version` | `__________` |
| `kiro-cli --version` | `__________` |
| `bwrap --version` | `__________` |
| `NAVETTE_COMMIT` (devcontainer.json) | `__________` |
| `MILLEFEUILLE_COMMIT` (devcontainer.json) | `__________` |
| `vendor-src/navette` HEAD | `__________` |
| `vendor-src/millefeuille` HEAD | `__________` |
| vendor-src/navette `status --porcelain` | ☐ empty / ☐ NOT empty |
| vendor-src/millefeuille `status --porcelain` | ☐ empty / ☐ NOT empty |
| `sha256sum bin/navette` (BEFORE run) | `__________` |

Version drift vs. `~/.atelier-versions`: ☐ none / ☐ noted below

Notes: `__________`

## Kiro authentication (step 2)

| Field | Value |
|---|---|
| `kiro-cli whoami` (dedicated HOME) | ☐ authenticated / ☐ not |
| Had to run device-flow login this time? | ☐ no / ☐ yes |

## Initial baseline (step 3)

### Target skeleton (3a)

| Check | Result |
|---|---|
| `go build ./...` | ☐ OK / ☐ fail |
| `go vet ./...` | ☐ clean / ☐ issues |
| `go test ./...` | ☐ FAIL (expected) / ☐ unexpectedly passed |

### Independent eval suite (3b)

| Check | Result |
|---|---|
| `go vet ./...` | ☐ clean / ☐ issues |
| `go test ./...` (CANDIDATE_DIR unset) | ☐ ok, all skipped / ☐ other |
| Eval suite hash (BEFORE run) | `__________` |
| Eval vs. skeleton (`CANDIDATE_DIR=.../targets/jsonl-summary`) | ☐ FAIL (expected) / ☐ unexpectedly passed |

## Run with two-stage approval (step 4)

| Field | Value |
|---|---|
| `--max-iter` / `--timeout` used | `__________` |
| Pre-execution approval | ☐ approved / ☐ rejected |
| Result approval | ☐ approved / ☐ rejected |
| Diff reviewed? | ☐ yes / ☐ no |
| Run log reviewed? | ☐ yes / ☐ no |
| `run-kiro.sh` final line | `__________` |
| `run-kiro.sh` exit code | `__________` |

Approval / diff summary (what the agent changed, in your words):

```
__________
```

## Run-ID artifact (step 5)

| Field | Value |
|---|---|
| Final task state (`show`) | `__________` (expect `Succeeded`) |
| `artifacts/<RUN_ID>/` exists | ☐ yes / ☐ no |
| Artifact contains files | ☐ yes / ☐ no |
| Exit↔state consistency (per run-kiro.sh) | ☐ OK / ☐ inconsistent |

## Independent artifact evaluation (step 6)

| Field | Value |
|---|---|
| Command | `scripts/eval-artifact.sh <RUN_ID> jsonl-summary` |
| Result summary line (`pass=.. fail=.. skip=..`) | `__________` |
| Output banner | ☐ `EVAL PASSED` / ☐ `EVAL FAILED` |
| Exit code | `__________` |

> This is the authoritative acceptance result. It is independent of the agent's
> own tests and the agent cannot alter it. A PASS requires `pass>=1`, `fail=0`,
> and `skip=0`; "no tests ran" and "all skipped" are reported as FAILED.

### NAVETTE run state vs. independent evaluation (reconcile explicitly)

| Field | Value |
|---|---|
| NAVETTE final state (step 5) | `__________` (e.g. Succeeded) |
| Independent eval (this step) | ☐ PASSED / ☐ FAILED |
| Do they agree? | ☐ both good / ☐ **DISCREPANCY** |

> NAVETTE "Succeeded" means only that the run completed and the human approved
> the diff. It does **not** imply the independent evaluation passed. If NAVETTE
> says Succeeded but the eval FAILED, the overall Stage-2 result is **FAIL** —
> record the discrepancy and its likely cause (e.g. agent weakened its own
> tests; implementation does not match the contract).

## Immutability / integrity (step 7)

| Check | Result |
|---|---|
| Eval suite hash (AFTER run) | `__________` |
| Eval suite hash == BEFORE (3b)? | ☐ equal / ☐ CHANGED |
| `git status --porcelain targets/jsonl-summary` | ☐ empty (unchanged) / ☐ modified |
| `vendor-src/navette` HEAD == pinned & clean | ☐ yes / ☐ no |
| `vendor-src/millefeuille` HEAD == pinned & clean | ☐ yes / ☐ no |
| `sha256sum bin/navette` (AFTER run) | `__________` |
| `bin/navette` hash == BEFORE (step 1)? | ☐ equal / ☐ CHANGED |
| ATELIER repo: only intended/zero changes | ☐ yes / ☐ no |
| Target secret-free | ☐ confirmed |
| Container posture unchanged (non-root; no `--privileged`/`--cap-add`/Docker socket; only `seccomp=unconfined`) | ☐ confirmed |

## Overall judgement

A run is **successful** only if ALL hold:
- [ ] Target baseline: build OK, skeleton tests FAIL (3a)
- [ ] Eval baseline: green-on-its-own, FAILs skeleton (3b)
- [ ] Reached **Succeeded** with both approvals granted (4)
- [ ] Run-ID artifact exists and is consistent (5)
- [ ] **Independent eval PASSED** (6)
- [ ] Eval suite hash unchanged (7a)
- [ ] Target on disk unchanged (7b)
- [ ] vendor-src pinned & clean; `bin/navette` hash unchanged; ATELIER integrity OK (7c)
- [ ] No secrets, no new permissions (7d)

**Result:** ☐ SUCCESS / ☐ FAIL / ☐ INCONCLUSIVE

Reason / evidence:

```
__________
```

## Known limitations / residual risks observed

- Iteration/time budget sufficient? ☐ yes / ☐ no — notes: `__________`
- Network openness (Kiro cloud) acknowledged: ☐ yes
- `seccomp=unconfined` PoC relaxation acknowledged: ☐ yes
- Process-group reclamation boundary acknowledged: ☐ yes
- Installer version drift observed? ☐ no / ☐ yes — notes: `__________`

## Free-form notes

```
__________
```
