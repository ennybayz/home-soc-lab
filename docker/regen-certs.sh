#!/bin/sh
# Manual cert regeneration with proper DNS + IP SANs.
# Replaces the buggy wazuh-certs-generator:0.0.2 output.
# Run from inside an alpine/openssl container, with the certs dir
# mounted at /certs.

set -e
cd /certs

echo "[*] Cleaning existing certs..."
rm -f *.pem *.key

# Root CA
echo "[*] Generating root CA..."
openssl genrsa -out root-ca.key 4096 2>/dev/null
openssl req -x509 -new -nodes -key root-ca.key -sha256 -days 3650 \
  -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=root-ca" \
  -out root-ca.pem 2>/dev/null

# Manager-trust CA (filebeat config expects a separate file).
# We use the same CA, just copied under a second name.
cp root-ca.pem  root-ca-manager.pem
cp root-ca.key  root-ca-manager.key

# Helper: generate a leaf cert with DNS + IP SANs. Args: name dns ip
gen_cert() {
  NAME="$1"
  DNS="$2"
  IP="$3"

  echo "[*] Generating cert for ${NAME} (DNS:${DNS}, IP:${IP})..."

  # DN order MUST match what wazuh.indexer.yml whitelists for admin_dn
  # and nodes_dn. OpenSSL writes attributes in the order listed below.
  cat > "/tmp/${NAME}.cnf" <<EOF
[req]
default_bits = 2048
prompt = no
distinguished_name = dn
req_extensions = req_ext

[dn]
C = US
L = California
O = Wazuh
OU = Wazuh
CN = ${DNS}

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DNS}
IP.1  = ${IP}
EOF

  cat > "/tmp/${NAME}.ext" <<EOF
subjectAltName = @alt_names
extendedKeyUsage = serverAuth,clientAuth
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment

[alt_names]
DNS.1 = ${DNS}
IP.1  = ${IP}
EOF

  openssl genrsa -out "${NAME}.key" 2048 2>/dev/null

  # admin cert is named admin-key.pem in the existing compose,
  # leaf certs use <name>-key.pem - rename for non-admin certs below.

  openssl req -new -key "${NAME}.key" -out "/tmp/${NAME}.csr" \
    -config "/tmp/${NAME}.cnf" 2>/dev/null

  openssl x509 -req -in "/tmp/${NAME}.csr" \
    -CA root-ca.pem -CAkey root-ca.key -CAcreateserial \
    -out "${NAME}.pem" -days 3650 -sha256 \
    -extfile "/tmp/${NAME}.ext" 2>/dev/null

  rm -f "/tmp/${NAME}.cnf" "/tmp/${NAME}.csr" "/tmp/${NAME}.ext"
}

# Admin cert authenticates to the OpenSearch security plugin.
gen_cert "admin" "admin" "127.0.0.1"
mv admin.key admin-key.pem

# Service certs - DNS names and IPs must match docker-compose.yml
gen_cert "wazuh.indexer"   "wazuh.indexer"   "172.26.0.20"
mv wazuh.indexer.key   wazuh.indexer-key.pem

gen_cert "wazuh.manager"   "wazuh.manager"   "172.26.0.10"
mv wazuh.manager.key   wazuh.manager-key.pem

gen_cert "wazuh.dashboard" "wazuh.dashboard" "172.26.0.30"
mv wazuh.dashboard.key wazuh.dashboard-key.pem

# Permissions - readable by container processes
chmod 644 *.pem
# Lab-grade perms: world-readable keys. Containers run as non-root and
# bind-mounted Windows volumes don't preserve owner/group, so 644 is the
# only mode that reliably works across container users. Do NOT use these
# certs in production.
chmod 644 *.key *-key.pem

echo ""
echo "[+] Done. Cert SANs:"
for f in wazuh.indexer.pem wazuh.manager.pem wazuh.dashboard.pem; do
  echo ""
  echo "--- $f ---"
  openssl x509 -in "$f" -noout -text | grep -A1 "Subject Alternative"
done
