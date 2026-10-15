#!/usr/bin/env bash
# eval-artifact.sh — evaluate a NAVETTE run's artifacts against the INDEPENDENT
# evaluation suite, safely and fail-closed.
#
# NAVETTE stores each run's artifacts as a plain filtered file tree under
#   artifacts/<run-id>/
# i.e. artifacts/<run-id>/ IS the project (top-level go.mod, *.go, ...). This
# script does NOT assume it can `cd` there and run tests in place. Instead it:
#   1. resolves the run-id's artifact directory (explicit run-id required),
#   2. copies it to a fresh, disposable temp directory (the artifact itself is
#      treated as read-only; we never write into it),
#   3. runs the independent eval suite (evals/<suite>) against the copy via
#      CANDIDATE_DIR,
#   4. removes the disposable copy.
#
# It NEVER writes outside the disposable copy, NEVER modifies the target under
# targets/, and NEVER applies the artifact's diff anywhere. Any ambiguity or
# unexpected path causes a non-zero exit (fail-closed).
#
# Usage: scripts/eval-artifact.sh <run-id> [eval-suite]
#   run-id       e.g. run-653a6d0ccdd6  (directory name under artifacts/)
#   eval-suite   subdirectory of evals/ to use (default: jsonl-summary)
set -euo pipefail

ROOT="/workspace"
ARTIFACTS="${ROOT}/artifacts"
EVALS_DIR="${ROOT}/evals"

RUN_ID="${1:-}"
SUITE="${2:-jsonl-summary}"

fail() { echo "EVAL FAIL: $*" >&2; exit 1; }

[ -n "${RUN_ID}" ] || fail "run-id (arg1) is required. Usage: eval-artifact.sh <run-id> [eval-suite]"

# ---- validate run-id (fail-closed) -------------------------------------------
# Allowlist: run- followed by hex (matches NAVETTE's newID("run")). No path
# separators, no traversal.
case "${RUN_ID}" in
  run-*) : ;;
  *) fail "run-id '${RUN_ID}' must look like 'run-<hex>'";;
esac
case "${RUN_ID}" in
  *[!a-zA-Z0-9._-]*|*..*) fail "run-id '${RUN_ID}' contains invalid characters";;
esac

# ---- validate eval suite name (fail-closed) ----------------------------------
case "${SUITE}" in
  *[!A-Za-z0-9._-]*|""|.|..|*..*) fail "invalid eval suite name '${SUITE}'";;
esac
SUITE_DIR="${EVALS_DIR}/${SUITE}"
if [ -L "${SUITE_DIR}" ]; then fail "eval suite '${SUITE}' is a symlink; refusing"; fi
[ -d "${SUITE_DIR}" ] || fail "eval suite not found: ${SUITE_DIR}"

# ---- resolve the artifact directory, confirm it is under artifacts/ ----------
ART_DIR="${ARTIFACTS}/${RUN_ID}"
if [ -L "${ART_DIR}" ]; then fail "artifact '${RUN_ID}' is a symlink; refusing"; fi
[ -d "${ART_DIR}" ] || fail "artifact directory not found: ${ART_DIR}"

ARTIFACTS_REAL="$(cd "${ARTIFACTS}" 2>/dev/null && pwd -P)" || fail "cannot resolve ${ARTIFACTS}"
ART_PARENT_REAL="$(cd "${ART_DIR}/.." 2>/dev/null && pwd -P)" || fail "cannot resolve artifact parent"
[ "${ART_PARENT_REAL}" = "${ARTIFACTS_REAL}" ] \
  || fail "artifact '${RUN_ID}' does not resolve directly under ${ARTIFACTS}"

# The artifact must look like a Go project (defence against evaluating junk).
[ -f "${ART_DIR}/go.mod" ] || fail "artifact ${RUN_ID} has no go.mod at its root; cannot evaluate as a Go project"

echo "== eval-artifact =="
echo "  run-id:     ${RUN_ID}"
echo "  artifact:   ${ART_DIR}"
echo "  eval suite: ${SUITE_DIR}"

# ---- copy artifact to a disposable dir (artifact treated read-only) ----------
CANDIDATE="$(mktemp -d "${TMPDIR:-/tmp}/atelier-candidate-${RUN_ID}-XXXXXX")" \
  || fail "could not create disposable candidate dir"
cleanup() { rm -rf "${CANDIDATE}"; }
trap cleanup EXIT

# Copy contents (regular files/dirs). cp -a preserves structure; we copy into
# the disposable dir only. The source artifact is never written to.
cp -a "${ART_DIR}/." "${CANDIDATE}/" || fail "failed to copy artifact to disposable dir"

echo "  candidate:  ${CANDIDATE} (disposable copy; removed on exit)"

# ---- run the independent eval suite against the disposable copy --------------
# The eval suite builds CANDIDATE_DIR's CLI and drives it black-box. It must not
# depend on the candidate's internal API. We run it from the eval module so the
# agent's artifact cannot alter the acceptance criteria.
#
# We use `go test -json` and inspect PER-TEST result events, because a bare
# `go test` exit code is NOT sufficient evidence of a real pass:
#   - "no test files" / zero tests  -> go exits 0 (nothing was actually checked);
#   - all tests skipped             -> go exits 0 (criteria not exercised).
# Both must be treated as FAILURE here. We therefore require, for a PASS:
#   go test exit == 0  AND  at least one test with Action=pass
#   AND  zero tests with Action=fail  AND  zero tests with Action=skip.
# This fails closed if the eval suite is ever renamed, emptied, or skipped.
echo "-- running independent eval suite --"
JSON_LOG="${CANDIDATE}/.eval.jsonl"   # inside the disposable dir; removed on exit
set +e
( cd "${SUITE_DIR}" && CANDIDATE_DIR="${CANDIDATE}" go test -json ./... ) >"${JSON_LOG}" 2>&1
EVAL_RC=$?
set -e

# Human-readable echo of the raw test output (reconstructed from -json "output"
# events) so reviewers still see build errors / failure messages.
if command -v python3 >/dev/null 2>&1; then
  python3 - "${JSON_LOG}" <<'PY' || true
import json, sys
with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except ValueError:
            print(line)
            continue
        if ev.get("Action") == "output":
            sys.stdout.write(ev.get("Output", ""))
PY
else
  # Fallback: show the raw json log (still informative).
  cat "${JSON_LOG}"
fi

# Count per-test result events. A test-level event has BOTH "Test" and the
# relevant "Action". Package-level pass/skip events have no "Test" key and are
# intentionally ignored by requiring the "Test" field to be present.
count_test_events() {
  # $1 = action (pass|fail|skip)
  grep -E '"Test":"[^"]+"' "${JSON_LOG}" 2>/dev/null \
    | grep -c "\"Action\":\"$1\"" || true
}
PASS_N="$(count_test_events pass)"
FAIL_N="$(count_test_events fail)"
SKIP_N="$(count_test_events skip)"

echo ""
echo "-- eval result summary: go-exit=${EVAL_RC} pass=${PASS_N} fail=${FAIL_N} skip=${SKIP_N} --"

if [ "${EVAL_RC}" -eq 0 ] && [ "${PASS_N}" -ge 1 ] && [ "${FAIL_N}" -eq 0 ] && [ "${SKIP_N}" -eq 0 ]; then
  echo "== EVAL PASSED (run ${RUN_ID} satisfies evals/${SUITE}; ${PASS_N} test(s) passed, none skipped) =="
  exit 0
fi

# Any other outcome is a failure. Explain WHY so a reviewer does not mistake a
# "no tests ran" / "all skipped" case for a success.
if [ "${EVAL_RC}" -ne 0 ]; then
  echo "== EVAL FAILED (run ${RUN_ID}: eval suite exited non-zero: ${EVAL_RC}) =="
elif [ "${PASS_N}" -eq 0 ]; then
  echo "== EVAL FAILED (run ${RUN_ID}: NO tests actually ran/passed — refusing to treat as success) =="
elif [ "${SKIP_N}" -ne 0 ]; then
  echo "== EVAL FAILED (run ${RUN_ID}: ${SKIP_N} test(s) were skipped — acceptance criteria not fully exercised) =="
else
  echo "== EVAL FAILED (run ${RUN_ID}: ${FAIL_N} test(s) failed) =="
fi
exit 1
