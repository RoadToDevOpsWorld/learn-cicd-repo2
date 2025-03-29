terraform {
  backend "s3" {}
}

provider "aws" {
  region = "us-east-1"
}

variable "cidr1" {}
variable "cidr2" {}
variable "env" {}

# Fetch the latest AMI owned by the user
data "aws_ami" "amazon2" {
  most_recent = true
  owners      = ["amazon"]
  image_id = "ami-011f06ce3c4c42cbc"
}

data "aws_vpc" "default" {
  default = true
}

# Lookup an existing subnet with a specific CIDR block
data "aws_subnet" "this1" {
  filter {
    name   = "cidr-block"
    values = [var.cidr1]
  }
}

# Lookup an existing subnet with a specific CIDR block
data "aws_subnet" "this2" {
  filter {
    name   = "cidr-block"
    values = [var.cidr2]
  }
}


resource "aws_iam_role" "this" {
  name = "ec2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    tag-key = "tag-value"
  }
}

resource "aws_iam_policy_attachment" "this" {
  name       = "test-attachment"
  roles      = [aws_iam_role.this.name]
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "this" {
  name = "ec2"
  role = aws_iam_role.this.name
}

resource "aws_iam_policy_attachment" "ssm_policy" {
  name       = "ssm-policy-attachment"
  roles      = [aws_iam_role.this.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create a Launch Template
resource "aws_launch_template" "this" {
  name_prefix   = "launch-template-${var.env}"
  image_id      = data.aws_ami.amazon2.id
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type = "gp3"
      delete_on_termination = true
      volume_size = 30
    }
  }
  instance_type = "t3.medium"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.this2.id]
  }
  iam_instance_profile {
    name = "ec2"
  }
  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "ASG-Instance"
    }
  }
}

# Create an Auto Scaling Group using the existing subnet
resource "aws_autoscaling_group" "this" {
  name                = "asg-${var.env}"
  desired_capacity    = 1
  max_size            = 1
  min_size            = 1
  vpc_zone_identifier = [data.aws_subnet.this1.id, data.aws_subnet.this2.id]
  target_group_arns = [aws_lb_target_group.this.arn]

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

# Security Group
resource "aws_security_group" "this1" {
  name_prefix = "alb-sg-${var.env}"
}

resource "aws_security_group" "this2" {
  name_prefix = "ec2-sg-${var.env}"
}

resource "aws_vpc_security_group_ingress_rule" "this1" {
  security_group_id = aws_security_group.this2.id
  referenced_security_group_id = aws_security_group.this1.id
  from_port   = 8080
  ip_protocol = "tcp"
  to_port     = 8080
}

resource "aws_vpc_security_group_egress_rule" "this1" {
  security_group_id = aws_security_group.this2.id
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = "-1"
  ip_protocol = "-1"
  to_port     = "-1"
}


resource "aws_lb" "this" {
  name               = "alb-tf-${var.env}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.this1.id]
  subnets            = [data.aws_subnet.this1.id, data.aws_subnet.this2.id]

  enable_deletion_protection = false

  # access_logs {
  # bucket  = aws_s3_bucket.lb_logs.id
  #  prefix  = "test-lb"
  #  enabled = true
  # }

  tags = {
    Environment = var.env
  }
}

# Create a target group for the ALB
resource "aws_lb_target_group" "this" {
  name     = "target-group-${var.env}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_subnet.this1.vpc_id
  
  health_check {
    enabled             = true
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }
}

# Create a listener on port 80 for the ALB
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.this.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
