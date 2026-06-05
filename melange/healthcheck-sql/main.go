package main

import (
	"database/sql"
	"flag"
	"fmt"
	"os"
	"strings"
	"golang.org/x/sys/unix"

	_ "github.com/go-sql-driver/mysql"
)

func main() {
	if err := unix.Mlockall(unix.MCL_CURRENT | unix.MCL_FUTURE); err != nil {
		fmt.Fprintf(os.Stderr, "error: mlockall: %v\n", err)
		os.Exit(1)
	}
	host := flag.String("host", "localhost", "MariaDB host")
	port := flag.Int("port", 3306, "MariaDB port")
	user := flag.String("user", "root", "MariaDB user")
	pass_file := flag.String("secret", "/run/secrets/mysql_password", "Path to password file")
	flag.Parse()
	data, err := os.ReadFile(*pass_file)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
	password := strings.TrimSpace(string(data))
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%d)/", *user, password, *host, *port)
	db, err := sql.Open("mysql", dsn)
	if err != nil{
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
	defer db.Close()
	if err := db.Ping(); err != nil {
		fmt.Fprintf(os.Stderr, "FAIL: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("OK: Healthcheck for MariaDB %s:%d is alive\n", *host, *port)
	os.Exit(0)
}
