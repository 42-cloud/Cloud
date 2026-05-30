package main

import (
	"database/sql"
	"flag"
	"fmt"
	"os"

	_ "github.com/go-sql-driver/mysql"
)

func main() {
	host := flag.String("host", "localhost", "MariaDB host")
	port := flag.Int("port", 3306, "MariaDB port")
	user := flag.String("user", "root", "MariaDB user")
	password := flag.String("password", "", "MariaDB password")
	flag.Parse()
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%d)/", *user, *password, *host, *port)
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
