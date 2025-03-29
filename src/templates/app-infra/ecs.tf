resource "aws_ecs_cluster" "this" {
  name = "white-hart"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

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
          "logs:*"
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
      image     = "637423192029.dkr.ecr.us-east-1.amazonaws.com/ecr01:tradding-platform-17"
      cpu       = 1024
      memory    = 1024
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort     = 8080
          protocol     = "tcp"
          appProtocol  = "http"
        }
      ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/tradapp"
        "awslogs-region"        = "us-east-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
    }
  ])

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn  # Use the execution role for pulling from ECR
}

resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "Security group for ALB"
  vpc_id      = data.aws_vpc.default.id

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

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_service" "tradapp" {
  name            = "tradapp"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.service.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.asg_capacity_provider.name
    weight            = 1
    base              = 1
  }


  ordered_placement_strategy {
    type  = "binpack"
    field = "cpu"
  }

  # Ensure the service can use the target group
  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "first"
    container_port   = 80
  }
}
