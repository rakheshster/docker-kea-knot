#!/bin/bash
# Usage ./buildxandpush.sh

# This variant makes use of the buildx plugin and can do multi-arch builds. It also pushes the DockerHub.
# Not all platforms have all archs if I am building locally. For example M1 Macs don't do linux/386 anymore. 
# ARCH="linux/amd64,linux/arm64,linux/386,linux/arm/v7,linux/arm/v6"
ARCH="linux/amd64,linux/arm64,linux/arm/v7,linux/arm/v6"

BUILDINFO="$(pwd)/buildinfo.json"
if ! [[ -r "$BUILDINFO" ]]; then echo "Cannot find $BUILDINFO file. Exiting ..."; exit 1; fi

if ! command -v jq &> /dev/null; then echo "Cannot find jq. Exiting ..."; exit 1; fi

VERSION=$(jq -r '.version' $BUILDINFO)
IMAGENAME=$(jq -r '.imagename' $BUILDINFO)

docker buildx build --platform $ARCH -t ${IMAGENAME}:${VERSION} -t ${IMAGENAME}:latest --progress=plain --push $(pwd)