Jenkins + Terraform CI/CD (AssumeRole) — Step-By-Step
0) What you’re building

Build node (EC2) with a minimal instance profile that can only call sts:AssumeRole on your Deploy Role.

Jenkins pipeline assumes the Deploy Role to run Terraform with permissions.

Terraform state in S3, locking via DynamoDB.

Pipeline stages: preflight → lint/validate → init → plan → approval (prod) → apply/destroy.

1) AWS prerequisites

State backend

S3 bucket (versioned, encrypted), e.g. my-company-terraform-state

DynamoDB table for locks, e.g. terraform-locks

Networking

A VPC and Subnet for the build node.

Security Group allowing SSH (22) ONLY from your office/VPN CIDR (prefer SSM over SSH if possible).

2) IAM setup (two roles)
A. Deploy Role (used by Terraform during pipeline)

Purpose: permissions to create/update/destroy infra executed by Terraform.

Permissions: start with AWS managed PowerUserAccess for bootstrap; replace with least privilege for production.

Trust policy: trust ONLY your build-node instance-profile role, and (optionally) require an ExternalId.

{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowBuildNodeToAssume",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<ACCOUNT_ID>:role/<BUILD_NODE_INSTANCE_PROFILE_ROLE_NAME>"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": { "sts:ExternalId": "jenkins-deploy" }
      }
    }
  ]
}


Save the ARN, e.g. arn:aws:iam::<ACCOUNT_ID>:role/TerraformDeployRole.

B. Build-node instance-profile role (minimal)

Purpose: only to call sts:AssumeRole on the Deploy Role.

Inline policy (tight):

{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AssumeOnlyDeployRole",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::<ACCOUNT_ID>:role/TerraformDeployRole",
      "Condition": {
        "StringEquals": { "sts:ExternalId": "jenkins-deploy" }
      }
    }
  ]
}


Trust policy (for EC2):

{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Principal": { "Service": "ec2.amazonaws.com" }, "Action": "sts:AssumeRole" }
  ]
}


Attach this role to an Instance Profile and assign it to the EC2 build node.

3) Provision the build node (EC2)

Launch a Linux EC2 in your subnet/VPC; attach the Instance Profile from section 2B.

Security Group: SSH (22) open to trusted CIDRs only (or none if using SSM).

Install tools (latest stable): Terraform, AWS CLI v2, kubectl, tflint, tfsec, checkov, jq, yq.

Quick identity test on the node:

aws sts get-caller-identity   # should show the instance-profile role
terraform -version


If you want, I can package your bootstrap script so it installs pinned “latest” versions and prints a readiness report.

4) Jenkins controller setup

Plugins: Pipeline, AWS Steps, AnsiColor, Credentials Binding, Timestamper.

Global Tool (optional): Terraform 1.10.x (or rely on system Terraform on the agent).

Credentials (Secret text):

tf-state-bucket → my-company-terraform-state

tf-lock-table → terraform-locks

Global env (optional):

TERRAFORM_DEPLOY_ROLE_ARN=arn:aws:iam::<ACCOUNT_ID>:role/TerraformDeployRole

5) Terraform code conventions

Backend is supplied at terraform init time (don’t hardcode the bucket/table in code if you want the same code across envs).

Variables: region, name_prefix, vpc_id, subnet_id, etc.

Example terraform.tfvars:

region      = "us-west-2"
name_prefix = "jenkins"
vpc_id      = "vpc-xxxxxxxx"
subnet_id   = "subnet-xxxxxxxx"

6) Jenkinsfile essentials (you already have a strong version)

Below are the key pieces your Jenkinsfile should contain (yours does):

Assume-role helper:

def withAssumedRole(String region, String roleArn, String sessionName='jenkins-session', Closure body) {
  withAWS(region: region, role: roleArn, roleSessionName: sessionName, duration: 3600) { body() }
}


Backend init (S3 + DynamoDB):

sh """
  cd "${TF_DIR}"
  terraform init -upgrade \
    -backend-config="bucket=${TF_STATE_BUCKET}" \
    -backend-config="key=${TF_ENV}/terraform.tfstate" \
    -backend-config="region=${AWS_REGION}" \
    -backend-config="dynamodb_table=${TF_LOCK_TABLE}"
"""


Plan with traceability:

withAssumedRole(AWS_REGION, roleArn, "jenkins-${env.BUILD_TAG}") {
  sh """
    cd "${TF_DIR}"
    terraform plan -lock=true -lock-timeout=5m \
      -var environment=${TF_ENV} \
      -var pipeline_run_id=${env.BUILD_TAG} \
      -out plan.tfplan
    terraform show -no-color plan.tfplan > plan.txt
  """
}
archiveArtifacts artifacts: "${TF_DIR}/plan.tfplan, ${TF_DIR}/plan.txt", fingerprint: true


Guarded prod apply:

if (params.ENVIRONMENT == 'prod') {
  if (!params.UNLOCK_PROD || params.CONFIRMATION != 'I-UNDERSTAND') {
    error "Prod apply locked. Set UNLOCK_PROD=true and CONFIRMATION=I-UNDERSTAND."
  }
  timeout(time: 30, unit: 'MINUTES') {
    input message: "Approve APPLY to PROD?", ok: 'Approve'
  }
}

7) Create the job (Multibranch recommended)

New Item → Multibranch Pipeline

Point to your Git repo containing Terraform and the Jenkinsfile.

Parameters (or env):

ENVIRONMENT (dev|qa|uat|prod)

REGION (e.g., us-west-2)

ACTION (plan|apply|destroy)

ASSUME_ROLE_ARN (or rely on global TERRAFORM_DEPLOY_ROLE_ARN)

Save → Jenkins scans branches/PRs and creates jobs.

8) First run checklist

 Build node can reach S3 + DynamoDB:

aws s3 ls s3://my-company-terraform-state
aws dynamodb describe-table --table-name terraform-locks --region us-west-2


 WhoAmI (before assume) shows the instance-profile role.

 Plan succeeds; artifacts plan.tfplan + plan.txt archived.

 WhoAmI (after assume) shows the Deploy Role (different ARN).

 Apply only after manual review (stronger gate for prod).

9) Security best practices

Keep the build node role minimal: only sts:AssumeRole on the single Deploy Role (+ require ExternalId).

Add permissions boundaries or move from PowerUserAccess to least-privilege JSON.

Prefer SSM Session Manager to SSH; if SSH, restrict CIDR tightly.

S3 bucket: versioning, encryption, and a tight bucket policy.

Use roleSessionName (e.g., jenkins-${BUILD_TAG}) for traceability in CloudTrail.

10) Troubleshooting quick table
Symptom	Likely cause	Fix
AccessDenied on AssumeRole	Bad trust policy or wrong ExternalId	Update trust to include build-node role; match ExternalId.
NoCredentialProviders	Node lacks instance profile	Attach instance profile; avoid static keys.
S3 backend AccessDenied	Wrong bucket/region or bucket policy	Verify names/region; allow init/read/write for your roles.
Stuck TF lock	Crash left lock item	Remove DDB lock row only if sure no job is running.
Provider mismatch	Cached old plugins	terraform init -upgrade; pin provider versions.
11) Optional enhancements

Nightly drift detection: plan only on main + notifications.

Policy scanning gates: fail on high severity from tflint, tfsec, checkov.

Workspaces: use terraform workspace select/new ENV instead of per-env folders (optional).

Docker/Buildx or AWS SSM plugin if your pipelines need them.

12) Quick copy/paste commands

On the node:

aws sts get-caller-identity
terraform -version
kubectl version --client || true
tflint --version || true
tfsec --version || true
checkov -v || true


Groovy (assume + plan):

def roleArn = params.ASSUME_ROLE_ARN
withAssumedRole(AWS_REGION, roleArn, "jenkins-${env.BUILD_TAG}") {
  sh '''
    cd "${TF_DIR}"
    terraform plan -lock=true -lock-timeout=5m -out plan.tfplan
  '''
}














🧱 Build Node Configuration (Step-by-Step)

This section explains how to configure and register a Linux build node (EC2 instance) with Jenkins so it can securely run Terraform pipelines using the assumed IAM role defined in your Terraform deployment.

1️⃣ Launch the Build Node EC2 Instance

Option 1 – Terraform (Recommended):
If you used the provided Terraform module (main.tf, variables.tf, outputs.tf), just apply it:

terraform init
terraform plan
terraform apply -auto-approve


This automatically:

Creates the EC2 build node (Amazon Linux 2023 by default).

Attaches the IAM Instance Profile with PowerUser + SSM permissions.

Opens port 22 via your Security Group (configurable CIDRs).

Enables SSM management (AmazonSSMManagedInstanceCore policy).

Option 2 – AWS Console (Manual):

Launch an instance (Amazon Linux 2023 or 2) in your subnet/VPC.

Under IAM Role, choose the instance profile Terraform created (e.g., cicd-ec2-profile).

Assign your security group (cicd-ssh).

Add a key pair only if you need SSH; otherwise, rely on Session Manager.

Storage: select gp3 root volume, at least 20 GB.

Launch the instance.

2️⃣ Verify IAM Role and SSM Connectivity

Once the instance is running:

a. Check IAM Identity

aws sts get-caller-identity


✅ You should see the build node instance profile ARN, not your personal user.

b. Verify SSM Connectivity (preferred over SSH)

aws ssm describe-instance-information --region us-west-2


✅ You should see your instance listed if SSM agent is active.

If not, run:

sudo systemctl status amazon-ssm-agent
sudo systemctl start amazon-ssm-agent


c. (Optional) SSH Access Test
Only if SSH was enabled:

ssh -i ~/.ssh/your-key.pem ec2-user@<public-ip>

3️⃣ Install Required Toolchain

If you used the provided terraform.sh script, just run it once on the instance (as root):

sudo bash terraform.sh


It installs and verifies:

Tool	Version (as of Nov 2025)	Purpose
Terraform	1.10.3	Infrastructure automation
AWS CLI v2	2.17.x	Authentication, S3, STS
kubectl	1.32.0	Optional, for EKS integrations
tflint	0.55.0	Terraform linting
tfsec	1.28.6	Security scanning
checkov	3.2.262	Policy compliance
jq / yq	Latest	JSON/YAML parsing

Confirm tools installed:

terraform -version
aws --version
kubectl version --client
tflint --version
tfsec --version
checkov -v

4️⃣ Harden the Instance (Recommended)
Task	Command	Purpose
Enforce IMDSv2	curl -s http://169.254.169.254/latest/meta-data/iam/info should fail unless IMDSv2 tokens are used	Prevent metadata spoofing
Enable auto-updates	sudo dnf update -y (AL2023)	Patch vulnerabilities
Limit inbound SSH	Use VPC security group CIDRs	Restrict SSH to VPN/IP
Enable CloudWatch metrics	Set enable_detailed_monitoring=true in Terraform	Visibility for scaling / alerts
5️⃣ Connect Build Node to Jenkins
A. On Jenkins Controller

Go to: Manage Jenkins → Nodes → New Node

Enter a name (e.g., terraform-build-node)

Choose Permanent Agent

Configure:

# of Executors: 1 or 2

Remote root directory: /home/ec2-user/jenkins

Labels: terraform (so pipelines can target agent { label 'terraform' })

Usage: "Only build jobs with label expressions matching this node"

Launch Method: Choose one:

SSH → enter the private key and EC2 hostname.

JNLP (Agent.jar) → start agent manually or via systemd.

SSM (recommended) → if using AWS SSM plugin (see below).

B. (Optional) Use AWS SSM to connect Jenkins agent

If you installed the AWS SSM plugin:

Add AWS credentials for Jenkins.

In node configuration, set Launch via SSM.

Jenkins connects securely without opening port 22.

6️⃣ Test Jenkins → Build Node Connection

Run a simple pipeline:

pipeline {
  agent { label 'terraform' }
  stages {
    stage('WhoAmI') {
      steps {
        sh 'aws sts get-caller-identity'
        sh 'terraform version'
      }
    }
  }
}


✅ Output should show:

The build node IAM role ARN (arn:aws:iam::<ACCOUNT_ID>:role/cicd-ec2-role)

The correct Terraform version.

7️⃣ Verify AssumeRole Works

Now test the STS AssumeRole logic to confirm that Jenkins can switch from the build-node role to the Deploy Role:

In Jenkins, run a quick job with:

aws sts assume-role \
  --role-arn arn:aws:iam::<ACCOUNT_ID>:role/TerraformDeployRole \
  --role-session-name jenkins-test \
  --external-id jenkins-deploy


✅ If successful, you’ll see temporary credentials (AccessKeyId, SecretAccessKey, SessionToken).

That confirms the trust policy and ExternalId setup are correct. 



ssh-keygen -t ed25519 -f ~/.ssh/jenkins-agent -N ""
