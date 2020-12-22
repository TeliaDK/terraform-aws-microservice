locals {
  cloudwatch_retention_in_days                     = 30
  service_discovery_dns_ttl                        = 10
  service_discovery_health_check_failure_threshold = 1
  aws_ecs_task_definition_family                   = var.app_name
}

resource "aws_cloudwatch_log_group" "current" {
  name              = "/ecs/${var.app_name}"
  tags              = var.tags
  retention_in_days = local.cloudwatch_retention_in_days
}

resource "aws_security_group" "current" {
  name        = var.app_name
  description = "Ingress rules for ${var.app_name}"
  vpc_id      = data.aws_vpc.current.id

  tags = var.tags
}

resource "aws_service_discovery_service" "current" {
  name = var.cloud_map.service.name

  dns_config {
    namespace_id = var.cloud_map.namespace.id

    dns_records {
      ttl  = local.service_discovery_dns_ttl
      type = "A"
    }

    routing_policy = var.service_discovery_dns_routing_policy
  }

  health_check_custom_config {
    failure_threshold = local.service_discovery_health_check_failure_threshold
  }
}

resource "aws_appmesh_virtual_router" "current" {
  name      = "${var.app_name}-virtual-route"
  mesh_name = var.appmesh_name

  spec {
    listener {
      port_mapping {
        port     = var.port
        protocol = "http"
      }
    }
  }

  tags = var.tags
}

resource "aws_appmesh_virtual_service" "current" {
  name      = "${var.app_name}-virtual-service"
  mesh_name = var.appmesh_name

  spec {
    provider {
      virtual_router {
        virtual_router_name = aws_appmesh_virtual_router.current.name
      }
    }
  }

  tags = var.tags
}

resource "aws_appmesh_virtual_node" "current" {
  name      = "${var.app_name}-virtual-node"
  mesh_name = var.appmesh_name

  spec {
    backend {
      virtual_service {
        virtual_service_name = aws_appmesh_virtual_service.current.name
      }
    }

    listener {
      port_mapping {
        port     = var.port
        protocol = "http"
      }
    }

    service_discovery {
      aws_cloud_map {
        attributes = {
          ECS_TASK_DEFINITION_FAMILY = local.aws_ecs_task_definition_family
        }

        service_name   = var.cloud_map.service.name
        namespace_name = var.cloud_map.namespace.name
      }
    }
  }

  tags = var.tags
}

resource "aws_appmesh_route" "current" {
  name                = "${var.app_name}-main-route"
  mesh_name           = var.appmesh_name
  virtual_router_name = aws_appmesh_virtual_router.current.name

  spec {
    http_route {
      match {
        prefix = "/"
      }

      action {
        weighted_target {
          virtual_node = aws_appmesh_virtual_node.current.name
          weight       = 100
        }
      }
    }
  }

  tags = var.tags
}

module "container_definition_xray" {
  source                       = "git::https://github.com/cloudposse/terraform-aws-ecs-container-definition.git?ref=0.46.0"
  container_name               = "xray-daemon"
  container_image              = "amazon/aws-xray-daemon"
  container_cpu                = var.xray_cpu
  container_memory_reservation = var.xray_memory
  container_memory             = var.xray_memory

  port_mappings = [
    {
      hostPort      = null
      containerPort = 2000
      protocol      = "udp"
    }
  ]

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = "/ecs/${var.app_name}"
      awslogs-region        = data.aws_region.current.name
      awslogs-stream-prefix = "ecs"
    }
    secretOptions = []
  }
}

module "container_definition_envoy" {
  source                       = "git::https://github.com/cloudposse/terraform-aws-ecs-container-definition.git?ref=0.46.0"
  container_name               = "envoy"
  container_image              = "840364872350.dkr.ecr.eu-west-1.amazonaws.com/aws-appmesh-envoy:v1.12.4.0-prod"
  container_cpu                = var.envoy_cpu
  container_memory_reservation = var.envoy_memory
  container_memory             = var.envoy_memory
  user                         = "1337"

  ulimits = [
    {
      name      = "nofile"
      hardLimit = 15000
      softLimit = 15000
    }
  ]

  port_mappings = [
    {
      hostPort      = 9901
      containerPort = 9901
      protocol      = "tcp"
    },
    {
      hostPort      = 15000
      containerPort = 15000
      protocol      = "tcp"
    },
    {
      hostPort      = 15001
      containerPort = 15001
      protocol      = "tcp"
    }
  ]

  environment = [
    {
      name  = "APPMESH_VIRTUAL_NODE_NAME",
      value = "mesh/${var.appmesh_name}/virtualNode/${aws_appmesh_virtual_node.current.name}"
    },
    {
      name  = "ENABLE_ENVOY_XRAY_TRACING",
      value = "1"
    }
  ]

  healthcheck = {
    command = [
      "CMD-SHELL",
      "curl -s http://localhost:9901/server_info | grep state | grep -q LIVE"
    ]
    interval    = 5
    timeout     = 2
    retries     = 3
    startPeriod = 10
  }

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = "/ecs/${var.app_name}"
      awslogs-region        = data.aws_region.current.name
      awslogs-stream-prefix = "ecs"
    }
    secretOptions = []
  }
}

module "container_definition_service" {
  source                       = "git::https://github.com/cloudposse/terraform-aws-ecs-container-definition.git?ref=0.46.0"
  container_name               = var.microservice_container.name
  container_image              = var.microservice_container.image
  container_cpu                = var.microservice_container.cpu
  container_memory_reservation = var.microservice_container.memory
  container_memory             = var.microservice_container.memory
  environment                  = var.env_variables
  secrets                      = var.secrets

  port_mappings = [
    {
      containerPort = var.port
      hostPort      = var.port
      protocol      = "tcp"
    }
  ]

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group           = "/ecs/${var.app_name}"
      awslogs-region          = data.aws_region.current.name
      awslogs-stream-prefix   = "ecs"
      awslogs-datetime-format = var.awslogs_datetime_format
    }
    secretOptions = []
  }

  container_depends_on = [
    {
      containerName = "envoy"
      condition     = "HEALTHY"
    }
  ]
}

resource "aws_ecs_task_definition" "current" {
  family                   = local.aws_ecs_task_definition_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  task_role_arn            = var.task_role_arn
  execution_role_arn       = var.task_execution_role_arn
  container_definitions    = <<EOF
  [
    ${module.container_definition_xray.json_map_encoded},
    ${module.container_definition_envoy.json_map_encoded},
    ${module.container_definition_service.json_map_encoded}
  ]
  EOF

  proxy_configuration {
    type           = "APPMESH"
    container_name = var.envoy_container_name
    properties = {
      AppPorts         = var.port
      EgressIgnoredIPs = "169.254.170.2,169.254.169.254" # Used for AWS metadata 
      IgnoredUID       = var.envoy_ignored_uid
      ProxyEgressPort  = 15001
      ProxyIngressPort = 15000
    }
  }

  tags = var.tags
}

resource "aws_ecs_service" "current" {
  name            = var.app_name
  cluster         = data.aws_ecs_cluster.current.arn
  desired_count   = 1
  task_definition = aws_ecs_task_definition.current.arn
  propagate_tags  = "SERVICE"

  launch_type = "FARGATE"


  network_configuration {
    security_groups = [aws_security_group.current.id]
    subnets         = var.subnet_ids
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  deployment_controller {
    type = var.deployment_controller_type
  }

  service_registries {
    registry_arn = aws_service_discovery_service.current.arn
  }

  dynamic "load_balancer" {
    for_each = var.load_balancers == null ? [] : var.load_balancers

    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = var.microservice_container.name
      container_port   = var.port
    }
  }

  tags = var.tags
}
