# API server ingress security group.
#
# Deliberately created here in the project rather than in the eks-cluster
# module, so security-group management can be centralized later: a dedicated SG
# plane can supply IDs via additional_security_group_ids and this project-local
# SG can be dropped without touching the module. The module only consumes the
# resulting IDs (vpc_config.security_group_ids).
#
# Created only when api_server_ingress_cidrs is non-empty. These groups are
# attached to the cluster's cross-account ENIs so connected networks (a
# VPC-attached deploy runner, operator VPN/TGW ranges) can reach the private API
# endpoint on 443 — the EKS-managed cluster security group only permits its own
# members.

locals {
  create_api_ingress_sg = length(var.api_server_ingress_cidrs) > 0

  # Externally/centrally-provided SG IDs plus the project-local one (when created).
  cluster_additional_security_group_ids = concat(
    var.additional_security_group_ids,
    local.create_api_ingress_sg ? [aws_security_group.api_ingress[0].id] : [],
  )
}

resource "aws_security_group" "api_ingress" {
  count = local.create_api_ingress_sg ? 1 : 0
  # checkov:skip=CKV2_AWS_5: attached to the EKS cluster cross-account ENIs via module.cluster vpc_config.security_group_ids; the indirection through the module and count is invisible to checkov's static graph.

  name        = "${var.cluster_name}-eks-api-ingress"
  description = "Inbound 443 to the EKS private API endpoint from connected networks."
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "api_ingress" {
  for_each = local.create_api_ingress_sg ? toset(var.api_server_ingress_cidrs) : toset([])

  security_group_id = aws_security_group.api_ingress[0].id
  description       = "Kubernetes API server access from a connected network."
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}
