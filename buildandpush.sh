#!/bin/bash
# Usage ./buildandpush.sh [image name]

# if no image name, default to something
if [[ -z $1 ]]; then
    IMAGE="rakheshster/kea-knot"
fi

BASE_VERSION=3.12-2.0.0.1

docker buildx build --platform linux/amd64,linux/arm64,linux/386,linux/arm/v7,linux/arm/v6 . --push -t ${IMAGE}:${BASE_VERSION}
