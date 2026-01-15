#!/usr/bin/env bash

export IMAGE="quay.io/spidee/aws-cli:latest-amd64"
AWS_DEFAULT_REGION="us-east-1"

# Resolve the actual script location (follows symlinks)
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    # If SOURCE is relative, resolve it relative to the symlink's directory
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

    # Check for --write flag to force using write credentials
    if [[ "${args[0]}" == "--write" ]]; then
        # Remove --write from the arguments list
        args=("${args[@]:1}")
        # Force using write credentials
        access_key="${WRITE_ACCESS_KEY}"
        secret_key="${WRITE_SECRET_KEY}"
        echo "🔐 Using READ-WRITE credentials (forced by --write flag)..."
    elif [[ "$mode" == "read" ]]; then
        access_key="${READ_ACCESS_KEY}"
        secret_key="${READ_SECRET_KEY}"
        echo "🔓 Using READ-ONLY credentials..."
    else
        access_key="${WRITE_ACCESS_KEY}"
        secret_key="${WRITE_SECRET_KEY}"
        echo "🔐 Using READ-WRITE credentials..."
    fi

    # Check for Manual Dry Run
    if [[ "${args[0]}" == "--dryrun" ]]; then
        dry_run_flag="--dryrun"
        # Remove --dryrun from the arguments list so it doesn't break pathing
        args=("${args[@]:1}")
    fi

    # Transform s3:// paths to include the actual bucket name
    # e.g., s3://folder -> s3://bucket-name/folder
    for i in "${!args[@]}"; do
        if [[ "${args[$i]}" =~ ^s3://(.*)$ ]]; then
            local path="${BASH_REMATCH[1]}"
            args[$i]="s3://${BUCKET_NAME}/${path}"
        fi
    done

    # Debug output
    echo "DEBUG: S3_ENDPOINT_URL=${S3_ENDPOINT_URL}"
    echo "DEBUG: Bucket=${BUCKET_NAME}"
    echo "DEBUG: Access Key=${access_key:0:5}..."
    echo "DEBUG: Args=${args[*]}"
    echo "DEBUG: Full command: s3 sync ${dry_run_flag} ${args[*]} --endpoint-url ${S3_ENDPOINT_URL} --no-verify-ssl"

    # Execute Podman
    # Note: Using :z (lowercase) for better compatibility with SELinux
    # The container needs write access when doing read operations (S3 -> local)
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
S3 WRAPPER - ODF/CEPH UTILITY

Usage:
  $0 [command] [--write] [--dryrun] [source] [destination]

Commands:
  read   - Sync from S3 to local (Uses READ_ACCESS_KEY by default)
  write  - Sync from local to S3 (Uses WRITE_ACCESS_KEY)

Flags:
  --write   - Force use of WRITE credentials (useful for read operations with read-only credential issues)
  --dryrun  - Perform a dry run without making changes

Note: s3:// paths are automatically prefixed with the bucket name.
      e.g., s3://folder becomes s3://${BUCKET_NAME}/folder

Examples:
  $0 write ./data s3://backup/           # Syncs ./data to s3://\${BUCKET_NAME}/backup/
  $0 write . s3://                        # Syncs current dir to bucket root
  $0 read s3://data/ ./local-copy/       # Syncs s3://\${BUCKET_NAME}/data/ to ./local-copy/
  $0 read --write s3://data/ ./local/    # Syncs using WRITE credentials
  $0 read --dryrun s3:// ./backup/       # Dry run: bucket root to ./backup/
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
