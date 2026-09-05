variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "floci_endpoint" {
  description = "floci(로컬 AWS 에뮬레이터) 엔드포인트"
  type        = string
  default     = "http://localhost:4566"
}

variable "docs_bucket" {
  description = "원본 문서를 올려두는 S3 버킷 이름"
  type        = string
  default     = "rag-documents"
}

variable "vector_bucket" {
  description = "S3 Vectors 버킷 이름"
  type        = string
  default     = "rag-vectors"
}

variable "index_name" {
  description = "S3 Vectors 인덱스 이름"
  type        = string
  default     = "docs-index"
}

variable "embedding_dim" {
  description = "임베딩 모델 차원 (예: nomic-embed-text=768)"
  type        = number
  default     = 1024
}

variable "embedding_url" {
  description = "Lambda 컨테이너 기준 llama.cpp 임베딩 서버 주소"
  type        = string
  default     = "http://host.docker.internal:8081/v1/embeddings"
}

variable "chat_url" {
  description = "Lambda 컨테이너 기준 llama.cpp 채팅 서버 주소"
  type        = string
  default     = "http://host.docker.internal:8082/v1/chat/completions"
}

variable "api_stage" {
  description = "API Gateway 배포 스테이지 이름"
  type        = string
  default     = "dev"
}
