data "aws_ami" "ubuntu" {
  count       = var.user_supplied_ami_id != null ? 0 : 1
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_security_group" "monitoring" {
  name   = "${var.resource_name_prefix}-monitoring"
  vpc_id = var.vpc_id

  tags = merge(
    { Name = "${var.resource_name_prefix}-sg" },
    var.common_tags,
  )
}

resource "aws_security_group_rule" "monitoring_ingress" {
  for_each          = var.ingress_ports
  description       = "Allow ${each.key} access"
  security_group_id = aws_security_group.monitoring.id
  type              = "ingress"
  from_port         = each.value
  to_port           = each.value
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "monitoring_outbound" {
  description       = "Allow monitoring nodes to send outbound traffic"
  security_group_id = aws_security_group.monitoring.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_launch_template" "monitoring" {
  name          = "${var.resource_name_prefix}-monitoring"
  image_id      = var.user_supplied_ami_id != null ? var.user_supplied_ami_id : data.aws_ami.ubuntu[0].id
  instance_type = var.instance_type
  key_name      = var.monitoring_key_name != null ? var.monitoring_key_name : null
  user_data     = var.userdata_monitoring_script

  network_interfaces {
    subnet_id                   = var.monitoring_subnets[2]
    associate_public_ip_address = false
    security_groups = [
      aws_security_group.monitoring.id,
    ]
    private_ip_address = var.private_ip_monitoring
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_type           = "gp3"
      volume_size           = 25
      throughput            = 150
      iops                  = 3000
      delete_on_termination = true
    }
  }

  iam_instance_profile {
    name = var.aws_iam_instance_profile
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
}

resource "aws_instance" "monitoring" {
  launch_template {
    id      = aws_launch_template.monitoring.id
    version = "$Latest"
  }
  tags = merge({ "Name" = "${var.resource_name_prefix}-monitoring-server" }, var.common_tags)
}
