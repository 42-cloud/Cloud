package main

import (
	"net/http"
	"os"
	"fmt"
	"flag"
)

func main() {
	url := flag.String("url", "http://localhost/", "URL to check")
	flag.Parse()
	resp, err := http.Get(*url)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
	defer resp.Body.Close()
	if resp.StatusCode <= 400 && resp.StatusCode >= 200 {
		fmt.Fprintf(os.Stdout, "OK: Healthcheck for %s return %d\n", *url, resp.StatusCode)
		os.Exit(0)
	}
	fmt.Fprintf(os.Stdout, "FAILED: Healthcheck for %s return %d\n", *url, resp.StatusCode)
	os.Exit(1)
}
