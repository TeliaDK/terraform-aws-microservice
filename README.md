# TeliaDK - AWS microservice module

Used for deploying microservices into AWS and utilise service discovery + service mesh (AppMesh).

The module will create the following resources:

1. New cloudwatch group under the /ecs/{var.app_name}
2. New security group
3. CloudMap service
4. AppMesh virtual router
5. AppMesh virtual service
6. AppMesh virtual node
7. AppMesh route
8. xray daemon sidecar ECS container definition
9. envoy proxy sidecar ECS container definition
10. microservice ECS container definition
11. microservice ECS task definition
12. microservice ECS service

## Inputs:

| Name                                 | Description                                                                                                                                                              |     Type     |  Default   | Required |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | :----------: | :--------: | :------: |
| region                               | The AWS region to deploy the compute module in                                                                                                                           |    string    | eu-west-1  |    no    |
| microservice_container               | Settings for the microservice container                                                                                                                                  |    object    |     -      |   yes    |
| port                                 | The port that will be uesd for port mapping <HOST>:<CONTAINER>                                                                                                           |    number    |    8080    |    no    |
| cpu                                  | The total vCPU to allocate for the ECS service. Valid configuration at https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html                      |    number    |    512     |    no    |
| memory                               | The total memory to allocate for the ECS service. Valid configuration at https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html                    |    number    |    2048    |    no    |
| xray_cpu                             | The total vCPU to allocate to the xray container                                                                                                                         |    number    |     32     |    no    |
| xray_memory                          | The total memory to allocate to the xray container                                                                                                                       |    number    |    256     |    no    |
| envoy_cpu                            | The total vCPU to allocate to the envoy container                                                                                                                        |    number    |    256     |    no    |
| envoy_cpu                            | The total memory to allocate to the envoy container                                                                                                                      |    number    |    512     |    no    |
| microservice_cpu                     | The total vCPU to allocate to the microservice                                                                                                                           |    number    |    224     |    no    |
| microservice_memory                  | The total memory to allocate to the microservice                                                                                                                         |    number    |    1280    |    no    |
| ecs_cluster_name                     | The ECS cluster to deploy the ECS Fargate into                                                                                                                           |    string    |     -      |   yes    |
| app_name                             | The shared name for the ECS Fargate service and task definitions                                                                                                         |    string    |     -      |   yes    |
| task_execution_role_arn              | The name of the execution role to use with the service                                                                                                                   |    string    |    null    |    no    |
| task_role_arn                        | The name of the task role to use with the service                                                                                                                        |    string    |    null    |    no    |
| deployment_controller_type           | The deployment controller type to use in ECS service. For blue/green, CODE_DEPLOY must be used                                                                           |    string    |    ECS     |    no    |
| envoy_container_name                 | The name of the envoy container to be used in AppMesh proxy                                                                                                              |    string    |   envoy    |    no    |
| envoy_ignored_uid                    | Which UID to ignore in envoy docker container                                                                                                                            |    string    |    1337    |    no    |
| service_discovery_dns_routing_policy | The routing policy that you want to apply to all records that Route 53 creates when you register an instance and specify the service. Valid Values: MULTIVALUE, WEIGHTED |    string    | MULTIVALUE |    no    |
| cloud_map                            | Settings needed to setup service discovery through AWS CloudMap                                                                                                          |    object    |     -      |   yes    |
| env_variables                        | Environment variables for the service                                                                                                                                    |    object    |    null    |    no    |
| secrets                              | Secrets for the service. Use arn of paramaters in parameter store for the valueFrom property                                                                             |    object    |    null    |    no    |
| vpc_id                               | The VPC to use                                                                                                                                                           |    string    |     -      |   yes    |
| subnet_ids                           | The subnets for the ECS service network configuration                                                                                                                    | list(string) |     -      |   yes    |
| appmesh_name                         | Name of AppMesh to register service components in                                                                                                                        |    string    |     -      |   yes    |
| tags                                 | Tags to use for the components created by the module                                                                                                                     | map(string)  |     -      |   yes    |

## Example:

```hcl

locals {
  tags = {
    author = "teliaDK"
  }

  env_variables = [
    { name = "environment", value = "dev" },
  ]
}


module "microservice" {
  source  = "git::https://github.com/teliadk/terraform-aws-microservice?ref=0.0.3"

  region = "eu-west-1"

  app_name                = "my-service"
  task_execution_role_arn = "arn::executionRole"
  task_role_arn           = "arn::taskRole"
  ecs_cluster_name        = "microservice-cluster"
  vpc_id                  = "vpc-id-123"
  subnet_ids              = ["1234","4321"]
  appmesh_name            = "service-mesh"
  env_variables           = local.env_variables
  port                    = 80

  secrets = [
    {
      name      = "SUPERSECRET"
      valueFrom = aws_ssm_parameter.certificate_password.arn
    }
  ]

  microservice_container = {
    name   = "my-service"
    image  = "1234567890.dkr.ecr.eu-west-1.amazonaws.com/my-service"
    cpu    = 224
    memory = 1280
  }

  cloud_map = {
    namespace = {
      id   = "123456789"
      name = "internal.svc.acme.org"
    }
    service = {
      name = "my-service"
    }
  }

  tags = local.tags
}
```
