# site-to-site-vpn

Creates AWS Site-to-Site VPN connections and their customer gateways, and attaches them to a transit gateway, to a virtual private gateway, or to nothing.

## Targets

Each connection has its own target. The project derives it from the fields of the connection. In this order, the first rule that matches wins:

1. `unattached = true`: no target.
2. `vpn_gateway_key`: a virtual private gateway from `vpn_gateways`.
3. `transit_gateway_id` on the connection, or else the project-level `transit_gateway_id`: a transit gateway.
4. Otherwise: no target.

A connection can set only one of `transit_gateway_id`, `vpn_gateway_key` and `unattached`. The project-level `transit_gateway_id` is a default, so a pipeline can wire it as a plain input. Use `unattached = true` to keep one connection without a target when a default is set. The output `connection_targets` shows the result for each connection.

| Target | Account that runs the step | Gateway |
|--------|----------------------------|---------|
| Transit gateway | The account that owns the transit gateway. | `transit_gateway_id`. |
| Virtual private gateway | The account that owns the VPC. | An item of `vpn_gateways`. |
| None | Any account. | None. The connection is not associated. |

AWS lets only the owner of the target gateway attach to it. One instance runs in one account, so connections with different targets can share an instance only when the targets are in the same account. Otherwise use one instance for each account.

No target lets you create the tunnels first and attach them later. Moving a live connection from no target to a virtual private gateway, or from a virtual private gateway to a transit gateway, updates it in place. The tunnels are down for about 5 minutes. The connection ID, the tunnel IPs and the pre-shared keys stay the same. See [Modify the target gateway](https://docs.aws.amazon.com/vpn/latest/s2svpn/modify-vpn-target.html).

Moving back to no target does not work. AWS cannot detach a target. Terraform reports success, nothing changes, and a diff stays forever. The module has a `check` that shows a warning in that case. To really detach, recreate the connection. This gives new tunnel IPs and new pre-shared keys, so the on-premises device must be configured again.

## Customer gateways

`customer_gateways` creates one gateway per device. A connection picks a gateway by key (`customer_gateway_key`) or by the ID of an existing gateway (`customer_gateway_id`). Exactly one of the two must be set.

One gateway can serve several connections in these cases:

- All of them are on transit gateways (ECMP, see the examples).
- They are on different virtual private gateways. The AWS documentation allows this. It is not tested in the sandbox.

On the same virtual private gateway, a second connection on the same gateway returns the first connection in AWS. Two state entries would then own one connection. Two connections without a target on one gateway are rejected too, because attaching them later gives the same problem. The project rejects these cases.

The `name` of a gateway is its Name tag. It defaults to the key. Names must be unique in the project. Renaming only changes the tag. The key stays the state address.

`ip_address` and `bgp_asn` force a new gateway. Changing them recreates the gateway and every connection that uses it, with new tunnel IPs. `certificate_arn` is accepted already, so certificate authentication can be added later without a breaking change. Issuing the certificate is out of scope.

## Connections and tunnels

Each connection has two tunnels in two Availability Zones. This is fixed by AWS. For more tunnels, add more connections. Two devices with one connection each give four tunnels (`config-tgw-ha.auto.tfvars.example`). See [Redundant connections](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-redundant-connection.html) and [Quotas](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-limits.html).

`connections` is a map. The key is the stable id and the state address. Renaming a key destroys and recreates the connection. The same applies to the keys of `customer_gateways` and `vpn_gateways`. The Name tag is `name`, or the key when `name` is not set. Changing `name` only changes the tag. Outputs use the key.

Fields of a connection (all optional except the gateway choice):

| Field | Meaning |
|-------|---------|
| `name` | Name tag. Default: the key. Must be unique. |
| `customer_gateway_key` / `customer_gateway_id` | Gateway to use. Exactly one. |
| `transit_gateway_id` | Transit gateway of this connection. Overrides the project default. |
| `vpn_gateway_key` | Key of an item in `vpn_gateways`. |
| `unattached` | `true` keeps the connection without a target, also when a default is set. |
| `routing` | `bgp` (default) or `static`. |
| `static_routes` | On-premises CIDRs. Only with a `vpn_gateway_key` and `routing = "static"`. |
| `tunnel_bandwidth` | `standard` or `large`. `large` needs a transit gateway and no acceleration. |
| `enable_acceleration` | Accelerated VPN. Only on a transit gateway. |
| `local_ipv4_network_cidr`, `remote_ipv4_network_cidr` | Traffic selectors. Null keeps the AWS default. |
| `preshared_key_storage` | `Standard` (default) or `SecretsManager`. |
| `log_group_arn`, `bgp_log_group_arn` | Existing log groups for tunnel logs and BGP logs. |
| `tunnel_options` | Crypto and lifecycle options, applied to both tunnels. |
| `tunnel1_inside_cidr`, `tunnel2_inside_cidr` | Inside `/30` blocks from `169.254.0.0/16`. |

With a transit gateway, on-premises routes are not set here. BGP routes come from the attachment. Static routes for a transit gateway go to the transit gateway route tables, in the routing project. See [Route priority](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-route-priority.html).

### Tunnel options

Every option is `null` by default, so AWS chooses. The project does not force a crypto profile, because the device decides what is possible. The file `config-strict-crypto.auto.tfvars.example` has the recommended profile:

```hcl
tunnel_options = {
  ike_versions                 = ["ikev2"]
  phase1_encryption_algorithms = ["AES256-GCM-16"]
  phase2_encryption_algorithms = ["AES256-GCM-16"]
  phase1_integrity_algorithms  = ["SHA2-256"]
  phase2_integrity_algorithms  = ["SHA2-256"]
  phase1_dh_group_numbers      = [20]
  phase2_dh_group_numbers      = [20]
  dpd_timeout_action           = "restart"
  startup_action               = "start"
}
```

Use single values. AWS evaluates the proposals from the lowest value, so a short list prevents a downgrade. GCM does not need an integrity algorithm, but AWS still negotiates one in phase 1, so keep `SHA2-256`. Check that the device supports the profile before you apply it. Changing options on a live connection restarts the tunnels. Options are the same for both tunnels. See [Tunnel options](https://docs.aws.amazon.com/vpn/latest/s2svpn/VPNTunnels.html).

### Pre-shared keys

AWS generates the keys. The project has no key input and never outputs a key.

- `Standard` (default): AWS keeps the keys in the VPN service. Get them from the configuration file that you download from the console (Site-to-Site VPN connections, Download configuration). The provider also keeps them in the Terraform state, so protect the state bucket.
- `SecretsManager` (opt-in, per connection): AWS keeps the keys in a Secrets Manager secret and the API shows only its ARN. `preshared_key_arns` publishes the ARN. The deploy role then needs permission to create and delete the secrets that the VPN service makes for the connection. See [Change the Secrets Manager pre-shared key](https://docs.aws.amazon.com/vpn/latest/s2svpn/enhanced-security-tunnel.html).

Indicative permission areas of a narrow deploy role (check them against the current service authorization reference before you use them): EC2 VPN actions (customer gateway, VPN connection, VPN gateway, route propagation), plus Secrets Manager secret management only for `SecretsManager` storage.

### Logs

The project creates no log group and no alarm. Give the ARN of an existing log group. Encryption of the group and alarms belong to the logging project. See [VPN logs](https://docs.aws.amazon.com/vpn/latest/s2svpn/monitoring-logs.html).

## Virtual private gateways

`vpn_gateways` is a map. Each item is one gateway. It creates the gateway from a `vpc_id`, or it uses an existing `vpn_gateway_id`. Set exactly one of the two. A connection uses an item with `vpn_gateway_key`, and several connections can use the same item.

| Field | Meaning |
|-------|---------|
| `name` | Name tag of a created gateway. Default: the key. |
| `vpc_id` | Creates a gateway in this VPC. A VPC has at most one gateway, so a `vpc_id` can appear in only one item. |
| `vpn_gateway_id` | Uses an existing gateway. It can appear in only one item. |
| `amazon_side_asn` | ASN of a created gateway. Null uses the AWS default. Only with `vpc_id`. |
| `route_table_ids` | Route tables that receive the routes of the gateway (propagation). |

The ASN and the propagation belong to the gateway, not to a connection. This is why they are in the item. With one propagation for each route table, two connections on one gateway cannot create it twice.

The VPC side has two exclusive choices. Using both gives a dependency cycle, because the routes project needs the gateway ID and the propagation needs the route table IDs.

- Static VPC routes: run this project first. Feed one entry of its `vpn_gateway_ids` output to the routes project.
- Propagation: run the routes project first. Feed its route table IDs to `route_table_ids` of the item.

## Pipeline wiring

Transit gateway as the default target, in the network account:

```yaml
- project: site-to-site-vpn-onprem
  source: propeller:site-to-site-vpn
  target: network
  inputs:
    - name: "@landing-zone/workload-parameters.tgw_id"
      var: transit_gateway_id
  outputs:
    - name: transit_gateway_attachment_ids
    - name: connection_targets
    - name: tunnels
    - name: preshared_key_arns
```

Virtual private gateway in a workload account. The VPC project gives the VPC ID. The `expr` builds the map, as in `dns-record`. The routes project gets one gateway ID with `$lookup($, "main")`:

```yaml
- project: site-to-site-vpn-app
  source: propeller:site-to-site-vpn
  target: app
  depends_on: [vpc]
  inputs:
    - name: vpc.vpc_id
      var: vpn_gateways
      expr: '{ "main": { "vpc_id": $ } }'
  outputs:
    - name: vpn_gateway_ids
```

The pipeline publishes outputs as strings. Empty maps stay `{}`, and no output is null.

## Consumer configuration

`config.auto.tfvars` of the consumer:

```hcl
region = "eu-central-2"

# Default target. A pipeline wires this input.
transit_gateway_id = "tgw-0123456789abcdef0"

customer_gateways = {
  hq = {
    ip_address = "203.0.113.10"
    bgp_asn    = 65010
  }
}

connections = {
  hq = {
    customer_gateway_key = "hq"
  }
}
```

The folder `terraform/` has more examples:

- `config.auto.tfvars.example`: minimal, one gateway, one BGP connection on a transit gateway.
- `config-tgw-ha.auto.tfvars.example`: two devices, four tunnels.
- `config-tgw-ecmp.auto.tfvars.example`: two connections on one gateway. The transit gateway needs VPN ECMP support.
- `config-vgw-static.auto.tfvars.example`: new virtual private gateway, static routing, route propagation.
- `config-mixed.auto.tfvars.example`: a transit gateway connection, a virtual private gateway connection and a connection without a target in one instance.
- `config-unattached.auto.tfvars.example`: no target.
- `config-strict-crypto.auto.tfvars.example`: the strict tunnel profile.

## Required inputs and outputs

| Input | Note |
|-------|------|
| `region` | AWS region. |
| `transit_gateway_id` | Optional default target. |
| `vpn_gateways` | Optional. Needed for connections with a `vpn_gateway_key`. |
| `customer_gateways`, `connections` | The gateways and the connections. |

| Output | Content |
|--------|---------|
| `vpn_connection_ids`, `vpn_connection_arns` | By connection key. |
| `connection_targets` | `type` (`tgw`, `vgw` or `none`) and `gateway_id` of each connection, by connection key. |
| `transit_gateway_attachment_ids` | By connection key. Only connections on a transit gateway. |
| `tunnels` | Addresses, inside addresses and BGP ASN of both tunnels, by connection key. |
| `preshared_key_arns` | Secret ARNs, by connection key. Only for `SecretsManager`. |
| `customer_gateway_ids` | Created gateways, by gateway key. |
| `vpn_gateway_ids` | Created or given gateways, by `vpn_gateways` key. |

## Operational notes

- First apply: the tunnels are down until the device is configured. Read the tunnel addresses from `tunnels` and the keys from the secrets. The tunnels can need up to a few minutes to come up after the device is ready.
- Import: connections are in the module. Use the state address with the key, for example `terraform import 'module.connection["hq"].aws_vpn_connection.this' <vpn-connection-id>`. Import customer gateways as `aws_customer_gateway.this["hq"]`. Static routes have the address `module.connection["hq"].aws_vpn_connection_route.this["192.0.2.0/24"]`. Check the import ID format in the provider docs.
- Sleep and wake: leave this project out of the sleep preset. Destroy and recreate gives new tunnel IPs and new keys, and the device must be configured again. A connection costs money for each hour it exists, also with the tunnels down. See [AWS VPN pricing](https://aws.amazon.com/vpn/pricing/).
- Keys are state addresses: renaming a key in `customer_gateways`, `vpn_gateways` or `connections` recreates the object. Use `name` to change only the Name tag.

## What does NOT belong here

- Transit gateway route tables and on-premises routes in them. They belong in the routing project.
- VPC route tables and routes. They belong in the VPC routes project.
- Log groups, their encryption and alarms.
- Certificate issuing (a private CA).
- IPv6 tunnels, VPN Concentrator, and private IP VPN over Direct Connect.

## References

- [Tunnel options](https://docs.aws.amazon.com/vpn/latest/s2svpn/VPNTunnels.html)
- [Quotas](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-limits.html)
- [Modify the target gateway](https://docs.aws.amazon.com/vpn/latest/s2svpn/modify-vpn-target.html)
- [Architectures](https://docs.aws.amazon.com/vpn/latest/s2svpn/site-site-architectures.html)
- [Redundant connections](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-redundant-connection.html)
- [Route priority](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-route-priority.html)
- [VPN logs](https://docs.aws.amazon.com/vpn/latest/s2svpn/monitoring-logs.html)
- [Transit gateway VPN attachments](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-vpn-attachments.html)
- [aws_vpn_connection](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_connection)
- [AWS VPN pricing](https://aws.amazon.com/vpn/pricing/)
- [site-to-site-vpn-connection module](../../shared/modules/site-to-site-vpn-connection)
