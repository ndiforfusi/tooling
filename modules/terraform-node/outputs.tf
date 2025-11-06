# output "ami_id" {
#   description = "Selected AMI ID"
#   value       = data.aws_ami.linux.id
# }

output "security_group_id" {
  description = "SSH security group"
  value       = aws_security_group.ssh.id
}

output "instance_profile_name" {
  description = "EC2 instance profile name"
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "ec2_role_arn" {
  description = "IAM role ARN attached to the instance profile"
  value       = aws_iam_role.ec2_role.arn
}

output "build_node_public_ip" {
  description = "Public IP of the build node (if associated)"
  value       = try(aws_instance.build_node.public_ip, null)
}

output "build_node_private_ip" {
  description = "Private IP of the build node"
  value       = aws_instance.build_node.private_ip
}


output "build_node_eip_public_ip" {
  description = "Public IP address of the build node's Elastic IP (if attached)"
  value       = try(aws_eip.build[0].public_ip, null)
}

output "build_node_eip_allocation_id" {
  description = "Allocation ID of the Elastic IP used by the build node"
  value       = var.eip_allocation_id != null ? var.eip_allocation_id : try(aws_eip.build[0].id, null)
}

