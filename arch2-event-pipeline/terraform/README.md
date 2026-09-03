# demo-api 파이프라인 (Terraform, dev/prod 완전 분리)

원본 bash 스크립트가 만들던 파이프라인(API Gateway → Lambda(entry) →
EventBridge → SQS → Lambda(consumer) → DynamoDB)을 Terraform으로 옮기고,
`dev`/`prod` 두 환경을 리소스 단위로 완전히 분리했습니다.

## 구조

```
terraform/
├── versions.tf              # terraform/provider 버전 고정
├── provider.tf               # Floci(localhost:4566) 엔드포인트 설정
├── variables.tf               # 리전, 계정ID
├── main.tf                    # module "dev" / module "prod" 호출
├── apigateway.tf               # 단일 REST API(demo-api) + dev/prod 스테이지
├── outputs.tf                 # dev/prod 각각의 invoke URL 등
├── .gitignore
├── lambda-src/
│   ├── entry-lambda-placeholder.zip
│   └── consumer-lambda-placeholder.zip
└── modules/pipeline/           # env 하나(dev 또는 prod)의 백엔드 리소스를 만드는 모듈
    ├── variables.tf
    ├── main.tf                 # DynamoDB, SQS, IAM role, EventBridge
    ├── lambda.tf                # entry/consumer Lambda 함수
    └── outputs.tf
```

`module "dev"`와 `module "prod"`가 같은 `modules/pipeline`을 각각 다른
`env` 값으로 호출하기 때문에, DynamoDB 테이블/SQS 큐/EventBridge
버스/Lambda/IAM role은 환경마다 완전히 독립적으로 생성됩니다.

**API Gateway만 예외입니다.** `demo-api` REST API 하나를 루트(`apigateway.tf`)에서
만들고, 그 안에 `dev`/`prod` 스테이지 두 개를 둡니다. REST API의 통합(integration)은
메서드당 1개뿐이라 스테이지별로 따로 만들 수 없어서, 통합 URI에 실제 함수
이름 대신 `${stageVariables.lambdaFunction}`을 넣고 스테이지마다 그 변수값을
다르게 줍니다:

- `dev` 스테이지의 `lambdaFunction` 변수 = `demo-entry-lambda-dev`
- `prod` 스테이지의 `lambdaFunction` 변수 = `demo-entry-lambda-prod`

같은 API를 호출해도 어느 스테이지 URL로 들어왔는지에 따라 실제로 실행되는
Lambda 함수(와 그 함수가 바라보는 이벤트 버스/테이블)가 완전히 달라집니다.

## 실행

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test

cd terraform
terraform init
terraform plan
terraform apply
```

적용 후 `terraform output`으로 dev/prod 각각의 API 호출 URL, 큐 URL,
테이블 이름, 이벤트 버스 이름을 확인할 수 있습니다.

```bash
terraform output dev_invoke_url
terraform output prod_invoke_url
```

## placeholder zip과 `ignore_changes`

말씀하신 대로 맞습니다. 다만 정확히는 **`.gitignore`가 아니라 Terraform의
`lifecycle { ignore_changes = [...] }`** 를 씁니다. 이 둘은 역할이 다릅니다.

- **`.gitignore`**: git이 파일을 커밋 추적하지 않게 함 (예: `terraform.tfstate`,
  실제 배포 zip인 `entry-lambda.zip`). 여기서도 썼습니다.
- **`lifecycle.ignore_changes`**: Terraform이 **state와 실제 리소스를 비교할 때
  특정 속성의 차이를 무시**하게 함. 이게 없으면, CI/CD가
  `aws lambda update-function-code`로 실제 코드를 배포한 뒤 누군가
  `terraform apply`를 실행하면 Terraform이 "코드가 state와 다르다"고 판단해서
  **placeholder zip으로 되돌려버립니다.**

그래서 `modules/pipeline/lambda.tf`의 두 Lambda 리소스에 각각 이렇게 넣었습니다:

```hcl
lifecycle {
  ignore_changes = [filename, source_code_hash]
}
```

이렇게 하면:
- `terraform apply`는 최초 1회만 `lambda-src/*.zip`으로 함수를 만들고,
- 그 이후 함수 코드가 CI/CD로 바뀌어도 Terraform은 그 차이를 "의도된 drift"로
  보고 건드리지 않습니다.
- 반대로 `handler`, `timeout`, `environment` 같은 다른 속성은 여전히
  Terraform이 관리하므로, 인프라 설정 변경은 정상적으로 apply됩니다.

placeholder zip 자체(`lambda-src/*.zip`)는 git에는 커밋해도 됩니다 —
"최초 생성용 더미"라는 의도가 명확하고, 실수로 재배포되어도 `ignore_changes` 덕분에
운영 중인 실제 코드에는 영향이 없기 때문입니다. `.gitignore`에 넣어야 하는 건
로컬 빌드 산출물인 `entry-lambda.zip`/`consumer-lambda.zip` 쪽입니다.

## 원본 스크립트와 달라진 점

| 항목 | 원본 bash | Terraform 버전 |
|---|---|---|
| DynamoDB | `Orders` 하나 | `Orders-dev`, `Orders-prod` |
| SQS | `demo-order-queue` 하나 | 환경별 별도 큐 |
| EventBridge | default 버스 | 환경별 커스텀 버스 |
| Lambda | 함수 하나씩 | 환경별 별도 함수 (alias 대신 완전 분리된 함수) |
| API Gateway | 한 API의 dev/prod 스테이지 | **동일** — API 1개(`demo-api`) + 스테이지 2개(`dev`, `prod`) |
| IAM Role | 공용 role 하나 | 환경별 별도 role |

Lambda를 "하나의 함수 + alias"로 할지 "환경별 별도 함수"로 할지는 트레이드오프가
있습니다. alias 방식은 함수가 하나라 관리가 단순하지만 IAM/CloudWatch 로그가
섞이고, 완전 분리 방식은 리소스가 늘어나는 대신 dev에서 무슨 짓을 해도 prod에
전혀 영향이 없다는 확실한 격리를 보장합니다. 백엔드(Lambda/큐/테이블/버스)는
후자로, API Gateway만 원본 스크립트처럼 단일 API + 스테이지 분리 구조로
구성했습니다.
