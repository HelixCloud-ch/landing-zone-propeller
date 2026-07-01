# Composes the per-addon shared modules.
#
# CoreDNS is managed here only when install_coredns is true. Fargate clusters
# require it (the default self-managed CoreDNS cannot schedule without nodes);
# EC2 node-group clusters get a working CoreDNS from EKS by default, so the
# managed add-on is optional there (enable it only to pin/upgrade versions).
#
# The LB Controller's Helm release needs working in-cluster DNS to become
# ready. On a fresh Fargate cluster a single apply can race the CoreDNS add-on
# rollout, so the controller module depends_on the CoreDNS module. When
# install_coredns is false this reference resolves to an empty set and the
# dependency is a no-op (DNS is assumed already up, e.g. from EC2 node groups).

module "coredns" {
  count  = var.install_coredns ? 1 : 0
  source = "../../../shared/modules/eks-addon-coredns"

  cluster_name  = var.cluster_name
  addon_version = var.coredns_version
  compute_type  = var.coredns_compute_type
}

module "lb_controller" {
  count  = var.install_lb_controller ? 1 : 0
  source = "../../../shared/modules/eks-addon-lb-controller"

  cluster_name      = var.cluster_name
  region            = var.region
  vpc_id            = var.vpc_id
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider_url = var.oidc_provider_url
  chart_version     = var.lbc_chart_version
  chart_repository  = var.lbc_chart_repository
  role_name         = var.lbc_role_name
  use_pod_identity  = var.lbc_use_pod_identity

  create_service_account = var.lbc_create_service_account

  depends_on = [module.coredns]
}
