data "aws_region" "current" {
}

data "aws_ecs_cluster" "current" {
  cluster_name = var.ecs_cluster_name
}

data "aws_vpc" "current" {
  id = var.vpc_id
}