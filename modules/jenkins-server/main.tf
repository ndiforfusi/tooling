resource "aws_instance" "jenkins_server" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  user_data     = file("${path.module}/jenkins.sh")

  tags = {
    Name = "jenkins-server"
  }
}
