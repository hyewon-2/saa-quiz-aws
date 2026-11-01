data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# 실행 역할(execution role): ECS가 태스크를 "띄울 때" 쓰는 권한.
# ECR에서 이미지를 받고, CloudWatch Logs에 로그 스트림을 만드는 데 쓴다.
resource "aws_iam_role" "task_execution" {
  name               = "${var.project}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# DB 비밀번호는 ECS가 컨테이너를 띄울 때 Secrets Manager에서 꺼내 환경변수로 넣어 준다 (ecs.tf의 secrets).
# 그래서 앱(태스크 역할)이 아니라 ECS(실행 역할)에 읽기 권한을 준다. 이 시크릿 하나만 읽을 수 있다.
data "aws_iam_policy_document" "read_db_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.main.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role_policy" "task_execution_db_secret" {
  name   = "read-db-secret"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.read_db_secret.json
}

# 태스크 역할(task role): 컨테이너 안의 "앱 코드"가 AWS API를 호출할 때 쓰는 권한.
# 지금은 앱이 AWS API를 직접 호출하지 않아서 비어 있다.
resource "aws_iam_role" "task" {
  name               = "${var.project}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}
