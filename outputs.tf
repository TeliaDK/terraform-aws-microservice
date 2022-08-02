output "task_definition_arn" {
  value = aws_ecs_task_definition.current.arn
}

output "aws_security_group_id" {
  value = aws_security_group.current.id
}

output "default_up_actions" {
  value = local.default_up_actions
}

output "default_down_actions" {
  value = local.default_down_actions
}