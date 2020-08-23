#!/bin/bash
# Usage ./buildlocal.sh [image name]

# if no image name, default to something
if [[ -z $1 ]]; then 
    IMAGE="rakheshster/kea-knot"
fi

# delete an existing image of the same name if it exists
# thanks to https://stackoverflow.com/questions/30543409/how-to-check-if-a-docker-image-with-a-specific-tag-exist-locally
if [[ $(docker image inspect ${IMAGE} 2>/dev/null) == "" ]]; then 
    docker rmi -f ${IMAGE}
fi

docker build . -t ${IMAGE}

# prune the intermediate images
# skip this for now as I want to keep them around to improve build times ...
# docker image prune --filter label=stage=alpinestubby -f
# docker image prune --filter label=stage=alpineunbound -f
