locals {
  cluster_name = "${var.prefix}-first-deployment-eks"
}

# VPC and Networking
resource "aws_vpc" "vpc" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.prefix}-first-deployment-vpc"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "subnet" {
  count = 2

  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.10.${count.index}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # Required for EKS
  map_public_ip_on_launch = true

  tags = {
    Name                                     = "${var.prefix}-first-deployment-subnet-${count.index + 1}"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.prefix}-first-deployment-igw"
  }
}

# Route Table
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.prefix}-first-deployment-rt"
  }
}

resource "aws_route_table_association" "main" {
  count = 2

  subnet_id      = aws_subnet.subnet[count.index].id
  route_table_id = aws_route_table.main.id
}

# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster" {
  name = "${var.prefix}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

# EKS Cluster
resource "aws_eks_cluster" "cluster" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = aws_subnet.subnet[*].id
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller
  ]
}

# EKS Node Group IAM Role
resource "aws_iam_role" "eks_nodes" {
  name = "${var.prefix}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

# EKS Node Group
resource "aws_eks_node_group" "nodes" {
  cluster_name    = aws_eks_cluster.cluster.name
  node_group_name = "${var.prefix}-first-deployment-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.subnet[*].id

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry
  ]
}

# OIDC Provider for EKS
data "tls_certificate" "eks" {
  url = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# IAM Role for Humanitec Runner (IRSA)
resource "aws_iam_role" "humanitec_runner" {
  name = "${var.prefix}-humanitec-runner-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:${kubernetes_namespace.runner.metadata[0].name}:${var.prefix}-humanitec-runner-sa"
          }
        }
      }
    ]
  })
}

# Policy for Humanitec Runner
resource "aws_iam_role_policy" "humanitec_runner" {
  name = "${var.prefix}-humanitec-runner-policy"
  role = aws_iam_role.humanitec_runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:*",
          "eks:*",
          "ec2:*",
          "elasticloadbalancing:*",
          "iam:*",
          "s3:*",
          "sqs:*",
          "sns:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Create IAM user for inner runner (jobs need explicit AWS credentials)
resource "aws_iam_user" "runner_user" {
  name = "${var.prefix}-humanitec-runner"
  path = "/humanitec/"
}

# Create access key for the runner user
resource "aws_iam_access_key" "runner_key" {
  user = aws_iam_user.runner_user.name
}

# Create a standalone policy with the same permissions as the role policy
resource "aws_iam_policy" "humanitec_runner_user" {
  name = "${var.prefix}-humanitec-runner-user-policy"
  path = "/humanitec/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:*",
          "eks:*",
          "ec2:*",
          "elasticloadbalancing:*",
          "iam:*",
          "s3:*",
          "sqs:*",
          "sns:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach the policy to the IAM user
resource "aws_iam_user_policy_attachment" "runner_policy" {
  user       = aws_iam_user.runner_user.name
  policy_arn = aws_iam_policy.humanitec_runner_user.arn
}

# Read the AWS credentials template
data "local_file" "aws_credentials_template" {
  filename = "${path.module}/../../aws-credentials.tpl"
}

# Secret for AWS credentials with actual access key credentials
resource "kubernetes_secret" "aws_creds" {
  metadata {
    name      = "${var.prefix}-canyon-runner-aws-creds"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  type = "Opaque"

  data = {
    "credentials" = templatefile(data.local_file.aws_credentials_template.filename, {
      aws_access_key_id     = aws_iam_access_key.runner_key.id
      aws_secret_access_key = aws_iam_access_key.runner_key.secret
      region                = var.aws_region
    })
  }
}

# AWS Auth ConfigMap
resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = aws_iam_role.eks_nodes.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups = [
          "system:bootstrappers",
          "system:nodes",
        ]
      },
      {
        rolearn  = aws_iam_role.humanitec_runner.arn
        username = "humanitec-runner"
        groups = [
          "system:masters",
        ]
      },
    ])
  }
}
