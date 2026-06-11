# ROSA RBAC

Grants cluster roles to htpasswd users on a ROSA HCP cluster using the `rosa`
CLI. Runs after the IDP is configured so users exist in the cluster's auth
system.

## What it does

- Logs into OCM via service account credentials
- Grants each user in `config.json` their specified cluster role using
  `rosa grant user`

## Configuration

Create a `config.json` in your consumer project directory:

```
platforms/<name>/projects/<project-name>/config.json
```

```json
[
  { "username": "alice", "role": "cluster-admin" },
  { "username": "bob", "role": "dedicated-admin" }
]
```

This file is overlaid onto the project at bundle time and read by the justfile
during apply.

## Pipeline wiring

```yaml
- name: cluster-config
  steps:
    - project: rosa-rbac
      source: rosa-rbac
      target: workload-account
      depends_on: [rosa-idp]
      inputs:
        - name: rosa-cluster.cluster_name
          var: cluster_name
```

## Available roles

Common roles: `cluster-admin`, `dedicated-admin`, `admin`, `edit`, `view`.

See
[Default cluster roles (OpenShift)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/authentication_and_authorization/using-rbac#default-roles_using-rbac)
for the full list.

Ref:
[Granting cluster-admin rights (ROSA)](https://cloud.redhat.com/learning/learn:getting-started-red-hat-openshift-service-aws-rosa/resource/resources:granting-cluster-admin-rights-users-red-hat-openshift-service-aws)

## Requirements

- `rosa` CLI (auto-installed by the init recipe)
- OCM service account credentials in Secrets Manager (same secret used by
  rosa-cluster, default: `propeller/rosa/ocm-token`)
- IDP must be applied first (users must exist before roles can be bound)

## Idempotency

Safe to run multiple times. `rosa grant user` is a no-op if the user already has
the role.
