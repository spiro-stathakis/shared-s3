#! /usr/bin/env bash 

export NAMESPACE=shared-data
export BUCKET=$(oc get cm shared-data-bucket -n ${NAMESPACE} -o jsonpath='{.data.BUCKET_NAME}')
export AWS_ACCESS_KEY_ID=$(oc get secret shared-data-bucket     -n ${NAMESPACE} -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
export AWS_SECRET_ACCESS_KEY=$(oc get secret shared-data-bucket -n ${NAMESPACE} -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
export ENDPOINT=$(oc get route -n openshift-storage | grep rgw | awk '{print $2}')
export DEFAULT_REGION="" 
export IMAGE="quay.io/spidee/aws-cli:latest-amd64"

podman run --rm \
	-v "$(pwd):/aws:Z" \
	-w /aws \
	-e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
	-e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
	-e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} \
	${IMAGE} \
	s3api put-bucket-policy \
	--bucket ${BUCKET} \
	--policy file://policy.json \
	--endpoint-url https://${ENDPOINT} \
	--no-verify-ssl
