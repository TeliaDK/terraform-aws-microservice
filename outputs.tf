output "task_definition_arn" {
  value = aws_ecs_task_definition.current.arn
}

output "aws_security_group_id" {
  value = aws_security_group.current.id
}

output "default_utilization_high_alarm_actions" {
  value = local.autoscaling_enabled ? [aws_appautoscaling_policy.up[0].arn] : []
}

output "default_utilization_low_alarm_actions" {
  value = local.autoscaling_enabled ? [aws_appautoscaling_policy.down[0].arn] : []
}
