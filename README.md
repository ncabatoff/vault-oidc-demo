# Using an Auth0 OIDC Provider with Vault

## Step 0: Install prerequisites.

You will need Vault 1.1+ and jq in your $PATH.

## Step 1: Create Auth0 account

Go to https://auth0.com and sign up, then verify yourself using the email they'll send you.

You get to choose a domain, I kept their suggested domain dev-9wgh3m41.auth0.com

## Step 2: Configure an Auth0 application

### Record your settings in a file named .env

In the Auth0 browser tab go to

  -> Application -> Default App -> Settings
  
We'll use Default App in this example, but if you're using the one created for
the tester application (see Notes section below) stick with that one, it doesn't 
matter.

Create a file in the same directory as this checkout named `.env`, and populate
it based on the values in the Auth0 Settings configuration tab:

```bash
AUTH0_DOMAIN=your-domain.auth0.com
AUTH0_CLIENT_ID=your-client-id
AUTH0_CLIENT_SECRET=your-secret
```

If you've done the Auth0 tutorial and downloaded the tester application this may
already be done.

### Set callback URLs

Still in 

  -> Application -> Default App -> Settings

modify the field Allowed Callback URLs, adding

```
http://localhost:8200/ui/vault/auth/oidc/oidc/callback,
http://localhost:8250/oidc/callback
```

Hit the `SAVE CHANGES` button.

## Step 3: Run testdemo1.sh and sign up to create your Auth0 provider user.

testdemo1 will:
- kill any currently running vault
- read your .env file
- spin up a vault server in dev mode
- configure it for your Auth0 OIDC provider using the values in .env
- do a `vault login`, which will open your browser for you to authenticate
  
When the browser window opens, choose Sign Up to create an account.
If all goes according to plan you should now be logged in at your terminal.

```bash
$ ./testdemo1.sh
Success! Uploaded policy: adm
Success! Uploaded policy: dev
Success! Enabled oidc auth method at: oidc/
Success! Data written to: auth/oidc/config
Success! Data written to: auth/oidc/role/demo
Complete the login via your OIDC provider. Launching browser to:

    https://dev-9wgh3m41.auth0.com/authorize?client_id=YVKcd_XIIBnsFKVxGYywBI91LLvSGxDd&nonce=908c20f03d8a90416a7ce6debacde11cac16559f&redirect_uri=http%3A%2F%2Flocalhost%3A8250%2Foidc%2Fcallback&response_type=code&scope=openid&state=93dd5b05269cf454b1eda65ed4ca86f4ad547db4


Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                s.RY3Qa8FgrZRSqj3qncQPMHJ1
token_accessor       fic3huc61Cn0sK569uguCnVH
token_duration       768h
token_renewable      true
token_policies       ["default" "dev"]
identity_policies    []
policies             ["default" "dev"]
token_meta_role      demo
```

From the command line you should be able to read but not write KV secrets,
because the 'dev' policy testdemo1 associates by default with OIDC logins
only has read/list privs on KV secrets.
  
```bash
export VAULT_ADDR=http://localhost:8200 
VAULT_TOKEN=       vault kv put secret/foo bar=1  # will fail
VAULT_TOKEN=myroot vault kv put secret/foo bar=1  # works
VAULT_TOKEN=       vault kv get secret/foo        # works
```

You should also be able to login using OIDC in the [vault ui](http://localhost:8200/ui).

## Step 4: Configure Groups in Auth0

We're going to use Auth0 app metadata to provide our grouping behaviour.
There are many ways to do grouping, but this is one of the simplest.

In Auth0: 
- -> Users & Roles -> Users
- Click on your user
- Under Metadata -> app_metadata, modify the json to look like:
```json
    {
      "roles": [
        "admin"
      ]
    }
```

In Auth0:
- -> Rules
- Click `+CREATE YOUR FIRST RULE`
- Choose the `empty rule` template
- Call it "Set user roles", and use this rule definition:
```javascript
function (user, context, callback) {
  user.app_metadata = user.app_metadata || {};
  context.idToken["https://example.com/roles"] = user.app_metadata.roles || [];
  callback(null, user, context);
}
```
- Click `SAVE`

Note that you can't use an Auth0 domain here for the context, not even the one 
they gave you.  For our purposes example.com is fine.

## Step 5: Run testdemo2.sh

testdemo2 does exactly what testdemo1 does, but also configures a `groups_claim` on
the OIDC auth method, and creates a group and group alias that link the claim 
with the group.

### groups_claim

`vault write auth/oidc/role/demo` now has the argument 
`groups_claim="https://example.com/roles"`, which is where our Auth0 rule is storing
the app_metadata roles field inside the JWT id_token coming back from the provider.

### group

The following asks Vault to create an external group with the (arbitrary) name
auth0-admin, and captures the group id for use in the next line.  

Anyone in this group will automatically get the `adm` policy.
  
```bash
gid=$(vault write -format=json identity/group \
    name="auth0-admin" \
    policies="adm" \
    type="external" \
    metadata=organization="Auth0 Users" | jq -r .data.id)
```

### group alias

Finally we ask Vault to create a group alias such that anything coming in 
via the OIDC auth method (based on mount_accessor) will have its groups_claim 
list checked to see if it contains an element `"admin"`; if so, the resulting
token will be associated with auth0-admin's policies, and the user will be
added to the external group.
  
```
vault write identity/group-alias name="admin" \
    mount_accessor=$(vault auth list -format=json  | jq -r '."oidc/".accessor') \
    canonical_id="${gid}"
```

### Running testdemo2

```bash
$ ./testdemo2.sh
Success! Uploaded policy: adm
Success! Uploaded policy: dev
Success! Enabled oidc auth method at: oidc/
Success! Data written to: auth/oidc/config
Success! Data written to: auth/oidc/role/demo
Key             Value
---             -----
canonical_id    01a7d5c0-5d5e-e713-b98b-d54cd8477d27
id              9e6007b2-7a64-4109-7be3-218285af757d
Complete the login via your OIDC provider. Launching browser to:

    https://dev-9wgh3m41.auth0.com/authorize?client_id=YVKcd_XIIBnsFKVxGYywBI91LLvSGxDd&nonce=e2097891fcabb5a3a7c2a3771fa98d35d0b4467d&redirect_uri=http%3A%2F%2Flocalhost%3A8250%2Foidc%2Fcallback&response_type=code&scope=openid&state=8319ce725d2abfec6af37fa53ddbe238e57560e8


Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                s.9g8zEGxbsXu3TpAMvrVWBC3a
token_accessor       1OchQQ7TsPBp7UgF1gnoeYYl
token_duration       768h
token_renewable      true
token_policies       ["default" "dev"]
identity_policies    ["adm"]
policies             ["adm" "default" "dev"]
token_meta_role      demo
```

Now you should see that your login session has write privileges to KV secrets
because your group has the "adm" policy attached:

```bash
export VAULT_ADDR=http://localhost:8200 
VAULT_TOKEN=       vault kv put secret/foo bar=1  # works
VAULT_TOKEN=       vault kv get secret/foo        # works
```

## Notes

Your groups_claim should always return a list, at worst an empty one.  If it
returns null the user will be unable to authenticate.

The demo scripts send Vault log output to /tmp/vault.log, if you're having problems
it may be worth looking at that.

Do the tutorial Auth0 suggests if you like.  As part of it they invite
you to download a tester application in the language of your choice.
I found this helpful, e.g. so I could use log statements to dump
the JWT token returned by Auth0.  Besides you don't really control
what Vault is doing, so I found it nice to get something working
that's designed to work with Auth0 first, then iterate from there
to getting Vault working.

