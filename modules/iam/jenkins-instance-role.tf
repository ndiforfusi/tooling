# Role attached to the Jenkins EC2 instance
resource "aws_iam_role" "jenkins_base_role" {
  name = var.jenkins_instance_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid      = "EC2AssumeRole"
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Allow SSM Session Manager access, etc.
resource "aws_iam_role_policy_attachment" "jenkins_ssm_core" {
  role       = aws_iam_role.jenkins_base_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Permit Jenkins base role to AssumeRole into the Terraform deploy role
resource "aws_iam_policy" "jenkins_assume_deploy" {
  name        = "${var.jenkins_instance_role_name}-Assume-${var.deploy_role_name}"
  description = "Allow Jenkins base role to assume the Terraform deploy role"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = "sts:AssumeRole",
      Resource = aws_iam_role.terraform_deploy_role.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_assume_deploy_attach" {
  role       = aws_iam_role.jenkins_base_role.name
  policy_arn = aws_iam_policy.jenkins_assume_deploy.arn
}

# Instance profile to attach to the Jenkins EC2 instance
resource "aws_iam_instance_profile" "jenkins_profile" {
  name = var.jenkins_instance_profile_name
  role = aws_iam_role.jenkins_base_role.name
}
