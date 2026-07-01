# ── CoreDNS (null when install_coredns = false) ───────────────────────────────

output "coredns_addon_version" {
  description = "Resolved version of the installed CoreDNS managed add-on. Null when install_coredns = false."
  value       = one(module.coredns[*].addon_version)
}

output "coredns_addon_arn" {
  description = "ARN of the CoreDNS managed add-on. Null when install_coredns = false."
  value       = one(module.coredns[*].addon_arn)
}

# ── AWS Load Balancer Controller (null when install_lb_controller = false) ─────

output "lb_controller_role_arn" {
  description = "ARN of the IRSA role assumed by the LB Controller service account. Null when the controller is not installed or lbc_use_pod_identity = true."
  value       = one(module.lb_controller[*].role_arn)
}

output "lb_controller_role_name" {
  description = "Name of the LB Controller IRSA role. Null when the controller is not installed or lbc_use_pod_identity = true."
  value       = one(module.lb_controller[*].role_name)
}
