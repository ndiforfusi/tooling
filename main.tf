module "jenkins-server" {
  source        = "./modules/jenkins-server"
  ami_id        = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  main-region   = var.main-region
}

module "terraform-node" {
  source        = "./modules/terraform-node"
  ami_id        = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  main-region   = var.main-region
}

module "maven-sonarqube-server" {
  source            = "./modules/maven-sonarqube-server"
  ami_id            = var.ami_id
  instance_type     = var.instance_type
  key_name          = var.key_name
  security_group_id = var.security_group_id
  subnet_id         = var.subnet_id
  # main-region   = var.main-region

  #   db_name              = var.db_name
  #   db_username          = var.db_username
  #   db_password          = var.db_password
  #   db_subnet_group      = var.db_subnet_group
  #   db_security_group_id = var.db_security_group_id
}

# # module "s3_dynamodb" {
# #   source = "./modules/s3-dynamodb"
# #   bucket = var.s3_bucket
# #   table  = var.dynamodb_table
# #   region = var.main-region
# # }
