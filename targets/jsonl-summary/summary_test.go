package main

import (
	"strings"
	"testing"
)

// These tests express the specification (README.md). They FAIL for the skeleton
// and should PASS once Summarize is implemented.
//
// NOTE: this test lives inside the agent-editable target, so it is NOT the sole
// acceptance basis. The authoritative evaluation is the independent suite in
// evals/jsonl-summary/ (outside this project, not editable by the agent).

func TestSummarize_Basic(t *testing.T) {
	in := strings.Join([]string{
		`{"category":"b","x":1}`,
		`{"category":"a"}`,
		`{"category":"b"}`,
	}, "\n")
	got, err := Summarize(strings.NewReader(in))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.Total != 3 {
		t.Errorf("Total = %d, want 3", got.Total)
	}
	// Categories sorted ascending: a(1), b(2).
	if len(got.Categories) != 2 ||
		got.Categories[0].Category != "a" || got.Categories[0].Count != 1 ||
		got.Categories[1].Category != "b" || got.Categories[1].Count != 2 {
		t.Errorf("Categories = %+v, want [{a 1} {b 2}]", got.Categories)
	}
}

func TestSummarize_EmptyInput(t *testing.T) {
	got, err := Summarize(strings.NewReader(""))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.Total != 0 || len(got.Categories) != 0 {
		t.Errorf("empty input: got %+v, want total=0 categories=[]", got)
	}
}

func TestSummarize_BlankLinesIgnored(t *testing.T) {
	in := "\n  \n{\"category\":\"a\"}\n\n"
	got, err := Summarize(strings.NewReader(in))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.Total != 1 || len(got.Categories) != 1 || got.Categories[0].Category != "a" {
		t.Errorf("blank-line handling: got %+v", got)
	}
}

func TestSummarize_InvalidJSON(t *testing.T) {
	if _, err := Summarize(strings.NewReader(`{not json}`)); err == nil {
		t.Error("expected error for invalid JSON line")
	}
}

func TestSummarize_NonObject(t *testing.T) {
	if _, err := Summarize(strings.NewReader(`[1,2,3]`)); err == nil {
		t.Error("expected error for non-object top-level value")
	}
}

func TestSummarize_MissingCategory(t *testing.T) {
	if _, err := Summarize(strings.NewReader(`{"x":1}`)); err == nil {
		t.Error("expected error for missing category field")
	}
}

func TestSummarize_NonStringCategory(t *testing.T) {
	if _, err := Summarize(strings.NewReader(`{"category":123}`)); err == nil {
		t.Error("expected error for non-string category")
	}
}
