output "task_definition_arn" {
  value = aws_ecs_task_definition.current.arn
}

output "aws_security_group_id" {
  value = aws_security_group.current.id
}

output "default_cpu_utilization_high_alarm_actions" {
  value = local.autoscaling_enabled ? [aws_appautoscaling_policy.cpuUp[0].arn] : []
}

output "default_cpu_utilization_low_alarm_actions" {
  value = local.autoscaling_enabled ? [aws_appautoscaling_policy.cpuDown[0].arn] : []
}

output "default_memory_utilization_high_alarm_actions" {
  value = local.autoscaling_enabled ? [aws_appautoscaling_policy.memoryUp[0].arn] : []
}

output "default_memory_utilization_low_alarm_actions" {
  value = local.autoscaling_enabled ? [aws_appautoscaling_policy.memoryDown[0].arn] : []
}