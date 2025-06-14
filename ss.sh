# Unset just in case
unset GLOBAL_AGENT_HTTP_PROXY GLOBAL_AGENT_HTTPS_PROXY HTTP_PROXY HTTPS_PROXY NO_PROXY NODE_EXTRA_CA_CERTS
export NUMBER_OF_PROXIES=1
# Set BOTH sets to your working proxy
export GLOBAL_AGENT_HTTP_PROXY=http://127.0.0.1:61809
export GLOBAL_AGENT_HTTPS_PROXY=http://127.0.0.1:61809
export SOCKS_PROXY=socks://127.0.0.1:61809
export HTTP_PROXY=http://127.0.0.1:61809
export HTTPS_PROXY=http://127.0.0.1:61809
export NO_PROXY=127.0.0.1,localhost
export GLOBAL_AGENT_NO_PROXY=localhost,aaa,127.0.0.1
export CORS_ORIGINS="http://127.0.0.1:8888"

# Explicitly point Node to the same CAs curl used (just in case)
export NODE_EXTRA_CA_CERTS="/etc/ssl/certs/ca-certificates.crt"


# Verify one of them
echo "Set HTTPS_PROXY to: $HTTPS_PROXY"
echo "Set NODE_EXTRA_CA_CERTS to: $NODE_EXTRA_CA_CERTS"


# --- VERY IMPORTANT: Run Flowise IMMEDIATELY in THIS SAME terminal ---
pnpm  start
