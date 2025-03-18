# output "asg_name" {
#   description = "Name of autoscaling group"
#   value       = aws_autoscaling_group.monitoring.name
# }

output "launch_template_id" {
  description = "ID of launch template for monitoring autoscaling group"
  value       = aws_launch_template.monitoring.id
}

output "monitoring_sg_id" {
  description = "Security group ID of monitoring cluster"
  value       = aws_security_group.monitoring.id
}