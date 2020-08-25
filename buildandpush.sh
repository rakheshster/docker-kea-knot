#!/bin/bash
# Usage ./buildandpush.sh

BUILDINFO="$(pwd)/buildinfo.json"
if ! [[ -r "$BUILDINFO" ]]; then echo "Cannot find $BUILDINFO file. Exiting ..."; exit 1; fi

if ! command -v jq &> /dev/null; then echo "Cannot find jq. Exiting ..."; exit 1; fi

VERSION=$(jq -r '.version' $BUILDINFO)
IMAGENAME=$(jq -r '.imagename' $BUILDINFO)

docker buildx build --platform linux/amd64,linux/arm64,linux/386,linux/arm/v7,linux/arm/v6 . --push -t ${IMAGENAME}:${VERSION} --progress=plain
