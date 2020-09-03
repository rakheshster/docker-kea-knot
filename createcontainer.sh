#!/bin/bash
# Usage ./createcontainer.sh <image name> <container name> [ip address] [network name]

# If the first or second arguments are missing give a usage message and exit
if [[ -z "$1" || -z "$2" ]]; then
    echo "Usage ./createcontainer.sh <image name> <container name> [ip address] [network name]"
    exit 1
else
    if [[ -z $(docker image ls -q $1) ]]; then
        # can't find the image, so exit
        echo "Image $1 does not exist"
        exit 1
    else
        IMAGE=$1
    fi

    NAME=$2
fi

# Create Docker volumes for storing data. This is automatically named after the container plus a suffix. 
# Knot needs (1) Config dir /etc/knot (2) a place to store zones (these could get dynamically updated based on DNSSEC or DDNS)
KNOT_CONFIG=${NAME}_knotconfig && docker volume create $KNOT_CONFIG
KNOT_ZONES=${NAME}_knotzones && docker volume create $KNOT_ZONES

# Kea needs (3) Config dir /etc/kea  and (4) a place to save the leases 
KEA_CONFIG=${NAME}_keaconfig && docker volume create $KEA_CONFIG
KEA_LEASES=${NAME}_kealeases && docker volume create $KEA_LEASES

# Networking stuff
if [[ -z "$4" ]]; then 
    # network name not specified, default to bridge
    NETWORK="bridge" 
elif [[ -z $(docker network ls -f name=$4 -q) ]]; then
    # network name specified, but we can't find it, so exit
    echo "Network $4 does not exist"
    exit 1
else
    # passed all validation checks, good to go ahead ...
    NETWORK=$4
fi

IP=$3
if [[ -z "$3" ]]; then
    docker create --name "$NAME" \
        -P --network="$NETWORK" \
        --restart=unless-stopped \
        --cap-add=NET_ADMIN \
        -e TZ="Europe/London" \
        --mount type=volume,source=$KNOT_CONFIG,target=/etc/knot \
        --mount type=volume,source=$KNOT_ZONES,target=/var/lib/knot/zones \
        --mount type=volume,source=$KEA_CONFIG,target=/etc/kea \
        --mount type=volume,source=$KEA_LEASES,target=/var/lib/kea \
        "$IMAGE"
else
    docker create --name "$NAME" \
        -P --network="$NETWORK" --ip=$IP \
        --restart=unless-stopped \
        --cap-add=NET_ADMIN \
        -e TZ="Europe/London" \
        --mount type=volume,source=$KNOT_CONFIG,target=/etc/knot \
        --mount type=volume,source=$KNOT_ZONES,target=/var/lib/knot/zones \
        --mount type=volume,source=$KEA_CONFIG,target=/etc/kea \
        --mount type=volume,source=$KEA_LEASES,target=/var/lib/kea \
        "$IMAGE"
fi
# Note that the container already has /etc/knot et al. folders which contains files copied in during the image build.
# When I create the docker volume above and map it to the container, if this volume is empty the files from within the container are copied over to it.
# Subsequently the files from the volume are used in preference to the files in the image. 

# quit if the above step gave any error
[[ $? -ne 0 ]] && exit 1

printf "\nTo start the container do: \n\tdocker start $NAME"

printf "\n\nCreating ./${NAME}.service for systemd"
cat <<EOF > $NAME.service
    [Unit]
    Description=Kea Knot Container
    Requires=docker.service
    After=docker.service

    [Service]
    Restart=on-abort
    ExecStart=/usr/bin/docker start -a $NAME
    ExecStop=/usr/bin/docker stop -t 2 $NAME

    [Install]
    WantedBy=local.target
EOF

printf "\n\nDo the following to install this in systemd & enable:"
printf "\n\tsudo cp ${NAME}.service /etc/systemd/system/"
printf "\n\tsudo systemctl enable ${NAME}.service"
printf "\n\nAnd if you want to start the service do: \n\tsudo systemctl start ${NAME}.service \n"
