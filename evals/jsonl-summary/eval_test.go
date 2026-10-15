// Package eval is the independent, black-box evaluation suite for the
// jsonl-summary experiment. It builds the candidate project's CLI (pointed to
// by CANDIDATE_DIR) and drives it only via stdin/stdout/exit code, so it does
// not depend on the candidate's internal Go API. It is NOT part of the agent's
// writable work copy and must not be editable by the agent.
package eval

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"testing"
)

// buildDir is a package-lifetime temp dir (created in TestMain) so the built
// candidate binary survives across all subtests. Using t.TempDir() would delete
// it when the first test finishes.
var buildDir string

func TestMain(m *testing.M) {
	d, err := os.MkdirTemp("", "jsonl-eval-")
	if err != nil {
		panic(err)
	}
	buildDir = d
	code := m.Run()
	_ = os.RemoveAll(d)
	os.Exit(code)
}

// candidateBin builds CANDIDATE_DIR once and returns the built binary path.
// Tests are skipped when CANDIDATE_DIR is unset so this module stays green on
// its own.
var (
	buildOnce sync.Once
	builtBin  string
	buildErr  error
)

func candidateBin(t *testing.T) string {
	t.Helper()
	dir := os.Getenv("CANDIDATE_DIR")
	if dir == "" {
		t.Skip("CANDIDATE_DIR not set; skipping (set it to a candidate project dir to evaluate)")
	}
	buildOnce.Do(func() {
		abs, err := filepath.Abs(dir)
		if err != nil {
			buildErr = err
			return
		}
		out := filepath.Join(buildDir, "candidate-bin")
		cmd := exec.Command("go", "build", "-o", out, ".")
		cmd.Dir = abs
		var stderr bytes.Buffer
		cmd.Stderr = &stderr
		if err := cmd.Run(); err != nil {
			buildErr = &buildFailure{dir: abs, detail: stderr.String(), err: err}
			return
		}
		builtBin = out
	})
	if buildErr != nil {
		t.Fatalf("failed to build candidate: %v", buildErr)
	}
	return builtBin
}

type buildFailure struct {
	dir, detail string
	err         error
}

func (e *buildFailure) Error() string {
	return "go build in " + e.dir + " failed: " + e.err.Error() + "\n" + e.detail
}

// runCLI runs the candidate binary with stdin and returns stdout, exit code.
func runCLI(t *testing.T, bin, stdin string) (stdout string, exitCode int) {
	t.Helper()
	cmd := exec.Command(bin)
	cmd.Stdin = bytes.NewBufferString(stdin)
	var out, errOut bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errOut
	err := cmd.Run()
	code := 0
	if err != nil {
		var ee *exec.ExitError
		if ok := asExit(err, &ee); ok {
			code = ee.ExitCode()
		} else {
			t.Fatalf("failed to run candidate: %v (stderr: %s)", err, errOut.String())
		}
	}
	return out.String(), code
}

func asExit(err error, target **exec.ExitError) bool {
	if ee, ok := err.(*exec.ExitError); ok {
		*target = ee
		return true
	}
	return false
}

// --- success cases: exact stdout, exit 0 ---

func TestEval_Basic(t *testing.T) {
	bin := candidateBin(t)
	in := `{"category":"b","x":1}` + "\n" + `{"category":"a"}` + "\n" + `{"category":"b"}` + "\n"
	out, code := runCLI(t, bin, in)
	if code != 0 {
		t.Fatalf("exit=%d, want 0", code)
	}
	want := `{"total":3,"categories":[{"category":"a","count":1},{"category":"b","count":2}]}` + "\n"
	if out != want {
		t.Errorf("stdout mismatch\n got: %q\nwant: %q", out, want)
	}
}

func TestEval_MultipleCategoriesSorted(t *testing.T) {
	bin := candidateBin(t)
	// Deliberately unsorted input; output must be lexicographically ascending.
	in := `{"category":"zeta"}` + "\n" + `{"category":"alpha"}` + "\n" + `{"category":"mid"}` + "\n" + `{"category":"alpha"}` + "\n"
	out, code := runCLI(t, bin, in)
	if code != 0 {
		t.Fatalf("exit=%d, want 0", code)
	}
	want := `{"total":4,"categories":[{"category":"alpha","count":2},{"category":"mid","count":1},{"category":"zeta","count":1}]}` + "\n"
	if out != want {
		t.Errorf("stdout mismatch\n got: %q\nwant: %q", out, want)
	}
}

func TestEval_EmptyInput(t *testing.T) {
	bin := candidateBin(t)
	out, code := runCLI(t, bin, "")
	if code != 0 {
		t.Fatalf("exit=%d, want 0", code)
	}
	want := `{"total":0,"categories":[]}` + "\n"
	if out != want {
		t.Errorf("empty stdout mismatch\n got: %q\nwant: %q", out, want)
	}
}

func TestEval_BlankLinesIgnored(t *testing.T) {
	bin := candidateBin(t)
	in := "\n   \n" + `{"category":"a"}` + "\n\n" + `{"category":"a"}` + "\n"
	out, code := runCLI(t, bin, in)
	if code != 0 {
		t.Fatalf("exit=%d, want 0", code)
	}
	want := `{"total":2,"categories":[{"category":"a","count":2}]}` + "\n"
	if out != want {
		t.Errorf("blank-line stdout mismatch\n got: %q\nwant: %q", out, want)
	}
}

// --- error cases: non-zero exit ---

func TestEval_InvalidJSON(t *testing.T) {
	bin := candidateBin(t)
	_, code := runCLI(t, bin, `{not json}`+"\n")
	if code == 0 {
		t.Error("invalid JSON: want non-zero exit, got 0")
	}
}

func TestEval_NonObjectTopLevel(t *testing.T) {
	bin := candidateBin(t)
	_, code := runCLI(t, bin, `[1,2,3]`+"\n")
	if code == 0 {
		t.Error("non-object top-level: want non-zero exit, got 0")
	}
}

func TestEval_MissingCategory(t *testing.T) {
	bin := candidateBin(t)
	_, code := runCLI(t, bin, `{"x":1}`+"\n")
	if code == 0 {
		t.Error("missing category: want non-zero exit, got 0")
	}
}

func TestEval_NonStringCategory(t *testing.T) {
	bin := candidateBin(t)
	_, code := runCLI(t, bin, `{"category":123}`+"\n")
	if code == 0 {
		t.Error("non-string category: want non-zero exit, got 0")
	}
}
