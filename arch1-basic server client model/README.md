# Route53 → CloudFront → WAF → ALB → ECS → RDS on Floci

## 실행 순서

```bash
docker-compose up -d          # Floci 기동 (docker.sock 마운트 필수 - RDS/ECS가 실컨테이너로 뜸)
chmod +x provision.sh
./provision.sh
```

## 레이어별 Floci 지원 수준 (2026-08 기준 확인)

| 레이어 | 지원 방식 | 비고 |
|---|---|---|
| Route53 | 설정 저장 + API 응답 | 실제 DNS resolver가 아니므로 로컬에서 `app.demo.local`이 진짜로 resolve되진 않음. `/etc/hosts`나 CloudFront 도메인으로 직접 접근해서 검증해야 함 |
| CloudFront | **실제 동작** | 1.7.0부터 config-only에서 벗어나 S3/커스텀 오리진에서 실제 콘텐츠를 서빙함. 오리진 라우팅, 캐시 비헤이비어, 서명 URL까지 동작 |
| WAF v2 | 지원 | REGIONAL(ALB용)과 CLOUDFRONT(반드시 us-east-1)용 스코프를 분리해서 만들어야 함 — 스크립트에서 처리함 |
| ALB (ELB v2) | 지원 | 타겟 그룹에 ECS 태스크의 IP를 자동으로 등록 |
| ECS | **실제 컨테이너** | Fargate 태스크가 실제 Docker 컨테이너로 기동됨. docker.sock 마운트 안 하면 아예 실행 안 됨 |
| RDS | **실제 PostgreSQL/MySQL** | 목업이 아니라 진짜 Postgres 컨테이너가 뜨므로 psql로 바로 접속 가능 |

## 알려진 제약 (공식 문서 https://floci.io/floci/services/* 확인)

1. **Route53은 관리 플레인만 제공** — 공식 문서 원문: "Actual DNS resolution is not provided — this is a management-plane-only implementation." 호스팅존/레코드 CRUD는 되지만 `app.demo.local` 같은 이름이 로컬에서 실제로 resolve되진 않음. CloudFront 도메인을 직접 호출해서 검증해야 함.
2. **WAF v2는 관리 API만 제공, 실시간 트래픽 필터링 없음** — 공식 문서 원문: "Floci does not inspect or filter live traffic — this surface lets you create, read, update, and delete WAF resources and validate IaC ... locally." IP 차단/Rate-based 룰의 실제 동작 검증은 로컬에서 불가능하고, Terraform/CDK로 만든 WAF 리소스가 올바른 모양으로 생성되는지 검증하는 용도로만 씀. 참고로 WAF v2는 서비스 전체를 끄고 켜는 `FLOCI_SERVICES_*_ENABLED` 변수 자체가 문서에 없음.
3. **CloudFront는 사설/루프백 오리진을 기본 차단** — `FLOCI_SERVICES_CLOUDFRONT_ALLOWED_PRIVATE_ORIGIN_HOSTS`에 명시적으로 등록된 호스트만 예외. 우리 스택은 ALB가 Docker 내부망에 있으므로 `provision.sh`가 ALB 생성 후 이 값을 자동으로 채우고 floci를 재시작함.
4. VPC/서브넷/보안그룹은 EC2 API 레벨에서 생성/조회는 되지만, **실제 네트워크 격리는 아님** (Docker 브릿지 네트워크 위에서 동작). 보안그룹 룰을 틀리게 짜도 로컬에서는 안 막힐 수 있음 — 실제 AWS 배포 전에 `terraform plan`/IAM 정책 리뷰로 별도 검증 필요.
5. **RDS/ALB는 포트를 명시적으로 publish해야 동작** — RDS는 `7001-7099` 프록시 포트 범위, ALB는 리스너 포트(80 등)를 compose에서 열어줘야 함. 공식 문서: "Listener sockets bind on the Floci host. Expose any listener ports you need in Docker Compose."
6. **`FLOCI_DOCKER_NETWORK`는 존재하지 않는 변수** (이전 버전 compose 파일의 실수) — 올바른 이름은 `FLOCI_SERVICES_DOCKER_NETWORK`(전역) 또는 `FLOCI_SERVICES_ECS_DOCKER_NETWORK`/`FLOCI_SERVICES_RDS_DOCKER_NETWORK`(서비스별 override).
7. **ECS `loadBalancers`는 `CreateService` 시점에만 지정 가능** — 실제 AWS도 `UpdateService`가 받는 파라미터에 `loadBalancers`가 없어서, 나중에 `update-service`로 붙이려 하면 API는 성공을 반환하지만 실제로는 무시됨. Floci가 이 AWS 동작을 충실히 재현하고 있어서 로컬에서도 똑같이 걸림. 그래서 이 스크립트는 **ALB/타겟그룹을 먼저 만들고 그 ARN을 들고 `ecs create-service`를 호출**하는 순서로 구성돼 있음.

## 정리(teardown)

```bash
docker-compose down -v
rm -rf data task-def.json cf-dist.json record.json
```

## 다음 단계 제안

- 이 스크립트를 Terraform으로 옮기고 `endpoints { }` 블록에 `http://localhost:4566`을 지정하면, 실제 AWS 배포용 Terraform 코드를 그대로 로컬 검증에 재사용 가능 (스택 그대로 운영 환경에 apply)
- ECS 태스크 이미지를 `nginxdemos/hello` 대신 실제 백엔드 이미지로 교체하고 `DB_HOST` 환경변수로 RDS_ENDPOINT를 넘기면 애플리케이션 레벨 통합 테스트까지 가능