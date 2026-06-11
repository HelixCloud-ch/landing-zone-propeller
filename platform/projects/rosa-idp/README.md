# ROSA IDP - htpasswd users

Configures an htpasswd identity provider on a ROSA HCP cluster, creating users
with credentials from a pre-existing Secrets Manager secret.

## Prerequisites

Create a Secrets Manager secret with your users:

```sh
aws secretsmanager create-secret \
  --name "propeller/rosa/<cluster_name>/htpasswd-users" \
  --secret-string '[{"username":"alice","password":"SecurePass123!"},{"username":"bob","password":"SecurePass456!"}]'
```

Passwords must be at least 14 characters with uppercase, lowercase, and numbers
or symbols.

## Pipeline wiring

```yaml
- name: cluster-config
  steps:
    - project: rosa-idp
      target: workload-account
      depends_on: [rosa-cluster]
      inputs:
        - name: rosa-cluster.cluster_id
          var: cluster_id
        - name: rosa-cluster.cluster_name
          var: cluster_name
```

## Consumer tfvars

```hcl
region = "eu-central-2"
# cluster_id comes from pipeline input
```

## How it works

The users secret lives outside Terraform's lifecycle. It's created once and
never destroyed. Every time the cluster is recreated, this project re-applies
the same users with the same passwords.
