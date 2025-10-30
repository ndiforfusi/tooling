# Role assumed by the Jenkins EC2 instance (base identity)
resource "aws_iam_role" "jenkins_base_role" {
  name = var.jenkins_instance_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid      = "EC2AssumeRole"
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Attach convenience policies (SSM recommended; add CW agent if you use it)
resource "aws_iam_role_policy_attachment" "jenkins_ssm_core" {
  role       = aws_iam_role.jenkins_base_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Optional: if you use CloudWatch agent on Jenkins
# resource "aws_iam_role_policy_attachment" "jenkins_cw_agent" {
#   role       = aws_iam_role.jenkins_base_role.name
#   policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
# }

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = var.jenkins_instance_profile_name
  role = aws_iam_role.jenkins_base_role.name
}
