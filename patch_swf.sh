#!/usr/bin/env bash

set -e

OLD_DRIVER_IMAGE="registry.redhat.io/rhoai/odh-ml-pipelines-driver-rhel8@sha256:78d5f5a81a3f0ee0b918dc2dab7ffab5b43fec94bd553ab4362f2216eef39688"
NEW_DRIVER_IMAGE="registry.redhat.io/rhoai/odh-ml-pipelines-driver-rhel8@sha256:4fce7736a6058110e56aacec3a0d5286a10b2644ced002662718280c69f7d9f3"

OLD_LAUNCHER_IMAGE="registry.redhat.io/rhoai/odh-ml-pipelines-launcher-rhel8@sha256:3a3ba3c4952dc9020a8a960bdd3c0b2f16ca89ac15fd17128a00c382f39cba81"
NEW_LAUNCHER_IMAGE="registry.redhat.io/rhoai/odh-ml-pipelines-launcher-rhel8@sha256:df79da94e81dad3ee6ede25cd98067649ce5736c2fb9bdbf4dec72ac24209003"

NAMESPACE=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --namespace) NAMESPACE="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "${NAMESPACE}" ]; then
    echo "Error: --namespace parameter is required."
    echo "Usage: $0 --namespace <namespace>"
    exit 1
fi

patch_image() {
    local workflow_spec=$1
    local old_image=$2
    local new_image=$3
    local patched_workflow_spec

    patched_workflow_spec=$(jq --arg OLD_IMAGE "${old_image}" --arg NEW_IMAGE "${new_image}" '
      (.. | objects | select(.image == $OLD_IMAGE) | .image) |= $NEW_IMAGE
    ' <<< "$workflow_spec")

    echo "${patched_workflow_spec}"
}

patch_swf() {
    local swf_name=$1

    local workflow_spec

    workflow_spec=$(oc get -oyaml swf "${swf_name}" -n "${NAMESPACE}" | yq .spec.workflow.spec)
    workflow_spec=$(patch_image "${workflow_spec}" "${OLD_DRIVER_IMAGE}" "${NEW_DRIVER_IMAGE}")
    workflow_spec=$(patch_image "${workflow_spec}" "${OLD_LAUNCHER_IMAGE}" "${NEW_LAUNCHER_IMAGE}")

    workflow_spec=$(echo -n "${workflow_spec}" | jq -c | jq -Rsa)

    oc patch swf "${swf_name}" --type=merge -p "{\"spec\":{\"workflow\":{\"spec\": $workflow_spec}}}" -n "${NAMESPACE}"
}

main() {
    local swf_names
    local workflow_spec

    swf_names=$(oc get swf --no-headers -o custom-columns=":metadata.name" -n "${NAMESPACE}")

    for swf_name in $swf_names; do
        echo "Processing Scheduled Workflow: $swf_name"

        workflow_spec=$(patch_swf "${swf_name}")

        echo "Scheduled Workflow successfully patched: $swf_name"
    done
}

main
