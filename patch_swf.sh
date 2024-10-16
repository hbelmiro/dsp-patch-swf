#!/usr/bin/env bash

set -e

OLD_DRIVER_IMAGE="registry.redhat.io/rhoai/odh-ml-pipelines-driver-rhel8@sha256:16a711ba5c770c3b93e9a5736735f972df9451a9a1903192fcb486aa929a44b7"

# Replace with the above image that's from 2.13
#OLD_DRIVER_IMAGE="quay.io/opendatahub/ds-pipelines-driver@sha256:ea1ceae99e7a4768da104076915b5271e88fd541e4f804aafee8798798db991d"

NEW_DRIVER_IMAGE="registry.redhat.io/rhoai/odh-ml-pipelines-driver-rhel8@sha256:78d5f5a81a3f0ee0b918dc2dab7ffab5b43fec94bd553ab4362f2216eef39688"

OLD_LAUNCHER_IMAGE="registry.redhat.io/rhoai/odh-ml-pipelines-launcher-rhel8@sha256:e8aa5ae0a36dc50bdc740d6d9753b05f2174e68a7edbd6c5b0ce3afd194c7a6e"

# Replace with the above image that's from 2.13
#OLD_LAUNCHER_IMAGE="quay.io/opendatahub/ds-pipelines-launcher@sha256:1a6b6328d30036ffd399960b84db4a306522f92f6ef8e8d2a0f88f112d401a7d"

NEW_LAUNCHER_IMAGE="registry.redhat.io/rhoai/odh-ml-pipelines-launcher-rhel8@sha256:3a3ba3c4952dc9020a8a960bdd3c0b2f16ca89ac15fd17128a00c382f39cba81"

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

add_arguments() {
    local workflow_spec=$1
    local driver_image=$2
    local dspa=$3
    local namespace=$4
    
    local new_args
    local server_address
    local port

    port=$(oc get service ds-pipeline-metadata-grpc-"${dspa}" -o jsonpath='{.spec.ports[*].port}')

    server_address="ds-pipeline-metadata-grpc-${dspa}.${namespace}.svc.cluster.local"

    new_args="[
        \"--mlmd_server_address\", \"${server_address}\",
        \"--mlmd_server_port\", \"${port}\",
        \"--metadataTLSEnabled\", \"true\"
    ]"

    updated_json=$(jq --arg image "${driver_image}" --argjson new_args "$new_args" '
      .spec.templates[].container |= if .image == $image then
          if (.args | index("--mlPipelineServiceTLSEnabled") as $i | if $i then .[$i + 1] == "true" else true end) then
              .args += $new_args
          else
              .
          end
        else
          .
        end
    ' <<< "${workflow_spec}")

    echo "$updated_json"
}

patch_swf() {
    local swf_name=$1

    local workflow_spec

    workflow_spec=$(oc get -oyaml swf "${swf_name}" | yq .spec.workflow.spec)
    workflow_spec=$(patch_image "${workflow_spec}" "${OLD_DRIVER_IMAGE}" "${NEW_DRIVER_IMAGE}")
    workflow_spec=$(patch_image "${workflow_spec}" "${OLD_LAUNCHER_IMAGE}" "${NEW_LAUNCHER_IMAGE}")

    dspa=$(oc get swf "${swf_name}" -o yaml | yq '.metadata.ownerReferences[] | select(.kind == "DataSciencePipelinesApplication") | .name')
    namespace=$(oc get swf "${swf_name}" -o yaml | yq .metadata.namespace)

    workflow_spec=$(add_arguments "${workflow_spec}" "${NEW_DRIVER_IMAGE}" "${dspa}" "${namespace}")

    workflow_spec=$(echo -n "${workflow_spec}" | jq -c | jq -Rsa)

    oc patch swf "${swf_name}" --type=merge -p "{\"spec\":{\"workflow\":{\"spec\": $workflow_spec}}}"
}

main() {
    local swf_names
    local workflow_spec

    swf_names=$(oc get swf --no-headers -o custom-columns=":metadata.name")

    for swf_name in $swf_names; do
        echo "Processing Scheduled Workflow: $swf_name"

        workflow_spec=$(patch_swf "${swf_name}")

        echo "Scheduled Workflow successfully patched: $swf_name"
    done
}

main
