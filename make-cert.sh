#!/bin/bash
# Creates the "ClaudeSwipe Local" self-signed code-signing certificate in your
# login keychain. build.sh signs with it when it exists, so macOS ties the
# Accessibility permission to this certificate instead of to each build, and
# the permission survives rebuilds. Run once per Mac.
set -euo pipefail
NAME="ClaudeSwipe Local"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "\"$NAME\" is already in your keychain."; exit 0
fi
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=$(openssl rand -hex 16)
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/k.pem" -out "$TMP/c.pem" -days 3650 -nodes \
  -subj "/CN=$NAME" -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "keyUsage=critical,digitalSignature" 2>/dev/null
openssl pkcs12 -export -legacy -out "$TMP/c.p12" -inkey "$TMP/k.pem" -in "$TMP/c.pem" -passout "pass:$PASS" 2>/dev/null \
  || openssl pkcs12 -export -out "$TMP/c.p12" -inkey "$TMP/k.pem" -in "$TMP/c.pem" -passout "pass:$PASS"
# -T lets codesign use the key without asking each time.
security import "$TMP/c.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign
echo "Added \"$NAME\". Now run ./build.sh --run, then turn on ClaudeSwipe in System Settings once more."
