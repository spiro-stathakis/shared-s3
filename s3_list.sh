#!/usr/bin/env bash

export IMAGE="quay.io/spidee/aws-cli:latest-amd64"
AWS_DEFAULT_REGION="us-east-1"

# Resolve the actual script location (follows symlinks)
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

source "${SCRIPT_DIR}/set_read_env.sh"
source "${SCRIPT_DIR}/set_write_env.sh"

# Validate that required variables are set
if [[ -z "${BUCKET_NAME}" ]]; then
    echo "ERROR: BUCKET_NAME is not set. Check that set_write_env.sh ran successfully."
    echo "       Make sure you are logged into OpenShift with 'oc login'."
    exit 1
fi

if [[ -z "${S3_ENDPOINT_URL}" ]]; then
    echo "ERROR: S3_ENDPOINT_URL is not set. Check that the env scripts ran successfully."
    exit 1
fi

echo "Listing contents of bucket: ${BUCKET_NAME}"
echo "Using READ-ONLY credentials..."
echo "----------------------------------------"

podman run --rm \
    -e AWS_ACCESS_KEY_ID="${READ_ACCESS_KEY}" \
    -e AWS_SECRET_ACCESS_KEY="${READ_SECRET_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    "${IMAGE}" \
    s3 ls "s3://${BUCKET_NAME}/" --recursive --endpoint-url "${S3_ENDPOINT_URL}" --no-verify-ssl
