#!/usr/bin/env bash
# ============================================================================
# Route53 -> CloudFront -> WAF -> ALB -> ECS -> RDS
# Floci(localhost:4566) 위에 이 스택을 그대로 구현하는 프로비저닝 스크립트
#
# 순서 주의: AWS ECS는 UpdateService로 로드밸런서를 나중에 붙이는 것을 지원하지
# 않는다 (loadBalancers는 CreateService 시점에만 지정 가능). Floci가 이 제약을
# 충실히 재현하므로, 반드시 ALB/타겟그룹을 먼저 만들고 그 ARN을 들고
# ECS create-service를 호출해야 한다.
#
# 사전 조건:
#   - docker-compose up -d 로 Floci가 4566 포트에서 떠 있어야 함
#   - AWS CLI v2 설치되어 있어야 함 (aws --version)
# ============================================================================
set -euo pipefail

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_ENDPOINT_URL=http://localhost:4566
REGION=ap-northeast-2
export AWS_DEFAULT_REGION=$REGION

log() { echo -e "\n\033[1;36m[$(date +%H:%M:%S)] $1\033[0m"; }

# ----------------------------------------------------------------------------
# 0. Floci 헬스체크
# ----------------------------------------------------------------------------
log "0. Floci 헬스체크"
curl -sf http://localhost:4566/_floci/health >/dev/null || {
  echo "Floci가 응답하지 않습니다. docker-compose up -d 먼저 실행하세요." >&2
  exit 1
}

# ----------------------------------------------------------------------------
# 1. 네트워크 준비 (기본 VPC/서브넷 조회, ALB/ECS가 사용)
# ----------------------------------------------------------------------------
log "1. 기본 VPC/서브넷 조회"
VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' --output text)
SUBNET_IDS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID \
  --query 'Subnets[].SubnetId' --output text | tr '\t' ',')
SUBNET1=$(echo $SUBNET_IDS | cut -d',' -f1)
SUBNET2=$(echo $SUBNET_IDS | cut -d',' -f2)
echo "VPC=$VPC_ID SUBNETS=$SUBNET_IDS"

SG_ID=$(aws ec2 create-security-group \
  --group-name app-sg --description "app sg" --vpc-id $VPC_ID \
  --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 5432 --cidr 0.0.0.0/0

# ----------------------------------------------------------------------------
# 2. RDS (PostgreSQL) - 실제 Postgres 컨테이너로 기동됨
# ----------------------------------------------------------------------------
log "2. RDS PostgreSQL 인스턴스 생성"
aws rds create-db-instance \
  --db-instance-identifier demo-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username appuser \
  --master-user-password apppassword123 \
  --allocated-storage 20 \
  --vpc-security-group-ids $SG_ID

log "   RDS 기동 대기 중..."
aws rds wait db-instance-available --db-instance-identifier demo-db
DB_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier demo-db \
  --query 'DBInstances[0].Endpoint.Address' --output text)
echo "DB_ENDPOINT=$DB_ENDPOINT"

# ----------------------------------------------------------------------------
# 3. ALB (ELB v2) + Target Group + Listener  (ECS보다 먼저 생성)
# ----------------------------------------------------------------------------
log "3. ALB + 타겟그룹 + 리스너 생성"
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name demo-alb --subnets $SUBNET1 $SUBNET2 --security-groups $SG_ID \
  --scheme internet-facing --type application \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)
ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN \
  --query 'LoadBalancers[0].DNSName' --output text)
echo "ALB_DNS=$ALB_DNS"

TG_ARN=$(aws elbv2 create-target-group \
  --name demo-tg --protocol HTTP --port 80 --vpc-id $VPC_ID \
  --target-type ip --health-check-path / \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
echo "TG_ARN=$TG_ARN"

aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN

# ----------------------------------------------------------------------------
# 4. ECS 클러스터 + 태스크 정의 + 서비스
#    (loadBalancers는 CreateService 시점에만 지정 가능 - UpdateService로는 불가)
# ----------------------------------------------------------------------------
log "4. ECS 클러스터 생성"
aws ecs create-cluster --cluster-name demo-cluster

cat > task-def.json <<EOF
{
  "family": "demo-app",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [
    {
      "name": "web",
      "image": "nginxdemos/hello:latest",
      "portMappings": [{ "containerPort": 80, "protocol": "tcp" }],
      "environment": [
        { "name": "DB_HOST", "value": "$DB_ENDPOINT" }
      ]
    }
  ]
}
EOF

aws ecs register-task-definition --cli-input-json file://task-def.json

log "4-1. ECS 서비스 생성 (ALB 타겟그룹을 처음부터 물고 생성)"
aws ecs create-service \
  --cluster demo-cluster \
  --service-name demo-service \
  --task-definition demo-app \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET1,$SUBNET2],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=$TG_ARN,containerName=web,containerPort=80"

log "   타겟이 healthy 상태가 될 때까지 대기 (최대 60초)"
for i in $(seq 1 12); do
  STATE=$(aws elbv2 describe-target-health --target-group-arn $TG_ARN \
    --query 'TargetHealthDescriptions[0].TargetHealth.State' --output text 2>/dev/null || echo "none")
  echo "   [$i/12] target health = $STATE"
  [ "$STATE" = "healthy" ] && break
  sleep 5
done

# ----------------------------------------------------------------------------
# 4-2. CloudFront가 ALB(사설 오리진)를 허용하도록 docker-compose.yml 갱신 + floci 재시작
#      공식 문서 확인 결과: FLOCI_SERVICES_CLOUDFRONT_ALLOWED_PRIVATE_ORIGIN_HOSTS를
#      비워두면 루프백/사설 주소로 resolve되는 커스텀 오리진은 기본적으로 거부됨.
# ----------------------------------------------------------------------------
log "4-3. CloudFront 사설 오리진 허용목록에 ALB DNS 반영 후 floci 재시작"
sed -i.bak "s/FLOCI_SERVICES_CLOUDFRONT_ALLOWED_PRIVATE_ORIGIN_HOSTS=.*/FLOCI_SERVICES_CLOUDFRONT_ALLOWED_PRIVATE_ORIGIN_HOSTS=$ALB_DNS/" docker-compose.yml
docker compose up -d floci
echo "   floci 재시작 대기 중..."
sleep 5
curl -sf http://localhost:4566/_floci/health >/dev/null || {
  echo "floci 재시작 후 응답 없음. docker compose logs floci 확인하세요." >&2
  exit 1
}

# ----------------------------------------------------------------------------
# 5. WAF v2 - ALB용 REGIONAL WebACL
# ----------------------------------------------------------------------------
log "5. WAF REGIONAL WebACL 생성 및 ALB 연결"
REGIONAL_WEBACL=$(aws wafv2 create-web-acl \
  --name demo-alb-waf --scope REGIONAL \
  --default-action Allow={} \
  --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=demoAlbWaf \
  --query 'Summary.ARN' --output text)

aws wafv2 associate-web-acl --web-acl-arn $REGIONAL_WEBACL --resource-arn $ALB_ARN

# ----------------------------------------------------------------------------
# 6. WAF v2 - CloudFront용 CLOUDFRONT WebACL (반드시 us-east-1)
# ----------------------------------------------------------------------------
log "6. WAF CLOUDFRONT WebACL 생성 (us-east-1)"
CF_WEBACL=$(aws wafv2 create-web-acl \
  --name demo-cf-waf --scope CLOUDFRONT --region us-east-1 \
  --default-action Allow={} \
  --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=demoCfWaf \
  --query 'Summary.ARN' --output text)

# ----------------------------------------------------------------------------
# 7. CloudFront - ALB를 커스텀 오리진으로
# ----------------------------------------------------------------------------
log "7. CloudFront 배포 생성 (오리진 = ALB)"
cat > cf-dist.json <<EOF
{
  "CallerReference": "demo-$(date +%s)",
  "Comment": "demo distribution",
  "Enabled": true,
  "WebACLId": "$CF_WEBACL",
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "alb-origin",
        "DomainName": "$ALB_DNS",
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "http-only"
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "alb-origin",
    "ViewerProtocolPolicy": "allow-all",
    "ForwardedValues": { "QueryString": true, "Cookies": { "Forward": "all" } },
    "TrustedSigners": { "Enabled": false, "Quantity": 0 },
    "MinTTL": 0
  }
}
EOF

CF_RESULT=$(aws cloudfront create-distribution --distribution-config file://cf-dist.json --region us-east-1)
CF_DOMAIN=$(echo "$CF_RESULT" | grep -o '"DomainName": "[^"]*"' | head -1 | cut -d'"' -f4)
echo "CF_DOMAIN=$CF_DOMAIN"

# ----------------------------------------------------------------------------
# 8. Route53 - 호스팅존 + CloudFront 앨리어스 레코드
# ----------------------------------------------------------------------------
log "8. Route53 호스팅존 및 레코드 생성"
ZONE_ID=$(aws route53 create-hosted-zone \
  --name demo.local --caller-reference "demo-$(date +%s)" \
  --query 'HostedZone.Id' --output text)

cat > record.json <<EOF
{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "app.demo.local",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{ "Value": "$CF_DOMAIN" }]
    }
  }]
}
EOF
aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch file://record.json

log "완료. 아래 값으로 각 레이어를 직접 curl 테스트할 수 있습니다."
cat <<EOF

  RDS Endpoint     : $DB_ENDPOINT
  ALB DNS          : $ALB_DNS   (WAF REGIONAL 적용됨)
  CloudFront Domain: $CF_DOMAIN  (WAF CLOUDFRONT 적용됨)
  Route53 Record   : app.demo.local -> $CF_DOMAIN

  테스트 예시:
    curl http://$ALB_DNS
    curl -H "Host: app.demo.local" http://localhost:4566/cloudfront/$CF_DOMAIN
EOF