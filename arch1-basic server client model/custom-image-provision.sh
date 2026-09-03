#!/usr/bin/env bash

set -euo pipefail

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_ENDPOINT_URL=http://localhost:4566

REGION=ap-northeast-2
export AWS_DEFAULT_REGION=$REGION

APP_NAME=demo-app
ECR_REPOSITORY=$APP_NAME
IMAGE_TAG=$(date +%Y%m%d%H%M%S)

log() {
  echo -e "\n\033[1;36m[$(date +%H:%M:%S)] $1\033[0m"
}

# ============================================================
# 0. Floci
# ============================================================

log "0. Floci 헬스체크"

curl -sf http://localhost:4566/_floci/health >/dev/null

# ============================================================
# 1. VPC / Subnet / Security Group
# ============================================================

log "1. 네트워크 준비"

VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' \
  --output text)

SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values=$VPC_ID \
  --query 'Subnets[].SubnetId' \
  --output text)

SUBNET1=$(echo "$SUBNET_IDS" | awk '{print $1}')
SUBNET2=$(echo "$SUBNET_IDS" | awk '{print $2}')

echo "VPC=$VPC_ID"
echo "SUBNET1=$SUBNET1"
echo "SUBNET2=$SUBNET2"

SG_ID=$(aws ec2 create-security-group \
  --group-name demo-sg \
  --description "demo sg" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' \
  --output text)

# ALB / ECS / RDS 테스트
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 5432 \
  --cidr 0.0.0.0/0

# ============================================================
# 2. RDS PostgreSQL
# ============================================================

log "2. RDS PostgreSQL 생성"

aws rds create-db-instance \
  --db-instance-identifier demo-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username appuser \
  --master-user-password apppassword123 \
  --allocated-storage 20 \
  --vpc-security-group-ids "$SG_ID"

log "RDS 준비 대기"

aws rds wait db-instance-available \
  --db-instance-identifier demo-db

DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier demo-db \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)
DB_PORT=$(aws rds describe-db-instances \
  --db-instance-identifier demo-db \
  --query 'DBInstances[0].Endpoint.Port' \
  --output text)

echo "DB_ENDPOINT=$DB_ENDPOINT"
echo "DB_PORT=$DB_PORT"

# ============================================================
# 3. ECR Repository
# ============================================================

log "3. ECR Repository 생성"

aws ecr create-repository \
  --repository-name "$ECR_REPOSITORY"

ECR_REPOSITORY_URI=$(aws ecr describe-repositories \
  --repository-name "$ECR_REPOSITORY" \
  --query 'repositories[0].repositoryUri' \
  --output text)

ECR_REGISTRY=localhost:5100
ECR_URI="$ECR_REGISTRY/$ECR_REPOSITORY"


echo "ECR_URI=$ECR_URI"

# ============================================================
# 4. Docker Image Build
# ============================================================

log "4. Docker 이미지 빌드"

docker build \
  -t "$APP_NAME:$IMAGE_TAG" \
  .

# ============================================================
# 5. ECR Login
# ============================================================

log "5. ECR 로그인"

aws ecr get-login-password | \
docker login \
  --username AWS \
  --password-stdin \
  localhost:5100

# ============================================================
# 6. Docker Image Tag
# ============================================================

log "6. ECR 이미지 태깅"

docker tag \
  "$APP_NAME:$IMAGE_TAG" \
  "$ECR_URI:$IMAGE_TAG"

echo "IMAGE=$ECR_URI:$IMAGE_TAG"

# ============================================================
# 7. ECR Push
# ============================================================

log "7. ECR 이미지 Push"

docker push \
  "$ECR_URI:$IMAGE_TAG"

# ============================================================
# 8. ALB
# ============================================================

log "8. ALB 생성"

ALB_ARN=$(aws elbv2 create-load-balancer \
  --name demo-alb \
  --subnets "$SUBNET1" "$SUBNET2" \
  --security-groups "$SG_ID" \
  --scheme internet-facing \
  --type application \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "ALB_DNS=$ALB_DNS"

# ============================================================
# 9. Target Group
# ============================================================

log "9. Target Group 생성"

TG_ARN=$(aws elbv2 create-target-group \
  --name demo-tg \
  --protocol HTTP \
  --port 80 \
  --vpc-id "$VPC_ID" \
  --target-type ip \
  --health-check-path / \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

echo "TG_ARN=$TG_ARN"

# ============================================================
# 10. ALB Listener
# ============================================================

log "10. ALB Listener 생성"

aws elbv2 create-listener \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn="$TG_ARN"

# ============================================================
# 11. ECS Cluster
# ============================================================

log "11. ECS Cluster 생성"

aws ecs create-cluster \
  --cluster-name demo-cluster

# ============================================================
# 12. ECS Task Definition
# ============================================================

log "12. ECS Task Definition 생성"

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
      "image": "$ECR_URI:$IMAGE_TAG",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 80,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "DB_HOST",
          "value": "$DB_ENDPOINT"
        },
        {
          "name": "DB_PORT",
          "value": "$DB_PORT"
        },
        {
          "name": "DB_USER",
          "value": "appuser"
        },
        {
          "name": "DB_PASSWORD",
          "value": "apppassword123"
        },
        {
          "name": "DB_NAME",
          "value": "postgres"
        }
      ]
    }
  ]
}
EOF

cat task-def.json

aws ecs register-task-definition \
  --cli-input-json file://task-def.json

# ============================================================
# 13. ECS Service
# ============================================================

log "13. ECS Service 생성"

aws ecs create-service \
  --cluster demo-cluster \
  --service-name demo-service \
  --task-definition demo-app \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration \
    "awsvpcConfiguration={
      subnets=[$SUBNET1,$SUBNET2],
      securityGroups=[$SG_ID],
      assignPublicIp=ENABLED
    }" \
  --load-balancers \
    "targetGroupArn=$TG_ARN,containerName=web,containerPort=80"

# ============================================================
# 14. ALB Target Health
# ============================================================

log "14. ECS Task / ALB Health Check"

for i in $(seq 1 30); do

  STATE=$(aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --query 'TargetHealthDescriptions[0].TargetHealth.State' \
    --output text 2>/dev/null || echo "none")

  echo "[$i/30] target health = $STATE"

  if [ "$STATE" = "healthy" ]; then
    break
  fi

  sleep 5

done

if [ "$STATE" != "healthy" ]; then

  echo
  echo "ALB target가 healthy 상태가 되지 않았습니다."

  echo
  echo "Target Health:"
  aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN"

  echo
  echo "ECS Service:"
  aws ecs describe-services \
    --cluster demo-cluster \
    --services demo-service

  exit 1
fi

# ============================================================
# 15. 결과
# ============================================================

log "완료"

echo
echo "=========================================="
echo "ECR"
echo "=========================================="
echo "Repository : $ECR_REPOSITORY"
echo "Image      : $ECR_URI:$IMAGE_TAG"
echo

echo "=========================================="
echo "RDS"
echo "=========================================="
echo "Endpoint : $DB_ENDPOINT"
echo

echo "=========================================="
echo "ALB"
echo "=========================================="
echo "DNS : $ALB_DNS"
echo

echo "=========================================="
echo "TEST"
echo "=========================================="
echo
echo "ALB -> ECS"
echo "curl http://$ALB_DNS/"
echo
echo "ALB -> ECS -> RDS"
echo "curl http://$ALB_DNS/db"
echo