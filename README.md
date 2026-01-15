# Shared S3 Access Scripts

Scripts for accessing Ceph/RGW S3 storage via Rook OBC (ObjectBucketClaim).

## Quick Start

```bash
# Read from S3 (sync from bucket to local)
./s3_wrapper.sh read --write s3://folder/ ./local-folder/

# Write to S3 (sync from local to bucket)
./s3_wrapper.sh write ./local-folder/ s3://folder/

# List bucket contents
./s3_list.sh --write

# Delete objects
./s3_delete.sh s3://folder/file.txt
```

## ⚠️ Important: Read-Only User Limitation

**The readonly-user does NOT work with OBC-created buckets due to a Rook/Ceph architecture limitation.**

### Why?

- OBC (ObjectBucketClaim) creates users in a separate authentication realm
- Users created with `radosgw-admin` (like readonly-user) cannot access OBC buckets
- Ceph RGW returns `InvalidAccessKeyId` (403) when readonly-user tries to access the bucket
- Bucket policies and ACLs cannot bridge this gap between the two user management systems

### Workaround

Use the `--write` flag with read operations to force use of OBC credentials:

```bash
# This uses WRITE credentials but only performs read operations
./s3_wrapper.sh read --write s3://folder/ ./local-folder/
```

**Note:** The `--write` flag simply selects which credentials to use - it doesn't grant additional permissions to the operation itself. `s3 sync` from S3 to local is inherently a read-only operation regardless of credentials used.

## Scripts

### s3_wrapper.sh

Main script for syncing files between S3 and local filesystem.

**Usage:**
```bash
./s3_wrapper.sh [command] [--write] [--dryrun] [source] [destination]
```

**Commands:**
- `read` - Sync FROM S3 TO local (download)
- `write` - Sync FROM local TO S3 (upload)

**Flags:**
- `--write` - Force use of WRITE credentials (required for read operations due to readonly-user limitation)
- `--dryrun` - Preview changes without making them

**Path Format:**
- S3 paths: `s3://folder/` (bucket name is auto-detected and prepended)
- Local paths: `./folder/` or absolute paths

**Examples:**
```bash
# Download entire bucket
./s3_wrapper.sh read --write s3:// ./backup/

# Download specific folder
./s3_wrapper.sh read --write s3://shared-s3/ ./local-data/

# Upload folder
./s3_wrapper.sh write ./data/ s3://backup/

# Dry run upload
./s3_wrapper.sh write --dryrun ./data/ s3://backup/
```

### s3_list.sh

List bucket contents recursively.

**Usage:**
```bash
./s3_list.sh [--write]
```

**Flags:**
- `--write` - Use WRITE credentials (recommended, READ credentials don't work with OBC buckets)

**Default:** Uses READ credentials (which will fail with OBC buckets)

### s3_delete.sh

Delete objects from S3.

**Usage:**
```bash
./s3_delete.sh s3://path/to/file.txt
./s3_delete.sh s3://folder/  # Delete entire folder recursively
```

## Setup (Initial)

The `init/` directory contains setup scripts (for reference/debugging):

1. `10_create_readonly_user.sh` - Creates readonly-user (⚠️ doesn't work with OBC buckets)
2. `20_apply_policy.sh` - Applies bucket policy (⚠️ doesn't work due to user realm mismatch)
3. `25_grant_acl_access.sh` - Attempts ACL grant (⚠️ doesn't work due to user realm mismatch)
4. `30_verify_setup.sh` - Verifies setup and tests access
5. `debug_user_tenant.sh` - Debug script showing user information and ACLs

## Technical Details

### Credential Sources

**READ credentials** (readonly-user):
- Created via: `radosgw-admin user create --uid=readonly-user`
- Source: OpenShift pod execution on rook-ceph-operator
- **Limitation: Cannot access OBC buckets** (returns InvalidAccessKeyId 403 error)
- Why it fails: radosgw-admin users and OBC users exist in separate authentication realms

**WRITE credentials** (OBC user):
- Created via: ObjectBucketClaim in `shared-data` namespace
- Source: Kubernetes secrets (`shared-data-bucket`)
- User ID format: `obc-shared-data-shared-data-bucket-<uuid>`
- Works for all operations on the OBC bucket

### Error: "argument of type 'NoneType' is not iterable"

This cryptic error occurs when:

1. readonly-user credentials are used with an OBC bucket
2. Ceph RGW returns `InvalidAccessKeyId` (403) with an **empty error message**
3. AWS CLI's error handler (`s3errormsg.py`) tries to parse the empty message
4. Python crashes when checking `if substring in None`

The root cause is authentication failure, not a sync/permission issue.

### Directory Structure

```
.
├── README.md               # This file
├── s3_wrapper.sh           # Main sync script
├── s3_list.sh              # List objects
├── s3_delete.sh            # Delete objects
├── set_read_env.sh         # Load READ credentials
├── set_write_env.sh        # Load WRITE credentials (and bucket name)
├── test_readonly.sh        # Test readonly-user access (for debugging)
├── init/                   # Setup scripts (mostly non-functional due to OBC limitation)
│   ├── namespace.yaml
│   ├── obc.yaml
│   ├── policy.json
│   ├── policy-extended.json
│   ├── policy-test-open.json
│   ├── 10_create_readonly_user.sh
│   ├── 20_apply_policy.sh
│   ├── 25_grant_acl_access.sh
│   ├── 30_verify_setup.sh
│   ├── check_user_caps.sh
│   └── debug_user_tenant.sh
```

## Troubleshooting

### "fatal error: argument of type 'NoneType' is not iterable"

**Cause:** Using readonly-user credentials with OBC buckets. Ceph returns InvalidAccessKeyId with empty message, AWS CLI crashes parsing it.

**Solution:** Use `--write` flag: `./s3_wrapper.sh read --write s3://folder/ ./local/`

### "InvalidAccessKeyId" (403)

**Cause:** The credentials don't have access to the bucket.

**For readonly-user:** This is expected with OBC buckets - use `--write` flag instead.
**For WRITE user:** Check that you're logged into OpenShift: `oc login`

### Bucket policy not working

**Cause:** Bucket policies cannot grant access across user management realms (OBC vs radosgw-admin).

**Solution:** Use OBC credentials (WRITE credentials) for all access.

### Why can't I create a truly read-only user?

OBC buckets are owned by OBC-managed users. The readonly-user created via `radosgw-admin` exists in a different authentication system. Ceph RGW does not provide a way to grant cross-realm access via policies or ACLs.

**Alternatives:**
1. Use WRITE credentials for read operations (current workaround)
2. Create a second OBC with limited permissions (if Rook supports read-only OBCs)
3. Use application-level access control instead of S3-level

## Environment Variables

Scripts automatically load these from OpenShift:

- `S3_ENDPOINT_URL` - Ceph RGW endpoint URL
- `BUCKET_NAME` - OBC bucket name (format: `shared-data-<uuid>`)
- `READ_ACCESS_KEY` / `READ_SECRET_KEY` - readonly-user credentials (⚠️ won't work)
- `WRITE_ACCESS_KEY` / `WRITE_SECRET_KEY` - OBC user credentials (✅ use these)

## Requirements

- OpenShift CLI (`oc`) configured and logged in
- Podman
- `jq` for JSON parsing
- Access to `openshift-storage` namespace (for readonly-user operations)
- Access to `shared-data` namespace (for OBC credentials)
- Rook-Ceph OBC provisioned

## References

- [Ceph Bucket Policies Documentation](https://docs.ceph.com/en/latest/radosgw/bucketpolicy/)
- [Rook OBC Documentation](https://rook.io/docs/rook/latest/Storage-Configuration/Object-Storage-RGW/object-bucket-claim/)
