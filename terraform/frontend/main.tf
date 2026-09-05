# Security Group for Internal ALB (Accessible only from Corporate Network)
resource "aws_security_group" "alb_sg" {
  name        = "private-rag-alb-sg"
  description = "Allow internal traffic from corporate network to ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from Corporate Network"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.corporate_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group for ECS Fargate Tasks
resource "aws_security_group" "ecs_tasks_sg" {
  name        = "private-rag-ecs-tasks-sg"
  description = "Allow inbound access from ALB only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 8501
    to_port         = 8501
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Internal Application Load Balancer
resource "aws_lb" "frontend_alb" {
  name               = "private-rag-frontend-alb"
  internal           = true # Critical: Ensures the ALB is not exposed to the internet
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.private_subnet_ids
}

# ALB Target Group
resource "aws_lb_target_group" "frontend_tg" {
  name        = "private-rag-frontend-tg"
  port        = 8501
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/_stcore/health"
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }
}

# ALB Listener
resource "aws_lb_listener" "frontend_listener" {
  load_balancer_arn = aws_lb.frontend_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend_tg.arn
  }
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_execution_role" {
  name = "rag-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Cluster
resource "aws_ecs_cluster" "rag_cluster" {
  name = "private-rag-cluster"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "frontend_task" {
  family                   = "private-rag-frontend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "streamlit-frontend"
      image     = var.ecr_image_url
      essential = true
      portMappings = [
        {
          containerPort = 8501
          hostPort      = 8501
        }
      ]
      environment = [
        {
          name  = "API_GATEWAY_URL"
          value = var.api_gateway_invoke_url
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/private-rag-frontend"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# ECS Service (Serverless compute for containers)
resource "aws_ecs_service" "frontend_service" {
  name            = "private-rag-frontend-service"
  cluster         = aws_ecs_cluster.rag_cluster.id
  task_definition = aws_ecs_task_definition.frontend_task.arn
  desired_count   = 2 # High availability across subnets
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [aws_security_group.ecs_tasks_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend_tg.arn
    container_name   = "streamlit-frontend"
    container_port   = 8501
  }

  depends_on = [aws_lb_listener.frontend_listener]
}
