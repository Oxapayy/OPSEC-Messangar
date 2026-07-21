package main

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/argon2"
)

// Argon2id parameters tuned for a small VPS. Bump when you upgrade hardware.
const (
	argonTime    = 2
	argonMemory  = 64 * 1024 // 64 MiB
	argonThreads = 2
	argonKeyLen  = 32
	saltLen      = 16
)

// HashArgon2id hashes the client-supplied auth_key with a random salt and
// returns a PHC-style string: $argon2id$v=19$m=..,t=..,p=..$salt$hash
func HashArgon2id(authKey string) string {
	salt := make([]byte, saltLen)
	_, _ = rand.Read(salt)
	sum := argon2.IDKey([]byte(authKey), salt, argonTime, argonMemory, argonThreads, argonKeyLen)
	return fmt.Sprintf("$argon2id$v=19$m=%d,t=%d,p=%d$%s$%s",
		argonMemory, argonTime, argonThreads,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(sum))
}

// VerifyArgon2id compares a fresh auth_key against a stored PHC hash.
func VerifyArgon2id(authKey, stored string) bool {
	parts := strings.Split(stored, "$")
	if len(parts) != 6 || parts[1] != "argon2id" {
		return false
	}
	var m, t uint32
	var p uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &m, &t, &p); err != nil {
		return false
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return false
	}
	want, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return false
	}
	got := argon2.IDKey([]byte(authKey), salt, t, m, p, uint32(len(want)))
	return subtle.ConstantTimeCompare(got, want) == 1
}

// RandomHex returns a hex-encoded random string of 2*n characters.
func RandomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

// AuthKeyLooksValid does very light sanity checking on the client-supplied
// auth key (hex-encoded 32-byte SHA-256).
var errBadAuthKey = errors.New("bad auth_key")

func AuthKeyLooksValid(k string) error {
	if len(k) != 64 {
		return errBadAuthKey
	}
	if _, err := hex.DecodeString(k); err != nil {
		return errBadAuthKey
	}
	return nil
}
