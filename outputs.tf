output "task_definition_arn" {
  value = aws_ecs_task_definition.current.arn
}

output "aws_security_group_id" {
  value = aws_security_group.current.id
}
