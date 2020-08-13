#!/bin/bash
# Usage ./buildimage.sh <arch> [image name]
# Valid <arch> options are amd64, x86, armhf (for Raspberry Pi), arm, aarch64, all (to create them all)

# validate the arch argument
case $1 in
    amd64)
        # create an array with the arch name. this is useful later on for the "all" case.
        ARCH=("amd64")
        ;;
    x86)
        ARCH=("x86")
        ;;
    armhf)
        ARCH=("armhf")
        ;;
    arm)
        ARCH=("arm")
        ;;
    aarch64)
        ARCH=("aarch64")
        ;;
    all)
        ARCH=("amd64 x86 armhf arm aarch64")
	;;
    *)
        echo "Usage ./buildimage.sh <arch> [image name]"
        echo "Valid <arch> options are amd64, x86, armhf (for Raspberry Pi), arm, aarch64, all (to create them all)"
        exit 1
        ;;
esac

# if no image name, default to something
if [[ -z $2 ]]; then 
    IMAGE="rakheshster/kea-knot"
fi

# delete an existing image of the same name if it exists
# thanks to https://stackoverflow.com/questions/30543409/how-to-check-if-a-docker-image-with-a-specific-tag-exist-locally
if [[ $(docker image inspect ${IMAGE}:${ARCH} 2>/dev/null) == "" ]]; then 
    docker rmi -f ${IMAGE}:${ARCH}
fi

# loop through the array and create them all
for A in ${ARCH[@]}; do
    echo "Building ${IMAGE}:${A}"
    docker build --build-arg ARCH=$A . -t ${IMAGE}:${A}
done
