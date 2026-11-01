# 풀이 기록과 통계를 저장하는 PostgreSQL.
# infra/ 레이어에 있어서 작업이 끝나면 다른 리소스와 함께 destroy 된다 (데이터도 함께 사라진다).

resource "aws_db_subnet_group" "main" {
  name       = var.project
  subnet_ids = aws_subnet.private[*].id # RDS는 서브넷 그룹에 AZ가 2개 이상 있어야 한다.
}

resource "aws_db_instance" "main" {
  identifier     = var.project
  engine         = "postgres"
  engine_version = "17"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  # 비밀번호를 코드나 state에 두지 않는다. RDS가 Secrets Manager에 만들고 관리한다.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  # 비용 절감: 단일 AZ. 운영이라면 Multi-AZ로 장애 대비를 해야 한다.
  multi_az = false

  # 매일 만들고 지우는 실습 환경이라 백업과 삭제 보호를 끈다. 운영 환경에서는 반대로 해야 한다.
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true
}
