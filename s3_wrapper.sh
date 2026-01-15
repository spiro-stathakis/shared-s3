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

run_s3_container() {
    local mode=$1
    shift
    local args=("$@")
    local access_key=""
    local secret_key=""
    local dry_run_flag=""

    # Select credentials based on operation mode
    if [[ "$mode" == "read" ]]; then
        access_key="${READ_ACCESS_KEY}"
        secret_key="${READ_SECRET_KEY}"
        echo "🔓 Using READ-ONLY credentials..."
    else
        access_key="${WRITE_ACCESS_KEY}"
        secret_key="${WRITE_SECRET_KEY}"
        echo "🔐 Using READ-WRITE credentials..."
    fi

    # Check for dry run flag
    if [[ "${args[0]}" == "--dryrun" ]]; then
        dry_run_flag="--dryrun"
        args=("${args[@]:1}")
    fi

    # Transform s3:// paths to include the actual bucket name
    for i in "${!args[@]}"; do
        if [[ "${args[$i]}" =~ ^s3://(.*)$ ]]; then
            local path="${BASH_REMATCH[1]}"
            args[$i]="s3://${BUCKET_NAME}/${path}"
        fi
    done

    # Debug output
    echo "Endpoint: ${S3_ENDPOINT_URL}"
    echo "Bucket:   ${BUCKET_NAME}"
    echo "Command:  s3 sync ${dry_run_flag} ${args[*]}"

    # Execute Podman
    podman run --rm \
        -v "$(pwd):/aws:z" \
        -w /aws \
        -e AWS_ACCESS_KEY_ID="$access_key" \
        -e AWS_SECRET_ACCESS_KEY="$secret_key" \
        -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
        "${IMAGE}" \
        s3 sync ${dry_run_flag} "${args[@]}" --endpoint-url "${S3_ENDPOINT_URL}" --no-verify-ssl 2>&1
}


usage() {
    cat << EOF
S3 WRAPPER - NOOBAA S3 UTILITY

Usage:
  $0 [command] [--dryrun] [source] [destination]

Commands:
  read   - Sync from S3 to local (uses READ-ONLY credentials)
  write  - Sync from local to S3 (uses READ-WRITE credentials)

Flags:
  --dryrun  - Perform a dry run without making changes

Path Format:
  S3 paths are automatically prefixed with the bucket name.
  e.g., s3://folder becomes s3://${BUCKET_NAME}/folder

Examples:
  $0 read s3://data/ ./local-copy/       # Download: S3 to local
  $0 read --dryrun s3:// ./backup/       # Dry run: entire bucket to local
  $0 write ./data s3://backup/           # Upload: local to S3
  $0 write --dryrun . s3://               # Dry run: current dir to bucket root

Notes:
  - Read operations use the readonly-user NooBaa account
  - Write operations use the OBC owner account with full access
  - All paths are relative to the current directory
EOF
    exit 1
}

if [[ $# -lt 2 ]]; then usage; fi

COMMAND=$1
shift

case "$COMMAND" in
    read|write)
        run_s3_container "$COMMAND" "$@"
        ;;
    *)
        usage
        ;;
esac
