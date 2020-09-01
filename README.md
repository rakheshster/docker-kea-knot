# Kea + Knot + Docker
![Buildx & Push [Debian]](https://github.com/rakheshster/docker-kea-knot/workflows/Buildx%20&%20Push%20%5BDebian%5D/badge.svg)
![Buildx & Push [Alpine]](https://github.com/rakheshster/docker-kea-knot/workflows/Buildx%20&%20Push%20%5BAlpine%5D/badge.svg)

## What is this?
This is a Docker image containing [Kea (for DHCP)](https://www.isc.org/kea/) and [Knot DNS](https://www.knot-dns.cz/) (for authoritative DNS; *not* a resolver). 

Kea can provide load balanced DHCP while Knot supports dynamic updates from Kea DHCP. 

## Why this?
I built this because I wanted a DHCP server for home use that could be load balanced (I run them on a couple of Raspberry Pi devices and they could fail any time) and also be able to provide name resolution for the DHCP and static clients in my network. The excellent Dnsmasq does most of this except the load balanced bit, so it was down to either Kea or DHCP server (both created by ISC) for load balanced DHCP. I decided to go with Kea as it is meant to be the [replacement for ISC DHCP](https://www.isc.org/kea/). 

Neither Kea nor DHCP server provide DNS resolution for its clients, so I needed an authoritative DNS server that supports Dynamic DNS updates so it could get DHCP assignments from Kea. The only authoritative DNS servers I could find that does this were Knot or Bind9. I decided to go with Knot as it's newer and more secure. This Docker image thus contains Kea and Knot packaged together with some config files thrown in to show how things could be setup. 

At home I have this container running side by side to my [Stubby-Unbound](https://github.com/rakheshster/docker-stubby-unbound) container. The former provides DHCP and local authoritative DNS, the latter is for upstream DNS-over-TLS resolution. Yes, I feel very fancy about my setup. 😉

## Debian and Alpine?
Initially I based this image on Alpine but I quickly realised that Kea takes ages to compile on it. If I do a `docker builds build` multi arch build for instance, it takes a whooping 17 hours! The same on a Debian based image is only 8 hours. Nearly half. (*Update*: Surprisingly, once I switched from Kea 1.7 to 1.8 the Alpine version too buids as fast as the Debian version. Not sure if it's a one time thing ... ymmv).

I have no idea why this is the case. Maybe it's because Alpine uses `musl` while Debian uses `glibc` for the C libraries? Since I had put in the effort for Alpine initially I decided to keep it around as the default but also add the Debian one as an alternative. Hence the additional `Dockerfile.debian` and two set of Docker images. I figure for the end user the compile times don't matter as it's just a simple download after all (both images are less than 300 MB in compressed size). 

## Getting this
It is best to target a specific release when pulling this repo. Either switch to the correct tag after downloading, or download a zip of the latest release from the [Releases](https://github.com/rakheshster/docker-kea-knot/releases) page. In the interest of speed however, as mentioned above I'd suggest downloading the built image from Docker Hub at [rakheshster/kea-knot](https://hub.docker.com/repository/docker/rakheshster/kea-knot).

The version numbers are of the format `<kea version>-<knot version>-<patch>` and optionally have a `-debian` suffix for the Debian variant. 

The current version is "1.8.0-2.9.5-2" and contains the following:
  * Alpine 3.12 or Debian Buster & s6-overlay 2.0.0.1 (via my [alpine-s6](https://hub.docker.com/repository/docker/rakheshster/alpine-s6) or [debiane-s6](https://hub.docker.com/repository/docker/rakheshster/debian-s6) images).
  * Kea DHCP 1.8.0
  * Knot DNS 2.9.5

I will update the `<patch>` number when there's any change introduced by me (e.g. a change to the Dockerfile or the base image).

## s6-overlay
This image contains [s6-overlay](https://github.com/just-containers/s6-overlay). I like their philosophy of a Docker container being “one thing” rather than “one process per container”. This image has services for Knot DNS, Kea DHCPv4, Kea DHCPv6 (currently disabled), Kea Control Agent, and Kea Dynamic DNS. 

# Running this
## Data
Knot has 1) its config file at `/etc/knot` and 2) stores its zones database at `/var/lib/knot/zones`. The latter is where we store our zones but these can be dynamically updated by Knot due to Dynamic DNS or DNSSEC, hence the location of `/var/lib` to store them. 

Kea has 1) its config file at `/etc/kea` and 2) store its leases at `/var/lib/kea`. There are multiple config files for each Kea service. 

I would recommend making Docker volumes for each of these locations and mapping them to the container. You don't need to keep the leases or zone DBs out of the container, but I prefer it that way. The way I run it at home is thus:

```
# name of the container; also used as a prefix for the volumes
NAME="kea-knot"
NETWORK="my_docker_network"
IMAGE="rakheshster/kea-knot:1.8.0-2.9.5-1"

# create Docker volumes to store data
KNOT_CONFIG=${NAME}_knotconfig && docker volume create $KNOT_CONFIG
KNOT_ZONES=${NAME}_knotzones && docker volume create $KNOT_ZONES
KEA_CONFIG=${NAME}_keaconfig && docker volume create $KEA_CONFIG
KEA_LEASES=${NAME}_kealeases && docker volume create $KEA_LEASES

# run the container
docker create --name "$NAME" \
    -P --network="$NETWORK" \
    --dns 127.0.0.1 \
    --restart=unless-stopped \
    --cap-add=NET_ADMIN \
    -e TZ="Europe/London" \
    --mount type=volume,source=$KNOT_CONFIG,target=/etc/knot \
    --mount type=volume,source=$KNOT_ZONES,target=/var/lib/knot/zones \
    --mount type=volume,source=$KEA_CONFIG,target=/etc/kea \
    --mount type=volume,source=$KEA_LEASES,target=/var/lib/kea \
    $IMAGE
```

The `createcontainer.sh` script does exactly this. It creates the volumes and container as above and also outputs a systemd service unit file so the container is automatically launched by systemd as a service. The script does not start the container however, you can do that via `docker start <container name>`. 

The timezone variable in the `docker run` command is useful so Kea & Knot set timestamps correctly. Also, Kea needs the `NET_ADMIN` capability as it is a DHCP server and needs to listen to broadcasts. I like to have a macvlan network with a separate IP for this container, but that's just my preference. The `createcontainer.sh` lets you specify the IP address and network name and if none is specified it uses the "bridge" network. 

## Knot zone editing
The Knot documentation gives steps on how to edit the zone files safely. To make it easy I include a script called `vizone`. This is copied to the `/sbin` folder of the container. Simply do the following to edit a zone safely and have Knot reload. 

```
docker exec -it <container name> vizone <zone name>
```

This script is a wrapper around the four commands specified in [this section](https://www.knot-dns.cz/docs/2.8/html/operation.html#reading-and-editing-the-zone-file-safely) of the Knot documentation. You can also `docker exec -it <container name> knotc <options>` too. My script is entirely optional. 

## Knot zone behaviour
As said above the Knot zones are stored at `/var/lib/knot/zones` and by default Knot overwrites the zone files with changes. This behaviour is controller by the `zonefile-sync` configuration parameter (default value is `0` which tells Knot to [update the file as soon as possible](https://www.knot-dns.cz/docs/2.8/singlehtml/index.html#zonefile-sync); it is possible to disable this by setting the value to `-1` (in which case the `knotc zone-flush` command can be used to perform a manual sync or dump the changes to a separate file)). 

The [zone loading](https://www.knot-dns.cz/docs/2.8/singlehtml/index.html#zone-loading), [journal behaviour](https://www.knot-dns.cz/docs/2.8/singlehtml/index.html#journal-behaviour), and [examples](https://www.knot-dns.cz/docs/2.8/singlehtml/index.html#example-1) sections in the Knot documentation are worth a read. The journal is where Knot saves changes to the zone file and is typically used to answer IXFR queries (this too can be changed such that the journal has both the zone and changes in it). By default the journal is [stored in a folder](https://www.knot-dns.cz/docs/2.7/html/reference.html#journal-db) called `journal` under `/var/lib/knot/zones`. 

The default settings for these values are as follows (this is not explicitly stated in the example `knot.conf` file):
```
zonefile-sync: 0
zonefile-load: whole
journal-content: changes
```

If you want to disable the zone file from being overwritten and would prefer all changes be stored in the journal change these to:
```
zonefile-sync: -1
zonefile-load: difference-no-serial
journal-content: changes
```

Do refer to the Knot documentation for more info though. I am no Knot expert and the above is just what I use at home. 

# Reloading
If you want to reload Knot or Kea I provide some useful wrapper scripts. These simply use `s6` to reload the appropriate service. To reload Knot for instance, do:

```
docker exec -it <container name> knot-reload
```

Or for Kea DHCP4:

```
docker exec -it <container name> kea-dhcp4-reload
```

# Systemd
Example unit file:

```
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
```

Copy this file to `/etc/systemd/system/`. 

Enable it in systemd via: `sudo systemctl enable <service file name>`.

# Thanks!
Creating this image was a terrific learning experience for me. 

I reworked my [stubby-unbound](https://github.com/rakheshster/docker-stubby-unbound) and [stubby-dnsmasq](https://github.com/rakheshster/docker-stubby-dnsmasq) images based on the learnings from this one. With each image I have delved more and more into Docker. I got into Docker with the stubby-unbound image, but with the stubby-dnsmasq image I picked up multi-stage builds while with the kea-knot container I picked up multi-arch builds, got more into the mindset of Docker of having multiple layers and leveraging these (e.g creating a common [alpine-s6](https://github.com/rakheshster/docker-alpine-s6) & [debian-s6](https://github.com/rakheshster/docker-debian-s6) image to use across my containers), started publishing to Docker Hub, and spent a lot of time with GitHub actions and Azure DevOps pipelines to build this container (it took ages on my home machine for a single architecture so it was time leverage the cloud and some automation). This was thus a fun exercise in that I had an itch to stratch and I went crazy with it and learnt a lot of new things. Funnily enough as of this writing I haven't yet gone "live" with this container at home because I got side-tracked in all these other areas! (Of course I tested it in a bunch of VMs so it all works, don't worry).

If you have read till here, thanks! I hope this image is of use to you. :)