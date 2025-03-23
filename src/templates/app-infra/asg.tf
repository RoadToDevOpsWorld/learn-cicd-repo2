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
data "aws_ami" "latest_owned_ami" {
  owners      = ["self"]
  most_recent = true

  filter {
    name   = "state"
    values = ["available"]
  }
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


# Create a Launch Template
resource "aws_launch_template" "this" {
  name_prefix   = "launch-template-${var.env}"
  image_id      = data.aws_ami.latest_owned_ami.id
  instance_type = "t3.medium"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.this2.id]
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
  desired_capacity    = 2
  max_size            = 2
  min_size            = 2
  vpc_zone_identifier = [data.aws_subnet.this1.id, data.aws_subnet.this2.id]
  target_group_arns = [aws_lb_target_group.this.arn]

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "ASG-${var.env}"
    propagate_at_launch = true
  }
}

# Security Group
resource "aws_security_group" "this1" {
  name_prefix = "alb-sg-${var.env}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
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
