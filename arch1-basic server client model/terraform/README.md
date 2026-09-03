# Terraform(IaC) + CI/CD 분리 구조

원본 `provision.sh` 한 파일에 있던 걸 두 영역으로 쪼갰습니다.

| 영역 | 담당 | 위치 |
|---|---|---|
| **IaC (거의 안 바뀌는 것)** | VPC/SG, RDS, ECR repo, ALB/타겟그룹/리스너, ECS 클러스터, ECS 서비스(네트워크/로드밸런서 설정), 태스크 정의의 "틀"(placeholder 이미지 포함) | `terraform/` |
| **CI/CD (배포마다 바뀌는 것)** | 이미지 빌드/푸시, 새 태스크 정의 리비전 등록, 서비스에 반영 | `ci-cd-deploy.sh` |

## 사용 순서

```bash
# 1. 인프라 부트스트랩 (nginx placeholder로 서비스가 일단 뜬 상태가 됨)
cd terraform
terraform init
terraform plan
terraform apply

# 2. 실제 애플리케이션 배포 (health-app 예시 사용)
cd ..
./ci-cd-deploy.sh ./health-app
```

`terraform apply` 직후엔 `curl http://$(terraform output -raw alb_dns_name)`가 nginx 기본 페이지를 반환합니다. `ci-cd-deploy.sh` 실행 후에는 실제 애플리케이션(예: health-app)의 응답으로 바뀝니다.

## 핵심 설계 포인트 (대화에서 정리된 원칙 그대로 반영)

1. **`aws_ecs_task_definition.demo`의 image는 항상 `nginx:latest`로 고정** — 실제 이미지가 아직 ECR에 없는 최초 `apply` 시점에도 태스크가 정상적으로 뜨도록. `CreateService`/`RegisterTaskDefinition`은 이미지 존재 여부를 검증하지 않지만, 존재하지 않는 이미지면 태스크가 `CannotPullContainerError`로 계속 크래시 루프를 돎.
2. **`aws_ecs_service.demo`에 `lifecycle { ignore_changes = [task_definition] }`** — CI/CD가 `register-task-definition` + `update-service`로 이후 리비전을 계속 갈아끼워도, 다음 `terraform apply` 때 Terraform이 이걸 nginx placeholder 리비전으로 되돌리지 않도록.
3. **`ci-cd-deploy.sh`는 인프라 리소스를 새로 만들지 않음** — 오직 `terraform output`으로 기존 인프라 정보(클러스터명, 서비스명, ALB DNS, ECR 레지스트리 주소 등)를 읽어서 이미지 배포만 수행. 레포가 분리된 실무 구조에서는 이 output들을 SSM Parameter Store나 `terraform_remote_state`로 대체해서 읽어오면 됨.
4. **`ecr_local_registry` vs `ecr_repository_url_api`** — Floci 특성상 ECR API가 반환하는 URI(`repository_url`, AWS 실환경 형식)와 실제 `docker push` 대상(`localhost:5100/...`, Floci 로컬 레지스트리)이 다름. `outputs.tf`에 둘 다 분리해서 노출해뒀으니 헷갈리지 않게 확인.

## 알려진 제약 (Floci + Terraform 조합)

- Floci GitHub 이슈(#871)에 따르면 `aws_instance`(EC2) 리소스는 apply 중 provider가 크래시하는 버그가 보고돼 있습니다. 이번 스택은 EC2 인스턴스를 직접 만들지 않아서(Fargate만 사용) 영향은 없지만, 나중에 EC2를 추가하게 되면 참고하세요.
- Terraform provider가 리소스를 만든 뒤 즉시 "읽기(Read)"를 시도하는데, 이 타이밍에 Floci 응답이 AWS 실제 스펙과 100% 동일하지 않은 경우가 종종 있다고 알려져 있습니다 (GitHub Issue #28). `apply` 도중 에러가 나면 `terraform apply` 재시도로 넘어가는 경우가 있으니 참고하세요.
- `terraform init`은 `registry.terraform.io`에서 AWS provider를 내려받아야 하므로, 사내/사설 네트워크에서 막혀있다면 프록시나 provider mirror 설정이 필요합니다.

## 정리 (teardown)

```bash
cd terraform
terraform destroy
```
