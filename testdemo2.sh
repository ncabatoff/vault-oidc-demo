#!/usr/bin/env bash

source .env
# AUTH0_DOMAIN="dev-9wgh3m41.auth0.com/" # Note trailing slash/
# AUTH0_CLIENT_ID="YVKcd_XIIBnsFKVxGYywBI91LLvSGxDd"
# AUTH0_CLIENT_SECRET="8IUitrjaXG4MdNBd5qXVs-gexouQYo6gF4HRBrsafnYr1SpoNMoGPyU1g-WqZbDC"

# Assumes vault 1.1+ is in $PATH.
# Kills any running vault server.

kill $(ps |grep 'vault server' |awk '{print $1}') 2>/dev/null
set -e
vault server -dev -dev-root-token-id=myroot -log-level=debug > /tmp/vault.log 2>&1 &
sleep 1
export VAULT_TOKEN=myroot
export VAULT_ADDR=http://127.0.0.1:8200

cat - > /tmp/policy.hcl <<EOF
path "/secret/*" {
	capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
vault policy write adm /tmp/policy.hcl

cat - > /tmp/devpolicy.hcl <<EOF
path "/secret/*" {
	capabilities = ["read", "list"]
}
EOF
vault policy write dev /tmp/devpolicy.hcl

vault auth enable oidc

vault write auth/oidc/config \
    oidc_discovery_url="https://$AUTH0_DOMAIN/" \
    oidc_client_id="$AUTH0_CLIENT_ID" \
    oidc_client_secret="$AUTH0_CLIENT_SECRET" \
    default_role="demo"

vault write auth/oidc/role/demo \
    bound_audiences="$AUTH0_CLIENT_ID" \
    allowed_redirect_uris="http://localhost:8200/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="http://localhost:8250/oidc/callback" \
    user_claim="sub" \
    policies=dev \
    groups_claim="https://example.com/roles"

gid=$(vault write -format=json identity/group \
    name="auth0-admin" \
    policies="adm" \
    type="external" \
    metadata=organization="Auth0 Users" | jq -r .data.id)

vault write identity/group-alias name="admin" \
    mount_accessor=$(vault auth list -format=json  | jq -r '."oidc/".accessor') \
    canonical_id="${gid}"

VAULT_TOKEN= vault login -method=oidc role=$VAULT_ROLE