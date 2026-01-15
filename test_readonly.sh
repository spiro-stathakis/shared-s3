#!/usr/bin/env bash

# Quick test script for readonly-user

cd "$(dirname "$0")"

source ./set_read_env.sh
source ./set_write_env.sh

IMAGE="quay.io/spidee/aws-cli:latest-amd64"
AWS_DEFAULT_REGION="us-east-1"

echo "Testing readonly-user access..."
echo "================================"
echo ""

echo "1. Test: s3 ls (list bucket)"
if podman run --rm \
    -e AWS_ACCESS_KEY_ID="${READ_ACCESS_KEY}" \
    -e AWS_SECRET_ACCESS_KEY="${READ_SECRET_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    "${IMAGE}" \
    s3 ls "s3://${BUCKET_NAME}/" \
    --endpoint-url "${S3_ENDPOINT_URL}" \
    --no-verify-ssl 2>/dev/null; then
    echo "✅ s3 ls works"
else
    echo "❌ s3 ls failed"
fi

echo ""
echo "2. Test: s3 cp (copy single file)"
echo "   (This will fail if no files exist, but shows if command works)"
podman run --rm \
    -v "$(pwd):/aws:z" \
    -w /aws \
    -e AWS_ACCESS_KEY_ID="${READ_ACCESS_KEY}" \
    -e AWS_SECRET_ACCESS_KEY="${READ_SECRET_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    "${IMAGE}" \
    s3 cp "s3://${BUCKET_NAME}/" ./ --recursive --dryrun \
    --endpoint-url "${S3_ENDPOINT_URL}" \
    --no-verify-ssl 2>&1 | head -20

echo ""
echo "3. Test: s3 sync with --debug to see where it fails"
podman run --rm \
    -v "$(pwd):/aws:z" \
    -w /aws \
    -e AWS_ACCESS_KEY_ID="${READ_ACCESS_KEY}" \
    -e AWS_SECRET_ACCESS_KEY="${READ_SECRET_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    "${IMAGE}" \
    s3 sync "s3://${BUCKET_NAME}/shared-s3/" ./test/ --dryrun --debug \
    --endpoint-url "${S3_ENDPOINT_URL}" \
    --no-verify-ssl 2>&1 | tail -50
