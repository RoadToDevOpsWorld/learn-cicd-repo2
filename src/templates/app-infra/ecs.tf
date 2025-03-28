resource "aws_ecs_cluster" "this" {
  name = "white-hart"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

# resource "aws_ecs_capacity_provider" "this" {
#   name = "this"

#   auto_scaling_group_provider {
#     auto_scaling_group_arn         = aws_autoscaling_group.this.arn
#     managed_termination_protection = "ENABLED"

#     managed_scaling {
#       maximum_scaling_step_size = 20
#       minimum_scaling_step_size = 1
#       status                    = "ENABLED"
#       target_capacity           = 10
#     }
#   }
# }

# Create an ECS Capacity Provider using the existing ASG
resource "aws_ecs_capacity_provider" "asg_capacity_provider" {
  name = "asg-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.this.arn
    managed_scaling {
      maximum_scaling_step_size = 10
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 5
    }
  }
}

# Associate the Capacity Provider with the ECS Cluster
resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = [aws_ecs_capacity_provider.asg_capacity_provider.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 2
    capacity_provider = aws_ecs_capacity_provider.asg_capacity_provider.name
  }
}

# Attach policies to the ECS task execution role to allow interaction with ECR
resource "aws_iam_role_policy" "ecs_task_execution_policy" {
  name   = "ecs_task_execution_policy"
  role   = aws_iam_role.ecs_task_execution_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "ecr:*"
        Resource = "*"
        Effect   = "Allow"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "this" {
  name = "/ecs/tradapp"

  tags = {
    Environment = "production"
    Application = "serviceA"
  }
}

# ECS task definition
resource "aws_ecs_task_definition" "service" {
  family                   = "service"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
   container_definitions    = jsonencode([
    {
      name      = "first"
      image     = "767397664936.dkr.ecr.us-east-1.amazonaws.com/ecr01:tradding-platform-14"
      cpu       = 1024  // Increase CPU units
      memory    = 1024
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort     = 8080
          protocol     = "tcp"  // Add protocol
        }
      ]
      logConfiguration = {  // Add logging
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn  # Use the execution role for pulling from ECR
  task_role_arn      = aws_iam_role.ecs_task_execution_role.arn   # Use the task role for additional permissions
}

# resource "aws_vpc" "main" {
#   cidr_block           = "10.0.0.0/16"
#   enable_dns_hostnames = true
#   enable_dns_support   = true

#   tags = {
#     Name = "ecs-vpc"
#   }
# }

# resource "aws_subnet" "private" {
#   count             = 2
#   vpc_id            = aws_vpc.main.id
#   cidr_block        = "10.0.${count.index + 1}.0/24"
#   availability_zone = data.aws_availability_zones.available.names[count.index]

#   tags = {
#     Name = "Private Subnet ${count.index + 1}"
#   }
# }

# Get available AZs
# data "aws_availability_zones" "available" {
#   state = "available"
# }

# resource "aws_internet_gateway" "main" {
#   vpc_id = aws_vpc.main.id

#   tags = {
#     Name = "Main IGW"
#   }
# }

resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "Security group for ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-security-group"
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs_task_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect    = "Allow"
        Sid       = ""
      }
    ]
  })
}

// Add this security group resource
resource "aws_security_group" "ecs_tasks" {
  name        = "ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = data.aws_vpc.default.id  // Make sure you have VPC defined

  ingress {
    protocol        = "tcp"
    from_port       = 8080
    to_port         = 8080
    security_groups = [aws_security_group.alb.id]  // If using ALB
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_service" "tradapp" {
  name            = "tradapp"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.service.arn
  desired_count   = 1
  # launch_type     = "EC2"  // Add this

  network_configuration {
    security_groups = [aws_security_group.ecs_tasks.id]
    subnets         = [data.aws_subnet.this1.id, data.aws_subnet.this2.id]   // Make sure you have private subnets defined
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.asg_capacity_provider.name
    weight           = 1
    base            = 1
  }

  ordered_placement_strategy {
    type  = "binpack"
    field = "cpu"
  }
}