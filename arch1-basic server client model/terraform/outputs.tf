output "vpc_id" {
  value = data.aws_vpc.default.id
}

output "subnet_ids" {
  value = data.aws_subnets.default.ids
}

output "security_group_id" {
  value = aws_security_group.demo.id
}

output "rds_endpoint" {
  value = aws_db_instance.demo.address
}

output "rds_port" {
  value = aws_db_instance.demo.port
}

output "ecr_repository_name" {
  value = aws_ecr_repository.demo.name
}

output "ecr_repository_url_api" {
  value       = aws_ecr_repository.demo.repository_url
  description = "ECR API가 반환하는 URI (AWS 실환경과 동일한 형식). 태스크 정의의 image 필드에는 이 값을 씀."
}

output "ecr_local_registry" {
  value       = "localhost:5100/${aws_ecr_repository.demo.name}"
  description = "docker tag / docker push 는 API URI가 아니라 이 로컬 레지스트리 주소를 써야 함 (Floci 특성)"
}

output "alb_dns_name" {
  value = aws_lb.demo.dns_name
}

output "target_group_arn" {
  value = aws_lb_target_group.demo.arn
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.demo.name
}

output "ecs_service_name" {
  value = aws_ecs_service.demo.name
}

output "ecs_task_family" {
  value = aws_ecs_task_definition.demo.family
}
