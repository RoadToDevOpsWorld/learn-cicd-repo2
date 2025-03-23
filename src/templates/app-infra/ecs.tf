resource "aws_ecs_cluster" "this" {
  name = "white-hart"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_ecs_capacity_provider" "this" {
  name = "this"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.this.arn

    managed_scaling {
      maximum_scaling_step_size = 2
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 2
    }
  }
}

# Define the ECS task execution role (for pulling the image from ECR)
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

# Attach policies to the ECS task execution role to allow interaction with ECR
resource "aws_iam_role_policy" "ecs_task_execution_policy" {
  name   = "ecs_task_execution_policy"
  role   = aws_iam_role.ecs_task_execution_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "ecr:GetAuthorizationToken"
        Resource = "arn:aws:ecr:us-east-1:905418418143:repository/ecr01"
        Effect   = "Allow"
      },
      {
        Action   = "ecr:BatchCheckLayerAvailability"
        Resource = "arn:aws:ecr:us-east-1:905418418143:repository/ecr01"
        Effect   = "Allow"
      },
      {
        Action   = "ecr:GetDownloadUrlForLayer"
        Resource = "arn:aws:ecr:us-east-1:905418418143:repository/ecr01"
        Effect   = "Allow"
      }
    ]
  })
}

# Define the ECS task role (for the permissions your task requires)
resource "aws_iam_role" "ecs_task_role" {
  name = "ecs_task_role"

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

# Optional: Attach additional policies for ECS task permissions, if needed
resource "aws_iam_role_policy" "ecs_task_policy" {
  name   = "ecs_task_policy"
  role   = aws_iam_role.ecs_task_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "s3:ListBucket"
        Resource = "*"
        Effect   = "Allow"
      }
    ]
  })
}

# ECS task definition
resource "aws_ecs_task_definition" "service" {
  family                   = "service"
  container_definitions    = jsonencode([
    {
      name      = "first"
      image     = "905418418143.dkr.ecr.us-east-1.amazonaws.com/ecr01:tradding-platform-10"  # Correct ECR repository and image tag
      cpu       = 10
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 8080
        }
      ]
    }
  ])

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn  # Use the execution role for pulling from ECR
  task_role_arn      = aws_iam_role.ecs_task_role.arn            # Use the task role for additional permissions
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

resource "aws_iam_role_policy" "ecs_task_execution_policy" {
  name   = "ecs_task_execution_policy"
  role   = aws_iam_role.ecs_task_execution_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "ecr:GetAuthorizationToken"
        Resource = "arn:aws:ecr:us-east-1:905418418143:repository/ecr01"
        Effect   = "Allow"
      },
      {
        Action   = "ecr:BatchCheckLayerAvailability"
        Resource = "arn:aws:ecr:us-east-1:905418418143:repository/ecr01"
        Effect   = "Allow"
      },
      {
        Action   = "ecr:GetDownloadUrlForLayer"
        Resource = "arn:aws:ecr:us-east-1:905418418143:repository/ecr01"
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_ecs_service" "tradapp" {
  name            = "tradapp"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.service.arn
  desired_count   = 1

  ordered_placement_strategy {
    type  = "binpack"
    field = "cpu"
  }

}