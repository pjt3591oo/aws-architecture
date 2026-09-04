#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Kinesis Analytics Demo
#
#                    ┌── Firehose(S3) ────────> S3
# Kinesis Data Stream┤
#                    └── Firehose(OpenSearch) -> OpenSearch
#
# S3 -> Glue -> Athena
#
# ============================================================


export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_DEFAULT_REGION=ap-northeast-2

AWS_REGION=$AWS_DEFAULT_REGION
ACCOUNT_ID=000000000000

PROJECT="${PROJECT:-kinesis-analytics-demo}"

BUCKET="${PROJECT}-${ACCOUNT_ID}"

KINESIS_STREAM="${PROJECT}-stream"

FIREHOSE_S3="${PROJECT}-to-s3"
FIREHOSE_OS="${PROJECT}-to-os"

FIREHOSE_ROLE="${PROJECT}-firehose-role"

GLUE_DATABASE="${PROJECT}_db"
GLUE_TABLE="${PROJECT}_events"

ATHENA_WORKGROUP="${PROJECT}-workgroup"

OPENSEARCH_DOMAIN="${PROJECT}-os"

RAW_PREFIX="raw/"
ATHENA_PREFIX="athena-results/"
OS_BACKUP_PREFIX="opensearch-backup/"

INDEX_NAME="events"

log() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}


# ============================================================
# 0. Configuration
# ============================================================

log "AWS Configuration"

echo "Region     : $AWS_REGION"
echo "Account ID : $ACCOUNT_ID"
echo "Project    : $PROJECT"


# ============================================================
# 1. S3
# ============================================================

log "Creating S3 bucket"

if aws s3api head-bucket \
  --bucket "$BUCKET" 2>/dev/null; then

  echo "S3 bucket already exists."

else

    aws s3api create-bucket \
      --bucket "$BUCKET" \
      --create-bucket-configuration \
        LocationConstraint="$AWS_REGION"

fi

aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,\
IgnorePublicAcls=true,\
BlockPublicPolicy=true,\
RestrictPublicBuckets=true

echo "S3: s3://$BUCKET"


# ============================================================
# 2. Kinesis Data Stream
# ============================================================

log "Creating Kinesis Data Stream"

if aws kinesis describe-stream-summary \
  --stream-name "$KINESIS_STREAM" >/dev/null 2>&1; then

  echo "Kinesis stream already exists."

else

  aws kinesis create-stream \
    --stream-name "$KINESIS_STREAM" \
    --shard-count 1

  aws kinesis wait stream-exists \
    --stream-name "$KINESIS_STREAM"

fi

KINESIS_ARN=$(aws kinesis describe-stream-summary \
  --stream-name "$KINESIS_STREAM" \
  --query 'StreamDescriptionSummary.StreamARN' \
  --output text)

echo "Kinesis ARN: $KINESIS_ARN"


# ============================================================
# 3. IAM Role for Firehose
# ============================================================

log "Creating Firehose IAM Role"

cat > firehose-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "firehose.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

if aws iam get-role \
  --role-name "$FIREHOSE_ROLE" >/dev/null 2>&1; then

  echo "Firehose role already exists."

else

  aws iam create-role \
    --role-name "$FIREHOSE_ROLE" \
    --assume-role-policy-document \
      file://firehose-trust-policy.json

fi

FIREHOSE_ROLE_ARN=$(aws iam get-role \
  --role-name "$FIREHOSE_ROLE" \
  --query 'Role.Arn' \
  --output text)


# ============================================================
# 4. OpenSearch Domain
# ============================================================

log "Creating OpenSearch Domain"

if aws opensearch describe-domain \
  --domain-name "$OPENSEARCH_DOMAIN" >/dev/null 2>&1; then

  echo "OpenSearch domain already exists."

else

  aws opensearch create-domain \
    --domain-name "$OPENSEARCH_DOMAIN" \
    --engine-version "OpenSearch_2.19" \
    --cluster-config \
      "InstanceType=t3.small.search,InstanceCount=1,DedicatedMasterEnabled=false" \
    --ebs-options \
      "EBSEnabled=true,VolumeType=gp3,VolumeSize=10" \
    --node-to-node-encryption-options \
      "Enabled=true" \
    --encryption-at-rest-options \
      "Enabled=true" \
    --domain-endpoint-options \
      "EnforceHTTPS=true"

fi


echo
echo "Waiting for OpenSearch..."

while true; do

  PROCESSING=$(aws opensearch describe-domain \
    --domain-name "$OPENSEARCH_DOMAIN" \
    --query 'DomainStatus.Processing' \
    --output text)

  if [ "$PROCESSING" = "False" ]; then
    break
  fi

  echo "OpenSearch is still processing..."
  sleep 5

done

echo "OpenSearch is ready."


OPENSEARCH_ARN=$(aws opensearch describe-domain \
  --domain-name "$OPENSEARCH_DOMAIN" \
  --query 'DomainStatus.ARN' \
  --output text)

OPENSEARCH_ENDPOINT=$(aws opensearch describe-domain \
  --domain-name "$OPENSEARCH_DOMAIN" \
  --query 'DomainStatus.Endpoint' \
  --output text)

echo "OpenSearch ARN      : $OPENSEARCH_ARN"
echo "OpenSearch Endpoint : https://$OPENSEARCH_ENDPOINT"


# ============================================================
# 5. Firehose IAM Policy
# ============================================================

log "Configuring Firehose IAM permissions"

cat > firehose-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [

    {
      "Effect": "Allow",
      "Action": [
        "kinesis:GetShardIterator",
        "kinesis:GetRecords",
        "kinesis:DescribeStream",
        "kinesis:DescribeStreamSummary",
        "kinesis:ListShards"
      ],
      "Resource": "$KINESIS_ARN"
    },

    {
      "Effect": "Allow",
      "Action": [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::$BUCKET",
        "arn:aws:s3:::$BUCKET/*"
      ]
    },

    {
      "Effect": "Allow",
      "Action": [
        "es:DescribeDomain",
        "es:DescribeDomains",
        "es:DescribeDomainConfig",
        "es:ESHttpPost",
        "es:ESHttpPut"
      ],
      "Resource": [
        "$OPENSEARCH_ARN",
        "${OPENSEARCH_ARN}/*"
      ]
    }

  ]
}
EOF

aws iam put-role-policy \
  --role-name "$FIREHOSE_ROLE" \
  --policy-name "${PROJECT}-firehose-policy" \
  --policy-document file://firehose-policy.json


# ============================================================
# 6. OpenSearch Domain Access Policy
#
# NOTE:
#   This is intentionally permissive for a local/lab demo.
#   Do NOT use this policy for production.
# ============================================================

log "Configuring OpenSearch access policy"

cat > opensearch-access-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": "es:ESHttp*",
      "Resource": "${OPENSEARCH_ARN}/*"
    }
  ]
}
EOF

aws opensearch update-domain-config \
  --domain-name "$OPENSEARCH_DOMAIN" \
  --access-policies file://opensearch-access-policy.json

echo "OpenSearch access policy configured."


# ============================================================
# 7. Firehose -> S3
# ============================================================

log "Creating Firehose -> S3"

if aws firehose describe-delivery-stream \
  --delivery-stream-name "$FIREHOSE_S3" >/dev/null 2>&1; then

  echo "Firehose S3 already exists."

else

  cat > firehose-s3.json <<EOF
{
  "DeliveryStreamName": "$FIREHOSE_S3",
  "DeliveryStreamType": "KinesisStreamAsSource",

  "KinesisStreamSourceConfiguration": {
    "KinesisStreamARN": "$KINESIS_ARN",
    "RoleARN": "$FIREHOSE_ROLE_ARN"
  },

  "ExtendedS3DestinationConfiguration": {
    "RoleARN": "$FIREHOSE_ROLE_ARN",
    "BucketARN": "arn:aws:s3:::$BUCKET",

    "Prefix": "$RAW_PREFIX",

    "ErrorOutputPrefix": "errors/",

    "BufferingHints": {
      "SizeInMBs": 1,
      "IntervalInSeconds": 60
    },

    "CompressionFormat": "GZIP"
  }
}
EOF

  aws firehose create-delivery-stream \
      --region ap-northeast-2 \
      --cli-input-json file://firehose-s3.json

fi


# ============================================================
# 8. Firehose -> OpenSearch
# ============================================================

log "Creating Firehose -> OpenSearch"

if aws firehose describe-delivery-stream \
  --delivery-stream-name "$FIREHOSE_OS" >/dev/null 2>&1; then

  echo "Firehose OpenSearch already exists."

else

  cat > firehose-opensearch.json <<EOF
{
  "DeliveryStreamName": "$FIREHOSE_OS",

  "DeliveryStreamType": "KinesisStreamAsSource",

  "KinesisStreamSourceConfiguration": {
    "KinesisStreamARN": "$KINESIS_ARN",
    "RoleARN": "$FIREHOSE_ROLE_ARN"
  },

  "AmazonopensearchserviceDestinationConfiguration": {

    "RoleARN": "$FIREHOSE_ROLE_ARN",

    "DomainARN": "$OPENSEARCH_ARN",

    "IndexName": "$INDEX_NAME",

    "IndexRotationPeriod": "OneDay",

    "BufferingHints": {
      "IntervalInSeconds": 60,
      "SizeInMBs": 1
    },

    "S3BackupMode": "FailedDocumentsOnly",

    "S3Configuration": {
      "RoleARN": "$FIREHOSE_ROLE_ARN",
      "BucketARN": "arn:aws:s3:::$BUCKET",
      "Prefix": "$OS_BACKUP_PREFIX",
      "CompressionFormat": "GZIP"
    }
  }
}
EOF

  aws firehose create-delivery-stream \
    --region ap-northeast-2 \
    --cli-input-json file://firehose-opensearch.json

fi


# ============================================================
# 9. Glue IAM Role
# ============================================================

log "Creating Glue IAM Role"

GLUE_ROLE="${PROJECT}-glue-role"

cat > glue-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "glue.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

if aws iam get-role \
  --role-name "$GLUE_ROLE" >/dev/null 2>&1; then

  echo "Glue role already exists."

else

  aws iam create-role \
    --role-name "$GLUE_ROLE" \
    --assume-role-policy-document \
      file://glue-trust-policy.json

fi

GLUE_ROLE_ARN=$(aws iam get-role \
  --role-name "$GLUE_ROLE" \
  --query 'Role.Arn' \
  --output text)

aws iam attach-role-policy \
  --role-name "$GLUE_ROLE" \
  --policy-arn \
    arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole

cat > glue-s3-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::$BUCKET",
        "arn:aws:s3:::$BUCKET/*"
      ]
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name "$GLUE_ROLE" \
  --policy-name "${PROJECT}-glue-s3-policy" \
  --policy-document file://glue-s3-policy.json


# ============================================================
# 10. Glue Database
# ============================================================

log "Creating Glue Database"

if aws glue get-database \
  --name "$GLUE_DATABASE" >/dev/null 2>&1; then

  echo "Glue database already exists."

else

  aws glue create-database \
    --database-input \
      "Name=$GLUE_DATABASE,Description=Kinesis Analytics Demo"

fi


# ============================================================
# 11. Glue Table
# ============================================================

log "Creating Glue Table"

cat > glue-table.json <<EOF
{
  "Name": "$GLUE_TABLE",

  "StorageDescriptor": {

    "Columns": [
      {
        "Name": "event_id",
        "Type": "string"
      },
      {
        "Name": "event_type",
        "Type": "string"
      },
      {
        "Name": "user_id",
        "Type": "string"
      },
      {
        "Name": "product_id",
        "Type": "string"
      },
      {
        "Name": "amount",
        "Type": "double"
      },
      {
        "Name": "timestamp",
        "Type": "string"
      }
    ],

    "Location": "s3://$BUCKET/$RAW_PREFIX",

    "InputFormat":
      "org.apache.hadoop.mapred.TextInputFormat",

    "OutputFormat":
      "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",

    "Compressed": true,

    "SerdeInfo": {
      "SerializationLibrary":
        "org.openx.data.jsonserde.JsonSerDe"
    }
  },

  "TableType": "EXTERNAL_TABLE",

  "Parameters": {
    "classification": "json",
    "compressionType": "gzip",
    "typeOfData": "file"
  }
}
EOF

if aws glue get-table \
  --database-name "$GLUE_DATABASE" \
  --name "$GLUE_TABLE" >/dev/null 2>&1; then

  echo "Glue table already exists."

else

  aws glue create-table \
    --database-name "$GLUE_DATABASE" \
    --table-input file://glue-table.json

fi


# ============================================================
# 12. Athena Workgroup
# ============================================================

log "Creating Athena Workgroup"

if aws athena get-work-group \
  --work-group "$ATHENA_WORKGROUP" >/dev/null 2>&1; then

  echo "Athena workgroup already exists."

else

  aws athena create-work-group \
    --name "$ATHENA_WORKGROUP" \
    --configuration \
      "ResultConfiguration={OutputLocation=s3://$BUCKET/$ATHENA_PREFIX}"

fi


# ============================================================
# 13. Save environment
# ============================================================

cat > .env <<EOF
AWS_REGION=$AWS_REGION
PROJECT=$PROJECT

BUCKET=$BUCKET

KINESIS_STREAM=$KINESIS_STREAM
KINESIS_ARN=$KINESIS_ARN

FIREHOSE_S3=$FIREHOSE_S3
FIREHOSE_OS=$FIREHOSE_OS

GLUE_DATABASE=$GLUE_DATABASE
GLUE_TABLE=$GLUE_TABLE

ATHENA_WORKGROUP=$ATHENA_WORKGROUP

OPENSEARCH_DOMAIN=$OPENSEARCH_DOMAIN
OPENSEARCH_ARN=$OPENSEARCH_ARN
OPENSEARCH_ENDPOINT=$OPENSEARCH_ENDPOINT
OPENSEARCH_INDEX=$INDEX_NAME
EOF


# ============================================================
# 14. Summary
# ============================================================

log "Provisioning Complete"

cat <<EOF

============================================================
Resources
============================================================

S3
  s3://$BUCKET

Kinesis
  $KINESIS_STREAM

Firehose -> S3
  $FIREHOSE_S3

Firehose -> OpenSearch
  $FIREHOSE_OS

Glue Database
  $GLUE_DATABASE

Glue Table
  $GLUE_TABLE

Athena Workgroup
  $ATHENA_WORKGROUP

OpenSearch
  https://$OPENSEARCH_ENDPOINT

OpenSearch Index
  $INDEX_NAME

============================================================
Pipeline
============================================================

Kinesis
   |
   +----> Firehose -> S3
   |
   +----> Firehose -> OpenSearch

S3
   |
   v
Glue
   |
   v
Athena

============================================================

Environment saved to:
  .env

EOF