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

  dynamic "statement" {
    for_each = var.enable_oidc ? [1] : []
    content {
      sid     = "TrustOIDCProvider"
      effect  = "Allow"
      actions = ["sts:AssumeRoleWithWebIdentity"]

      principals {
        type        = "Federated"
        identifiers = [aws_iam_openid_connect_provider.jenkins_oidc[0].arn]
      }

      condition {
        test     = "StringEquals"
        variable = "${local.issuer_host}:aud"
        values   = [var.oidc_audience]
      }

      # Narrow to a specific subject (e.g., a GitHub repo/branch)
      condition {
        test     = "StringLike"
        variable = "${local.issuer_host}:sub"
        values   = [var.oidc_sub_claim]
      }
    }
  }
}

resource "aws_iam_role" "terraform_deploy_role" {
  name               = var.deploy_role_name
  assume_role_policy = data.aws_iam_policy_document.deploy_trust.json
}

# Attach AWS managed PowerUserAccess (broad permissions without account admin)
resource "aws_iam_role_policy_attachment" "deploy_power_user" {
  role       = aws_iam_role.terraform_deploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# (Optional) If you prefer custom policy instead of PowerUserAccess, define here:
# resource "aws_iam_policy" "deploy_custom" {
#   name        = "${var.deploy_role_name}-policy"
#   description = "Least-privilege policy for Terraform deployments"
#   policy      = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         "Effect": "Allow",
#         "Action": [
#           "s3:*",
#           "dynamodb:*",
#           "ec2:*",
#           "iam:PassRole",
#           "cloudwatch:*",
#           "logs:*",
#           "events:*",
#           "elasticloadbalancing:*",
#           "autoscaling:*",
#           "rds:*",
#           "kms:Describe*",
#           "kms:List*",
#           "kms:Decrypt"
#         ],
#         "Resource": "*"
#       }
#     ]
#   })
# }
#
# resource "aws_iam_role_policy_attachment" "deploy_attach_custom" {
#   role       = aws_iam_role.terraform_deploy_role.name
#   policy_arn = aws_iam_policy.deploy_custom.arn
# }
