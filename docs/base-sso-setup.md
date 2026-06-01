# Base SSO setup

How to configure and operate the `base-sso` project, which lands the identity
baseline of the landing zone: the four base permission sets (`ReadOnly`,
`PowerUser`, `Admin`, `IdentityOperator`) and the IdentityOperators group, then
pre-assigns `IdentityOperator` to that group on the management account.

IdentityOperators do access management only: they assign the existing permission
sets to users and groups across accounts and manage the base groups. They do not
create or edit permission sets. To onboard more operators later, just add them to
the IdentityOperators group — no further apply of this project is needed.

## Prerequisites

- IAM Identity Center is enabled as an **organization instance** in the home
  Region (bootstrap [step 3](../bootstrap/README.md)). The `region` you set for
  `base-sso` must match that home Region.
- If you intend to use an external identity provider, decide that **before**
  the first apply — the chosen mode drives the group source and the directory
  permissions IdentityOperators receive, and switching later means re-applying
  with a different group.

## Configuration

All `base-sso` inputs live in the consumer overlay:

```
landing-zone/projects/base-sso/terraform/config.auto.tfvars
```

The two variables that decide the setup path:

| Variable | Default | Purpose |
|---|---|---|
| `external_idp` | `false` | Selects the identity source mode (local directory vs. external IdP). |
| `identity_operators_group_name` | `"aws-identity-operators"` | Display name of the IdentityOperators group. |

Pick the matching section below.

## Case 1 — Identity Center directory (local, `external_idp = false`)

This is the default. Terraform **creates** the IdentityOperators group in the
Identity Center directory and IdentityOperators get full directory admin
(`AWSSSODirectoryAdministrator`), so they can create the other base groups
(`aws-admins`, `aws-powerusers`, `aws-readonly-users`) at runtime.

### Evaluate the group name

The group is created with the default display name `aws-identity-operators`.
Change it only if a different naming convention has been agreed for the landing
zone — for example to align with a corporate group-naming standard. Set it
explicitly in the overlay:

```hcl
external_idp                  = false
region                        = "eu-central-2"
identity_operators_group_name = "aws-identity-operators"  # rename if a different convention was agreed
```

Because Terraform owns the group in this mode, renaming it after the first
apply replaces the group (destroy + create) and drops its memberships and the
account assignment, which are then re-created on apply. Decide the name up
front to avoid re-onboarding operators.

### Create the first user and add them to the group

Terraform creates the group and the `IdentityOperator` assignment but
intentionally does **not** add any member. Add the first operator (typically
the platform admin) manually after the first apply, then they manage everyone
else from the console.

Console:

1. Open the [IAM Identity Center console](https://console.aws.amazon.com/singlesignon)
   in the home Region.
2. **Users** → **Add user**. Provide the username, email, first name, and last
   name. Choose **Send an email with password setup instructions** so the user
   sets their own password (the invitation expires in seven days). See
   [Add users to your Identity Center directory](https://docs.aws.amazon.com/singlesignon/latest/userguide/addusers.html).
3. **Groups** → open the IdentityOperators group → **Add users to group** →
   select the new user. See
   [Add users to groups](https://docs.aws.amazon.com/singlesignon/latest/userguide/adduserstogroups.html).
4. Find the sign-in URL to hand to the operator: in the IAM Identity Center
   console, the **Dashboard** shows the **AWS access portal URL** (also under
   **Settings**). It looks like `https://d-xxxxxxxxxx.awsapps.com/start`.

CLI (equivalent). First set the identity store and group IDs. You can read them
from the project outputs (`identity_store_id`, `identity_operators_group_id`),
or resolve them with the CLI as shown below:

```bash
# Identity Center home Region (must match base-sso's `region`)
export AWS_REGION=eu-central-2

# Identity store ID of the organization instance
export IDENTITY_STORE_ID=$(aws sso-admin list-instances \
  --query 'Instances[0].IdentityStoreId' --output text)

# IdentityOperators group ID — use the name set in identity_operators_group_name
export IDENTITY_OPERATORS_GROUP_ID=$(aws identitystore get-group-id \
  --identity-store-id "$IDENTITY_STORE_ID" \
  --alternate-identifier '{"UniqueAttribute":{"AttributePath":"displayName","AttributeValue":"aws-identity-operators"}}' \
  --query GroupId --output text)
```

Then create the user and add them to the group:

```bash
# Create the user (returns a UserId). CLI-created users have no password —
# trigger a password reset from the console afterwards so the user can sign in.
USER_ID=$(aws identitystore create-user \
  --identity-store-id "$IDENTITY_STORE_ID" \
  --user-name jane.doe \
  --name "GivenName=Jane,FamilyName=Doe" \
  --display-name "Jane Doe" \
  --emails "Type=work,Value=jane.doe@example.com,Primary=true" \
  --query UserId --output text)

# Add the user to the IdentityOperators group
aws identitystore create-group-membership \
  --identity-store-id "$IDENTITY_STORE_ID" \
  --group-id "$IDENTITY_OPERATORS_GROUP_ID" \
  --member-id "UserId=$USER_ID"
```

Finally, print the default sign-in URL to hand to the operator (this is the
default form:

```bash
echo "https://${IDENTITY_STORE_ID}.awsapps.com/start"
```

Once the user is a member, they can sign in and start operating — see
[First operator: signing in and operating](#first-operator-signing-in-and-operating).

## Case 2 — External identity provider (`external_idp = true`)

Set this when Identity Center is fed by an external IdP (e.g. Microsoft Entra
ID, Okta) over SCIM. In this mode Terraform does **not** create the group — it
looks it up via a data source — and IdentityOperators get directory read-only
(`AWSSSODirectoryReadOnly`), because any local write would be overwritten by the
next SCIM sync.

### Connect the IdP and provision the group first

The IdP connection (SAML metadata exchange, SCIM endpoint and bearer token) is
configured manually — see the external IdP note in bootstrap
[step 3](../bootstrap/README.md) and
[Connect an external identity provider](https://docs.aws.amazon.com/singlesignon/latest/userguide/manage-your-identity-source-idp.html).
The IdentityOperators group must already exist in Identity Center (provisioned
from the IdP via SCIM) before you apply `base-sso`; the data source lookup fails
at plan time by design if the group is not present. Note that
[SCIM provisions only users and groups assigned to the IAM Identity Center
application in the IdP](https://docs.aws.amazon.com/singlesignon/latest/userguide/provision-automatically.html),
so make sure the operators group is in scope of the sync.

### Match the agreed group name

`identity_operators_group_name` must match, **exactly**, the display name of the
group as it is synced from the IdP. The default `aws-identity-operators` rarely
matches a corporate directory, so confirm the name that was agreed for the IdP
and set it explicitly:

```hcl
external_idp                  = true
region                        = "eu-central-2"
identity_operators_group_name = "aws-identity-operators"  # set to the exact group name agreed in the IdP
```

A mismatch (including case or whitespace) causes the lookup to fail at plan
time. The name is the contract between the IdP and this project — agree on it
with whoever owns the IdP before applying.

### First user and membership

Do **not** create users or manage memberships in the Identity Center console in
this mode — after SCIM is enabled, the console no longer allows it and any
manual change is reverted on the next sync. Provision the first operator and add
them to the IdentityOperators group **in the IdP**, then let SCIM sync them in.
Once synced and a member of the group, they sign in and operate the same way as
in the local case — see
[First operator: signing in and operating](#first-operator-signing-in-and-operating).
The only difference is the directory access level: read-only, so groups are
managed in the IdP rather than in the Identity Center console (detailed below).

## First operator: signing in and operating

Once the first operator is a member of the IdentityOperators group, the steps to
sign in are identical in both scenarios; only group management differs.

### 1. Sign in to the AWS access portal

1. Open the AWS access portal URL. It looks like
   `https://d-xxxxxxxxxx.awsapps.com/start` or
   `https://<your-subdomain>.awsapps.com/start`. Find it in the IAM Identity
   Center console under **Settings** → **AWS access portal URL**.
2. Sign in with the assigned credentials. On first sign-in with a one-time
   password (local mode) the operator is prompted to set a new password and
   register MFA; with an external IdP they use their corporate credentials.
3. On the **Accounts** tab the management account appears with the
   `IdentityOperator` role. Choosing it opens the console (or yields CLI
   credentials) with the IdentityOperator permissions.

See [Signing in to the AWS access portal](https://docs.aws.amazon.com/singlesignon/latest/userguide/howtosignin.html).

### 2. Create the base groups

`base-sso` deliberately creates only the IdentityOperators group. As a
recommended baseline, create the other base groups — `aws-admins`,
`aws-powerusers`, `aws-readonly-users` — to mirror the three non-operator
permission sets. This is only a suggestion: the operator has full freedom to
name the groups differently or create whatever group structure fits the
organization. Create them where they belong for the chosen identity source:

- **Local mode (`external_idp = false`)**: the operator has directory admin, so
  they create the groups directly in the Identity Center console (**Groups** →
  **Create group**) or via `aws identitystore create-group`. See
  [Add groups to your Identity Center directory](https://docs.aws.amazon.com/singlesignon/latest/userguide/addgroups.html).
- **External IdP mode (`external_idp = true`)**: the operator has directory
  read-only, so the groups are created **in the IdP** and synced via SCIM —
  they cannot be created in the Identity Center console. See
  [Provision users and groups from an external identity provider using SCIM](https://docs.aws.amazon.com/singlesignon/latest/userguide/provision-automatically.html).

### 3. Assign permission sets to accounts

With the groups in place, the operator assigns the base permission sets
(`ReadOnly`, `PowerUser`, `Admin`) on the target accounts. The recommendation is
to assign to **groups** rather than individual users, so membership changes
alone grant or revoke access — but assigning directly to users is also possible
where it makes sense. In the IAM Identity Center console:
**Multi-account permissions** → **AWS accounts** → select the account(s) →
**Assign users or groups** → pick the group (or user) and the permission set. See
[Assign user or group access to AWS accounts](https://docs.aws.amazon.com/singlesignon/latest/userguide/assignusers.html).

## Verify

After the first apply and after onboarding the first operator:

- The four permission sets and the IdentityOperators group exist in the
  Identity Center console.
- `IdentityOperator` is assigned to the group on the management account
  (Terraform creates this; it is the `identity_operator_self` assignment).
- The first operator can sign in to the AWS access portal and see the
  `IdentityOperator` role for the management account, then proceed to create the
  base groups and assign permission sets (see
  [First operator: signing in and operating](#first-operator-signing-in-and-operating)).

## References

- [Add users to your Identity Center directory](https://docs.aws.amazon.com/singlesignon/latest/userguide/addusers.html)
- [Add users to groups](https://docs.aws.amazon.com/singlesignon/latest/userguide/adduserstogroups.html)
- [Add groups to your Identity Center directory](https://docs.aws.amazon.com/singlesignon/latest/userguide/addgroups.html)
- [Signing in to the AWS access portal](https://docs.aws.amazon.com/singlesignon/latest/userguide/howtosignin.html)
- [Assign user or group access to AWS accounts](https://docs.aws.amazon.com/singlesignon/latest/userguide/assignusers.html)
- [Connect an external identity provider](https://docs.aws.amazon.com/singlesignon/latest/userguide/manage-your-identity-source-idp.html)
- [Provision users and groups from an external identity provider using SCIM](https://docs.aws.amazon.com/singlesignon/latest/userguide/provision-automatically.html)
