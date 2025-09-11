terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "random_id" "fleet_id" {
  byte_length = 8
}

# Get the default VPC
data "aws_vpc" "default" {
  default = true
}

# Get default subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Create key pair for SSH access
resource "aws_key_pair" "fleet_key" {
  key_name   = "fleet-key-${random_id.fleet_id.hex}"
  public_key = tls_private_key.ssh.public_key_openssh
}

# Security group for SSH and HTTP access
resource "aws_security_group" "fleet_sg" {
  name_prefix = "fleet-sg-${random_id.fleet_id.hex}"
  vpc_id      = data.aws_vpc.default.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "fleet-sg-${random_id.fleet_id.hex}"
  }
}

# Launch template for the instances
resource "aws_launch_template" "fleet_template" {
  name_prefix   = "fleet-template-${random_id.fleet_id.hex}"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.fleet_key.key_name

  vpc_security_group_ids = [aws_security_group.fleet_sg.id]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "fleet-instance-${random_id.fleet_id.hex}"
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "fleet_asg" {
  name                = "fleet-asg-${random_id.fleet_id.hex}"
  vpc_zone_identifier = data.aws_subnets.default.ids
  target_group_arns   = [aws_lb_target_group.fleet_tg.arn]
  health_check_type   = "ELB"
  min_size            = 3
  max_size            = 3
  desired_capacity    = 3

  launch_template {
    id      = aws_launch_template.fleet_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "fleet-asg-${random_id.fleet_id.hex}"
    propagate_at_launch = false
  }
}

# Application Load Balancer
resource "aws_lb" "fleet_alb" {
  name               = "fleet-alb-${substr(random_id.fleet_id.hex, 0, 8)}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.fleet_sg.id]
  subnets            = data.aws_subnets.default.ids

  enable_deletion_protection = false

  tags = {
    Name = "fleet-alb-${random_id.fleet_id.hex}"
  }
}

# Target group for the ALB
resource "aws_lb_target_group" "fleet_tg" {
  name     = "fleet-tg-${substr(random_id.fleet_id.hex, 0, 8)}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "fleet-tg-${random_id.fleet_id.hex}"
  }
}

# ALB Listener
resource "aws_lb_listener" "fleet_listener" {
  load_balancer_arn = aws_lb.fleet_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.fleet_tg.arn
  }
}

# Data source to get instance IPs after they're created
data "aws_instances" "fleet_instances" {
  depends_on = [aws_autoscaling_group.fleet_asg]

  filter {
    name   = "tag:Name"
    values = ["fleet-instance-${random_id.fleet_id.hex}"]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

output "loadbalancer_ip" {
  value = aws_lb.fleet_alb.dns_name
}

output "instance_ips" {
  value = data.aws_instances.fleet_instances.public_ips
}

output "ssh_username" {
  value = "ubuntu"
}

output "ssh_private_key" {
  value     = tls_private_key.ssh.private_key_pem
  sensitive = true
}