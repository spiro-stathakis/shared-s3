#!/usr/bin/env bash

set -e

READONLY_ACCOUNT="readonly-user"

echo "=========================================="
echo "CREATING NOOBAA READ-ONLY ACCOUNT"
echo "=========================================="
echo ""

# Find the noobaa-operator pod
OPERATOR_POD=$(oc get pod -n openshift-storage -l noobaa-operator=deployment -o jsonpath='{.items[0].metadata.name}')

if [[ -z "$OPERATOR_POD" ]]; then
    echo "ERROR: Could not find NooBaa operator pod in openshift-storage namespace"
    exit 1
fi

echo "NooBaa operator pod: $OPERATOR_POD"
echo ""

# Check if account already exists
echo "Checking if account '${READONLY_ACCOUNT}' already exists..."
EXISTING_ACCOUNT=$(oc exec -n openshift-storage "$OPERATOR_POD" -- noobaa-operator account list 2>/dev/null | grep -w "${READONLY_ACCOUNT}" || true)

if [[ -n "$EXISTING_ACCOUNT" ]]; then
    echo "⚠️  Account '${READONLY_ACCOUNT}' already exists"
    echo ""
    read -p "Do you want to delete and recreate it? (yes/no): " RECREATE
    if [[ "$RECREATE" == "yes" ]]; then
        echo "Deleting existing account..."
        oc exec -n openshift-storage "$OPERATOR_POD" -- noobaa-operator account delete "${READONLY_ACCOUNT}"
        echo "✅ Account deleted"
        echo ""
        sleep 2
    else
        echo "Keeping existing account. Exiting."
        exit 0
    fi
fi

# Create NooBaa account with read-only permissions
echo "Creating NooBaa account: ${READONLY_ACCOUNT}"
echo "Permissions: Read-only (no bucket creation allowed)"
echo ""

oc exec -n openshift-storage "$OPERATOR_POD" -- \
    noobaa-operator account create "${READONLY_ACCOUNT}" \
    --allow_bucket_create=false

echo ""
echo "Waiting for account secret to be created..."
sleep 5

# Wait for the secret to be created
RETRIES=30
COUNT=0
while [[ $COUNT -lt $RETRIES ]]; do
    if oc get secret "${READONLY_ACCOUNT}" -n openshift-storage &>/dev/null; then
        echo "✅ Account secret created!"
        break
    fi
    COUNT=$((COUNT + 1))
    echo "  Waiting... ($COUNT/$RETRIES)"
    sleep 2
done

if [[ $COUNT -eq $RETRIES ]]; then
    echo "❌ Timeout waiting for account secret to be created"
    exit 1
fi

echo ""
echo "Account details:"
echo "----------------------------------------"
ACCESS_KEY=$(oc get secret "${READONLY_ACCOUNT}" -n openshift-storage -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
echo "Account Name:  ${READONLY_ACCOUNT}"
echo "Access Key:    ${ACCESS_KEY}"
echo "Secret:        ${READONLY_ACCOUNT} (in openshift-storage namespace)"
echo "Permissions:   Read-only (allow_bucket_create: false)"

echo ""
echo "✅ NooBaa account '${READONLY_ACCOUNT}' created successfully!"
echo ""
echo "=========================================="
echo "NEXT STEPS"
echo "=========================================="
echo "1. Apply bucket policy to grant read access:"
echo "   cd init && ./20_apply_policy.sh"
echo ""
echo "2. Verify the setup:"
echo "   cd init && ./30_verify_setup.sh"
echo ""
