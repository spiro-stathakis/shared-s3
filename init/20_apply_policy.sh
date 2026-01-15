#!/usr/bin/env bash

set -e

NAMESPACE="shared-data"
IMAGE="quay.io/spidee/aws-cli:latest-amd64"
AWS_DEFAULT_REGION="us-east-1"

echo "=========================================="
echo "APPLYING NOOBAA BUCKET POLICY"
echo "=========================================="
echo ""

# Get bucket name
BUCKET=$(oc get cm shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.BUCKET_NAME}')

# Get write credentials
AWS_ACCESS_KEY_ID=$(oc get secret shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
AWS_SECRET_ACCESS_KEY=$(oc get secret shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)

# Get NooBaa S3 endpoint
S3_ENDPOINT_URL="https://$(oc get route s3 -n openshift-storage -o jsonpath='{.spec.host}')"

echo "Bucket:   ${BUCKET}"
echo "Endpoint: ${S3_ENDPOINT_URL}"
echo ""

# Create policy with actual bucket name
POLICY_FILE="./policy-applied.json"
sed "s/BUCKET_NAME_PLACEHOLDER/${BUCKET}/g" policy.json > "${POLICY_FILE}"

echo "Policy contents:"
cat "${POLICY_FILE}" | jq '.'
echo ""

echo "Applying bucket policy..."
podman run --rm \
    -v "$(pwd):/aws:z" \
    -w /aws \
    -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
    -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    "${IMAGE}" \
    s3api put-bucket-policy \
    --bucket "${BUCKET}" \
    --policy file://policy-applied.json \
    --endpoint-url "${S3_ENDPOINT_URL}" \
    --no-verify-ssl

rm "${POLICY_FILE}"

echo ""
echo "✅ Bucket policy applied successfully!"
echo ""
echo "=========================================="
echo "NEXT STEPS"
echo "=========================================="
echo "1. Verify the policy was applied:"
echo "   cd init && ./30_verify_setup.sh"
echo ""
echo "2. Test read operations with readonly-user:"
echo "   ./s3_wrapper.sh read s3://folder/ ./local/"
echo ""
