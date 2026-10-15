package main

import (
	"encoding/json"
	"fmt"
	"os"
)

// main wires standard input/output to Summarize. On success it prints the
// summary JSON followed by a newline and exits 0; on error it prints a
// diagnostic to standard error and exits non-zero.
//
// This wiring is complete; the missing piece is Summarize (see summary.go).
func main() {
	summary, err := Summarize(os.Stdin)
	if err != nil {
		fmt.Fprintln(os.Stderr, "jsonl-summary:", err)
		os.Exit(1)
	}
	out, err := json.Marshal(summary)
	if err != nil {
		fmt.Fprintln(os.Stderr, "jsonl-summary: marshal:", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stdout, "%s\n", out)
}
