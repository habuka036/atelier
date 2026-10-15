#!/usr/bin/env bash
# post-create for atelier.
#
# Responsibilities (idempotent — safe to re-run):
#   1. Fix ownership of the durable named-volume mount points (scoped sudo).
#   2. Fetch NAVETTE and MILLEFEUILLE at pinned FULL commit SHAs into
#      vendor-src/, verifying the checkout and refusing to proceed if an
#      existing vendor-src working tree has uncommitted changes.
#   3. Build the navette CLI into bin/navette.
#   4. Record tool/version provenance into the setup log.
#
# It does NOT authenticate Kiro (that is a human device-flow step) and does NOT
# run any real agent. See README.
#
# vendor-src is intended for READ-ONLY use (fetched upstreams at pinned SHAs).
# Note: the container user owns these files and *could* technically modify them;
# "read-only" is a usage/process guarantee, not an OS permission. To make that
# guarantee enforceable, this script DETECTS local modifications and stops.
set -euo pipefail

echo "== atelier post-create =="

ROOT="/workspace"
VENDOR="${ROOT}/vendor-src"
BIN="${ROOT}/bin"
STATE="${ROOT}/state"
ARTIFACTS="${ROOT}/artifacts"

NAVETTE_REPO="${NAVETTE_REPO:-https://github.com/habuka036/navette.git}"
NAVETTE_COMMIT="${NAVETTE_COMMIT:-}"
MILLEFEUILLE_REPO="${MILLEFEUILLE_REPO:-https://github.com/habuka036/millefeuille.git}"
MILLEFEUILLE_COMMIT="${MILLEFEUILLE_COMMIT:-}"

mkdir -p "${VENDOR}" "${BIN}"

# ---- version / tool provenance ------------------------------------------------
echo "-- tool versions --"
if [ -f "${HOME}/.atelier-versions" ]; then
  sed 's/^/  /' "${HOME}/.atelier-versions"
else
  echo "  (image version record missing; printing live versions)"
fi
echo "  live go:       $(go version 2>/dev/null || echo 'MISSING')"
echo "  live mise:     $(mise --version 2>/dev/null | head -n1 || echo 'MISSING')"
echo "  live kiro-cli: $(kiro-cli --version 2>/dev/null || echo 'MISSING')"
echo "  live bwrap:    $(bwrap --version 2>/dev/null || echo 'MISSING')"

# ---- durable volume ownership -------------------------------------------------
# The state/ and artifacts/ dirs are Docker named volumes created root-owned,
# while this container runs as non-root. Fix ownership via a scoped, verified
# root helper (see Dockerfile) — not general sudo.
ensure_owned() {
  local dir="$1"
  mkdir -p "${dir}" 2>/dev/null || true
  if [ -w "${dir}" ] && touch "${dir}/.write-probe" 2>/dev/null; then
    rm -f "${dir}/.write-probe"
    return 0
  fi
  echo "  fixing ownership of root-owned volume mount points"
  sudo /usr/local/sbin/atelier-fix-volumes
}
ensure_owned "${STATE}"
ensure_owned "${ARTIFACTS}"
mkdir -p "${STATE}/kiro-home"

# ---- pinned-SHA validation ----------------------------------------------------
require_full_sha() {
  local name="$1" value="$2"
  if [ -z "${value}" ]; then
    echo "ERROR: ${name} is empty; a full 40-char commit SHA is required." >&2
    exit 2
  fi
  if ! printf '%s' "${value}" | grep -Eq '^[0-9a-f]{40}$'; then
    echo "ERROR: ${name}='${value}' is not a full 40-char commit SHA." >&2
    echo "       Set the complete SHA (not an abbreviation or tag) in devcontainer.json." >&2
    exit 2
  fi
}
require_full_sha "NAVETTE_COMMIT" "${NAVETTE_COMMIT}"
require_full_sha "MILLEFEUILLE_COMMIT" "${MILLEFEUILLE_COMMIT}"

# fetch_pinned <repo-url> <full-sha> <dest-dir>
# Fetches and checks out an exact commit SHA. If the destination already exists
# and has LOCAL MODIFICATIONS (dirty working tree or staged changes), it STOPS
# rather than discarding work. After checkout it verifies HEAD equals the pinned
# SHA exactly.
fetch_pinned() {
  local url="$1" sha="$2" dest="$3"

  if [ -d "${dest}/.git" ]; then
    (
      cd "${dest}"
      if ! git diff --quiet || ! git diff --cached --quiet || \
         [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
        echo "ERROR: ${dest} has local modifications (uncommitted/untracked)." >&2
        echo "       Refusing to overwrite. Inspect with: git -C ${dest} status" >&2
        echo "       Remove or reset ${dest} intentionally, then re-run." >&2
        exit 3
      fi
    )
  else
    echo "  cloning ${url} -> ${dest}"
    git clone --no-checkout "${url}" "${dest}"
  fi

  (
    cd "${dest}"
    if ! git cat-file -e "${sha}^{commit}" 2>/dev/null; then
      echo "  fetching ${sha:0:12}..."
      git fetch --tags origin || true
      if ! git cat-file -e "${sha}^{commit}" 2>/dev/null; then
        git fetch --unshallow origin 2>/dev/null || git fetch origin || true
      fi
    fi
    if ! git cat-file -e "${sha}^{commit}" 2>/dev/null; then
      echo "ERROR: commit ${sha} not found in ${url}" >&2
      exit 3
    fi
    git checkout --quiet --detach "${sha}"
    local head
    head="$(git rev-parse HEAD)"
    if [ "${head}" != "${sha}" ]; then
      echo "ERROR: ${dest} HEAD ${head} does not match pinned ${sha}" >&2
      exit 3
    fi
    echo "  ${dest} verified at ${head}"
  )
}

echo "-- fetching pinned sources (full-SHA, verified) --"
fetch_pinned "${NAVETTE_REPO}" "${NAVETTE_COMMIT}" "${VENDOR}/navette"
fetch_pinned "${MILLEFEUILLE_REPO}" "${MILLEFEUILLE_COMMIT}" "${VENDOR}/millefeuille"

echo "-- building navette CLI --"
(
  cd "${VENDOR}/navette"
  go build -o "${BIN}/navette" ./cmd/navette
)
echo "  built ${BIN}/navette"

cat <<EOF

== post-create complete ==
Fetched (pinned full SHA, verified, read-only use):
  navette      @ ${NAVETTE_COMMIT}
  millefeuille @ ${MILLEFEUILLE_COMMIT}
CLI:            ${BIN}/navette
Durable state:  ${STATE} (navette.db, kiro-home)
Artifacts:      ${ARTIFACTS}

Next steps are in README.md:
  1. Smoke test with the fake runtime (no auth, no network): bash scripts/smoke.sh
  2. Authenticate the dedicated Kiro HOME (human device flow) before run-kiro.
EOF
