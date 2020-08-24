#!/bin/bash
# Usage ./buildandpush.sh [image name]

# if no image name, default to something
if [[ -z $1 ]]; then
    IMAGE="rakheshster/kea-knot"
fi

VERSION=v0.1.0

docker buildx build --platform linux/amd64,linux/386,linux/arm/v7,linux/arm/v6 . --push -t ${IMAGE}:${VERSION} --progress=plain

# NOTE: no linux/arm64. The build was breaking for that. 
