output "asg_name" {
  description = "Name of autoscaling group"
  value       = aws_autoscaling_group.bastion.name
}

output "launch_template_id" {
  description = "ID of launch template for bastion autoscaling group"
  value       = aws_launch_template.bastion.id
}

output "bastion_sg_id" {
  description = "Security group ID of bastion cluster"
  value       = aws_security_group.bastion.id
}