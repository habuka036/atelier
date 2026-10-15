# evals/jsonl-summary — independent evaluation suite

This is the **authoritative** acceptance test for the `jsonl-summary`
experiment. It is deliberately kept **outside** `targets/jsonl-summary/` so that:

- it is **not** part of the agent's writable work copy (the agent only edits a
  disposable copy of the target; it never sees or edits `evals/`), and
- its contents and hash can be **fixed before** the experiment and verified
  afterwards (the agent cannot weaken the acceptance criteria).

## What it evaluates (black-box, via the CLI)

It builds the candidate project's CLI and drives it through **stdin/stdout/exit
code only** — it does NOT import the candidate's Go package, so renaming
internal symbols cannot affect the verdict. It checks the observable contract
from `targets/jsonl-summary/README.md`:

- normal aggregation + lexicographic category ordering + exact JSON shape,
- multiple categories / multiple records,
- empty input → `{"total":0,"categories":[]}`,
- blank lines ignored,
- invalid JSON line → non-zero exit,
- non-object top-level value → non-zero exit,
- missing / non-string `category` → non-zero exit.

## How to run

Point `CANDIDATE_DIR` at the project to evaluate (a disposable copy of an
artifact), then run the suite:

```sh
CANDIDATE_DIR=/path/to/candidate go test ./...
```

The suite compiles `CANDIDATE_DIR` with `go build` into a temp binary and runs
it. If `CANDIDATE_DIR` is unset, the tests are skipped (so this module stays
green on its own in CI without a candidate).

## Freezing the acceptance criteria

Before an experiment, record the hash of this directory's test sources so you
can prove they were not altered:

```sh
find evals/jsonl-summary -type f -name '*.go' -o -name 'go.mod' | sort \
  | xargs sha256sum
```

Keep the output with the experiment report. Re-run afterwards to confirm the
evaluation basis is unchanged.
