# alb

Creates one Application Load Balancer (ALB) with `ip` target groups, listeners and listener rules in the account and VPC of the step.

The project is generic. A typical use is an internal ALB in front of a router that sits behind a Network Load Balancer (NLB). TLS ends at the ALB, HTTP redirects to HTTPS, known hosts go to the targets, and unknown hosts get a fixed 404.

## How it is built

The project composes four shared modules: [`alb`](../../shared/modules/alb), [`alb-ipv4-target-group`](../../shared/modules/alb-ipv4-target-group), [`alb-listener`](../../shared/modules/alb-listener) and [`alb-listener-rule`](../../shared/modules/alb-listener-rule). The project calls the last three with `for_each`, one module instance per item. Rules for one item live in the module. Rules across items (unknown keys, duplicate ports, duplicate priorities) live in the project, as `validation` blocks.

The project creates target groups of type `ip` (IPv4) only, from `ip_target_groups`. Other types (`instance`, `lambda`, `alb`) will be added when needed, each with its own project variable, so the change does not break existing configs. Until then, a target group of any type can be created elsewhere and passed in by ARN (see "Target groups owned elsewhere").

The project holds the security group itself. At most one group exists per instance, and a module would have no second caller. The `alb` module only takes security group IDs.

## Keys are state addresses

`ip_target_groups`, `listeners` and `listener_rules` are maps. Each key is the Terraform state address of the item (`module.listener["https"]`). Rename a key and Terraform recreates the item. For a target group, this also recreates its attachments. Keys match `^[a-z0-9-]{1,32}$`.

Actions and rules refer to other items by key: `target_group_key`, `listener_key` and `certificate_keys`. The project turns the keys into ARNs. The modules never see keys.

## Security group modes

- Created (default): `create_security_group = true`. The project opens each listener port to `security_group_ingress_cidrs`. It opens egress only to the target ports, the numeric health check ports and `security_group_egress_ports`, on `security_group_egress_cidrs`. With no egress CIDR, the VPC CIDR is used. No all-protocol rule exists.
- Given: `create_security_group = false` and `security_group_ids`. Only the given groups are attached. Use this when a central plane owns the groups.
- Both: the created group plus extra IDs from `security_group_ids`. The created group is first in the `security_group_ids` output.

An internal ALB rejects the literal `0.0.0.0/0` as an ingress CIDR. Other very wide ranges, such as two `/1` blocks, are not checked.

## Certificates

`certificate_arns` maps a key to an ACM certificate ARN. A listener lists keys in `certificate_keys`. The first key is the default certificate. The others are added to the listener.

This project does not request or validate certificates. The ARN can come from any source: an ACM request, a validation step, or an import. The `arns` output of the `acm-certificates` project has the same key shape, so the map wires as a whole.

## Listeners and rules

HTTPS listeners need a TLS policy with a TLS 1.2 minimum. The default is `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`. An HTTP listener must redirect to HTTPS. To forward plain HTTP, set `allow_plain_http = true` on that listener.

Fields of `ip_target_groups` items:

- `name` (default `<name>-<key>`, at most 32 characters), `port` (443), `protocol` (`HTTPS`), `protocol_version`, `deregistration_delay`.
- `target_ips`, `target_availability_zone` (`all` for IPs outside the VPC).
- `health_check`: `protocol`, `port` (`traffic-port` or a number), `path`, `matcher`, `interval`, `timeout`, `healthy_threshold`, `unhealthy_threshold`. Unset fields use the AWS default, except `protocol`, which follows the target group. Health checks are always on for `ip` targets.

Fields of `listeners` items: `port`, `protocol` (`HTTP` or `HTTPS`), `certificate_keys`, `ssl_policy`, `allow_plain_http` and `default_action`.

Fields of `listener_rules` items: `listener_key`, `priority`, `name` (Name tag, default the key), `conditions` and `action`. A `forward` rule on an HTTP listener needs `allow_plain_http = true` on it.

Rule order comes only from `priority`, never from the order of the keys in the map. Terraform sorts map keys, so the map order carries no meaning. `priority` is required (1 to 50000), and the project rejects two rules with the same priority on one listener. The load balancer evaluates a listener's rules from the lowest priority up, and the first match wins. Leave gaps (10, 20, 30) so that a new rule fits between two others without renumbering. In one apply, a rule can only move to a priority that no rule holds before the apply: a swap of two priorities fails with `PriorityInUse`. To reorder, move the rules to free values (for example a new range). See the [`alb-listener-rule`](../../shared/modules/alb-listener-rule) README.

An action is one of three shapes:

- `forward`: `target_group_key`.
- `redirect`: `redirect` with `status_code` (`HTTP_301` or `HTTP_302`), `protocol`, `host`, `port`, `path` and `query`.
- `fixed-response`: `fixed_response` with `status_code`, `content_type` and `message_body`.

Conditions combine with AND: `host_headers`, `path_patterns`, `http_request_methods`, `source_ips`, `http_headers` and `query_strings`. Each `http_headers` and `query_strings` item is its own condition. The values inside one group are OR. AWS allows at most five match evaluations (values) per rule. Weighted forward, authentication actions and regex conditions are not supported.

Targets that answer 404 or 503 for an unknown host need a health check `matcher` such as `200-499`, or a dedicated health port. The ALB sends no SNI to the targets. Health checks carry no custom `Host` header.

## Target groups owned elsewhere

`existing_target_group_arns` maps a key to the ARN of a target group that another project owns, of any target type. Actions refer to these keys with `target_group_key`, as to the keys of `ip_target_groups`. The two maps share one key space, so a key must not be in both.

- The created security group computes its egress ports from `ip_target_groups` only. Add the ports of the external groups (traffic and health check) to `security_group_egress_ports`, or attach a group that allows them through `security_group_ids`.
- AWS allows a target group to be used by the listeners of one load balancer only ([create a target group](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/create-target-group.html)). Do not pass a group that another ALB already uses.
- The `target_group_*` outputs list only the groups this project creates.

Listeners and listener rules are always created by this project, on its own load balancer. Rules on a listener that another project owns (for example, route self-service for an application team) belong in a separate project that calls the `alb-listener-rule` module with that `listener_arn`.

## Target IPs

Target IPs come from the item (`target_ips`) or from the pipeline input `target_ips_by_group`. The pipeline value replaces the item list. A group without an entry keeps its own list. An empty list is valid and creates no attachments.

IPs must be private IPv4 addresses in `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` or `100.64.0.0/10`. This is stricter than AWS, which also accepts other VPC CIDRs.

The step that supplies the IPs must publish an empty list, never `null`. A pipeline publishes `null` as the string `None`, and that fails the type check of `target_ips_by_group` at plan.

## Pipeline wiring

```yaml
- project: alb-1
  source: propeller:alb
  target: <workload account>
  depends_on: [<target-ip-step>, acm-certificates-1]
  inputs:
    - name: workload-vpc.vpc_id
      var: vpc_id
    - name: workload-vpc.subnet_ids_by_tier
      var: subnet_ids
      expr: "<tier>"
    - name: acm-certificates-1.arns
      var: certificate_arns
    - name: <target-ip-step>.<ip list output>
      var: target_ips_by_group
      expr: '{ "router": $ }'
  outputs:
    - name: alb_alias
    - name: alb_dns_name
    - name: target_group_arns
    - name: security_group_ids
```

A `dns-record` step in the zone account publishes the name. Wire `alb-1.alb_alias` into it with `expr: '{ "<key>": { "name": "<record>", "type": "A", "alias": $ } }'`.

## Consumer config

Everything except the wired inputs goes in `config.auto.tfvars`. See `terraform/config.auto.tfvars.example` for a full file. A short version:

```hcl
region = "eu-central-2"
name   = "apps"

security_group_ingress_cidrs = ["10.0.0.0/8"]
enable_deletion_protection   = false

ip_target_groups = {
  router = { port = 443, protocol = "HTTPS" }
}

listeners = {
  https = {
    port             = 443
    protocol         = "HTTPS"
    certificate_keys = ["apps"]
    default_action = {
      type           = "fixed-response"
      fixed_response = { status_code = "404" }
    }
  }
}

listener_rules = {
  apps = {
    listener_key = "https"
    priority     = 10
    conditions   = { host_headers = ["apps.example.com"] }
    action       = { type = "forward", target_group_key = "router" }
  }
}
```

## Inputs and outputs

Required inputs, besides the wired ones:

| Input | Why |
|-------|-----|
| `region` | Provider region. |
| `name` | Load balancer name and prefix of derived names. |
| `vpc_id` | VPC of the load balancer and target groups. |
| `subnet_ids` | At least two subnets in different Availability Zones. |
| `security_group_ingress_cidrs` | Needed while `create_security_group` is true. |

Outputs (no output is ever null):

| Output | Value |
|--------|-------|
| `alb_arn`, `alb_arn_suffix`, `alb_dns_name`, `alb_zone_id` | Load balancer attributes. |
| `alb_alias` | `{ name, zone_id }`, the `alias` shape of `dns-record`. |
| `security_group_ids` | Attached groups. The created group is first. |
| `target_group_arns`, `target_group_arn_suffixes`, `target_group_names`, `target_ips` | Maps keyed by `ip_target_groups` key. |
| `listener_arns`, `listener_rule_arns` | Maps keyed by `listeners` and `listener_rules` key. |

## Operational notes

- First apply: the subnets, the certificate ARNs and the target IPs must exist before the step runs. Put the steps that supply them in `depends_on`.
- Import: to adopt an existing load balancer, import it at its module address, then plan until the diff is empty:

  ```bash
  terraform import 'module.alb.aws_lb.this' <load-balancer-arn>
  terraform import 'module.listener["https"].aws_lb_listener.this' <listener-arn>
  ```

- Deletion protection: the module default is `true`, and it blocks `destroy`. Set `enable_deletion_protection = false` and apply before a destroy, or before sleep in `destroy` mode.
- Target group replacement: a change of `port`, `protocol`, `protocol_version` or `name` replaces the group. With a fixed name, the replacement fails while a listener still uses the old group. Change the name together with the port.
- Sleep and wake: in a test environment, use `destroy` mode, so nothing is billed while the environment sleeps. Wake runs a full apply with the new target IPs. The ALB gets a new DNS name on every wake. Put the `dns-record` step that publishes the alias in the same preset with `apply-on-wake`, after this step.

  ```yaml
  sleep_presets:
    light:
      alb-1: destroy
      alb-dns-1: apply-on-wake
  ```

  With `apply-on-wake` on this step, sleep does nothing and wake re-applies. While the environment sleeps, the target group holds stale IPs and the ALB answers with 5xx.
- Access and connection logs, and the WAF web ACL, are optional inputs. The caller owns the bucket (with its ELB log delivery policy) and the web ACL.

## What does NOT belong here

- Certificate requests, validation and import. Use `acm-certificates` or another source.
- DNS records. Use `dns-record` with the `alb_alias` output.
- Target discovery. Another step supplies the IPs.
- Rules on a listener of another load balancer (a separate project with the `alb-listener-rule` module).
- Security groups of the targets.
- The NLB, the WAF web ACL and the log bucket.

## References

- [Application Load Balancers](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html)
- [Target groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html)
- [Health checks](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html)
- [Listeners](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html)
- [HTTPS listener](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/create-https-listener.html)
- [Security policies](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html)
- [Access logs](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-access-logs.html)
- [aws_lb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb)
- [dns-record project](../dns-record)
