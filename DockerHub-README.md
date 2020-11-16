# What is this?
This is a Docker image containing [Kea (for DHCP)](https://www.isc.org/kea/) and [Knot DNS](https://www.knot-dns.cz/) (for authoritative DNS; *not* a resolver). 

Kea can provide load balanced DHCP while Knot supports dynamic updates from Kea DHCP. 

# Why this?
I built this because I wanted a DHCP server for home use that could be load balanced (I run them on a couple of Raspberry Pi devices and they could fail any time) and also be able to provide name resolution for the DHCP and static clients in my network. The excellent Dnsmasq does most of this except the load balanced bit, so it was down to either Kea or DHCP server (both created by ISC) for load balanced DHCP. I decided to go with Kea as it is meant to be the [replacement for ISC DHCP](https://www.isc.org/kea/). 

Neither Kea nor DHCP server provide DNS resolution for its clients, so I needed an authoritative DNS server that supports Dynamic DNS updates so it could get DHCP assignments from Kea. The only authoritative DNS servers I could find that does this were Knot or Bind9. I decided to go with Knot as it's newer and more secure. This Docker image thus contains Kea and Knot packaged together with some config files thrown in to show how things could be setup. 

At home I have this container running side by side to my [Stubby-Unbound](https://hub.docker.com/repository/docker/rakheshster/stubby-dnsmasq) container. The former provides DHCP and local authoritative DNS, the latter is for upstream DNS-over-TLS resolution. Yes, I feel very fancy about my setup. 😉

# Debian and Alpine?
Initially I based this image on Alpine but I quickly realised that Kea takes ages to compile on it. If I do a `docker builds build` multi arch build for instance, it takes a whooping 17 hours! The same on a Debian based image is only 8 hours. Nearly half. 

I have no idea why this is the case. Maybe it's because Alpine uses `musl` while Debian uses `glibc` for the C libraries? Since I had put in the effort for Alpine initially I decided to keep it around as the default but also add the Debian one as an alternative. Hence the additional `Dockerfile.debian` and two set of Docker images. I figure for the end user the compile times don't matter as it's just a simple download after all (both images are less than 300 MB in compressed size). 

# Versions
Version numbers are of the format `<kea version>-<knot version>-<patch>` and optionally have a `-debian` suffix for the Debian variant. 

# Source
The `Dockerfile` can be found in the [GitHub repository](https://github.com/rakheshster/docker-kea-knot). 

# Running this
## Data
Knot has: 
  1. its config file at `/etc/knot`, and 
  2. stores its zones database at `/var/lib/knot/zones` (this is where we store our zones but these can be dynamically updated by Knot due to Dynamic DNS or DNSSEC, hence the location of `/var/lib`). 

Kea has:
  1. its config file at `/etc/kea`, and 
  2. stores its leases at `/var/lib/kea`. There are multiple config files for each Kea service. 

I would recommend making Docker volumes for each of these locations and mapping them to the container. You don't need to keep the leases or zone DBs out of the container, but I prefer it that way. The way I run it at home is thus:

```
# name of the container; also used as a prefix for the volumes
NAME="kea-knot"
NETWORK="my_docker_network"
IMAGE="rakheshster/kea-knot:1.8.0-2.9.5-3"

# create Docker volumes to store data
KNOT_CONFIG=${NAME}_knotconfig && docker volume create $KNOT_CONFIG
KNOT_ZONES=${NAME}_knotzones && docker volume create $KNOT_ZONES
KEA_CONFIG=${NAME}_keaconfig && docker volume create $KEA_CONFIG
KEA_LEASES=${NAME}_kealeases && docker volume create $KEA_LEASES

# run the container
docker create --name "$NAME" \
    -P --network="$NETWORK" \
    --restart=unless-stopped \
    --cap-add=NET_ADMIN \
    -e TZ="Europe/London" \
    --mount type=volume,source=$KNOT_CONFIG,target=/etc/knot \
    --mount type=volume,source=$KNOT_ZONES,target=/var/lib/knot/zones \
    --mount type=volume,source=$KEA_CONFIG,target=/etc/kea \
    --mount type=volume,source=$KEA_LEASES,target=/var/lib/kea \
    $IMAGE
```

On my [GitHub repository](https://github.com/rakheshster/docker-kea-knot) there's a [script](https://raw.githubusercontent.com/rakheshster/docker-kea-knot/master/createcontainer.sh) which does this and also outputs a systemd service unit file so the container is automatically launched by systemd as a service. 

Here's an example of what you could do (this uses a macvlan network I created prior called `my_macvlan_network` and assigns the container an IP address of 192.168.0.1):

```shell
# get the script, make it executable, and run it. this saves the script to the $(pwd) so use a different path if needed
curl -O -s -L https://raw.githubusercontent.com/rakheshster/docker-kea-knot/master/createcontainer.sh
chmod +x ./createcontainer.sh

./createcontainer.sh rakheshster/kea-knot:1.8.0-2.9.5-3 kea-knot 192.168.0.1 my_macvlan_network
```

The timezone variable in the `docker run` command is useful so Kea & Knot set timestamps correctly. Also, Kea needs the `NET_ADMIN` capability as it is a DHCP server and needs to listen to broadcasts. I like to have a macvlan network with a separate IP for this container, but that's just my preference. 

## Knot zone editing
The Knot documentation gives steps on how to edit the zone files safely. To make it easy I include a script called `vizone`. Simply do the following to edit a zone safely and have Knot reload. 

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

Do refer to the Knot documentation for more info though. I decided to go with the zone file being overwritten.  

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

# Updating
Here's what I do at home to update the container. This is just my way of doing things for my environment of course:

```shell
# get the latest version
docker pull rakheshster/kea-knot:1.8.0-2.9.5-3

# get my script as before
curl -O -s -L https://raw.githubusercontent.com/rakheshster/docker-kea-knot/master/createcontainer.sh
chmod +x ./createcontainer.sh

# remove the existing container, called kea-knot
docker rm -f kea-knot

# make a new container, called kea-knot, with an IP and network etc. 
./createcontainer.sh rakheshster/kea-knot:1.8.0-2.9.5-3 kea-knot 192.168.0.1 my_macvlan_network

# start it
docker start kea-knot
```

# Thanks!
If you have read till here, thanks! I hope this image is of use to you. :)
