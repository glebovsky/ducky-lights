#!/bin/bash
# One-time: create a self-signed code-signing identity "Ducky Lights Local" in the login
# keychain. Signing with a stable identity keeps macOS privacy permissions (Input
# Monitoring) across rebuilds; ad-hoc signatures change every build and lose them.
# macOS asks for your password to trust the certificate for code signing. On the next
# builds it asks whether codesign may use the key: enter the login password and pick
# "Always Allow" once. If it keeps asking:
#   security set-key-partition-list -S apple-tool:,apple: -s ~/Library/Keychains/login.keychain-db
set -euo pipefail
# System LibreSSL on purpose: OpenSSL 3+ writes PKCS#12 that `security import` rejects.
NAME="Ducky Lights Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
    echo "identity \"$NAME\" already exists"; exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
pass=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$NAME" \
    -passout "pass:$pass" -out "$tmp/id.p12" 2>/dev/null
security import "$tmp/id.p12" -k "$KEYCHAIN" -P "$pass" -T /usr/bin/codesign >/dev/null
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$tmp/cert.pem"
security find-identity -v -p codesigning | grep "\"$NAME\""
