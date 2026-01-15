#!/usr/bin/env 

export OPERATOR_POD=$(oc get pod -n openshift-storage -l app=rook-ceph-operator -o jsonpath='{.items[0].metadata.name}')
oc exec -n openshift-storage $OPERATOR_POD -- \
  radosgw-admin user create \
  --uid="readonly-user" \
  --display-name="Read Only User" \
  --conf=/var/lib/rook/openshift-storage/openshift-storage.config \
  --keyring=/var/lib/rook/openshift-storage/client.admin.keyring
