# ATELIER Stage 2 — human-run experiment procedure (Workspace B)

This document is the **step-by-step procedure a human runs in Workspace B** (the
DevContainer) to execute the ATELIER Stage 2 experiment end-to-end with the
**real Kiro CLI**.

Stage 2 asks an AI agent (via NAVETTE, inside bubblewrap) to **implement** the
`jsonl-summary` target so that its own tests and an **independent evaluation
suite** pass — then has a human review, approve, and judge the result against
criteria the agent could not weaken.

> **Where this runs.** All steps below run **inside the DevContainer**
> (Workspace B), where this repository is mounted at `/workspace`. The
> preparation (target skeleton, independent evals, scripts, these docs) was
> authored in Workspace A and must be reviewed/pushed there first; **no real
> Kiro run happens in Workspace A**.

---

## 0. Ground rules (read first)

- **Do not edit** anything under `vendor-src/` (pinned NAVETTE/MILLEFEUILLE).
- **Do not edit** the independent eval suite `evals/jsonl-summary/` during the
  run. It is the acceptance criteria and must be fixed/hashed **before** the
  agent runs.
- **Do not edit** the NAVETTE/ATELIER sources to make a run pass.
- The agent may write **only** inside its disposable work copy (enforced by
  bubblewrap). It must not be able to touch `evals/`, `scripts/`, `vendor-src/`,
  `state/`, or the host.
- The experiment target is **secret-free and throwaway**. Never place real
  projects or secrets under `targets/`.
- Record everything in the report (see `report-template.md`). A command exiting
  `0` is **not** sufficient evidence of success — verify each criterion.

---

## 1. Pin / version checks (reproducibility baseline)

Capture the exact versions and pinned SHAs **before** doing anything else. These
go into the report's "Environment" section.

```sh
# Recorded tool provenance baked into the image at build time:
cat ~/.atelier-versions

# Live tool versions (should match the record above; note any drift):
go version
mise --version
kiro-cli --version
bwrap --version

# Pinned upstream SHAs (source of truth is devcontainer.json containerEnv):
grep -E 'NAVETTE_COMMIT|MILLEFEUILLE_COMMIT' .devcontainer/devcontainer.json

# Actually checked-out HEADs in vendor-src must equal the pinned SHAs:
git -C vendor-src/navette      rev-parse HEAD
git -C vendor-src/millefeuille rev-parse HEAD

# vendor-src must be clean (no local modifications). Expect empty output:
git -C vendor-src/navette      status --porcelain
git -C vendor-src/millefeuille status --porcelain
```

Expected:
- `go version` → `go1.26.0` (pinned via `mise.toml`).
- `vendor-src/navette` HEAD == `NAVETTE_COMMIT` from `devcontainer.json`.
- `vendor-src/millefeuille` HEAD == `MILLEFEUILLE_COMMIT` from `devcontainer.json`.
- Both `status --porcelain` outputs **empty**.

If `post-create.sh` has not run yet (fresh container), run it; it re-fetches the
pinned SHAs, verifies HEAD, refuses to overwrite a dirty `vendor-src/`, and
builds `bin/navette`:

```sh
bash .devcontainer/post-create.sh
```

### Record the harness binary hash (tamper check)

The experiment must use the NAVETTE binary built from the pinned source and
nothing else. Record its hash now and again after the run; they must match.

```sh
sha256sum bin/navette
```

---

## 2. Kiro authentication check (dedicated profile, no secrets printed)

The real-agent path uses a **dedicated, persistent** Kiro HOME at
`state/kiro-home`. Host credentials are never copied or mounted.

```sh
# Must report an authenticated profile (no credential VALUES are printed):
HOME=/workspace/state/kiro-home kiro-cli whoami
```

If it is not authenticated, do the one-time interactive device-flow login, then
re-check:

```sh
HOME=/workspace/state/kiro-home kiro-cli login --use-device-flow
HOME=/workspace/state/kiro-home kiro-cli whoami
```

`scripts/run-kiro.sh` also performs this check and exits `7` if the dedicated
profile is not authenticated — it never reads or logs credential values.

---

## 3. Initial build / test baseline (BEFORE the agent runs)

Confirm the starting state of the **target** and the **independent eval suite**.
These are part of the acceptance evidence: the target must build but fail its
tests (skeleton), and the eval suite must be green-on-its-own (skips) and FAIL
against the skeleton.

### 3a. Target skeleton baseline

```sh
cd /workspace/targets/jsonl-summary
go build ./...        # expect: success (skeleton builds)
go vet ./...          # expect: clean
go test ./...         # expect: FAIL (Summarize is not implemented)
cd /workspace
```

Expected: `go build` and `go vet` succeed; `go test` **fails** with
`jsonl-summary: Summarize is not implemented`.

### 3b. Independent eval suite baseline + immutability hash

The eval suite is the acceptance criteria. **Hash it now** and keep the hash in
the report so you can prove it was unchanged during the run.

```sh
# Green on its own (CANDIDATE_DIR unset -> all tests Skip):
cd /workspace/evals/jsonl-summary
go vet ./...          # expect: clean
go test ./...         # expect: ok (all tests skipped)
cd /workspace

# Immutability hash of the eval suite (record this value):
find evals/jsonl-summary -type f -name '*.go' -o -name 'go.mod' -o -name 'README.md' \
  | sort | xargs sha256sum | sha256sum
```

Sanity check that the eval suite correctly **fails** the skeleton (so you know a
PASS later is meaningful). This is a throwaway check that does not modify the
target or the evals:

```sh
# Point the eval suite at the current skeleton; expect FAIL.
( cd /workspace/evals/jsonl-summary && CANDIDATE_DIR=/workspace/targets/jsonl-summary go test ./... ) ; echo "exit=$?"
# exit must be non-zero (skeleton does not satisfy the evals).
```

---

## 4. Run the experiment with two-stage approval (real Kiro, bubblewrap)

Use the wrapper. **arg1 is the GOAL (required); arg2 is the target name**
(a plain directory name directly under `targets/`). For Stage 2 the target is
`jsonl-summary`.

```sh
scripts/run-kiro.sh "Implement Summarize in summary.go so that go test ./... passes. Read README.md for the exact input/output/error contract. Do not add dependencies or network access; edit only this project." jsonl-summary
```

The wrapper:
1. Validates the GOAL and target name **before** invoking NAVETTE (rejects
   empty goal, path separators, `..`, dotfiles, and symlinked targets — all
   fail-closed, non-zero).
2. Verifies the dedicated Kiro profile is authenticated (exit `7` if not).
3. Registers the task and runs it through NAVETTE inside bubblewrap.

Two-stage approval (both are **interactive**; there is no auto-approve for the
real runtime):
- **Pre-execution approval** — approve to launch the agent.
- **Result approval** — NAVETTE shows the **unified diff** and the **run log**.
  Review them, then approve or reject.

On acceptance, artifacts are saved under `artifacts/<run-id>/` and NAVETTE
verifies them against what you approved. **The target on disk is unchanged**
(the agent only ever wrote to its disposable work copy).

Record from this step: the task id, the run id, every approval decision
(pre/result, approve/reject), and the wrapper's final line / exit code.

> If the agent cannot finish within `--max-iter` / `--timeout` (set in
> `run-kiro.sh`), the run may end non-successfully. That is a legitimate result,
> not a script error — record it and, if desired, raise the limits in
> `run-kiro.sh` and re-run. See "Known limitations" below.

---

## 5. Verify the run-ID artifact (durable, consistent)

Confirm the artifact exists and is internally consistent with the approval.

> **Get THIS run's run-id from NAVETTE's own output**, not by guessing. On a
> finalized, successful run NAVETTE prints a line of the form:
> `artifacts saved and verified: <artifacts-base>/<run-id>`
> `scripts/run-kiro.sh` parses exactly that line to identify the current run's
> artifact directory and verifies it is directly under the `--artifacts` base
> and named `run-*`. It does **not** fall back to "most-recent run- dir", so a
> stale artifact from an earlier run can never be mistaken for the current one.
> `show --task <TASK_ID>` is a task-level review view and does **not** print the
> run-id; use the run-kiro output line (or the `verified THIS run's artifacts`
> line that `run-kiro.sh` echoes) for the run-id.

```sh
# List runs and inspect the one you just approved:
bin/navette --db /workspace/state/navette.db list
bin/navette --db /workspace/state/navette.db show --task <TASK_ID>

# The run-ID artifact directory should exist and contain files (RUN_ID is the
# value parsed from NAVETTE's "artifacts saved and verified:" line):
ls -la artifacts/<RUN_ID>/
find artifacts/<RUN_ID> -type f | head
```

Expected for an accepted/succeeded run: `show` reports **Succeeded**, and
`artifacts/<RUN_ID>/` is a plain filtered copy of the project tree (top-level
`go.mod`, `*.go`, …; `.git`, secrets, and `node_modules` are excluded).

`run-kiro.sh` already asserts the exit-code↔state consistency (exit `0` ⇒
Succeeded ⇒ non-empty artifact dir) and fails otherwise.

---

## 6. Evaluate the artifact with the INDEPENDENT eval suite

This is the real acceptance test. **Do not** `cd` into the artifact and run its
own tests — the agent could have weakened them. Instead run the independent eval
suite against a **disposable copy** of the artifact using the dedicated script.
The script treats the artifact as read-only, copies it to a `mktemp -d` dir,
builds the candidate CLI there, drives it black-box, and cleans up.

```sh
scripts/eval-artifact.sh <RUN_ID> jsonl-summary ; echo "exit=$?"
```

Expected for a successful implementation: `== EVAL PASSED ==` and exit `0`.
A non-zero exit means the artifact does **not** satisfy the contract — record it
as a FAIL regardless of what the agent's own tests claimed.

The script does **not** trust a bare `go test` exit code: it inspects per-test
results and treats a run as PASSED only when at least one test actually passed,
**zero tests failed, and zero tests were skipped**. "No tests ran" (eval suite
emptied/renamed) and "all tests skipped" both count as **FAILED** (exit `1`),
so a green-looking exit code can never be mistaken for a satisfied contract.

> **Independent evaluation is separate from NAVETTE's run state.** NAVETTE can
> legitimately report **Succeeded** (you approved a diff you liked, artifacts
> saved and fingerprint-verified) while this independent evaluation **FAILS**
> — e.g. the agent weakened its own tests, or its implementation does not match
> the contract. The two are different questions:
>   - NAVETTE "Succeeded" = "the run completed and the human approved the diff".
>   - `eval-artifact.sh` PASSED = "the saved artifact objectively satisfies the
>     independent acceptance criteria".
> **Report them as distinct outcomes.** A run is only a true Stage-2 success
> when NAVETTE Succeeded **AND** the independent evaluation PASSED. If NAVETTE
> says Succeeded but the eval FAILS, record the overall result as **FAIL** (not
> success) and note the discrepancy explicitly in the report.

The script is **fail-closed**: a malformed run-id, a traversal attempt, a
symlinked artifact or suite, a missing suite, or an artifact with no top-level
`go.mod` all exit non-zero **without** running anything.

---

## 7. Immutability / integrity checks (AFTER the run)

Prove the acceptance criteria and the harness were not altered to force a pass.

### 7a. Independent eval suite unchanged

```sh
# Re-hash the eval suite; must EQUAL the hash recorded in step 3b.
find evals/jsonl-summary -type f -name '*.go' -o -name 'go.mod' -o -name 'README.md' \
  | sort | xargs sha256sum | sha256sum
```

### 7b. Target on disk unchanged by the run

The agent writes only to its disposable work copy, so the committed target must
be byte-identical to its pre-run state.

```sh
# Expect NO output (target working tree clean relative to the repo):
git status --porcelain targets/jsonl-summary
```

(If `targets/jsonl-summary` shows modifications, something wrote back to the
real target — investigate before trusting any result.)

### 7c. NAVETTE / ATELIER source integrity

```sh
# vendor-src still at the pinned SHAs and clean:
git -C vendor-src/navette      rev-parse HEAD
git -C vendor-src/millefeuille rev-parse HEAD
git -C vendor-src/navette      status --porcelain   # expect empty
git -C vendor-src/millefeuille status --porcelain   # expect empty

# NAVETTE binary unchanged (compare to step 1's hash):
sha256sum bin/navette

# ATELIER repo: only intended changes (ideally none from a run). Review:
git -C /workspace status
```

### 7d. No secrets / no new permissions

- Confirm `targets/jsonl-summary` contains no secrets (it is a throwaway target).
- Confirm the container still runs with the Stage-1 posture: non-root,
  no `--privileged`, no `--cap-add`, no Docker socket; only
  `seccomp=unconfined` relaxed (see README "Security model").

---

## 8. Fill in the report

Complete `report-template.md` with every recorded value and the PASS/FAIL
judgement. The run is "successful" only if **all** of the following hold:

- Target baseline: build OK, skeleton tests FAIL (step 3a).
- Eval suite baseline: green-on-its-own, FAILs the skeleton (step 3b).
- Run reached **Succeeded** with both approvals granted (step 4).
- Run-ID artifact exists and is consistent (step 5).
- **Independent eval PASSED** against the artifact (step 6).
- Eval suite hash **unchanged** (step 7a).
- Target on disk **unchanged** (step 7b).
- vendor-src at pinned SHAs & clean; `bin/navette` hash unchanged; ATELIER
  source integrity OK (step 7c).
- No secrets, no new permissions (step 7d).

If any check fails, record it honestly as a FAIL with the evidence; do **not**
edit the evals, target, or sources to force a pass.

---

## Known limitations / residual risks (carry into the report)

- **Iteration/time budget.** `--max-iter` / `--timeout` in `run-kiro.sh` may be
  too small for a full implementation task; a non-successful run can simply mean
  the budget was exhausted. Raise the limits and re-run if appropriate.
- **Network is open** to the Kiro cloud backend; destinations/content are not
  restricted. Only secret-free throwaway targets are used.
- **`seccomp=unconfined`** is a deliberate PoC-only relaxation (needed by
  bubblewrap/bun). It widens the syscall surface; do not carry it to production.
- **Process reclamation is process-group based**; a grandchild that escapes its
  group (setsid/double-fork) is outside the guaranteed boundary
  (`--die-with-parent` is a backstop).
- **External installers** (mise, Kiro CLI) are fetched at image build; recorded
  versions in `~/.atelier-versions` let you detect drift but are not a pin.
