# ROSA ECR Pull

Attaches cross-account ECR pull permissions to the ROSA HCP worker node IAM
role. Once applied, all pods on the cluster can pull images from the specified
ECR registry without any per-pod configuration (no imagePullSecrets or service
account annotations needed).

## How it works

ROSA HCP worker nodes are provisioned with a predefined IAM role. This project
attaches an inline IAM policy to that role granting `ecr:GetAuthorizationToken`
and image pull actions on the target ECR registry. The kubelet on each node uses
the role's credentials to authenticate to ECR transparently.

Ref:
[Configuring a ROSA cluster to pull images from ECR (Red Hat)](https://cloud.redhat.com/experts/rosa/ecr/)
Ref:
[Configuring ROSA for fine-grained ECR access (AWS Blog)](https://aws.amazon.com/blogs/ibm-redhat/configuring-rosa-for-fine-grained-ecr-repository-access/)

## What it deploys

- **Inline IAM policy** (`ecr-cross-account-pull`) on the ROSA worker node role,
  granting pull access to all repositories in the specified ECR account.

## Pipeline wiring

```yaml
- name: cluster-config
  steps:
    - project: rosa-ecr-pull
      target: workload-account
      inputs:
        - name: rosa-cluster.cluster_name
          var: cluster_name
```

## Consumer tfvars

```hcl
region         = "eu-central-2"
ecr_account_id = "111111111111"  # account hosting ECR
```

## Worker role naming

By default, the project looks for an IAM role named
`<cluster_name>-operator-cloud-credentials`. This is the ROSA HCP convention
when using `operator_role_prefix = "<cluster_name>-operator"`.

If your cluster uses a different naming pattern, override with:

```hcl
worker_role_name = "ManagedOpenShift-HCP-ROSA-Worker-Role"
```

## After deploy

No cluster-side configuration needed. Once the policy is attached, any pod can
reference images from the ECR registry:

```yaml
spec:
  containers:
    - image: 111111111111.dkr.ecr.eu-central-2.amazonaws.com/my-app:latest
```
