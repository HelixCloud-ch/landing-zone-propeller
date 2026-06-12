# Redis

Deploys an ElastiCache replication group (Valkey engine by default, Redis OSS
compatible) with encryption, optional AUTH, and configurable replicas.

## What it deploys

- **Subnet group** from the data tier subnets
- **Security group** with configurable ingress (CIDRs or SG references)
- **ElastiCache replication group** (single shard, primary + replicas)
- TLS in-transit and at-rest encryption enabled by default

## Engine choice

The default engine is **Valkey 8.0** — an open-source Redis fork with full wire
compatibility. It's 20% cheaper than Redis OSS on ElastiCache with identical
API and client library support. Set `engine = "redis"` and
`engine_version = "7.1"` if you specifically need Redis OSS.

## Pipeline wiring

```yaml
stages:
  - name: data
    steps:
      - project: redis
        target: workload-account
        depends_on: [workload-vpc]
        inputs:
          - name: workload-vpc.vpc_id
            var: vpc_id
          - name: workload-vpc.subnet_ids_by_tier
            var: subnet_ids_json
        outputs:
          - name: primary_endpoint
          - name: port
          - name: connection_url
          - name: security_group_id
```

The `subnet_ids_json` input is the JSON-encoded tier map from the VPC project.
The project decodes it and uses the `data` tier by default (configurable via
`subnet_tier`).

## Consumer tfvars

Only `region` and `identifier` are required:

```hcl
region     = "eu-central-2"
identifier = "my-redis"

# Allow ROSA worker nodes to connect
allowed_cidrs = ["10.16.0.0/24"]
```

## Connecting from ROSA

Applications in ROSA connect using the primary endpoint output. With TLS
enabled (default), use `rediss://` scheme:

```
rediss://<primary_endpoint>:6379
```

Common client libraries (ioredis, redis-py, lettuce) support TLS natively.

## Cost

With `cache.t4g.small` (default) + 1 replica in eu-central-2:

- ~$0.034/hr × 2 nodes = ~$49/month on-demand
- Reserved (1yr, no upfront): ~$22/month

Valkey pricing is 20% lower than equivalent Redis OSS nodes.

## Node types

To list available node types and engine versions in your region:

```bash
# Available node types
aws elasticache describe-reserved-cache-nodes-offerings \
  --region eu-central-2 \
  --query 'ReservedCacheNodesOfferings[].CacheNodeType' \
  --output text | tr '\t' '\n' | sort -u

# Available engine versions
aws elasticache describe-cache-engine-versions \
  --region eu-central-2 \
  --query 'CacheEngineVersions[].[Engine,EngineVersion]' \
  --output table
```

Ref:
[Supported node types](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheNodes.SupportedTypes.html) |
[Selecting node sizes](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/nodes-select-size.html)
