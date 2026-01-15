#!/usr/bin/env bash

# READ credentials for the NooBaa readonly-user account

READONLY_ACCOUNT="readonly-user"
READONLY_SECRET="noobaa-account-readonly-user"

# Get S3 endpoint from NooBaa service
export S3_ENDPOINT_URL="https://$(oc get route s3 -n openshift-storage -o jsonpath='{.spec.host}')"

# Get readonly account credentials from NooBaa secret
export READ_ACCESS_KEY=$(oc get secret "${READONLY_SECRET}" -n openshift-storage -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' 2>/dev/null | base64 -d)
export READ_SECRET_KEY=$(oc get secret "${READONLY_SECRET}" -n openshift-storage -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' 2>/dev/null | base64 -d)

if [[ -z "$READ_ACCESS_KEY" ]]; then
    echo "ERROR: Could not retrieve READ credentials from NooBaa secret '${READONLY_SECRET}'"
    echo "       Make sure the readonly account exists: cd init && ./10_create_readonly_account.sh"
    exit 1
fi

echo "READ credentials are now set."
echo "Endpoint:   $S3_ENDPOINT_URL"
echo "Access Key: $READ_ACCESS_KEY"
