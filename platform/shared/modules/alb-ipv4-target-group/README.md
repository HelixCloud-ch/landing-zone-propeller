# alb-ipv4-target-group

Creates one ALB target group of type `ip` (IPv4) and attaches a list of IP addresses to it. Other target types (`instance`, `lambda`, `alb`) and IPv6 are not supported. They get their own module when needed. A caller can also forward to a target group created elsewhere by its ARN (see the `alb` project).

## Usage

```hcl
module "target_group" {
  source = "../../../shared/modules/alb-ipv4-target-group"

  name       = "apps-router"
  vpc_id     = "vpc-0123456789abcdef0"
  target_ips = ["10.0.1.10", "10.0.2.10"]

  health_check = {
    matcher = "200-499"
  }
}
```

## Design notes

- The default is HTTPS on port 443. Unset health check fields use the AWS default, except the protocol: it follows the target group protocol, because AWS would otherwise probe with plain HTTP.
- An empty `target_ips` list is valid and creates no attachment.
- The attachment key is the IP. Changing the list adds or removes single attachments.
- `target_ips` accepts private IPv4 addresses in `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` and `100.64.0.0/10`. AWS also accepts other VPC CIDRs. The module is stricter on purpose.
- Leave `target_availability_zone` null for targets in the VPC. AWS derives the zone. Use `all` for IPs outside the VPC.
- A change of `port`, `protocol`, `protocol_version` or `name` replaces the group. With a fixed name, the replacement fails while a listener uses the old group. Change the name together with the port.

## References

- [Target groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html)
- [Health checks](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html)
- [aws_lb_target_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group)
