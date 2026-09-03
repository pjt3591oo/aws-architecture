# 원본 스크립트 3단계: ECR Repository 생성
#
# 주의: aws_ecr_repository.demo.repository_url 은 API가 반환하는
# "account.dkr.ecr.region.amazonaws.com/..." 형식 URI 이고,
# 실제로 docker push 해야 하는 대상은 Floci의 로컬 레지스트리(localhost:5100)이다.
# 원본 스크립트가 ECR_URI를 API 응답과 별개로 "localhost:5100/$REPO"로
# 직접 조립했던 것과 동일한 이유 -> outputs.tf 의 ecr_local_registry 참고.
resource "aws_ecr_repository" "demo" {
  name = "demo-app"
}
