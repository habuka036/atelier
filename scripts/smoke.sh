#!/usr/bin/env bash
# Smoke test for atelier: verifies NAVETTE is runnable end-to-end WITHOUT any
# real agent, network, or Kiro authentication. It exercises the Control Plane
# with the fake runtime only, then INSPECTS the final state and FAILS (non-zero)
# if the outcome is not exactly as expected.
#
# This does NOT run run-kiro (which requires human Kiro authentication).
set -euo pipefail

ROOT="/workspace"
BIN="${ROOT}/bin/navette"
STATE="${ROOT}/state"
SMOKE_DB="${STATE}/smoke.db"

fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }

echo "== atelier smoke test (fake runtime) =="

[ -x "${BIN}" ] || fail "navette CLI not found at ${BIN}; run .devcontainer/post-create.sh first"

echo "-- tool availability --"
echo "  go:       $(go version 2>/dev/null || echo MISSING)"
echo "  bwrap:    $(command -v bwrap || echo MISSING)"
echo "  kiro-cli: $(command -v kiro-cli || echo MISSING)"

# Fresh smoke DB each run.
rm -f "${SMOKE_DB}" "${SMOKE_DB}-wal" "${SMOKE_DB}-shm"

echo "-- registering a task --"
ADD_OUT="$("${BIN}" --db "${SMOKE_DB}" add --goal "smoke: change the dummy greeting" --max-iter 3 --timeout 30s)"
echo "  ${ADD_OUT}"
TASK_ID="$(printf '%s\n' "${ADD_OUT}" | awk '{print $3}')"
[ -n "${TASK_ID}" ] || fail "could not parse task id from: ${ADD_OUT}"

echo "-- running with FAKE runtime (pre+result auto-approved; TEST-ONLY) --"
# Preserve the approval flow (scripted approvals are fake-only). Capture the
# exit code without aborting the script so we can inspect/report it.
set +e
"${BIN}" --db "${SMOKE_DB}" run --task "${TASK_ID}" --fake --approve-pre=y --approve-result=y
RUN_RC=$?
set -e
echo "  run exit code: ${RUN_RC}"
[ "${RUN_RC}" -eq 0 ] || fail "fake run returned non-zero exit code ${RUN_RC}"

echo "-- verifying final state --"
SHOW_OUT="$("${BIN}" --db "${SMOKE_DB}" show --task "${TASK_ID}")"
printf '%s\n' "${SHOW_OUT}" | sed 's/^/    /'

# The task MUST have reached Succeeded.
printf '%s\n' "${SHOW_OUT}" | grep -q 'State: \*\*Succeeded\*\*' \
  || fail "task ${TASK_ID} did not reach Succeeded"

# The DB file MUST now exist (persistence happened).
[ -f "${SMOKE_DB}" ] || fail "expected SQLite DB at ${SMOKE_DB} was not created"

# The fake runtime makes no file changes; there must be no artifacts dir claim.
echo ""
echo "== smoke test PASSED =="
echo "NAVETTE Control Plane works (fake runtime). Clean up: rm ${SMOKE_DB}*"
echo "Next: authenticate Kiro (README) then try: scripts/run-kiro.sh"
