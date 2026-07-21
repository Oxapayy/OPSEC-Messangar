package main

import (
	"os"
	"path/filepath"
)

type Config struct {
	Listen        string // e.g. 127.0.0.1:8080
	DBPath        string
	UploadDir     string
	MaxUploadSize int64
}

func LoadConfig() Config {
	base := getenv("OPSEC_DATA_DIR", "/var/lib/opsec-backend")
	return Config{
		Listen:        getenv("OPSEC_LISTEN", "127.0.0.1:8080"),
		DBPath:        getenv("OPSEC_DB", filepath.Join(base, "opsec.db")),
		UploadDir:     getenv("OPSEC_UPLOADS", filepath.Join(base, "uploads")),
		MaxUploadSize: 25 * 1024 * 1024, // 25 MiB per attachment
	}
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
