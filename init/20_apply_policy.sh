#!/usr/bin/env bash

NAMESPACE="shared-data"
IMAGE="quay.io/spidee/aws-cli:latest-amd64"
AWS_DEFAULT_REGION="us-east-1"

# Get bucket name
BUCKET=$(oc get cm shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.BUCKET_NAME}')

# Get write credentials
AWS_ACCESS_KEY_ID=$(oc get secret shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
AWS_SECRET_ACCESS_KEY=$(oc get secret shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)

# Get endpoint (same method as other scripts)
S3_ENDPOINT_URL="https://$(oc get route ocs-storagecluster-cephobjectstore-secure -n openshift-storage -o jsonpath='{.spec.host}')"

echo "Applying bucket policy..."
echo "Bucket:   ${BUCKET}"
echo "Endpoint: ${S3_ENDPOINT_URL}"

podman run --rm \
    -v "$(pwd):/aws:Z" \
    -w /aws \
    -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
    -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    "${IMAGE}" \
    s3api put-bucket-policy \
    --bucket "${BUCKET}" \
    --policy file://policy.json \
    --endpoint-url "${S3_ENDPOINT_URL}" \
    --no-verify-ssl
