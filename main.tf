locals {
  cloudwatch_retention_in_days                     = 30
  service_discovery_dns_ttl                        = 10
  service_discovery_health_check_failure_threshold = 1
  aws_ecs_task_definition_family                   = var.app_name

  cpu_utilization_high_threshold    = var.autoscaling_cpu != null ? var.autoscaling_cpu.utilization_high_threshold : 0
  cpu_utilization_low_threshold     = var.autoscaling_cpu != null ? var.autoscaling_cpu.utilization_low_threshold : 0
  memory_utilization_high_threshold = var.autoscaling_memory != null ? var.autoscaling_memory.utilization_high_threshold : 0
  memory_utilization_low_threshold  = var.autoscaling_memory != null ? var.autoscaling_memory.utilization_low_threshold : 0

  thresholds = {
    CPUUtilizationHighThreshold    = min(max(local.cpu_utilization_high_threshold, 0), 100)
    CPUUtilizationLowThreshold     = min(max(local.cpu_utilization_low_threshold, 0), 100)
    MemoryUtilizationHighThreshold = min(max(local.memory_utilization_high_threshold, 0), 100)
    MemoryUtilizationLowThreshold  = min(max(local.memory_utilization_low_threshold, 0), 100)
  }
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

  ingress {
    protocol    = "tcp"
    from_port   = var.port
    to_port     = var.port
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

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
  source                       = "git::https://github.com/cloudposse/terraform-aws-ecs-container-definition.git?ref=0.23.0"
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
  source                       = "git::https://github.com/cloudposse/terraform-aws-ecs-container-definition.git?ref=0.23.0"
  container_name               = "envoy"
  container_image              = "840364872350.dkr.ecr.eu-west-1.amazonaws.com/aws-appmesh-envoy:v1.12.2.1-prod"
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
  source                       = "git::https://github.com/cloudposse/terraform-aws-ecs-container-definition.git?ref=0.23.0"
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
    ${module.container_definition_xray.json_map},
    ${module.container_definition_envoy.json_map},
    ${module.container_definition_service.json_map}
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
    ignore_changes = [task_definition, desired_count]
  }

  deployment_controller {
    type = var.deployment_controller_type
  }

  service_registries {
    registry_arn = aws_service_discovery_service.current.arn
  }

  dynamic "load_balancer" {
    for_each = var.load_balancer == null ? [] : [var.load_balancer]

    content {
      target_group_arn = load_balancer.value.arn
      container_name   = var.microservice_container.name
      container_port   = var.port
    }
  }

  tags = var.tags
}

module "scale_up_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  enabled    = var.autoscaling.enabled
  name       = var.autoscaling.name
  namespace  = var.autoscaling.namespace
  stage      = var.autoscaling.stage
  attributes = compact(concat(var.autoscaling.attributes, ["up"]))
  tags       = var.tags
}

module "scale_down_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  enabled    = var.autoscaling.enabled
  name       = var.autoscaling.name
  namespace  = var.autoscaling.namespace
  stage      = var.autoscaling.stage
  attributes = compact(concat(var.autoscaling.attributes, ["down"]))
  tags       = var.tags
}


module "cpu_utilization_high_alarm_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  enabled    = var.autoscaling.enabled
  name       = var.autoscaling.name
  namespace  = var.autoscaling.namespace
  stage      = var.autoscaling.stage
  attributes = compact(concat(var.autoscaling.attributes, ["cpu", "utilization", "high"]))
  delimiter  = var.autoscaling_delimiter
  tags       = var.tags
}

module "cpu_utilization_low_alarm_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  enabled    = var.autoscaling.enabled
  name       = var.autoscaling.name
  namespace  = var.autoscaling.namespace
  stage      = var.autoscaling.stage
  attributes = compact(concat(var.autoscaling.attributes, ["cpu", "utilization", "low"]))
  delimiter  = var.autoscaling_delimiter
  tags       = var.tags
}

module "memory_utilization_high_alarm_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  enabled    = var.autoscaling.enabled
  name       = var.autoscaling.name
  namespace  = var.autoscaling.namespace
  stage      = var.autoscaling.stage
  attributes = compact(concat(var.autoscaling.attributes, ["memory", "utilization", "high"]))
  delimiter  = var.autoscaling_delimiter
  tags       = var.tags
}

module "memory_utilization_low_alarm_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  enabled    = var.autoscaling.enabled
  name       = var.autoscaling.name
  namespace  = var.autoscaling.namespace
  stage      = var.autoscaling.stage
  attributes = compact(concat(var.autoscaling.attributes, ["memory", "utilization", "low"]))
  tags       = var.tags
}

resource "aws_appautoscaling_target" "default" {
  count              = var.autoscaling.enabled ? 1 : 0
  service_namespace  = "ecs"
  resource_id        = aws_ecs_service.current.id
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.autoscaling.min_capacity
  max_capacity       = var.autoscaling.max_capacity
}

resource "aws_appautoscaling_policy" "up" {
  count              = var.autoscaling.enabled ? 1 : 0
  name               = module.scale_up_label.id
  service_namespace  = "ecs"
  resource_id        = aws_ecs_service.current.id
  scalable_dimension = "ecs:service:DesiredCount"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = var.autoscaling.scale_up_cooldown
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = var.autoscaling.scale_up_adjustment
    }
  }
}

resource "aws_appautoscaling_policy" "down" {
  count              = var.autoscaling.enabled ? 1 : 0
  name               = module.scale_down_label.id
  service_namespace  = "ecs"
  resource_id        = aws_ecs_service.current.id
  scalable_dimension = "ecs:service:DesiredCount"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = var.autoscaling.scale_down_cooldown
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = var.autoscaling.scale_down_adjustment
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_utilization_high" {
  count               = var.autoscaling_cpu != null ? 1 : 0
  alarm_name          = module.cpu_utilization_high_alarm_label.id
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.autoscaling_cpu.utilization_high_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = var.autoscaling_cpu.utilization_high_period
  statistic           = "Average"
  threshold           = local.thresholds["CPUUtilizationHighThreshold"]

  alarm_description = format(
    var.autoscaling_alarm_description,
    "CPU",
    "High",
    var.autoscaling_cpu.utilization_high_period / 60,
    var.autoscaling_cpu.utilization_high_evaluation_periods
  )

  alarm_actions = compact(var.autoscaling_cpu.utilization_high_alarm_actions)
  ok_actions    = compact(var.autoscaling_cpu.utilization_high_ok_actions)

  dimensions = {
    "ClusterName" = aws_ecs_service.current.cluster
    "ServiceName" = aws_ecs_service.current.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_utilization_low" {
  count               = var.autoscaling_cpu != null ? 1 : 0
  alarm_name          = module.cpu_utilization_low_alarm_label.id
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.autoscaling_cpu.utilization_low_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = var.autoscaling_cpu.utilization_low_period
  statistic           = "Average"
  threshold           = local.thresholds["CPUUtilizationLowThreshold"]

  alarm_description = format(
    var.autoscaling_alarm_description,
    "CPU",
    "Low",
    var.autoscaling_cpu.utilization_low_period / 60,
    var.autoscaling_cpu.utilization_low_evaluation_periods
  )

  alarm_actions = compact(var.autoscaling_cpu.utilization_low_alarm_actions)
  ok_actions    = compact(var.autoscaling_cpu.utilization_low_ok_actions)

  dimensions = {
    "ClusterName" = aws_ecs_service.current.cluster
    "ServiceName" = aws_ecs_service.current.name
  }
}

resource "aws_cloudwatch_metric_alarm" "memory_utilization_high" {
  count               = var.autoscaling_memory != null ? 1 : 0
  alarm_name          = module.memory_utilization_high_alarm_label.id
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.autoscaling_memory.utilization_high_evaluation_periods
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = var.autoscaling_memory.utilization_high_period
  statistic           = "Average"
  threshold           = local.thresholds["MemoryUtilizationHighThreshold"]

  alarm_description = format(
    var.autoscaling_alarm_description,
    "Memory",
    "Hight",
    var.autoscaling_memory.utilization_high_period / 60,
    var.autoscaling_memory.utilization_high_evaluation_periods
  )

  alarm_actions = compact(var.autoscaling_memory.utilization_high_alarm_actions)
  ok_actions    = compact(var.autoscaling_memory.utilization_high_ok_actions)

  dimensions = {
    "ClusterName" = aws_ecs_service.current.cluster
    "ServiceName" = aws_ecs_service.current.name
  }
}

resource "aws_cloudwatch_metric_alarm" "memory_utilization_low" {
  count               = var.autoscaling_memory != null ? 1 : 0
  alarm_name          = module.memory_utilization_low_alarm_label.id
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.autoscaling_memory.utilization_low_evaluation_periods
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = var.autoscaling_memory.utilization_low_period
  statistic           = "Average"
  threshold           = local.thresholds["MemoryUtilizationLowThreshold"]

  alarm_description = format(
    var.autoscaling_alarm_description,
    "Memory",
    "Low",
    var.autoscaling_memory.utilization_low_period / 60,
    var.autoscaling_memory.utilization_low_evaluation_periods
  )

  alarm_actions = compact(var.autoscaling_memory.utilization_low_alarm_actions)
  ok_actions    = compact(var.autoscaling_memory.utilization_low_ok_actions)

  dimensions = {
    "ClusterName" = aws_ecs_service.current.cluster
    "ServiceName" = aws_ecs_service.current.name
  }
}
