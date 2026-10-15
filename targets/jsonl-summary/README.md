# jsonl-summary (ATELIER Stage 2 experiment target)

A throwaway, secret-free target project for an ATELIER experiment. An AI agent
(via NAVETTE) is asked to **implement** the aggregation logic so the project's
tests pass. The skeleton below builds but its tests fail until the logic is
implemented.

**This project contains no secrets and is not a real repository.** Do not add
network access or external dependencies.

## What the CLI does

`jsonl-summary` reads **JSON Lines** (one JSON object per line) from standard
input and writes a single JSON summary object to standard output.

```
jsonl-summary < input.jsonl
```

It aggregates records by a string field named `category` and counts them.

### Input format

- Standard input, UTF-8, one JSON **object** per line (JSON Lines / `.jsonl`).
- Blank lines (empty or whitespace-only) are **ignored** (not counted, not an
  error).
- Each non-blank line MUST be a JSON object (`{...}`). Arrays, numbers, strings,
  etc. at the top level are invalid.
- Each object MUST contain a `category` field whose value is a JSON string.
  Other fields are allowed and ignored.

### Output format

A single JSON object printed to standard output, followed by a trailing
newline. Field order and formatting are fixed for determinism:

```json
{"total":<int>,"categories":[{"category":"<name>","count":<int>}, ...]}
```

- `total`: the number of valid records processed (excludes blank lines).
- `categories`: one entry per distinct `category` value.
  - Sorted by `category` **ascending (byte-wise/lexicographic)** for
    deterministic output.
  - `count`: number of records with that category.
- The output MUST be deterministic: identical input always yields byte-identical
  output. Use the exact key order shown (`total` then `categories`; within each
  entry `category` then `count`).

For empty input (no valid records), output:

```json
{"total":0,"categories":[]}
```

### Error conditions

On any of the following, the CLI MUST:
- write nothing (or nothing meaningful) to standard output,
- write a diagnostic message to standard error,
- exit with a **non-zero** status.

Error cases:
1. A non-blank line that is not valid JSON.
2. A non-blank line whose top-level JSON value is not an object.
3. An object missing the `category` field, or whose `category` is not a string.

Blank lines are NOT errors.

### Determinism requirements

- Category ordering is lexicographic ascending by the raw `category` string.
- No map-iteration-order leakage into the output.
- No timestamps, hostnames, or other nondeterministic content in the output.

## Expected public API (to implement)

See `summary.go`. The agent should implement:

- `Summarize(r io.Reader) (Summary, error)` — parse JSONL from `r`, return the
  aggregated `Summary` or an error per the rules above.
- The `Summary` type must marshal to the exact JSON shape described above.

`main.go` wires standard input/output to `Summarize` and sets the exit code.

## Done criteria

- `go build ./...` succeeds (it already does for the skeleton).
- `go test ./...` passes (it fails for the skeleton until `Summarize` is
  implemented).
- The independent evaluation suite in `evals/jsonl-summary/` (outside this
  project, not editable by the agent) also passes against the produced binary /
  package.
