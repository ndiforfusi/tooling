# Trust policy for the deploy role (trust only the Jenkins EC2 base role)
data "aws_iam_policy_document" "deploy_trust" {
  statement {
    sid     = "TrustJenkinsEC2Role"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.jenkins_base_role.arn]
    }
  }
}

resource "aws_iam_role" "terraform_deploy_role" {
  name               = var.deploy_role_name
  assume_role_policy = data.aws_iam_policy_document.deploy_trust.json
}

# Give TerraformDeployRole broad permissions (swap with custom least-privilege policy if desired)
resource "aws_iam_role_policy_attachment" "deploy_power_user" {
  role       = aws_iam_role.terraform_deploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

/* Example custom policy alternative (optional):
resource "aws_iam_policy" "deploy_custom" {
  name        = "${var.deploy_role_name}-policy"
  description = "Least-privilege policy for Terraform deployments"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect: "Allow",
      Action: [
        "s3:*",
        "dynamodb:*",
        "ec2:*",
        "iam:PassRole",
        "cloudwatch:*",
        "logs:*",
        "events:*",
        "elasticloadbalancing:*",
        "autoscaling:*",
        "rds:*",
        "kms:Describe*",
        "kms:List*",
        "kms:Decrypt"
      ],
      Resource: "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "deploy_attach_custom" {
  role       = aws_iam_role.terraform_deploy_role.name
  policy_arn = aws_iam_policy.deploy_custom.arn
}
*/
