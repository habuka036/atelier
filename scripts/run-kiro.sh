#!/usr/bin/env bash
# Convenience wrapper to run a real-Kiro-CLI experiment against the dummy target
# with the dedicated, persistent Kiro HOME and durable artifacts.
#
# PREREQUISITE: the dedicated Kiro HOME must already be authenticated by a human
# via device flow (see README "Authenticate Kiro"). This script does NOT log in
# and does NOT read credentials.
#
# After the (interactive) run it INSPECTS the final task state and, when the run
# succeeded, verifies that durable artifacts were recorded. It exits non-zero if
# the result is not internally consistent. The approval flow is unchanged:
# approvals are interactive and there is no auto-approve for the real runtime.
#
# Usage: scripts/run-kiro.sh "goal text"
set -euo pipefail

ROOT="/workspace"
BIN="${ROOT}/bin/navette"
STATE="${ROOT}/state"
DB="${STATE}/navette.db"
KIRO_HOME="${STATE}/kiro-home"
ARTIFACTS="${ROOT}/artifacts"
TARGET="${ROOT}/targets/dummy-go"

GOAL="${1:-In main.go, change the greeting string. Only edit main.go.}"

fail() { echo "RUN-KIRO FAIL: $*" >&2; exit 1; }

[ -x "${BIN}" ] || fail "navette CLI not found; run .devcontainer/post-create.sh first"

# Verify the dedicated profile is authenticated WITHOUT reading credentials.
if ! HOME="${KIRO_HOME}" kiro-cli whoami 2>/dev/null | grep -qi "logged in"; then
  cat >&2 <<EOF
Dedicated Kiro profile is not authenticated.
Run this once yourself (interactive device flow), then re-run this script:

  HOME=${KIRO_HOME} kiro-cli login --use-device-flow

EOF
  exit 7
fi

echo "-- registering task --"
ADD_OUT="$("${BIN}" --db "${DB}" add --goal "${GOAL}" --max-iter 5 --timeout 180s)"
echo "  ${ADD_OUT}"
TASK_ID="$(printf '%s\n' "${ADD_OUT}" | awk '{print $3}')"
[ -n "${TASK_ID}" ] || fail "could not parse task id from: ${ADD_OUT}"

echo "-- run-kiro (real Kiro CLI inside bubblewrap; interactive approvals) --"
# Do not abort on non-zero so we can inspect and report precisely.
set +e
"${BIN}" --db "${DB}" run-kiro \
  --task "${TASK_ID}" \
  --src "${TARGET}" \
  --kiro-home "${KIRO_HOME}" \
  --artifacts "${ARTIFACTS}"
RUN_RC=$?
set -e
echo "  run-kiro exit code: ${RUN_RC}"

echo "-- review view --"
SHOW_OUT="$("${BIN}" --db "${DB}" show --task "${TASK_ID}")"
printf '%s\n' "${SHOW_OUT}"

# Derive the final state from the review view.
if printf '%s\n' "${SHOW_OUT}" | grep -q 'State: \*\*Succeeded\*\*'; then
  FINAL="Succeeded"
elif printf '%s\n' "${SHOW_OUT}" | grep -q 'State: \*\*Rejected\*\*'; then
  FINAL="Rejected"
else
  FINAL="$(printf '%s\n' "${SHOW_OUT}" | sed -n 's/.*State: \*\*\(.*\)\*\*.*/\1/p' | head -n1)"
fi
echo "-- final state: ${FINAL:-unknown} (exit ${RUN_RC}) --"

# Consistency checks.
if [ "${RUN_RC}" -eq 0 ]; then
  # Exit 0 must mean Succeeded.
  [ "${FINAL}" = "Succeeded" ] || fail "exit 0 but final state is '${FINAL}', not Succeeded"
  # A succeeded run must have produced a durable artifact dir with content.
  LATEST_ART="$(ls -1dt "${ARTIFACTS}"/run-* 2>/dev/null | head -n1 || true)"
  [ -n "${LATEST_ART}" ] || fail "Succeeded but no artifact directory found under ${ARTIFACTS}"
  [ -n "$(find "${LATEST_ART}" -type f 2>/dev/null | head -n1)" ] \
    || fail "artifact directory ${LATEST_ART} is empty"
  echo "  verified artifacts present: ${LATEST_ART}"
  echo "== run-kiro PASSED (Succeeded; artifacts preserved; real repo untouched) =="
else
  # Non-zero exit must NOT be reported as a success.
  [ "${FINAL}" != "Succeeded" ] || fail "non-zero exit (${RUN_RC}) but state is Succeeded — inconsistent"
  echo "== run-kiro ended non-successfully: state='${FINAL}', exit=${RUN_RC} =="
  echo "   (rejection / timeout / failure — see review view above. Not a script error.)"
  exit "${RUN_RC}"
fi
