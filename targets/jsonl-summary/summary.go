// Package main implements jsonl-summary. See README.md for the full
// specification.
//
// SKELETON: the public types and the Summarize signature are defined so the
// project builds and the tests compile, but the aggregation logic is NOT
// implemented. The AI agent is expected to implement Summarize so that the
// project's own tests (summary_test.go) and the independent evaluation suite
// pass. Do not add external dependencies or network access.
package main

import (
	"errors"
	"io"
)

// CategoryCount is one aggregated category and its record count.
//
// The JSON field order is fixed for deterministic output: "category" then
// "count".
type CategoryCount struct {
	Category string `json:"category"`
	Count    int    `json:"count"`
}

// Summary is the aggregated result marshalled to standard output.
//
// The JSON field order is fixed for deterministic output: "total" then
// "categories". Categories must be sorted lexicographically ascending by
// Category.
type Summary struct {
	Total      int             `json:"total"`
	Categories []CategoryCount `json:"categories"`
}

// errNotImplemented is returned by the skeleton. Implementing Summarize must
// remove this and perform the aggregation described in README.md.
var errNotImplemented = errors.New("jsonl-summary: Summarize is not implemented")

// Summarize reads JSON Lines from r and returns the aggregated Summary.
//
// Contract (see README.md):
//   - one JSON object per line; blank/whitespace-only lines are ignored;
//   - each object must have a string "category" field;
//   - invalid JSON, non-object top-level values, or a missing/non-string
//     "category" are errors (return a non-nil error);
//   - Categories sorted ascending by Category; output deterministic.
//
// SKELETON: not implemented yet.
func Summarize(r io.Reader) (Summary, error) {
	_ = r
	return Summary{}, errNotImplemented
}
