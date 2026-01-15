#!/usr/bin/env bash

echo "Checking readonly-user capabilities and details..."
echo ""

OPERATOR_POD=$(oc get pod -n openshift-storage -l app=rook-ceph-operator -o jsonpath='{.items[0].metadata.name}')

echo "Full user info:"
oc exec -n openshift-storage "$OPERATOR_POD" -- \
  radosgw-admin user info \
  --uid="readonly-user" \
  --conf=/var/lib/rook/openshift-storage/openshift-storage.config \
  --keyring=/var/lib/rook/openshift-storage/client.admin.keyring | jq '.'

echo ""
echo "=========================================="
echo ""
echo "To grant read-only access via Ceph caps instead of bucket policy, you could run:"
echo ""
echo "oc exec -n openshift-storage \$OPERATOR_POD -- \\"
echo "  radosgw-admin caps add \\"
echo "  --uid=readonly-user \\"
echo "  --caps='buckets=read;metadata=read' \\"
echo "  --conf=/var/lib/rook/openshift-storage/openshift-storage.config \\"
echo "  --keyring=/var/lib/rook/openshift-storage/client.admin.keyring"
