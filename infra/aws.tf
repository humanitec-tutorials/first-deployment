provider "aws" {
  region = var.aws_region
}

locals {
  create_aws = contains(var.enabled_cloud_providers, "aws")
  create_gcp = contains(var.enabled_cloud_providers, "gcp")
}

# VPC and networking
resource "aws_vpc" "vpc" {
  count = local.create_aws ? 1 : 0

  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.prefix}-first-deployment-vpc"
  }
}

resource "aws_subnet" "subnet" {
  count = local.create_aws ? 2 : 0

  vpc_id            = aws_vpc.vpc[0].id
  cidr_block        = "10.10.${count.index}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # Required for EKS
  map_public_ip_on_launch = true

  tags = {
    Name                                          = "${local.prefix}-first-deployment-subnet-${count.index + 1}"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  count = local.create_aws ? 1 : 0

  vpc_id = aws_vpc.vpc[0].id

  tags = {
    Name = "${local.prefix}-first-deployment-igw"
  }
}

# Route Table
resource "aws_route_table" "main" {
  count = local.create_aws ? 1 : 0

  vpc_id = aws_vpc.vpc[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw[0].id
  }

  tags = {
    Name = "${local.prefix}-first-deployment-rt"
  }
}

resource "aws_route_table_association" "main" {
  count = local.create_aws ? 2 : 0

  subnet_id      = aws_subnet.subnet[count.index].id
  route_table_id = aws_route_table.main[0].id
}

# EKS Cluster
locals {
  cluster_name = "${local.prefix}-first-deployment-eks"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_eks_cluster" "cluster" {
  count = local.create_aws ? 1 : 0

  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster[0].arn

  vpc_config {
    subnet_ids = aws_subnet.subnet[*].id
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller
  ]
}

resource "aws_eks_node_group" "nodes" {
  count = local.create_aws ? 1 : 0

  cluster_name    = aws_eks_cluster.cluster[0].name
  node_group_name = "${local.prefix}-first-deployment-nodes"
  node_role_arn   = aws_iam_role.eks_nodes[0].arn
  subnet_ids      = aws_subnet.subnet[*].id

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry
  ]
}

# IAM Roles and Policies
resource "aws_iam_role" "eks_cluster" {
  count = local.create_aws ? 1 : 0
  name  = "${local.prefix}-eks-cluster-role"

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
  count = local.create_aws ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster[0].name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  count = local.create_aws ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster[0].name
}

resource "aws_iam_role" "eks_nodes" {
  count = local.create_aws ? 1 : 0
  name  = "${local.prefix}-eks-node-role"

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
  count = local.create_aws ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes[0].name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  count = local.create_aws ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes[0].name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry" {
  count = local.create_aws ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes[0].name
}

# OIDC Provider for Humanitec Integration
data "tls_certificate" "eks" {
  count = local.create_aws ? 1 : 0
  url   = aws_eks_cluster.cluster[0].identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  count = local.create_aws ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks[0].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.cluster[0].identity[0].oidc[0].issuer
}

# IAM Role for Humanitec Runner
resource "aws_iam_role" "humanitec_runner" {
  count = local.create_aws ? 1 : 0
  name  = "${local.prefix}-humanitec-runner-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks[0].arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks[0].url, "https://", "")}:sub" = "${var.humanitec_org}+${local.prefix}-first-deployment-eks-runner"
          }
        }
      }
    ]
  })
}

# Policy for Humanitec Runner
resource "aws_iam_role_policy" "humanitec_runner" {
  count = local.create_aws ? 1 : 0
  name  = "${local.prefix}-humanitec-runner-policy"
  role  = aws_iam_role.humanitec_runner[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
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
