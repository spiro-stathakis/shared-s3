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

# Get the path to delete (optional argument)
DELETE_PATH="${1:-}"

# Transform s3:// path if provided
if [[ -n "${DELETE_PATH}" && "${DELETE_PATH}" =~ ^s3://(.*)$ ]]; then
    DELETE_PATH="s3://${BUCKET_NAME}/${BASH_REMATCH[1]}"
else
    DELETE_PATH="s3://${BUCKET_NAME}/${DELETE_PATH}"
fi

echo "WARNING: This will delete contents from: ${DELETE_PATH}"
echo "Using WRITE credentials..."
echo "----------------------------------------"

# Check for --force flag
if [[ "$1" == "--force" || "$2" == "--force" ]]; then
    CONFIRM="yes"
else
    read -p "Are you sure you want to delete? Type 'yes' to confirm: " CONFIRM
fi

if [[ "${CONFIRM}" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

echo "Deleting..."

podman run --rm \
    -e AWS_ACCESS_KEY_ID="${WRITE_ACCESS_KEY}" \
    -e AWS_SECRET_ACCESS_KEY="${WRITE_SECRET_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    "${IMAGE}" \
    s3 rm "${DELETE_PATH}" --recursive --endpoint-url "${S3_ENDPOINT_URL}" --no-verify-ssl

echo "Done."
