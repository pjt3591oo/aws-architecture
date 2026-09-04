#!/usr/bin/env bash

set -euo pipefail

source .env

echo "Deleting Firehose streams..."

aws firehose delete-delivery-stream \
  --delivery-stream-name "$FIREHOSE_S3" \
  2>/dev/null || true

aws firehose delete-delivery-stream \
  --delivery-stream-name "$FIREHOSE_OS" \
  2>/dev/null || true


echo "Deleting Kinesis..."

aws kinesis delete-stream \
  --stream-name "$KINESIS_STREAM" \
  --enforce-deletion-policy \
  2>/dev/null || true


echo "Deleting Glue table..."

aws glue delete-table \
  --database-name "$GLUE_DATABASE" \
  --name "$GLUE_TABLE" \
  2>/dev/null || true


echo "Deleting Glue database..."

aws glue delete-database \
  --name "$GLUE_DATABASE" \
  2>/dev/null || true


echo "Deleting Athena workgroup..."

aws athena delete-work-group \
  --work-group "$ATHENA_WORKGROUP" \
  --recursive-delete-option \
  2>/dev/null || true


echo "Deleting OpenSearch..."

aws opensearch delete-domain \
  --domain-name "$OPENSEARCH_DOMAIN" \
  2>/dev/null || true


echo "Deleting IAM policies..."

aws iam delete-role-policy \
  --role-name "$FIREHOSE_ROLE" \
  --policy-name "${PROJECT}-firehose-policy" \
  2>/dev/null || true

aws iam delete-role \
  --role-name "$FIREHOSE_ROLE" \
  2>/dev/null || true


aws iam delete-role-policy \
  --role-name "${PROJECT}-glue-role" \
  --policy-name "${PROJECT}-glue-s3-policy" \
  2>/dev/null || true

aws iam detach-role-policy \
  --role-name "${PROJECT}-glue-role" \
  --policy-arn \
    arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole \
  2>/dev/null || true

aws iam delete-role \
  --role-name "${PROJECT}-glue-role" \
  2>/dev/null || true


echo
echo "============================================================"
echo "AWS resources deleted."
echo "============================================================"
echo
echo "S3 bucket was NOT deleted:"
echo "  s3://$BUCKET"
echo
echo "Delete it manually after checking the data:"
echo
echo "  aws s3 rm s3://$BUCKET --recursive"
echo "  aws s3api delete-bucket --bucket $BUCKET"