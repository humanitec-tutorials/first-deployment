output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.cluster.name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.cluster.endpoint
}

output "cluster_ca_certificate" {
  description = "EKS cluster CA certificate"
  value       = aws_eks_cluster.cluster.certificate_authority[0].data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "EKS cluster OIDC issuer URL"
  value       = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

output "runner_role_arn" {
  description = "Humanitec runner IAM role ARN"
  value       = aws_iam_role.humanitec_runner.arn
}

output "runner_id" {
  description = "Humanitec runner ID"
  value       = module.runner.runner_id
}

output "runner_rule_id" {
  description = "Humanitec runner rule ID"
  value       = module.runner.runner_rule_id
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.vpc.id
}

output "subnet_ids" {
  description = "Subnet IDs"
  value       = aws_subnet.subnet[*].id
}

output "cnpg_helm_release" {
  description = "CloudNativePG helm release for dependency tracking"
  value       = helm_release.cloudnative_pg.id
}
