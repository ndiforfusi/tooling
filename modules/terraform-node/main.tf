terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.50"
    }
  }
}

provider "aws" {
  region = var.region
}

# Helpful identity/partition data
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}



# --- Networking: default VPC + a default (public) subnet in chosen AZ ---
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default_public_in_az" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "availability-zone"
    values = [var.availability_zone]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}


# --- AMI ---
# Retrieve Latest Ubuntu 24.04 AMI (Canonical)
data "aws_ami" "ubuntu_2404" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = [
      "ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*",
      "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*",
    ]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}
# -----------------------------------------------------------------------------
# Security Group: SSH (22) open to provided CIDR(s)
# -----------------------------------------------------------------------------
resource "aws_security_group" "ssh" {
  name        = "${var.name_prefix}-ssh"
  description = "Allow SSH from approved CIDR ranges"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  egress {
    description      = "All egress"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-ssh" })
}

# -----------------------------------------------------------------------------
# IAM Role + Instance Profile (PowerUserAccess + SSM core)
# -----------------------------------------------------------------------------
# Managed policy ARNs built per-partition for portability
locals {
  admin_policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"
  ssm_core_policy_arn  = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Trust policy for EC2 with optional ExternalId condition (if var.external_id set)
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    sid     = "EC2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    dynamic "condition" {
      for_each = var.external_id == null ? [] : [1]
      content {
        test     = "StringEquals"
        variable = "sts:ExternalId"
        values   = [var.external_id]
      }
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "${var.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json

  tags = merge(var.tags, { Name = "${var.name_prefix}-ec2-role" })
}

# Attach PowerUserAccess (as requested). Consider replacing with least-privilege in prod.
# Attach full admin to the role
resource "aws_iam_role_policy_attachment" "admin_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = local.admin_policy_arn
}

# Attach SSM core so you can manage the node without SSH
resource "aws_iam_role_policy_attachment" "ssm_core_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = local.ssm_core_policy_arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2_role.name

  tags = merge(var.tags, { Name = "${var.name_prefix}-ec2-profile" })
}


# Inline policy: IAM exceptions for a PowerUser role
resource "aws_iam_role_policy" "ec2_role_iam_exceptions" {
  name = "${var.name_prefix}-iam-exceptions"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = concat(
      [
        # 1) Fix: allow role to read itself (needed by modules reading caller identity)
        {
          "Sid"    : "AllowGetSelf",
          "Effect" : "Allow",
          "Action" : ["iam:GetRole"],
          "Resource": aws_iam_role.ec2_role.arn
        }
      ],
      # 2) Allow PassRole to specific roles only (least-privilege)
      length(var.passrole_arns) > 0 ? [
        {
          "Sid"    : "AllowPassSpecificRoles",
          "Effect" : "Allow",
          "Action" : ["iam:PassRole"],
          "Resource": var.passrole_arns,
          "Condition": {
            "StringEquals": {
              "iam:PassedToService": [
                "eks.amazonaws.com",
                "ec2.amazonaws.com"
              ]
            }
          }
        }
      ] : [],
      # 3) (Optional) Allow creating specific service-linked roles some modules require
      var.allow_create_slr ? [
        {
          "Sid"    : "AllowCreateServiceLinkedRoleForCommonServices",
          "Effect" : "Allow",
          "Action" : ["iam:CreateServiceLinkedRole"],
          "Resource": "*",
          "Condition": {
            "StringEquals": {
              "iam:AWSServiceName": local.slr_services
            }
          }
        }
      ] : []
    )
  })
}


# Allocate a new EIP (only when requested and when the instance has/will have a public IP)
resource "aws_eip" "build" {
  count  = var.allocate_eip && var.associate_public_ip ? 1 : 0
  domain = "vpc"             # VPC-scoped EIP (AWS provider v5+)
  tags   = merge(var.tags, { Name = "${var.name_prefix}-build-eip" })
}

# Associate EIP to the instance (handles both new or pre-existing EIP)
resource "aws_eip_association" "build" {
  count         = var.associate_public_ip ? 1 : 0
  instance_id   = aws_instance.build_node.id
  allocation_id = var.eip_allocation_id != null ? var.eip_allocation_id : try(aws_eip.build[0].id, null)

  # If you prefer to pin to the primary NIC explicitly:
  # network_interface_id = aws_instance.build_node.primary_network_interface_id
}

# -----------------------------------------------------------------------------
# EC2 Build Node
# -----------------------------------------------------------------------------
resource "aws_instance" "build_node" {
  ami                    = data.aws_ami.ubuntu_2404.id
  instance_type               = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = var.associate_public_ip
  monitoring                  = try(var.enable_detailed_monitoring, false)

  # Optional SSH key (null-safe)
  key_name = try(var.ssh_key_name, null)

  # Harden metadata service (IMDSv2)
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # Modern root volume (gp3) with adjustable size
  root_block_device {
    volume_type = "gp3"
    volume_size = try(var.root_volume_size_gb, 30)
    encrypted   = true
    tags        = merge(var.tags, { Name = "${var.name_prefix}-root" })
  }

  user_data = var.user_data   # pass in your terraform.sh or cloud-init if desired

  tags = merge(var.tags, { Name = "${var.name_prefix}-build-node" })
}
