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

The current version is "1.8.0-2.9.5-1" and contains the following:
  * Alpine 3.12 or Debian Buster & s6-overlay 2.0.0.1 (via my [alpine-s6](https://hub.docker.com/repository/docker/rakheshster/alpine-s6) or [debiane-s6](https://hub.docker.com/repository/docker/rakheshster/debian-s6) images).
  * Kea DHCP 1.8.0
  * Knot DNS 2.9.5

I will update the `<patch>` number when there's any change introduced by me (e.g. a change to the Dockerfile or the base image).

## s6-overlay
This image contains [s6-overlay](https://github.com/just-containers/s6-overlay). I like their philosophy of a Docker container being “one thing” rather than “one process per container”. This image has services for Knot DNS, Kea DHCPv4, Kea DHCPv6 (currently disabled), Kea Control Agent, and Kea Dynamic DNS. 