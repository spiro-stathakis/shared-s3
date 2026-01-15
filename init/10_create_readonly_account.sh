#!/usr/bin/env bash

set -e

NAMESPACE="shared-data"
READONLY_ACCOUNT="readonly-user"

echo "=========================================="
echo "CREATING NOOBAA READ-ONLY ACCOUNT"
echo "=========================================="
echo ""

# Get NooBaa CLI pod
NOOBAA_POD=$(oc get pod -n openshift-storage -l noobaa-mgmt=noobaa -o jsonpath='{.items[0].metadata.name}')

if [[ -z "$NOOBAA_POD" ]]; then
    echo "ERROR: Could not find NooBaa pod in openshift-storage namespace"
    exit 1
fi

echo "NooBaa pod: $NOOBAA_POD"
echo ""

# Check if account already exists
echo "Checking if account '${READONLY_ACCOUNT}' already exists..."
EXISTING_ACCOUNT=$(oc exec -n openshift-storage "$NOOBAA_POD" -- noobaa account list 2>/dev/null | grep -w "${READONLY_ACCOUNT}" || true)

if [[ -n "$EXISTING_ACCOUNT" ]]; then
    echo "⚠️  Account '${READONLY_ACCOUNT}' already exists"
    echo ""
    read -p "Do you want to delete and recreate it? (yes/no): " RECREATE
    if [[ "$RECREATE" == "yes" ]]; then
        echo "Deleting existing account..."
        oc exec -n openshift-storage "$NOOBAA_POD" -- noobaa account delete "${READONLY_ACCOUNT}"
        echo "✅ Account deleted"
        echo ""
    else
        echo "Keeping existing account. Exiting."
        exit 0
    fi
fi

# Create NooBaa account with read-only permissions
echo "Creating NooBaa account: ${READONLY_ACCOUNT}"
echo "Permissions: Read-only (no bucket creation allowed)"
echo ""

oc exec -n openshift-storage "$NOOBAA_POD" -- \
    noobaa account create \
    "${READONLY_ACCOUNT}" \
    --allow_bucket_create=false

echo ""
echo "✅ NooBaa account '${READONLY_ACCOUNT}' created successfully!"
echo ""

# Get the account details
echo "Account details:"
oc exec -n openshift-storage "$NOOBAA_POD" -- noobaa account status "${READONLY_ACCOUNT}"

echo ""
echo "=========================================="
echo "NEXT STEPS"
echo "=========================================="
echo "1. Get the access credentials from the secret:"
echo "   oc get secret ${READONLY_ACCOUNT} -n openshift-storage -o yaml"
echo ""
echo "2. Apply bucket policy to grant read access:"
echo "   cd init && ./20_apply_policy.sh"
echo ""
echo "3. Verify the setup:"
echo "   cd init && ./30_verify_setup.sh"
echo ""
