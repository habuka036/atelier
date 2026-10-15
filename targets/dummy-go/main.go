// Package main is a throwaway target project for atelier experiments.
//
// It contains NO secrets and is NOT a real repository. NAVETTE copies this
// directory (excluding .git and sensitive files) into a disposable, isolated
// work copy; the agent edits only that copy. Changes are never auto-applied
// back here.
package main

import "fmt"

func main() {
	fmt.Println(greeting())
}

// greeting returns the program's message. A typical experiment asks the agent
// to change this string and then a human reviews the diff before accepting.
func greeting() string {
	return "hello from dummy-go"
}
