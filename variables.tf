variable "region" {
  type        = string
  default     = "eu-west-1"
  description = "The AWS region to deploy the compute module in"
}

variable "microservice_container" {
  type = object({
    name   = string
    image  = string
    cpu    = number
    memory = number
  })
  description = "Settings for the microservice container"
}

variable "port" {
  type        = number
  description = "The port that will be uesd for port mapping <HOST>:<CONTAINER>"
  default     = 8080
}

variable "cpu" {
  type        = number
  description = "The total vCPU to allocate for the ECS service. Valid configuration at https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html "
  default     = 512
}

variable "memory" {
  type        = number
  description = "The total memory to allocate for the ECS service. Valid configuration at https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html"
  default     = 2048
}

variable "xray_cpu" {
  type        = number
  description = "The total vCPU to allocate to the xray container"
  default     = 32
}

variable "xray_memory" {
  type        = number
  description = "The total memory to allocate to the xray container"
  default     = 256
}

variable "envoy_cpu" {
  type        = number
  description = "The total vCPU to allocate to the envoy container"
  default     = 256
}

variable "envoy_memory" {
  type        = number
  description = "The total memory to allocate to the envoy container"
  default     = 512
}

variable "microservice_cpu" {
  type        = number
  description = "The total vCPU to allocate to the microservice"
  default     = 224
}

variable "microservice_memory" {
  type        = number
  description = "The total memory to allocate to the microservice"
  default     = 1280
}

variable "ecs_cluster_name" {
  type        = string
  description = "The ECS cluster to deploy the ECS Fargate into"
}

variable "app_name" {
  type        = string
  description = "The shared name for the ECS Fargate service and task definitions"
}

variable "task_execution_role_arn" {
  type        = string
  description = "The name of the execution role to use with the service"
  default     = ""
}

variable "task_role_arn" {
  type        = string
  description = "The name of the task role to use with the service"
  default     = ""
}

variable "deployment_controller_type" {
  type        = string
  description = "The deployment controller type to use in ECS service. For blue/green, CODE_DEPLOY must be used"
  default     = "ECS"
}

variable "envoy_container_name" {
  type        = string
  description = "The name of the envoy container to be used in AppMesh proxy"
  default     = "envoy"
}

variable "envoy_ignored_uid" {
  type        = string
  description = "Which UID to ignore in envoy docker container"
  default     = "1337"
}

variable "service_discovery_dns_routing_policy" {
  type        = string
  description = "The routing policy that you want to apply to all records that Route 53 creates when you register an instance and specify the service. Valid Values: MULTIVALUE, WEIGHTED"
  default     = "MULTIVALUE"
}

variable "cloud_map" {
  type = object({
    namespace = object({
      name = string
      id   = string
    })
    service = object({
      name = string
    })
  })
  description = "Settings needed to setup service discovery through AWS CloudMap"
}

variable "env_variables" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "Environment variables for the service."
  default     = null
}

variable "secrets" {
  type = list(object({
    name      = string
    valueFrom = string
  }))
  description = "Secrets for the service. Use arn of paramaters in parameter store for the valueFrom property"
  default     = null
}

variable "vpc_id" {
  type        = string
  description = "The VPC to use"
}

variable "subnet_ids" {
  type        = list(string)
  description = "The subnets for the ECS service network configuration"
}

variable "appmesh_name" {
  type        = string
  description = "Name of AppMesh to register service components in"
}

variable "tags" {
  type = map(string)
}

variable "load_balancer" {
  type = object({
    arn = string
  })
  default     = null
  description = "Load balancer config to be used in ECS service"
}

variable "awslogs_datetime_format" {
  type        = string
  description = "The format used in logs written by the application in the container. Used for ensuring that the aws log driver can parse the logs correctly and not split them into several entries (e.g. stack traces are kept in one entry)."
  default     = "%Y-%m-%d %H:%M:%S"
}

variable "autoscaling" {
  type = object({
    enabled               = bool
    name                  = string
    namespace             = string
    stage                 = string
    attributes            = list(string)
    min_capacity          = number
    max_capacity          = number
    scale_down_adjustment = number
    scale_down_cooldown   = number
    scale_up_adjustment   = number
    scale_up_cooldown     = number
  })
  default     = null
  description = "Used to define and enable autoscaling for the ECS service"
}


variable "autoscaling_alarm_description" {
  type        = string
  description = "The string to format and use as the alarm description"
  default     = "Average service %v utilization %v last %d minute(s) over %v period(s)"
}

variable "autoscaling_delimiter" {
  type        = string
  default     = "-"
  description = "Delimiter between `namespace`, `stage`, `name` and `attributes`"
}

variable "autoscaling_cpu" {
  type = object({
    utilization_high_threshold          = number
    utilization_high_evaluation_periods = number
    utilization_high_period             = number
    utilization_high_alarm_actions      = list(string)
    utilization_high_ok_actions         = list(string)
    utilization_low_threshold           = number
    utilization_low_evaluation_periods  = number
    utilization_low_period              = number
    utilization_low_alarm_actions       = list(string)
    utilization_low_ok_actions          = list(string)
  })
  default     = null
  description = "Used to define autoscaling based on CPU usage"
}

variable "autoscaling_memory" {
  type = object({
    utilization_high_threshold          = number
    utilization_high_evaluation_periods = number
    utilization_high_period             = number
    utilization_high_alarm_actions      = list(string)
    utilization_high_ok_actions         = list(string)
    utilization_low_threshold           = number
    utilization_low_evaluation_periods  = number
    utilization_low_period              = number
    utilization_low_alarm_actions       = list(string)
    utilization_low_ok_actions          = list(string)
  })
  default     = null
  description = "Used to define autoscaling based on Memory usage"
}
