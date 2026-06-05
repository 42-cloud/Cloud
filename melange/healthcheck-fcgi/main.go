package main

import (
	"net"
	"os"
	"fmt"
	"flag"
)

func main() {
	addr := flag.String("addr", "localhost:9000", "ADDR to check")
	flag.Parse()
	conn, err := net.Dial("tcp", *addr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close()
	fmt.Fprintf(os.Stderr, "OK: Healthcheck for %s\n", *addr)
	os.Exit(0)
}
