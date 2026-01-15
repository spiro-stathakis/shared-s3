#!/usr/bin/env bash

IMAGE="quay.io/spidee/aws-cli:latest-amd64"
AWS_DEFAULT_REGION="us-east-1"
NAMESPACE="shared-data"

echo "=========================================="
echo "CHECKING USER AND BUCKET INFORMATION"
echo "=========================================="
echo ""

OPERATOR_POD=$(oc get pod -n openshift-storage -l app=rook-ceph-operator -o jsonpath='{.items[0].metadata.name}')
BUCKET=$(oc get cm shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.BUCKET_NAME}')
S3_ENDPOINT_URL="https://$(oc get route ocs-storagecluster-cephobjectstore-secure -n openshift-storage -o jsonpath='{.spec.host}')"

echo "Bucket: $BUCKET"
echo ""

echo "=== 1. readonly-user info ==="
oc exec -n openshift-storage "$OPERATOR_POD" -- \
  radosgw-admin user info \
  --uid="readonly-user" \
  --conf=/var/lib/rook/openshift-storage/openshift-storage.config \
  --keyring=/var/lib/rook/openshift-storage/client.admin.keyring | jq '{user_id, tenant, display_name, keys, caps}'

echo ""
echo "=== 2. Write user (from OBC) info ==="
WRITE_ACCESS_KEY=$(oc get secret shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
WRITE_SECRET_KEY=$(oc get secret shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)

echo "Write access key: $WRITE_ACCESS_KEY"
echo ""
echo "Looking up user by access key..."

WRITE_USER_INFO=$(oc exec -n openshift-storage "$OPERATOR_POD" -- \
  radosgw-admin user info \
  --access-key="$WRITE_ACCESS_KEY" \
  --conf=/var/lib/rook/openshift-storage/openshift-storage.config \
  --keyring=/var/lib/rook/openshift-storage/client.admin.keyring 2>/dev/null)

if [[ -n "$WRITE_USER_INFO" ]]; then
    echo "$WRITE_USER_INFO" | jq '{user_id, tenant, display_name, keys, caps}'
else
    echo "Could not find write user info"
fi

echo ""
echo "=== 3. Bucket ACL (shows owner) ==="
podman run --rm \
    -e AWS_ACCESS_KEY_ID="${WRITE_ACCESS_KEY}" \
    -e AWS_SECRET_ACCESS_KEY="${WRITE_SECRET_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    "${IMAGE}" \
    s3api get-bucket-acl \
    --bucket "${BUCKET}" \
    --endpoint-url "${S3_ENDPOINT_URL}" \
    --no-verify-ssl 2>/dev/null | jq '.'

echo ""
echo "=== 4. List all users in RGW ==="
echo "All users:"
oc exec -n openshift-storage "$OPERATOR_POD" -- \
  radosgw-admin user list \
  --conf=/var/lib/rook/openshift-storage/openshift-storage.config \
  --keyring=/var/lib/rook/openshift-storage/client.admin.keyring | jq '.'

echo ""
echo "=========================================="
echo "ANALYSIS:"
echo "- Check if user_id formats match between readonly and write users"
echo "- Check if tenants are the same or if one has a tenant"
echo "- The bucket owner shown in ACL should match the write user"
echo "- Use the exact user_id format from write user in policy"
echo "=========================================="
