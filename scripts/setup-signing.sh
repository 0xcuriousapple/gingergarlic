#!/bin/zsh
# Creates a stable, self-signed code-signing identity so macOS keeps the
# Accessibility grant across rebuilds. Ad-hoc signing (codesign -s -) keys the
# TCC grant to the binary's hash, which changes every build — this doesn't.
# Run once. Idempotent: re-running is a no-op once the identity exists.
set -e

IDENTITY="gingergarlic-local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "✅ signing identity '$IDENTITY' already exists — nothing to do"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.conf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = gingergarlic-local
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "generating self-signed code-signing certificate…"
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -config "$TMP/cert.conf" >/dev/null 2>&1

# -legacy: macOS `security import` only reads PKCS12 with 3DES/SHA1, not
# OpenSSL 3's default AES-256/SHA256. A non-empty password is also required
# (empty-password MAC verification fails on import).
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout pass:gingergarlic -name "$IDENTITY" >/dev/null 2>&1

echo "importing into your login keychain…"
echo "  (if macOS pops a dialog asking to allow access to the key, click Always Allow)"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P gingergarlic -T /usr/bin/codesign -A

# Note: a self-signed cert shows as NOT_TRUSTED and won't appear under
# "valid identities only" — that's fine, codesign can still sign with it, and
# TCC keys the Accessibility grant to this stable identity instead of the
# per-build hash.
echo "✅ created signing identity:"
security find-identity -p codesigning | grep "$IDENTITY" || true
