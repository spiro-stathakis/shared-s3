#!/usr/bin/env bash

set -e

NAMESPACE="shared-data"
IMAGE="quay.io/spidee/aws-cli:latest-amd64"
AWS_DEFAULT_REGION="us-east-1"

echo "=========================================="
echo "VERIFYING READONLY USER AND POLICY SETUP"
echo "=========================================="
echo ""

# 1. Check if readonly-user exists
echo "1. Checking if readonly-user exists..."
OPERATOR_POD=$(oc get pod -n openshift-storage -l app=rook-ceph-operator -o jsonpath='{.items[0].metadata.name}')

if oc exec -n openshift-storage "$OPERATOR_POD" -- \
    radosgw-admin user info \
    --uid="readonly-user" \
    --conf=/var/lib/rook/openshift-storage/openshift-storage.config \
    --keyring=/var/lib/rook/openshift-storage/client.admin.keyring \
    > /dev/null 2>&1; then
    echo "✅ readonly-user exists"

    # Get user details
    USER_INFO=$(oc exec -n openshift-storage "$OPERATOR_POD" -- \
        radosgw-admin user info \
        --uid="readonly-user" \
        --conf=/var/lib/rook/openshift-storage/openshift-storage.config \
        --keyring=/var/lib/rook/openshift-storage/client.admin.keyring)

    ACCESS_KEY=$(echo "$USER_INFO" | jq -r '.keys[0].access_key')
    echo "   Access Key: ${ACCESS_KEY}"
else
    echo "❌ readonly-user does NOT exist"
    echo "   Run: ./init/10_create_readonly_user.sh"
    exit 1
fi

echo ""

# 2. Get bucket info
echo "2. Getting bucket information..."
BUCKET=$(oc get cm shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.BUCKET_NAME}')
echo "   Bucket: ${BUCKET}"

# Get write credentials for checking policy
WRITE_ACCESS_KEY=$(oc get secret shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
WRITE_SECRET_KEY=$(oc get secret shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)

# Get endpoint
S3_ENDPOINT_URL="https://$(oc get route ocs-storagecluster-cephobjectstore-secure -n openshift-storage -o jsonpath='{.spec.host}')"
echo "   Endpoint: ${S3_ENDPOINT_URL}"

echo ""

# 3. Check if bucket policy exists
echo "3. Checking bucket policy..."
POLICY_OUTPUT=$(podman run --rm \
    -e AWS_ACCESS_KEY_ID="${WRITE_ACCESS_KEY}" \
    -e AWS_SECRET_ACCESS_KEY="${WRITE_SECRET_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    "${IMAGE}" \
    s3api get-bucket-policy \
    --bucket "${BUCKET}" \
    --endpoint-url "${S3_ENDPOINT_URL}" \
    --no-verify-ssl 2>&1 || echo "NO_POLICY")

if [[ "$POLICY_OUTPUT" == *"NO_POLICY"* ]] || [[ "$POLICY_OUTPUT" == *"NoSuchBucketPolicy"* ]]; then
    echo "❌ No bucket policy found"
    echo "   Run: ./init/20_apply_policy.sh"
    exit 1
else
    echo "✅ Bucket policy exists"
    echo ""
    echo "   Policy contents:"
    echo "$POLICY_OUTPUT" | jq '.Policy | fromjson' 2>/dev/null || echo "$POLICY_OUTPUT"
fi

echo ""

# 4. Test readonly-user permissions with simple list
echo "4. Testing readonly-user permissions (s3 ls)..."
# Get readonly credentials
READ_ACCESS_KEY=$(echo "$USER_INFO" | jq -r '.keys[0].access_key')
READ_SECRET_KEY=$(echo "$USER_INFO" | jq -r '.keys[0].secret_key')

if podman run --rm \
    -e AWS_ACCESS_KEY_ID="${READ_ACCESS_KEY}" \
    -e AWS_SECRET_ACCESS_KEY="${READ_SECRET_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    "${IMAGE}" \
    s3 ls "s3://${BUCKET}/" \
    --endpoint-url "${S3_ENDPOINT_URL}" \
    --no-verify-ssl > /dev/null 2>&1; then
    echo "✅ readonly-user can list bucket (s3:ListBucket works)"
else
    echo "❌ readonly-user CANNOT list bucket"
    echo "   Policy may not be correctly applied"
    exit 1
fi

echo ""

# 5. Test readonly-user with sync (this is where it fails)
echo "5. Testing readonly-user with s3 sync (dry-run)..."
mkdir -p /tmp/s3-test
if podman run --rm \
    -v "/tmp/s3-test:/aws:z" \
    -w /aws \
    -e AWS_ACCESS_KEY_ID="${READ_ACCESS_KEY}" \
    -e AWS_SECRET_ACCESS_KEY="${READ_SECRET_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    "${IMAGE}" \
    s3 sync "s3://${BUCKET}/" /aws/test/ --dryrun \
    --endpoint-url "${S3_ENDPOINT_URL}" \
    --no-verify-ssl 2>&1; then
    echo "✅ readonly-user can use s3 sync"
else
    echo "❌ readonly-user CANNOT use s3 sync"
    echo ""
    echo "DIAGNOSIS:"
    echo "The readonly-user has s3:GetObject and s3:ListBucket permissions,"
    echo "but 's3 sync' may require additional permissions that aren't granted."
    echo ""
    echo "WORKAROUND:"
    echo "Use the --write flag with read operations:"
    echo "  ./s3_wrapper.sh read --write s3://folder/ ./local/"
fi

echo ""
echo "=========================================="
echo "VERIFICATION COMPLETE"
echo "=========================================="
