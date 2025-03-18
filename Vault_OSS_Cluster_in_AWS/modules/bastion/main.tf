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

resource "aws_security_group" "bastion" {
  name   = "${var.resource_name_prefix}-bastion"
  vpc_id = var.vpc_id

  tags = merge(
    { Name = "${var.resource_name_prefix}-sg" },
    var.common_tags,
  )
}

resource "aws_security_group_rule" "bastion_ssh" {
  description       = "Allow ssh to bastion hosts"
  security_group_id = aws_security_group.bastion.id
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "node_exporter_inbound" {
  description       = "Allow Prometheus to scrape node_exporter"
  security_group_id = aws_security_group.bastion.id
  type              = "ingress"
  from_port         = 9100
  to_port           = 9100
  protocol          = "tcp"
  cidr_blocks       = ["${var.private_ip_monitoring}/32"]
}

resource "aws_security_group_rule" "bastion_outbound" {
  description       = "Allow bastion nodes to send outbound traffic"
  security_group_id = aws_security_group.bastion.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_launch_template" "bastion" {
  name          = "${var.resource_name_prefix}-bastion"
  image_id      = var.user_supplied_ami_id != null ? var.user_supplied_ami_id : data.aws_ami.ubuntu[0].id
  instance_type = var.instance_type
  key_name      = var.bastion_key_name != null ? var.bastion_key_name : null
  user_data     = var.userdata_bastion_script

  network_interfaces {
    associate_public_ip_address = true
    security_groups = [
      aws_security_group.bastion.id,
    ]
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



resource "aws_autoscaling_group" "bastion" {
  name                = "${var.resource_name_prefix}-bastion"
  min_size            = var.bastion_node_count
  max_size            = var.bastion_node_count
  desired_capacity    = var.bastion_node_count
  vpc_zone_identifier = var.bastion_subnets

  launch_template {
    id      = aws_launch_template.bastion.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.resource_name_prefix}-bastion-server"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }

}