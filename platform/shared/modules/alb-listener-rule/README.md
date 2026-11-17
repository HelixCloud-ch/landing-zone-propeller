# alb-listener-rule

Creates one rule on an existing listener. The module takes the listener ARN, so a later project can add rules to a listener that another project owns.

## Usage

```hcl
module "listener_rule" {
  source = "../../../shared/modules/alb-listener-rule"

  listener_arn = module.listener.arn
  priority     = 10
  name         = "apps"

  conditions = {
    host_headers  = ["apps.example.com"]
    path_patterns = ["/api/*"]
  }

  action = {
    type             = "forward"
    target_group_arn = module.target_group.arn
  }
}
```

## Priority

`priority` is required, an integer from 1 to 50000. The load balancer evaluates the rules of a listener from the lowest priority to the highest, and the first match wins. The default action runs when no rule matches. Priorities must be unique per listener. Two rules with the same priority fail at apply.

The module has no automatic priority on purpose. Without one, AWS gives the next free priority in the order of creation, so the order would depend on the order in which Terraform creates the rules, not on the configuration.

Changing the priority updates the rule in place (`SetRulePriorities`). In one apply, a rule can only move to a priority that no rule holds before the apply. A swap of two priorities in one apply fails with `PriorityInUse`, and AWS keeps both rules unchanged. To reorder, move the rules to free values, for example a new range (10, 20 → 200, 100).

## Design notes

- A rule needs at least one condition. All non-empty condition groups must match (AND). Each `http_headers` and `query_strings` item is its own condition. A rule allows at most five condition values in total (AWS limit).
- Each host header and path pattern has at most 128 characters.
- `http_headers` must not name `Host`. Use `host_headers`.
- `source_ips` takes IPv4 CIDR blocks.
- Not supported: weighted forward, authentication actions, `transform` and `regex_values`.

## The action object

The object is the same as in `alb-listener`. `type` is `forward`, `redirect` or `fixed-response`, and only the matching block is set.

| `type` | Required | Rules |
|--------|----------|-------|
| `forward` | `target_group_arn` | A target group ARN. |
| `redirect` | `redirect` | `status_code` is `HTTP_301` or `HTTP_302`. `protocol` is `HTTP`, `HTTPS` or `#{protocol}`. `path` starts with `/`. |
| `fixed-response` | `fixed_response` | `status_code` is 2XX, 4XX or 5XX. `content_type` is one of the five supported types. |

## References

- [Listener rules](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/listener-update-rules.html)
- [Rule condition types](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/rule-condition-types.html)
- [aws_lb_listener_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule)
