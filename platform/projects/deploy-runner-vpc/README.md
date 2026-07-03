# VPC Deploy Runner

Provisions a CodeBuild project attached to a VPC private subnet. This allows
propeller to execute terraform (or helm/kubectl) against resources with private
endpoints — e.g. private EKS or ROSA clusters.

## Why a separate runner?

The default `deploy-runner` (provisioned via Service Catalog during bootstrap)
runs outside any VPC. It can reach public AWS APIs but cannot connect to private
cluster endpoints. This VPC-attached runner coexists alongside the default one
and is used only by steps that need private network access.

## How it works

1. The project creates a CodeBuild project with `vpc_config` pointing at the
   consumer's private subnets.
2. Steps that need VPC access specify `runner: deploy-runner-vpc` in the
   pipeline.yaml.
3. The autopilot Lambda reads the `runner` field and invokes the VPC-attached
   CodeBuild project instead of the default one.

## Pipeline wiring

```yaml
stages:
  - name: network
    steps:
      - project: workload-vpc
        # ...
      - project: deploy-runner-vpc
        source: deploy-runner-vpc
        target: my-account
        depends_on: [workload-vpc]
        inputs:
          - name: workload-vpc.vpc_id
            var: vpc_id
          - name: workload-vpc.subnet_ids_by_tier
            var: subnet_ids_json
          - name: "@landing-zone/workload-parameters.autopilot_role_arn"
            var: caller_arn
          - name: "@landing-zone/workload-parameters.operations_account_id"
            var: caller_account_id
          - name: "@landing-zone/workload-parameters.bundle_bucket_name"
            var: bundle_bucket_name
        outputs:
          - name: project_name

  - name: cluster
    steps:
      - project: eks-cluster
        # ...

  - name: cluster-addons
    steps:
      - project: eks-lb-controller
        source: eks-lb-controller
        target: my-account
        runner: deploy-runner-vpc     # ← uses the VPC runner
        inputs:
          - name: eks-cluster.cluster_name
            var: cluster_name
```

## Consumer tfvars

Most values come via pipeline wiring. The consumer must set:

```hcl
region       = "eu-central-2"
project_name = "deploy-runner-vpc"   # matches the `runner:` value in pipeline steps
subnet_tier  = "app"
```
