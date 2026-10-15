#!/usr/bin/env bash
# Regression test for scripts/run-kiro.sh artifact verification.
#
# It verifies that run-kiro.sh identifies and checks THIS run's artifact
# directory (parsed from NAVETTE's own output) and NOT the most-recent run-
# directory. In particular, a stale artifact from a PRIOR run must never be
# mistaken for a current one.
#
# This test does NOT launch the real Kiro CLI. It stubs:
#   - kiro-cli : whoami -> "logged in" (auth gate passes without secrets)
#   - navette  : add  -> prints "created task <id> (state=Pending)"
#                run-kiro -> prints a scripted stdout (incl. or excl. the
#                            "artifacts saved and verified: <dir>" line) and
#                            optionally creates the artifact dir
#                show -> prints "State: **Succeeded**"
#
# Each case runs a ROOT-rewritten copy of run-kiro.sh in a sandbox so the real
# workspace is untouched. The approval flow, isolation, fingerprint verification,
# target switching, and the independent-eval spec are not exercised or changed
# here — only the artifact-identification logic.
set -euo pipefail

REAL_SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/run-kiro.sh"
[ -f "${REAL_SCRIPT}" ] || { echo "cannot find run-kiro.sh at ${REAL_SCRIPT}" >&2; exit 1; }

PASS=0
FAIL=0
note() { printf '%s\n' "$*"; }
ok()   { PASS=$((PASS+1)); printf '  PASS: %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$*"; }

# make_sandbox <scenario> : creates /tmp/rk-regress-<scenario> with a ROOT-
# rewritten run-kiro.sh, stub bin/navette + fakebin/kiro-cli, targets/dummy-go,
# state/, artifacts/. Prints the sandbox dir on stdout.
make_sandbox() {
  local scen="$1"
  local sb="/tmp/rk-regress-${scen}"
  rm -rf "${sb}"
  mkdir -p "${sb}/bin" "${sb}/fakebin" "${sb}/targets/dummy-go" \
           "${sb}/state/kiro-home" "${sb}/artifacts"
  # ROOT-rewritten copy of the real script.
  sed "s#^ROOT=\"/workspace\"#ROOT=\"${sb}\"#" "${REAL_SCRIPT}" > "${sb}/run-kiro.sh"
  chmod +x "${sb}/run-kiro.sh"
  # stub kiro-cli: whoami -> logged in.
  cat > "${sb}/fakebin/kiro-cli" <<'EOF'
#!/bin/sh
if [ "$1" = "whoami" ]; then echo "logged in"; exit 0; fi
exit 0
EOF
  chmod +x "${sb}/fakebin/kiro-cli"
  printf '%s\n' "${sb}"
}

# run_case executes the sandbox's run-kiro.sh with PATH including the stub
# kiro-cli, capturing combined output + exit code.
run_case() {
  local sb="$1"
  ( cd "${sb}" && PATH="${sb}/fakebin:${PATH}" ./run-kiro.sh "do something" "dummy-go" ) \
    >"${sb}/out.log" 2>&1
  echo "$?"
}

# ---------------------------------------------------------------------------
# Case R1: normal success — navette prints the verified line AND creates the
#          dir -> run-kiro.sh must PASS (exit 0).
# ---------------------------------------------------------------------------
case_r1() {
  local sb; sb="$(make_sandbox r1)"
  cat > "${sb}/bin/navette" <<EOF
#!/bin/sh
case "\$*" in
  *" add "*) echo "created task task-r1 (state=Pending)" ;;
  *"run-kiro"*)
    mkdir -p "${sb}/artifacts/run-NEW1"
    echo "hello" > "${sb}/artifacts/run-NEW1/main.go"
    echo "artifacts saved and verified: ${sb}/artifacts/run-NEW1"
    echo "task task-r1 final state: Succeeded (artifacts preserved; NOT applied to any real repo)"
    exit 0 ;;
  *" show "*) echo "- State: **Succeeded**" ;;
esac
EOF
  chmod +x "${sb}/bin/navette"
  local rc; rc="$(run_case "${sb}")"
  if [ "${rc}" = "0" ] && grep -q "run-kiro PASSED" "${sb}/out.log" \
     && grep -q "run-NEW1" "${sb}/out.log"; then
    ok "R1 normal success verifies THIS run's dir (run-NEW1), exit 0"
  else
    bad "R1 expected PASS on fresh artifact (rc=${rc}); log:"; sed 's/^/      /' "${sb}/out.log"
  fi
}

# ---------------------------------------------------------------------------
# Case R2 (core regression): a PRIOR run's artifact dir exists, but THIS run
#          produces NO artifact and prints NO "saved and verified" line, while
#          still reporting exit 0 + Succeeded. run-kiro.sh must FAIL (not pass by
#          grabbing the stale run-OLD dir).
# ---------------------------------------------------------------------------
case_r2() {
  local sb; sb="$(make_sandbox r2)"
  # Seed a stale PRIOR artifact dir (as if from an earlier run).
  mkdir -p "${sb}/artifacts/run-OLD"
  echo "stale" > "${sb}/artifacts/run-OLD/old.go"
  cat > "${sb}/bin/navette" <<EOF
#!/bin/sh
case "\$*" in
  *" add "*) echo "created task task-r2 (state=Pending)" ;;
  *"run-kiro"*)
    # NO artifact created, NO "saved and verified" line, but claims success.
    echo "task task-r2 final state: Succeeded (artifacts preserved; NOT applied to any real repo)"
    exit 0 ;;
  *" show "*) echo "- State: **Succeeded**" ;;
esac
EOF
  chmod +x "${sb}/bin/navette"
  local rc; rc="$(run_case "${sb}")"
  if [ "${rc}" != "0" ] \
     && grep -q "could not find 'artifacts saved and verified:'" "${sb}/out.log" \
     && ! grep -q "run-OLD" "${sb}/out.log"; then
    ok "R2 stale prior artifact (run-OLD) is NOT accepted; fails closed (rc=${rc})"
  else
    bad "R2 expected FAIL without touching run-OLD (rc=${rc}); log:"; sed 's/^/      /' "${sb}/out.log"
  fi
}

# ---------------------------------------------------------------------------
# Case R3: navette prints the verified line but the dir is MISSING -> FAIL.
# ---------------------------------------------------------------------------
case_r3() {
  local sb; sb="$(make_sandbox r3)"
  cat > "${sb}/bin/navette" <<EOF
#!/bin/sh
case "\$*" in
  *" add "*) echo "created task task-r3 (state=Pending)" ;;
  *"run-kiro"*)
    # Announce a dir but DO NOT create it.
    echo "artifacts saved and verified: ${sb}/artifacts/run-GHOST"
    echo "task task-r3 final state: Succeeded"
    exit 0 ;;
  *" show "*) echo "- State: **Succeeded**" ;;
esac
EOF
  chmod +x "${sb}/bin/navette"
  local rc; rc="$(run_case "${sb}")"
  if [ "${rc}" != "0" ] && grep -q "artifact directory is missing" "${sb}/out.log"; then
    ok "R3 announced-but-missing artifact dir fails closed (rc=${rc})"
  else
    bad "R3 expected FAIL on missing dir (rc=${rc}); log:"; sed 's/^/      /' "${sb}/out.log"
  fi
}

# ---------------------------------------------------------------------------
# Case R4: navette prints an artifact path OUTSIDE the --artifacts base -> FAIL
#          (defence in depth: must not accept a path we did not target).
# ---------------------------------------------------------------------------
case_r4() {
  local sb; sb="$(make_sandbox r4)"
  mkdir -p "${sb}/elsewhere/run-OUT"
  echo "x" > "${sb}/elsewhere/run-OUT/x.go"
  cat > "${sb}/bin/navette" <<EOF
#!/bin/sh
case "\$*" in
  *" add "*) echo "created task task-r4 (state=Pending)" ;;
  *"run-kiro"*)
    echo "artifacts saved and verified: ${sb}/elsewhere/run-OUT"
    echo "task task-r4 final state: Succeeded"
    exit 0 ;;
  *" show "*) echo "- State: **Succeeded**" ;;
esac
EOF
  chmod +x "${sb}/bin/navette"
  local rc; rc="$(run_case "${sb}")"
  if [ "${rc}" != "0" ] && grep -q "is not under the artifacts base" "${sb}/out.log"; then
    ok "R4 artifact path outside --artifacts base fails closed (rc=${rc})"
  else
    bad "R4 expected FAIL on out-of-base path (rc=${rc}); log:"; sed 's/^/      /' "${sb}/out.log"
  fi
}

note "== run-kiro.sh artifact-identification regression tests =="
case_r1
case_r2
case_r3
case_r4

note ""
note "passed=${PASS} failed=${FAIL}"
# cleanup
rm -rf /tmp/rk-regress-r1 /tmp/rk-regress-r2 /tmp/rk-regress-r3 /tmp/rk-regress-r4
[ "${FAIL}" -eq 0 ]
