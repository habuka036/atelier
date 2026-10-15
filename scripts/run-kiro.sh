#!/usr/bin/env bash
# Convenience wrapper to run a real-Kiro-CLI experiment against a target project
# under targets/, with the dedicated, persistent Kiro HOME and durable artifacts.
#
# PREREQUISITE: the dedicated Kiro HOME must already be authenticated by a human
# via device flow (see README "Authenticate Kiro"). This script does NOT log in
# and does NOT read credentials.
#
# After the (interactive) run it INSPECTS the final task state and, when the run
# succeeded, verifies that THIS run's durable artifacts exist and are non-empty.
# It identifies this run's artifact directory from NAVETTE's own output line
# ("artifacts saved and verified: <base>/<run-id>") rather than guessing the
# most-recent run- directory, so a stale artifact from an earlier run can never
# be mistaken for the current one. It exits non-zero if the result is not
# internally consistent, if this run's run-id cannot be identified, or if its
# artifact directory is missing/empty. The approval flow is unchanged: approvals
# are interactive and there is no auto-approve for the real runtime.
#
# Usage: scripts/run-kiro.sh "goal text" [target-name]
#   arg1 GOAL         (required) the task goal passed to NAVETTE.
#   arg2 target-name  (optional) a directory name directly under targets/.
#                     Defaults to "dummy-go". Only a plain allowlisted name is
#                     accepted; path separators, "..", and symlink escape are
#                     rejected BEFORE NAVETTE is invoked.
set -euo pipefail

ROOT="/workspace"
BIN="${ROOT}/bin/navette"
STATE="${ROOT}/state"
DB="${STATE}/navette.db"
KIRO_HOME="${STATE}/kiro-home"
ARTIFACTS="${ROOT}/artifacts"
TARGETS_DIR="${ROOT}/targets"

GOAL="${1:-}"
TARGET_NAME="${2:-dummy-go}"

fail() { echo "RUN-KIRO FAIL: $*" >&2; exit 1; }

[ -n "${GOAL}" ] || fail "goal (arg1) is required. Usage: run-kiro.sh \"goal\" [target-name]"
[ -x "${BIN}" ] || fail "navette CLI not found; run .devcontainer/post-create.sh first"

# ---- target name validation (fail-closed, BEFORE invoking NAVETTE) -----------
# 1) Allowlist: only [A-Za-z0-9._-]; reject everything else (covers '/' and
#    spaces). This alone blocks path separators.
case "${TARGET_NAME}" in
  *[!A-Za-z0-9._-]*) fail "invalid target name '${TARGET_NAME}' (allowed: A-Za-z0-9._-)";;
esac
# 2) Explicitly reject traversal / dotfiles that could escape or surprise.
case "${TARGET_NAME}" in
  ""|"."|".."|*..*) fail "invalid target name '${TARGET_NAME}'";;
esac

TARGET="${TARGETS_DIR}/${TARGET_NAME}"

# 3) Must be an existing directory, not a symlink (symlink could escape targets/).
if [ -L "${TARGET}" ]; then
  fail "target '${TARGET_NAME}' is a symlink; refusing (could escape targets/)"
fi
[ -d "${TARGET}" ] || fail "target directory not found: ${TARGET}"

# 4) Resolve and confirm it stays directly under targets/ (defence in depth).
#    Compare realpath of the parent to realpath of targets/.
TARGETS_REAL="$(cd "${TARGETS_DIR}" 2>/dev/null && pwd -P)" || fail "cannot resolve ${TARGETS_DIR}"
TARGET_PARENT_REAL="$(cd "${TARGET}/.." 2>/dev/null && pwd -P)" || fail "cannot resolve target parent"
[ "${TARGET_PARENT_REAL}" = "${TARGETS_REAL}" ] \
  || fail "target '${TARGET_NAME}' does not resolve directly under ${TARGETS_DIR}"

echo "-- target: ${TARGET} --"

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
# Capture run-kiro's stdout to a log while still showing it live, so we can
# extract THIS run's run-id deterministically from NAVETTE's own output. The
# approval prompts remain interactive: `tee` does not consume stdin, so the
# child still reads the terminal. We must capture the EXIT CODE OF run-kiro,
# not of `tee`; dash has no PIPESTATUS and no process substitution, so we route
# the exit code through a small file written inside the pipeline's first stage.
RUN_LOG="$(mktemp "${TMPDIR:-/tmp}/run-kiro-out-XXXXXX")"
RUN_RC_FILE="$(mktemp "${TMPDIR:-/tmp}/run-kiro-rc-XXXXXX")"
cleanup_run() { rm -f "${RUN_LOG}" "${RUN_RC_FILE}"; }
trap cleanup_run EXIT

set +e
{
  "${BIN}" --db "${DB}" run-kiro \
    --task "${TASK_ID}" \
    --src "${TARGET}" \
    --kiro-home "${KIRO_HOME}" \
    --artifacts "${ARTIFACTS}"
  echo "$?" >"${RUN_RC_FILE}"
} | tee "${RUN_LOG}"
set -e
RUN_RC="$(cat "${RUN_RC_FILE}" 2>/dev/null || echo 1)"
case "${RUN_RC}" in ''|*[!0-9]*) RUN_RC=1;; esac
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

  # Identify THIS run's artifact directory from NAVETTE's own output — NOT by
  # guessing the most-recent run- dir (which could be an unrelated earlier run).
  # On a finalized, successful run NAVETTE prints exactly:
  #     artifacts saved and verified: <artifacts-base>/<run-id>
  # We take the LAST such line (defensive) and use that exact path.
  ART_LINE="$(grep -E '^artifacts saved and verified: ' "${RUN_LOG}" 2>/dev/null | tail -n1 || true)"
  [ -n "${ART_LINE}" ] \
    || fail "Succeeded but could not find 'artifacts saved and verified:' in run-kiro output; cannot identify this run's artifact dir"
  RUN_ART="${ART_LINE#artifacts saved and verified: }"
  [ -n "${RUN_ART}" ] || fail "could not parse artifact path from run-kiro output line: ${ART_LINE}"

  # The parsed path must be the artifact dir for THIS invocation: it must live
  # directly under the --artifacts base we passed, and be named run-*.
  RUN_ID="$(basename "${RUN_ART}")"
  RUN_ART_PARENT="$(dirname "${RUN_ART}")"
  case "${RUN_ID}" in
    run-*) : ;;
    *) fail "parsed artifact dir '${RUN_ART}' is not named run-* (got '${RUN_ID}')";;
  esac
  # Compare against the --artifacts base we actually passed (realpath both).
  ARTIFACTS_REAL="$(cd "${ARTIFACTS}" 2>/dev/null && pwd -P)" || fail "cannot resolve ${ARTIFACTS}"
  RUN_ART_PARENT_REAL="$(cd "${RUN_ART_PARENT}" 2>/dev/null && pwd -P)" \
    || fail "artifact dir parent '${RUN_ART_PARENT}' does not exist"
  [ "${RUN_ART_PARENT_REAL}" = "${ARTIFACTS_REAL}" ] \
    || fail "this run's artifact dir '${RUN_ART}' is not under the artifacts base '${ARTIFACTS}'"

  # Existence + non-empty, limited to THIS run's directory only.
  [ -d "${RUN_ART}" ] || fail "Succeeded but this run's artifact directory is missing: ${RUN_ART}"
  [ -n "$(find "${RUN_ART}" -type f 2>/dev/null | head -n1)" ] \
    || fail "this run's artifact directory ${RUN_ART} is empty"
  echo "  verified THIS run's artifacts present: ${RUN_ART} (run-id: ${RUN_ID})"
  echo "== run-kiro PASSED (Succeeded; artifacts preserved; real repo untouched) =="
else
  # Non-zero exit must NOT be reported as a success.
  [ "${FINAL}" != "Succeeded" ] || fail "non-zero exit (${RUN_RC}) but state is Succeeded — inconsistent"
  echo "== run-kiro ended non-successfully: state='${FINAL}', exit=${RUN_RC} =="
  echo "   (rejection / timeout / failure — see review view above. Not a script error.)"
  exit "${RUN_RC}"
fi
