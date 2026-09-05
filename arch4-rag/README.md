# S3 → S3 Vectors → Vector Search → Lambda/API → LLM (floci + llama.cpp)

floci(로컬 AWS 에뮬레이터)와 직접 실행하는 llama.cpp를 이용해 로컬에서 동작하는
RAG(검색 증강 생성) 파이프라인을 구성합니다. Lambda 함수는 Node.js(nodejs20.x)로 작성되어 있습니다.

## 아키텍처

```
[문서 업로드]
   aws s3 cp doc.txt s3://rag-documents/
        │  (S3 ObjectCreated 이벤트)
        ▼
  ingest-handler (Lambda, Node.js)
   ├─ 텍스트 청킹
   ├─ llama.cpp 임베딩 서버(:8081)로 임베딩
   └─ S3 Vectors 인덱스(rag-vectors/docs-index)에 저장

[질의]
   POST /query  (API Gateway)
        ▼
  query-handler (Lambda, Node.js)
   ├─ 질문 임베딩 (llama.cpp :8081)
   ├─ S3 Vectors 유사도 검색 (QueryVectorsCommand, top-k)
   ├─ 컨텍스트 구성
   └─ llama.cpp 채팅 서버(:8082)로 답변 생성 → JSON 응답
```

`docker-compose.yaml`에는 **floci만** 정의되어 있습니다. llama.cpp는 직접 별도로 실행하세요.

## 폴더 구조

```
rag-floci/
├── docker-compose.yaml     # floci만 정의
├── provision.sh            # 전체 인프라 프로비저닝 스크립트
└── lambda/
    ├── ingest/
    │   ├── index.js        # S3 -> 임베딩 -> S3 Vectors 저장
    │   └── package.json
    └── query/
        ├── index.js        # API -> 검색 -> LLM 답변 생성
        └── package.json
```

## 사전 준비

1. Docker / Docker Compose v2
2. AWS CLI v2 (s3vectors 서브커맨드를 지원하는 최신 버전)
3. `jq`, `zip`, `node`/`npm` (Lambda 패키징에 사용, Lambda 런타임은 nodejs20.x)
4. llama.cpp를 직접 빌드/설치 후, GGUF 모델로 두 서버를 미리 실행해두세요.

```bash
# 임베딩 서버
llama server  -hf bartowski/Qwen_Qwen3-0.6B-GGUF:Q4_K_M --embedding --pooling mean --port 8081 --host 0.0.0.0 

# 채팅(답변 생성) 서버
llama server  -hf bartowski/Qwen_Qwen3-0.6B-GGUF:Q4_K_M --port 8082 --host 0.0.0.0
```

> 다른 임베딩 모델을 쓰면 `provision.sh`의 `EMBEDDING_DIM` 값을 모델 차원에 맞게 수정하세요.
> `provision.sh up` 실행 시 두 서버(`:8081`, `:8082`)의 `/health`를 확인하고, 접근이 안 되면 스크립트가 중단됩니다.

## 실행

```bash
chmod +x provision.sh
./provision.sh up
```

완료되면 다음이 자동 생성됩니다:
- S3 버킷 `rag-documents`
- S3 Vectors 버킷 `rag-vectors` + 인덱스 `docs-index`
- Lambda 함수 `ingest-handler`, `query-handler` (Node.js 20.x, `index.handler`)
- S3 → ingest-handler 이벤트 트리거
- API Gateway REST API (`POST /query`) → query-handler 통합

```bash
$ aws s3vectors list-indexes \
  --vector-bucket-name rag-vectors
```

```bash
$ aws s3vectors list-vectors \
  --vector-bucket-name rag-vectors \
  --index-name docs-index \
  --return-data \
  --return-metadata
```

```bash
$ aws s3vectors list-vectors \
  --vector-bucket-name rag-vectors \
  --index-name docs-index \
  --return-metadata \
  --query 'vectors[].{key:key,metadata:metadata}' \
  --output json
```

## 테라폼 배포

* 인프라 구축

```bash
$ terraform init

$ terraform apply
```

* 람다 배포

```bash
$ cd lambda/ingest

$ ./deploy.sh
```


```bash
$ cd lambda/ingest

$ ./deploy.sh
```

## 사용

```bash
# 1) 문서 업로드 (자동으로 임베딩되어 S3 Vectors에 저장됨)
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=ap-northeast-2

aws s3 cp ./test_docs/01_architecture_overview.md s3://rag-documents/architecture_overview.md
aws s3 cp ./test_docs/02_kinesis.md s3://rag-documents/kinesis.md
aws s3 cp ./test_docs/03_opensearch.md s3://rag-documents/opensearch.md
aws s3 cp ./test_docs/04_s3_glue_athena.md s3://rag-documents/s3_glue_athena.md
aws s3 cp ./test_docs/05_scenarios.md s3://rag-documents/scenarios.md
aws s3 cp ./test_docs/06_design_decisions.md s3://rag-documents/design_decisions.md

# 2) 질의
export INVOKE_URL="http://localhost:4566/restapis/5a6321dabe/dev/_user_request_/query"
curl -X POST $INVOKE_URL \
  -H 'Content-Type: application/json' \
  -d '{"question": "Kinesis Data Streams의 역할은 무엇인가?"}'

curl -X POST $INVOKE_URL \
  -H 'Content-Type: application/json' \
  -d '{"question": " OpenSearch와 S3의 용도 차이를 설명하라."}'

curl -X POST $INVOKE_URL \
  -H 'Content-Type: application/json' \
  -d '{"question": "데이터 생산자가 이벤트를 생성한 뒤 Athena에서 SQL로 조회하기까지의 전체 흐름을 설명하라."}'

curl -X POST $INVOKE_URL \
  -H 'Content-Type: application/json' \
  -d '{"question": "Athena가 S3에 데이터를 저장하는 서비스인가?"}'

curl -X POST $INVOKE_URL \
  -H 'Content-Type: application/json' \
  -d '{"question": "S3의 새로운 이벤트 데이터셋을 Athena에서 조회하려면 어떤 메타데이터 구성이 필요한가?"}'

curl -X POST $INVOKE_URL \
  -H 'Content-Type: application/json' \
  -d '{"question": "Glue Database와 Glue Table의 차이는 무엇인가?"}'

curl -X POST $INVOKE_URL \
  -H 'Content-Type: application/json' \
  -d '{"question": "OpenSearch가 Raw Data의 장기 보관을 위한 기본 저장소인가?"}'


curl -X POST $INVOKE_URL \
  -H 'Content-Type: application/json' \
  -d '{"question": "aws의 ECS에 대해 설명하세요."}'
```

## 정리

```bash
./provision.sh down
```

