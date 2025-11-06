data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

data "aws_ssm_parameter" "al2" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

locals {
  subnet_id = data.aws_subnets.default_public_in_az.ids[0]
}


locals {
  # Service-linked role names you may need; trim if not used
  slr_services = [
    "eks.amazonaws.com",
    "ec2.amazonaws.com",
    "autoscaling.amazonaws.com",
    "elasticloadbalancing.amazonaws.com",
    "spot.amazonaws.com"
  ]
}