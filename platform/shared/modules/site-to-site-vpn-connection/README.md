# site-to-site-vpn-connection

Creates one AWS Site-to-Site VPN connection for an existing customer gateway, with its optional static routes. The target is a transit gateway, a virtual private gateway, or nothing.

## Usage

```hcl
module "vpn" {
  source = "../../../shared/modules/site-to-site-vpn-connection"

  name                = "onprem-hq"
  customer_gateway_id = "cgw-0123456789abcdef0"
  target_type         = "tgw"
  target_gateway_id   = "tgw-0123456789abcdef0"

  tunnel_options = {
    ike_versions                 = ["ikev2"]
    phase1_encryption_algorithms = ["AES256-GCM-16"]
    phase2_encryption_algorithms = ["AES256-GCM-16"]
    phase1_dh_group_numbers      = [20]
    phase2_dh_group_numbers      = [20]
  }
}
```

The module has no provider block and no backend. It works with a plain `terraform apply`.

## Design notes

- The module is one connection. The caller uses `for_each` to make several. The customer gateway, the virtual private gateway and route propagation stay with the caller.
- `target_type` is a plain string, so it is known at plan time. `target_gateway_id` must be null for `none` and set for the other values. The module sets either `transit_gateway_id` or `vpn_gateway_id` on the connection.
- `routing = "static"` sets `static_routes_only`. `static_routes` creates one `aws_vpn_connection_route` per CIDR. AWS allows this only for a virtual private gateway, so the module rejects other cases at plan time.
- `tunnel_options` is written to both tunnels. Every field is null by default, so AWS defaults apply. Per-tunnel options are not supported. They can be added later without a breaking change. Changing an option restarts the tunnel.
- Pre-shared keys default to `Standard` storage (VPN service; the provider also keeps them in state). `SecretsManager` is opt-in; only then is `preshared_key_arn` set. The module has no key input and no key output.
- A log group ARN turns on JSON logs for both tunnels. The module creates no log group.
- Detach check: the `unassociated_target` check reads the real connection. When `target_type` is `none` and AWS still shows a target, it shows a warning. AWS cannot detach a target, so the connection must be recreated (new tunnel IPs and new keys). A check is a warning, not an error.
- Two connections on the same customer gateway and the same virtual private gateway collapse into one in AWS. The caller must avoid this. With a transit gateway it is allowed.

## Outputs

`id`, `arn`, `transit_gateway_attachment_id` (meaningful only for `tgw`), `tunnels` (addresses, inside addresses and BGP ASN of both tunnels), and `preshared_key_arn`.

## References

- [aws_vpn_connection](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_connection)
- [Tunnel options](https://docs.aws.amazon.com/vpn/latest/s2svpn/VPNTunnels.html)
- [Modify the target gateway](https://docs.aws.amazon.com/vpn/latest/s2svpn/modify-vpn-target.html)
- [VPN logs](https://docs.aws.amazon.com/vpn/latest/s2svpn/monitoring-logs.html)
- [site-to-site-vpn project](../../../projects/site-to-site-vpn)
