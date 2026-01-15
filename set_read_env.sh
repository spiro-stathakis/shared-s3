#!/usr/bin/env bash

# READ credentials for the readonly-user

export S3_ENDPOINT_URL="https://$(oc get route ocs-storagecluster-cephobjectstore-secure -n openshift-storage -o jsonpath='{.spec.host}')"

OPERATOR_POD=$(oc get pod -n openshift-storage -l app=rook-ceph-operator -o jsonpath='{.items[0].metadata.name}')

DATA=$(oc exec -n openshift-storage "$OPERATOR_POD" -- \
  radosgw-admin user info \
  --uid="readonly-user" \
  --conf=/var/lib/rook/openshift-storage/openshift-storage.config \
  --keyring=/var/lib/rook/openshift-storage/client.admin.keyring)

export READ_ACCESS_KEY=$(jq -r '.keys[0].access_key' <<< "$DATA")
export READ_SECRET_KEY=$(jq -r '.keys[0].secret_key' <<< "$DATA")

echo "READ credentials are now set."
echo "Endpoint:   $S3_ENDPOINT_URL"
echo "Access Key: $READ_ACCESS_KEY"
