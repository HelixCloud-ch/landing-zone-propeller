output "role_arn" {
  description = "ARN of the IRSA role for the vpc-cni add-on's aws-node ServiceAccount."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the IRSA role for vpc-cni."
  value       = aws_iam_role.this.name
}

output "addon_version" {
  description = "Resolved version of the installed vpc-cni add-on."
  value       = module.vpc_cni.addon_version
}
