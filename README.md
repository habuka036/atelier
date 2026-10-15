# atelier

A general-purpose **AI software development environment**: an independent VS
Code DevContainer workspace that combines **NAVETTE** (the development harness)
with **MILLEFEUILLE / Une Feuille** (a memory/observation foundation, available
for future wiring). It lets an AI agent develop arbitrary software inside an
isolated sandbox, with a human reviewing and approving the results. It is **not
tied to any specific project**.

This workspace does **not** modify the NAVETTE, MILLEFEUILLE, or Une Feuille
source repositories. NAVETTE and MILLEFEUILLE are fetched at **pinned full-SHA
commits** into `vendor-src/` and used read-only.

## What this environment does (and does not) do

- Runs **NAVETTE** to register a task, execute it, and let a human approve.
- The default experiment target is a **throwaway, secret-free dummy Go project**
  (`targets/dummy-go/`), not a real repository. (Pointing NAVETTE at other
  targets is a future enhancement and is intentionally not wired yet.)
- The agent (Kiro CLI) runs inside **bubblewrap** isolation: it may write only
  to a disposable work copy (`.git` and secrets excluded); references are
  read-only; `/tmp` is a private tmpfs; the host SSH agent, Docker socket, and
  cloud credentials are **not** exposed.
- NAVETTE performs **no** automatic apply / commit / push to any real
  repository. A human reviews the diff and accepts artifacts only.
- Ollama Provider and Une Feuille integration are **out of scope for now**; the
  current milestone is confirming NAVETTE itself runs.

## Layout

```
atelier/
├── .devcontainer/
│   ├── devcontainer.json   # volumes for state/ & artifacts/, seccomp=unconfined, no privileged
│   ├── Dockerfile          # Debian + bubblewrap + mise(go 1.26.0) + Kiro CLI
│   ├── mise.toml           # go 1.26.0 (matches navette/millefeuille go.mod)
│   └── post-create.sh      # fetch pinned navette/millefeuille, build CLI
├── scripts/
│   ├── smoke.sh            # fake-runtime end-to-end (no auth/network)
│   └── run-kiro.sh         # real Kiro run against the target (needs auth)
├── targets/dummy-go/       # secret-free experiment target
├── vendor-src/             # pinned navette/ & millefeuille/ (gitignored)
├── bin/navette             # built CLI (gitignored)
├── artifacts/              # durable per-run artifacts (volume, gitignored)
├── state/                  # durable navette.db + kiro-home (volume, gitignored)
├── .gitignore
└── README.md
```

`vendor-src/`, `bin/`, `state/`, and `artifacts/` are gitignored. `state/` and
`artifacts/` are also backed by Docker **named volumes** (`atelier_state`,
`atelier_artifacts`), so they survive container rebuilds.

## Prerequisites

- Docker + VS Code Dev Containers extension (Apple Silicon host supported; the
  container runs as `arm64` Linux).
- A Kiro account you can authenticate via device flow.

## Setup

1. Open this `atelier/` folder in VS Code and "Reopen in Container". The build
   installs bubblewrap, Go 1.26.0 (via mise), and the Kiro CLI.
2. `postCreateCommand` runs `.devcontainer/post-create.sh`, which:
   - fetches `navette` and `millefeuille` at the pinned full-SHA commits into
     `vendor-src/` (read-only use),
   - builds `bin/navette`,
   - ensures `state/` and `artifacts/` exist.
   Re-run it any time with: `bash .devcontainer/post-create.sh`.

Pinned commits are set in `devcontainer.json` (`NAVETTE_COMMIT`,
`MILLEFEUILLE_COMMIT`) as full 40-char SHAs. Change them there to use different
revisions.

## Smoke test (no authentication, no network)

Confirms NAVETTE's Control Plane works using the **fake** runtime:

```sh
bash scripts/smoke.sh
```

Expect the task to reach **Succeeded** and a Markdown review view to print. The
script fails (non-zero) if the final state is not exactly as expected. This
exercises registration → pre-approval → execution (fake) → result approval →
success, persisted in SQLite. No agent, network, or Kiro login is involved.

## Authenticate Kiro (human, one-time)

The real-agent path uses a **dedicated, persistent** Kiro HOME at
`state/kiro-home` — separate from any normal profile. Host credentials are
never copied or mounted. Authenticate it yourself once (interactive device
flow):

```sh
HOME=/workspace/state/kiro-home kiro-cli login --use-device-flow
```

Follow the printed URL + code in a browser (choose your license/account type
when prompted). Verify (no secrets are printed by this workspace):

```sh
HOME=/workspace/state/kiro-home kiro-cli whoami
```

The authentication persists in the `atelier_state` volume across container
rebuilds. (Renaming the volume starts a fresh, unauthenticated profile and
requires re-authentication.)

## Run a real experiment (after authentication)

Drives the real Kiro CLI, inside bubblewrap, against the target. Approvals are
interactive; the result approval shows a unified diff and run log before you
accept. Nothing is applied back to any real repository.

```sh
scripts/run-kiro.sh "In main.go, change the greeting string. Only edit main.go."
```

- Approve **pre-execution** to launch the agent.
- Review the **unified diff** and **run log**, then approve/reject the **result**.
- On acceptance, artifacts are saved under `artifacts/<run-id>/` and verified
  against what you approved. The target on disk is unchanged.

Inspect later:

```sh
bin/navette --db /workspace/state/navette.db list
bin/navette --db /workspace/state/navette.db show --task <TASK_ID>
```

## NAVETTE CLI quick reference

```
navette --db PATH add      --goal "..." [--max-iter N] [--timeout D] [--workdir P]
navette --db PATH run      --task ID --fake [--approve-pre=y/n] [--approve-result=y/n]
navette --db PATH run-kiro --task ID --src DIR [--agent-engine v2|v3] \
                           [--kiro-home PATH] [--ref DIR] [--artifacts DIR]
navette --db PATH list
navette --db PATH show     --task ID
navette --db PATH recover
```

Exit codes (run/run-kiro): `0` success, `1` run error, `3` awaiting approval,
`4` rejected, `5` persistence failure, `6` sandbox unavailable, `7` Kiro profile
not authenticated, `8` result finalization failed / artifact mismatch.

## Security model

- **No `--privileged`, no `--cap-add`, no Docker socket.** Only
  `seccomp=unconfined` is relaxed (required by bubblewrap/bun). **This is a known
  PoC-only risk** (see "Residual risks"): a disabled seccomp filter widens the
  syscall surface available to processes in the container. It does **not** grant
  privilege escalation and is far narrower than `--privileged`, but it is a
  deliberate relaxation accepted only for this experiment. Runs as non-root
  `developer`.
- **Scoped volume chown**: Docker named volumes mount root-owned, but the
  container runs as `developer`. A fixed root-owned helper
  (`/usr/local/sbin/atelier-fix-volumes`) chowns ONLY `/workspace/state` and
  `/workspace/artifacts`, and only after verifying each is the expected path and
  an actual mount point. `developer` has a passwordless sudo entry limited to
  exactly that helper with no arguments. No general sudo is granted.
- **bubblewrap isolation** for the agent: work-copy-only writable, references
  read-only, private `/tmp`, host home/SSH-agent/Docker-socket not exposed,
  environment cleared (`--clearenv`) with only an allowlist set.
- **Dedicated Kiro HOME** (`state/kiro-home`): the only place Kiro auth lives;
  host credentials are never copied/mounted. This workspace never reads or logs
  credential values.
- **No auto-apply/commit/push** to real repositories; humans review and apply.
- **Pinned, read-only upstreams**: `vendor-src/` is fetched at fixed full SHAs.

### Residual risks (known, accepted for the PoC)

- **`seccomp=unconfined`** is enabled (needed by bubblewrap/bun). This is a
  deliberate, **PoC-only** relaxation that widens the syscall surface. Do not
  carry this setting into any non-experiment or production use.
- **Network is open** to the Kiro cloud backend (Kiro CLI is a cloud agent).
  Destinations and transmitted content are not restricted; therefore only
  **secret-free, throwaway** targets are used. Do **not** place real projects or
  any secrets under `targets/`. This PoC does not add new permissions and does
  not process real projects.
- The dedicated Kiro HOME contains auth tokens and is not fully opaque to the
  agent process within its own profile.
- Process reclamation is process-group based; a grandchild that deliberately
  escapes its group (setsid/double-fork) is outside the guaranteed boundary
  (bubblewrap `--die-with-parent` is a backstop).

## Reproducibility

This environment pins what it can and records what it cannot:

- **NAVETTE / MILLEFEUILLE**: pinned by **full 40-char commit SHA** in
  `devcontainer.json` (`NAVETTE_COMMIT`, `MILLEFEUILLE_COMMIT`).
  `post-create.sh` rejects anything that is not a full SHA, verifies the checked
  -out `HEAD` matches exactly, and **refuses to proceed** if an existing
  `vendor-src/` checkout has local (uncommitted/untracked) modifications.
- **Go**: pinned to `1.26.0` via `mise.toml` (matches both `go.mod`s).
- **mise**: pinned via the `MISE_VERSION` build arg in the `Dockerfile`.
- **Kiro CLI**: installed via the upstream installer
  (`https://cli.kiro.dev/install`), which does **not** accept a version pin. The
  installed version is **recorded** (baked into `~/.atelier-versions` and
  printed by `post-create.sh`), but it is **not** reproducibly pinned.

**Reproducibility risk — external installers.** The mise and Kiro CLI install
scripts are fetched from the network at image build time. Upstream changes to
those installers (or to the artifacts they download) can change tool behaviour
between rebuilds even with the same `Dockerfile`. The recorded versions in
`~/.atelier-versions` let you detect such drift. For stronger reproducibility,
pin to specific installer artifacts / checksums in a follow-up (out of scope for
this PoC).

### "Read-only" vendor-src — what it means

`vendor-src/` holds the fetched upstreams at pinned SHAs and is intended for
**read-only use**. Note this is a **usage/process guarantee, not an OS
permission**: the files are owned by the container user and could technically be
edited. To make the guarantee enforceable, `post-create.sh` **detects** local
modifications (dirty working tree, staged, or untracked files) in an existing
`vendor-src/` checkout and **stops** rather than overwriting them. `vendor-src/`
is also gitignored, so accidental edits are never committed from this workspace.

## Troubleshooting

- `sandbox unavailable (bwrap missing)` (exit 6): ensure `bwrap` is installed
  (it is in the image) and that `seccomp=unconfined` is set (it is in
  `devcontainer.json`).
- `dedicated Kiro profile not authenticated` (exit 7): run the device-flow login
  above.
- `go` not found: open a new shell so mise shims are on PATH, or
  `eval "$(mise activate bash)"`.
