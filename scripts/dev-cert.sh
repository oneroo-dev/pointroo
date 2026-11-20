#!/bin/bash
# Run ONCE in your own terminal: bash scripts/dev-cert.sh
# Makes a self-signed code-signing certificate "Pointroo Dev" in your login keychain, so every build is signed the
# same way and macOS keeps the Screen Recording and Accessibility permissions across rebuilds. It may ask for your
# password (to trust the certificate for code signing).
set -euo pipefail
NAME="Pointroo Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "\"$NAME\" already exists, nothing to do."
  security find-identity -v -p codesigning
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PASSWORD="pointroo-dev-temp"

cat > "$WORK/openssl.cnf" <<CONFIG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONFIG

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/openssl.cnf" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem"
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
  -out "$WORK/pointroo-dev.p12" -passout "pass:$PASSWORD"

security import "$WORK/pointroo-dev.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo
echo "Done. Valid code-signing identities:"
security find-identity -v -p codesigning
