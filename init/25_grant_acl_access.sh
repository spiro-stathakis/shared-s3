#!/usr/bin/env bash

set -e

NAMESPACE="shared-data"
IMAGE="quay.io/spidee/aws-cli:latest-amd64"
AWS_DEFAULT_REGION="us-east-1"

echo "=========================================="
echo "GRANTING ACL-BASED READ ACCESS"
echo "=========================================="
echo ""

# Get bucket and credentials
BUCKET=$(oc get cm shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.BUCKET_NAME}')
WRITE_ACCESS_KEY=$(oc get secret shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
WRITE_SECRET_KEY=$(oc get secret shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
S3_ENDPOINT_URL="https://$(oc get route ocs-storagecluster-cephobjectstore-secure -n openshift-storage -o jsonpath='{.spec.host}')"

# Get readonly-user canonical ID
OPERATOR_POD=$(oc get pod -n openshift-storage -l app=rook-ceph-operator -o jsonpath='{.items[0].metadata.name}')
READONLY_USER_ID=$(oc exec -n openshift-storage "$OPERATOR_POD" -- \
  radosgw-admin user info \
  --uid="readonly-user" \
  --conf=/var/lib/rook/openshift-storage/openshift-storage.config \
  --keyring=/var/lib/rook/openshift-storage/client.admin.keyring | jq -r '.user_id')

echo "Bucket: ${BUCKET}"
echo "Readonly User ID: ${READONLY_USER_ID}"
echo "Endpoint: ${S3_ENDPOINT_URL}"
echo ""

# Get current ACL
echo "Getting current bucket ACL..."
CURRENT_ACL=$(podman run --rm \
    -e AWS_ACCESS_KEY_ID="${WRITE_ACCESS_KEY}" \
    -e AWS_SECRET_ACCESS_KEY="${WRITE_SECRET_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    "${IMAGE}" \
    s3api get-bucket-acl \
    --bucket "${BUCKET}" \
    --endpoint-url "${S3_ENDPOINT_URL}" \
    --no-verify-ssl 2>/dev/null)

OWNER_ID=$(echo "$CURRENT_ACL" | jq -r '.Owner.ID')
OWNER_DISPLAY=$(echo "$CURRENT_ACL" | jq -r '.Owner.DisplayName')

echo "Current bucket owner: ${OWNER_DISPLAY}"
echo ""

# Create new ACL with readonly-user added
echo "Creating new ACL with readonly-user granted READ permission..."

NEW_ACL=$(cat <<EOF
{
  "Owner": {
    "ID": "${OWNER_ID}",
    "DisplayName": "${OWNER_DISPLAY}"
  },
  "Grants": [
    {
      "Grantee": {
        "ID": "${OWNER_ID}",
        "DisplayName": "${OWNER_DISPLAY}",
        "Type": "CanonicalUser"
      },
      "Permission": "FULL_CONTROL"
    },
    {
      "Grantee": {
        "ID": "${READONLY_USER_ID}",
        "Type": "CanonicalUser"
      },
      "Permission": "READ"
    }
  ]
}
EOF
)

echo "$NEW_ACL" | jq '.'
echo ""

# Write ACL to temp file and apply
TEMP_ACL_FILE=$(mktemp)
echo "$NEW_ACL" > "$TEMP_ACL_FILE"

echo "Applying new ACL..."
podman run --rm \
    -v "$(dirname $TEMP_ACL_FILE):/tmp:z" \
    -e AWS_ACCESS_KEY_ID="${WRITE_ACCESS_KEY}" \
    -e AWS_SECRET_ACCESS_KEY="${WRITE_SECRET_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    "${IMAGE}" \
    s3api put-bucket-acl \
    --bucket "${BUCKET}" \
    --access-control-policy "file:///tmp/$(basename $TEMP_ACL_FILE)" \
    --endpoint-url "${S3_ENDPOINT_URL}" \
    --no-verify-ssl

rm "$TEMP_ACL_FILE"

echo ""
echo "✅ ACL applied successfully!"
echo ""
echo "Note: ACLs grant READ permission at the bucket level."
echo "This allows listing and reading objects, which should work for s3 sync."
echo ""
echo "Run ./30_verify_setup.sh to test the access."
