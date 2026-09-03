# 원본 스크립트 11단계: ECS Cluster
resource "aws_ecs_cluster" "demo" {
  name = "demo-cluster"
}

# 원본 스크립트 12단계 대응.
#
# 원본 스크립트는 매 실행마다 로컬에서 docker build/push 한 실제 이미지 태그를
# 태스크 정의에 박아 넣었지만, IaC/CI-CD가 분리된 구조에서는 이 리소스가
# "이미지가 아직 없는" 최초 부트스트랩 시점에도 apply가 성공해야 한다.
# 그래서 image는 항상 pull 가능한 nginx:latest로 고정해두고,
# 실제 애플리케이션 이미지는 CI/CD가 register-task-definition으로
# 같은 family("demo-app") 밑에 새 리비전을 계속 등록하는 방식으로 넘어간다.
resource "aws_ecs_task_definition" "demo" {
  family                   = "demo-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name      = "web"
      image     = "nginx:latest" # 부트스트랩 placeholder - CI/CD가 실제 이미지로 교체
      essential = true
      portMappings = [
        { containerPort = 80, protocol = "tcp" }
      ]
      environment = [
        { name = "DB_HOST", value = aws_db_instance.demo.address },
        { name = "DB_PORT", value = tostring(aws_db_instance.demo.port) },
        { name = "DB_USER", value = "appuser" },
        { name = "DB_PASSWORD", value = "apppassword123" },
        { name = "DB_NAME", value = "postgres" }
      ]
    }
  ])
}

# 원본 스크립트 13단계 대응.
resource "aws_ecs_service" "demo" {
  name            = "demo-service"
  cluster         = aws_ecs_cluster.demo.id
  task_definition = aws_ecs_task_definition.demo.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = slice(data.aws_subnets.default.ids, 0, 2)
    security_groups  = [aws_security_group.demo.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.demo.arn
    container_name   = "web"
    container_port   = 80
  }

  # 핵심: CI/CD가 이후 register-task-definition + update-service로 갈아끼우는
  # 리비전 변경을 Terraform이 되돌리지 않도록 함. 이게 없으면 apply할 때마다
  # 서비스가 다시 nginx placeholder 리비전으로 돌아가버림.
  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_lb_listener.demo]
}
