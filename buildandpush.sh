#!/bin/bash
# Usage ./buildandpush.sh [<flavour>]

BUILDINFO="$(pwd)/buildinfo.json"
if ! [[ -r "$BUILDINFO" ]]; then echo "Cannot find $BUILDINFO file. Exiting ..."; exit 1; fi

if ! command -v jq &> /dev/null; then echo "Cannot find jq. Exiting ..."; exit 1; fi

VERSION=$(jq -r '.version' $BUILDINFO)
IMAGENAME=$(jq -r '.imagename' $BUILDINFO)
[[ $1 == "debian" ]] && FLAVOUR="debian" || FLAVOUR="alpine"

echo "Building $IMAGENAME-$VERSION (flavour: $FLAVOUR)"

if [[ $FLAVOUR == "debian" ]]; then
	docker buildx build --platform linux/amd64,linux/arm64,linux/386,linux/arm/v7,linux/arm/v6 . --push -t ${IMAGENAME}:${VERSION}-${FLAVOUR} --progress=plain -f "$(pwd)/Dockerfile.debian"
else
	docker buildx build --platform linux/amd64,linux/arm64,linux/386,linux/arm/v7,linux/arm/v6 . --push -t ${IMAGENAME}:${VERSION} --progress=plain -f "$(pwd)/Dockerfile"
fi