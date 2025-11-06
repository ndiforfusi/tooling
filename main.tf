module "jenkins-server" {
  source        = "./modules/jenkins-server"
  instance_type = var.instance_type
  ssh_key_name      = var.key_name
}

module "terraform-node" {
  source        = "./modules/terraform-node"
  instance_type = var.instance_type
  ssh_key_name      = var.key_name
  region   = var.region
}

# module "maven-sonarqube-server" {
#   source            = "./modules/maven-sonarqube-server"
#   ami_id            = var.ami_id
#   instance_type     = var.instance_type
#   key_name          = var.key_name
#   security_group_id = var.security_group_id
#   subnet_id         = var.subnet_id
#   # main-region   = var.main-region

#   #   db_name              = var.db_name
#   #   db_username          = var.db_username
#   #   db_password          = var.db_password
#   #   db_subnet_group      = var.db_subnet_group
#   #   db_security_group_id = var.db_security_group_id
# }

# # module "s3_dynamodb" {
# #   source = "./modules/s3-dynamodb"
# #   bucket = var.s3_bucket
# #   table  = var.dynamodb_table
# #   region = var.main-region
# # }

module "ecr-image-storage" {
  source         = "./modules/ecr-image-storage"
  ecr_image_repo = var.ecr_image_repo
}

