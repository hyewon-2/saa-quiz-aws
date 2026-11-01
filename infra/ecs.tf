# ECR 저장소는 bootstrap/ 레이어에서 만들었다. 여기서는 조회만 한다.
data "aws_ecr_repository" "app" {
  name = var.project
}

# 가장 최근에 push된 이미지를 배포한다. 저장소에 이미지가 하나도 없으면 plan이 실패한다.
data "aws_ecr_image" "latest" {
  repository_name = data.aws_ecr_repository.app.name
  most_recent     = true
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project}"
  retention_in_days = 7 # 로그 저장 비용을 줄이려고 짧게 둔다.
}

resource "aws_ecs_cluster" "main" {
  name = var.project

  setting {
    name  = "containerInsights"
    value = "disabled" # 켜면 지표당 비용이 붙는다. 모니터링 단계에서 다시 판단한다.
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.project
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # 태스크마다 ENI(IP)를 하나씩 받는다. Fargate는 이 모드만 지원한다.
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64" # 이미지를 x86(AMD64) PC와 GitHub Actions에서 빌드한다.
  }

  container_definitions = jsonencode([{
    name      = "app"
    image     = "${data.aws_ecr_repository.app.repository_url}@${data.aws_ecr_image.latest.image_digest}"
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    environment = [
      { name = "DB_HOST", value = aws_db_instance.main.address },
      { name = "DB_PORT", value = tostring(aws_db_instance.main.port) },
      { name = "DB_NAME", value = var.db_name },
      { name = "DB_USER", value = var.db_username },
    ]

    # 비밀번호는 태스크 정의에 값이 아니라 "위치"만 적는다. RDS가 만든 시크릿(JSON)의 password 키를 꺼낸다.
    # 주의: 비밀번호가 교체(rotation)돼도 이미 떠 있는 태스크는 옛 값을 갖고 있다. 새 태스크부터 새 값을 받는다.
    secrets = [
      { name = "DB_PASSWORD", valueFrom = "${aws_db_instance.main.master_user_secret[0].secret_arn}:password::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "app"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name            = var.project
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # 새 태스크가 ALB 헬스체크를 통과하기 전에 죽은 것으로 판단하지 않도록 기다리는 시간.
  health_check_grace_period_seconds = 30

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true # NAT 없이 ECR에서 이미지를 받으려면 필요하다 (network.tf 참고).
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  # 무중단 배포: 새 태스크가 정상이 된 뒤에 옛 태스크를 내린다.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # 새 버전이 계속 실패하면 배포를 멈추고 직전 버전으로 자동 롤백한다.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # 리스너가 먼저 있어야 서비스가 대상 그룹에 태스크를 등록할 수 있다.
  depends_on = [aws_lb_listener.http]

  # 배포 후 태스크 정의 버전은 GitHub Actions가 바꾼다. Terraform이 옛 버전으로 되돌리지 않게 무시한다.
  lifecycle {
    ignore_changes = [task_definition]
  }
}
