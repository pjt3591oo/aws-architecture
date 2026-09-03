variable "env" {
  description = "환경 이름 (dev / prod). 모든 리소스 이름의 접미사로 쓰인다."
  type        = string
}

variable "aws_region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "entry_zip_path" {
  description = "entry-lambda placeholder zip 경로 (최초 생성용, 이후 apply에서는 무시됨)"
  type        = string
}

variable "consumer_zip_path" {
  description = "consumer-lambda placeholder zip 경로 (최초 생성용, 이후 apply에서는 무시됨)"
  type        = string
}
