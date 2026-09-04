resource "aws_opensearch_domain" "this" {
  domain_name    = local.opensearch_domain
  engine_version = "OpenSearch_2.19"

  cluster_config {
    instance_type             = "t3.small.search"
    instance_count             = 1
    dedicated_master_enabled  = false
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = 10
  }

  node_to_node_encryption {
    enabled = true
  }

  encrypt_at_rest {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https = true
  }
}

# NOTE: 로컬/실습 환경 전제로 Principal을 전체 허용("*")함.
# 원본 스크립트 주석과 동일하게, 프로덕션에서는 절대 이 정책 그대로 쓰면 안 됨.
data "aws_iam_policy_document" "opensearch_access" {
  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["es:ESHttp*"]
    resources = ["${aws_opensearch_domain.this.arn}/*"]
  }
}

resource "aws_opensearch_domain_policy" "this" {
  domain_name     = aws_opensearch_domain.this.domain_name
  access_policies = data.aws_iam_policy_document.opensearch_access.json
}
