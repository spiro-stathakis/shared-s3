#!/usr/bin/env bash

set -e

NAMESPACE="shared-data"
IMAGE="quay.io/spidee/aws-cli:latest-amd64"
AWS_DEFAULT_REGION="us-east-1"
READONLY_ACCOUNT="readonly-user"
READONLY_SECRET="noobaa-account-readonly-user"

echo "=========================================="
echo "VERIFYING NOOBAA SETUP"
echo "=========================================="
echo ""

# 1. Check if NooBaa readonly account exists
echo "1. Checking NooBaa readonly account..."

# Find the noobaa-operator pod
OPERATOR_POD=$(oc get pod -n openshift-storage -l noobaa-operator=deployment -o jsonpath='{.items[0].metadata.name}')

if [[ -z "$OPERATOR_POD" ]]; then
    echo "❌ NooBaa operator pod not found"
    exit 1
fi

# Check if account exists using operator
ACCOUNT_CHECK=$(oc exec -n openshift-storage "$OPERATOR_POD" -- noobaa-operator account list 2>/dev/null | grep -w "${READONLY_ACCOUNT}" || echo "NOT_FOUND")

if [[ "$ACCOUNT_CHECK" == "NOT_FOUND" ]]; then
    echo "❌ NooBaa account '${READONLY_ACCOUNT}' does not exist"
    echo "   Run: cd init && ./10_create_readonly_account.sh"
    exit 1
else
    echo "✅ NooBaa account '${READONLY_ACCOUNT}' exists"
fi

# Check if secret exists
if oc get secret "${READONLY_SECRET}" -n openshift-storage &>/dev/null; then
    echo "✅ Account secret exists"
else
    echo "❌ Account secret not found (may still be provisioning)"
    echo "   Wait a moment and try again"
    exit 1
fi

echo ""

# 2. Get bucket and credentials
echo "2. Retrieving bucket information..."
BUCKET=$(oc get cm shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.BUCKET_NAME}')
WRITE_ACCESS_KEY=$(oc get secret shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
WRITE_SECRET_KEY=$(oc get secret shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
S3_ENDPOINT_URL="https://$(oc get route s3 -n openshift-storage -o jsonpath='{.spec.host}')"

echo "   Bucket:   ${BUCKET}"
echo "   Endpoint: ${S3_ENDPOINT_URL}"
echo "✅ Bucket information retrieved"

echo ""

# 3. Check bucket policy
echo "3. Checking bucket policy..."
POLICY_OUTPUT=$(podman run --rm \
    -e AWS_ACCESS_KEY_ID="${WRITE_ACCESS_KEY}" \
    -e AWS_SECRET_ACCESS_KEY="${WRITE_SECRET_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    "${IMAGE}" \
    s3api get-bucket-policy \
    --bucket "${BUCKET}" \
    --endpoint-url "${S3_ENDPOINT_URL}" \
    --no-verify-ssl 2>/dev/null || echo "NO_POLICY")

if [[ "$POLICY_OUTPUT" == *"NO_POLICY"* ]] || [[ "$POLICY_OUTPUT" == *"NoSuchBucketPolicy"* ]]; then
    echo "❌ No bucket policy found"
    echo "   Run: cd init && ./20_apply_policy.sh"
    exit 1
else
    echo "✅ Bucket policy exists"
    echo ""
    echo "   Policy contents:"
    echo "$POLICY_OUTPUT" | jq -r '.Policy' | jq '.'
fi

echo ""

# 4. Test readonly-user permissions with simple list
echo "4. Testing readonly-user permissions (s3 ls)..."
# Get readonly credentials
READ_ACCESS_KEY=$(oc get secret "${READONLY_SECRET}" -n openshift-storage -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
READ_SECRET_KEY=$(oc get secret "${READONLY_SECRET}" -n openshift-storage -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)

if podman run --rm \
    -e AWS_ACCESS_KEY_ID="${READ_ACCESS_KEY}" \
    -e AWS_SECRET_ACCESS_KEY="${READ_SECRET_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    "${IMAGE}" \
    s3 ls "s3://${BUCKET}/" \
    --endpoint-url "${S3_ENDPOINT_URL}" \
    --no-verify-ssl 2>/dev/null > /dev/null; then
    echo "✅ readonly-user can list bucket (s3:ListBucket works)"
else
    echo "❌ readonly-user CANNOT list bucket"
    echo "   Policy may not be correctly applied"
    echo "   Run: cd init && ./20_apply_policy.sh"
    exit 1
fi

echo ""

# 5. Test readonly-user with sync
echo "5. Testing readonly-user with s3 sync (dry-run)..."
mkdir -p /tmp/s3-test-noobaa
SYNC_OUTPUT=$(podman run --rm \
    -v "/tmp/s3-test-noobaa:/aws:z" \
    -w /aws \
    -e AWS_ACCESS_KEY_ID="${READ_ACCESS_KEY}" \
    -e AWS_SECRET_ACCESS_KEY="${READ_SECRET_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    "${IMAGE}" \
    s3 sync "s3://${BUCKET}/" /aws/test/ --dryrun \
    --endpoint-url "${S3_ENDPOINT_URL}" \
    --no-verify-ssl 2>&1)

SYNC_EXIT_CODE=$?

if [[ $SYNC_EXIT_CODE -eq 0 ]]; then
    echo "✅ readonly-user can use s3 sync"
elif echo "$SYNC_OUTPUT" | grep -q "AccessDenied"; then
    echo "❌ readonly-user has AccessDenied error"
    echo "   This may indicate the bucket policy is not properly configured"
    echo "   Run: cd init && ./20_apply_policy.sh"
    exit 1
else
    echo "⚠️  readonly-user s3 sync test returned error:"
    echo "$SYNC_OUTPUT" | tail -10
fi

echo ""
echo "=========================================="
echo "VERIFICATION COMPLETE"
echo "=========================================="
echo ""
echo "✅ NooBaa setup is working correctly!"
echo ""
echo "You can now use the read-only user with:"
echo "  ./s3_synch.sh read s3://folder/ ./local/"
echo ""
