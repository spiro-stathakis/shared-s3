# Shared S3 Bucket with Read-Only Access for ODF

This project provides scripts to create and manage a shared S3 bucket on OpenShift Data Foundation (ODF) with separate read-only and read-write credentials. This is useful when you need to share data with external clients who should only have read access, while maintaining full write access for data updates.

## Architecture

- **Write credentials**: Full access to create, update, and delete objects in the bucket (from OBC secret)
- **Read credentials**: Read-only access for consuming clients (via Ceph `readonly-user`)

## Prerequisites

- OpenShift cluster with ODF (OpenShift Data Foundation) installed
- `oc` CLI logged in with cluster-admin privileges
- `podman` installed locally
- `jq` installed locally

## Initial Setup

Run these steps in order to create the shared bucket and configure read-only access.

### 1. Create the Namespace

```bash
oc apply -f init/namespace.yaml
```

### 2. Create the Object Bucket Claim

This creates the S3 bucket and generates write credentials:

```bash
oc apply -f init/obc.yaml
```

Wait for the OBC to be bound:

```bash
oc get obc -n shared-data
```

### 3. Create the Read-Only User

Create a read-only user in Ceph RGW:

```bash
./init/10_create_readonly_user.sh
```

### 4. Apply the Bucket Policy

Update `init/policy.json` with your actual bucket name, then apply the policy to grant the read-only user access:

```bash
cd init
./20_apply_policy.sh
```

**Note**: The bucket name in `policy.json` must match the generated bucket name from the OBC. Check it with:

```bash
oc get cm shared-data-bucket -n shared-data -o jsonpath='{.data.BUCKET_NAME}'
```

## Usage

### Setting Up Credentials

Before using the wrapper, source the appropriate environment script:

```bash
# For read-only operations
source set_read_env.sh

# For write operations
source set_write_env.sh
```

Each script exports:
- `S3_ENDPOINT_URL` - The RGW endpoint URL
- `READ_ACCESS_KEY` / `READ_SECRET_KEY` - Read-only credentials
- `WRITE_ACCESS_KEY` / `WRITE_SECRET_KEY` - Read-write credentials

### Using the S3 Wrapper

The `s3_wrapper.sh` script provides a simple interface for syncing data to/from the bucket.

**Automatic Bucket Name Injection**: You don't need to know the full bucket name. The wrapper automatically transforms `s3://` paths to include the actual bucket name. For example:
- `s3://backup/` becomes `s3://<generated-bucket-name>/backup/`
- `s3://` becomes `s3://<generated-bucket-name>/`

```bash
# Sync local data TO a folder in the bucket (uses write credentials)
./s3_wrapper.sh write ./local-data/ s3://backup/

# Sync current directory to the bucket root
./s3_wrapper.sh write . s3://

# Sync FROM the bucket to local (uses read credentials)
./s3_wrapper.sh read s3://data/ ./local-copy/

# Dry run (preview changes without executing)
./s3_wrapper.sh read --dryrun s3:// ./local-copy/
./s3_wrapper.sh write --dryrun ./local-data/ s3://backup/
```

## File Structure

```
shared-s3/
├── init/
│   ├── namespace.yaml          # Namespace definition
│   ├── obc.yaml                # ObjectBucketClaim for the shared bucket
│   ├── policy.json             # S3 bucket policy for read-only access
│   ├── 10_create_readonly_user.sh  # Creates the readonly-user in Ceph
│   └── 20_apply_policy.sh      # Applies the bucket policy
├── set_read_env.sh             # Exports READ_* credentials
├── set_write_env.sh            # Exports WRITE_* credentials
├── s3_wrapper.sh               # Main wrapper script for S3 operations
└── README.md
```

## Environment Variables

| Variable | Description | Set By |
|----------|-------------|--------|
| `S3_ENDPOINT_URL` | RGW endpoint URL | Both env scripts |
| `READ_ACCESS_KEY` | Read-only access key | `set_read_env.sh` |
| `READ_SECRET_KEY` | Read-only secret key | `set_read_env.sh` |
| `WRITE_ACCESS_KEY` | Read-write access key | `set_write_env.sh` |
| `WRITE_SECRET_KEY` | Read-write secret key | `set_write_env.sh` |
| `BUCKET_NAME` | Generated bucket name | `set_write_env.sh` |

## Distributing Read-Only Credentials

To share read-only access with clients, provide them with:

1. The S3 endpoint URL
2. The read-only access key and secret key (from `set_read_env.sh` output)
3. The bucket name

Clients can then use any S3-compatible tool (aws-cli, s3cmd, boto3, etc.) with these credentials.

## Troubleshooting

### OBC not binding
Check the ODF storage cluster is healthy:
```bash
oc get storagecluster -n openshift-storage
```

### Read-only user not found
Verify the user was created:
```bash
OPERATOR_POD=$(oc get pod -n openshift-storage -l app=rook-ceph-operator -o jsonpath='{.items[0].metadata.name}')
oc exec -n openshift-storage $OPERATOR_POD -- radosgw-admin user info --uid="readonly-user" \
  --conf=/var/lib/rook/openshift-storage/openshift-storage.config \
  --keyring=/var/lib/rook/openshift-storage/client.admin.keyring
```

### Permission denied with read credentials
Ensure the bucket policy was applied correctly and the bucket name in `policy.json` matches the actual bucket name.
