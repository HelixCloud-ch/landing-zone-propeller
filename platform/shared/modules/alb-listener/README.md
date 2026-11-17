# alb-listener

Creates one listener (HTTP or HTTPS) on a load balancer, with its default action and extra certificates.

## Usage

```hcl
module "listener" {
  source = "../../../shared/modules/alb-listener"

  load_balancer_arn = module.alb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arns  = [var.default_certificate_arn, var.extra_certificate_arn]

  default_action = {
    type           = "fixed-response"
    fixed_response = { status_code = "404" }
  }
}
```

## Design notes

- For HTTPS, the first certificate is the default. Each other one becomes an `aws_lb_listener_certificate`. An HTTP listener takes no certificate.
- The default `ssl_policy` is `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`. Only `TLS13-1-2` and `TLS13-1-3` policies pass, so TLS 1.2 is the minimum. The policy is ignored for HTTP.
- An HTTP listener must redirect to HTTPS. Set `allow_plain_http = true` to forward plain HTTP.

## The action object

`default_action` has a `type` and the one block that matches it. The other blocks stay null.

| `type` | Required | Rules |
|--------|----------|-------|
| `forward` | `target_group_arn` | A target group ARN. |
| `redirect` | `redirect` | `status_code` is `HTTP_301` or `HTTP_302`. `protocol` is `HTTP`, `HTTPS` or `#{protocol}`. `path` starts with `/`. |
| `fixed-response` | `fixed_response` | `status_code` is 2XX, 4XX or 5XX. `content_type` is `text/plain`, `text/css`, `text/html`, `application/javascript` or `application/json`. |

The `alb-listener-rule` module uses the same object.

## References

- [Listeners](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html)
- [HTTPS listener](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/create-https-listener.html)
- [Security policies](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html)
- [aws_lb_listener](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener)
