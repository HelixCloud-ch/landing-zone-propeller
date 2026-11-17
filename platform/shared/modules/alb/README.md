# alb

Creates one Application Load Balancer, with an optional WAF web ACL association. The module takes plain IDs and ARNs. It creates no security group, listener or target group.

## Usage

```hcl
module "alb" {
  source = "../../../shared/modules/alb"

  name               = "apps"
  subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  security_group_ids = ["sg-0123456789abcdef0"]
}
```

## Design notes

- The load balancer is internal by default. `ip_address_type` is `ipv4`.
- Secure defaults are fixed or preset: `drop_invalid_header_fields = true`, `desync_mitigation_mode = "defensive"`, `enable_deletion_protection = true`.
- Set `enable_deletion_protection = false` and apply before `destroy`.
- The name has 1-32 characters (letters, digits, hyphens) and must not start with `internal-`. The API reserves that prefix.
- At least two subnets are required. AWS checks that they are in different Availability Zones.
- Access logs, connection logs and the web ACL are optional. The caller owns the S3 bucket (with the ELB log delivery policy) and the web ACL.

## References

- [Application Load Balancers](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html)
- [Load balancer attributes](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/edit-load-balancer-attributes.html)
- [Access logs](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-access-logs.html)
- [aws_lb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb)
