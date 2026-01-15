#!/usr/bin/env bash

# WRITE credentials for the shared-data bucket

NAMESPACE="shared-data"

export S3_ENDPOINT_URL="https://$(oc get route ocs-storagecluster-cephobjectstore-secure -n openshift-storage -o jsonpath='{.spec.host}')"

export BUCKET_NAME=$(oc get cm shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.BUCKET_NAME}')

export WRITE_ACCESS_KEY=$(oc get secret shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
export WRITE_SECRET_KEY=$(oc get secret shared-data-bucket -n "${NAMESPACE}" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)

echo "WRITE credentials are now set."
echo "Endpoint:   $S3_ENDPOINT_URL"
echo "Bucket:     $BUCKET_NAME"
echo "Access Key: $WRITE_ACCESS_KEY"
