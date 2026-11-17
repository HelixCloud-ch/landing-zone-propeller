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

## Design notes

- A rule needs at least one condition. All non-empty condition groups must match (AND).
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
