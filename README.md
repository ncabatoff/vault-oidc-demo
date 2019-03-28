# Step 0: Install prerequisites.

You will need Vault 1.1+ and jq in your $PATH.

# Step 1: Create Auth0 account

Go to https://auth0.com and sign up, then verify yourself using the email they'll send you.

You get to choose a domain, I kept their suggested domain dev-9wgh3m41@auth0.com

Do the suggested tutorial if you like.  As part of it they invite
you to download a tester application in the language of your choice.
I found this helpful, e.g. so I could use log statements to dump
the JWT token returned by Auth0.  Besides you don't really control
what Vault is doing, so I found it nice to get something working
that's designed to work with Auth0 first, then iterate from there
to getting Vault working.

# Step 2: Configure an Auth0 application

## Record your settings locally

In the Auth0 browser tab go to

  Application -> Default App -> Settings
  
We'll use Default App in this example, but if you're using the one created for
the tester application stick with that one, it doesn't matter.

Create a file in the same directory as this checkout named ".env", and populate
it like so based on the values in the Auth0 Settings configuration tab.

```bash
AUTH0_DOMAIN=your-domain.auth0.com
AUTH0_CLIENT_ID=your-client-id
AUTH0_CLIENT_SECRET=your-secret
```

If you've done the tutorial and downloaded the helper application this may
already be done.

## Set callback URLs

Still in 

  Application -> Default App -> Settings

modify the field Allowed Callback URLs, adding

```
http://localhost:8200/ui/vault/auth/oidc/oidc/callback
http://localhost:8250/oidc/callback
```

Hit the `SAVE CHANGES` button.

# Step 3: Run testdemo1.sh

```bash
./testdemo1.sh
```

testdemo1 will:
- read your .env file
- kill any currently running vault
- spin up a vault in dev mode
- configure it for your Auth0 OIDC provider
- do a 'vault login', which will open your browser for you to authenticate
  
Choose Sign Up to create an account.

If all goes according to plan you should now be logged in at your terminal.

Output from testdemo1:

```
Key                  Value
---                  -----
token                s.wIxSBK0hd6d19GSi6nIVfudK
token_accessor       RTgWQ6BHFfhA4RzttwUJEQXn
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
VAULT_TOKEN=       vault kv put secret/foo bar=1  # will fail
VAULT_TOKEN=myroot vault kv put secret/foo bar=1  # works
VAULT_TOKEN=       vault kv get secret/foo        # works
```

# Step 4: Configure Groups

We're going to use Auth0 app metadata to provide our grouping behaviour.
There are many ways to do grouping, but this is one of the simplest.

In Auth0: 
- Users & Roles -> Users
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
- Rules
- Click `+CREATE YOUR FIRST RULE`
- Call it "Set user roles", and use this rule definition:
```javascript
function (user, context, callback) {
  user.app_metadata = user.app_metadata || {};
  context.idToken["https://example.com/roles"] = user.app_metadata.roles || [];
  callback(null, user, context);
}
```
- Click `SAVE`

Note that you can't use an auth0 domain here for the context, not even the one 
they gave you.  For our purposes example.com is fine.

# Step 5: Run testdemo2.sh

```bash
./testdemo2.sh
```

testdemo2 does exactly what testdemo1 does, but also configures a groups_claim on
the OIDC auth method, and creates a group and group alias that link the claim 
with the group.

Let's break this down:
- `vault write auth/oidc/role/demo` now has the argument 
  `groups_claim="https://example.com/roles"`, which is where our Auth0 rule is storing
  the app_metadata roles field inside the JWT id_token coming back from the provider.
- The following asks Vault to create an external group named auth0-admin, and captures
  the group id for use in the next line.  Note that anyone in this group will 
  automatically get the "adm" policy applied.
```bash
gid=$(vault write -format=json identity/group \
    name="auth0-admin" \
    policies="adm" \
    type="external" \
    metadata=organization="Auth0 Users" | jq -r .data.id)
```
- Finally we ask Vault to create a group alias such that anything coming in 
  via the OIDC auth method (based on mount_accessor) will have its groups_claim 
  list checked to see if it contains an element "admin"; if so, the resulting
  token will be associated with the auth0-admin's policies, and the user will be
  added to the external group.
```
vault write identity/group-alias name="admin" \
    mount_accessor=$(vault auth list -format=json  | jq -r '."oidc/".accessor') \
    canonical_id="${gid}"
```

Output from testdemo2:

```
Key                  Value
---                  -----
token                s.I6TuCWDWaGZuhyNvLohEpb8v
token_accessor       Qx1MfHw5jzqKT1VMyxKYL9a8
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
VAULT_TOKEN=       vault kv put secret/foo bar=1  # works
VAULT_TOKEN=       vault kv get secret/foo        # works
```

# Notes

Your groups_claim should always return a list, at worst an empty one.  If it
returns null the user will be unable to authenticate.
