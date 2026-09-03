# 원본 스크립트 2단계: RDS PostgreSQL 생성
resource "aws_db_instance" "demo" {
  identifier             = "demo-db"
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  username               = "appuser"
  password               = "apppassword123"
  vpc_security_group_ids = [aws_security_group.demo.id]

  # 로컬 실습용 - 실제 운영에선 이 두 값을 그대로 쓰면 안 됨
  skip_final_snapshot = true
  publicly_accessible = true
}
