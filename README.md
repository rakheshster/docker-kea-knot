# Kea + Knot + Docker
![Buildx & Push [Debian]](https://github.com/rakheshster/docker-kea-knot/workflows/Buildx%20&%20Push%20%5BDebian%5D/badge.svg)
![Buildx & Push [Alpine]](https://github.com/rakheshster/docker-kea-knot/workflows/Buildx%20&%20Push%20%5BAlpine%5D/badge.svg)

**WIP** 

## What is this?
This is a Docker image containing Kea (for DHCP) and Knot DNS (for authoritative DNS; *not* a resolver). 

Kea can provide load balanced DHCP while Knot supports dynamic updates from Kea DHCP. 

## Why this?
I built this because I wanted a DHCP server for home use that could be load balanced (I run them on a couple of Raspberry Pi devices and they could fail any time) and also the ability to provide name resolution for the DHCP and static clients in my network. The excellent Dnsmasq does most of this except the load balanced bit, so it was down to either ISC's Kea or DHCP server for load balanced DHCP. I decided to go with Kea. The only authoritative DNS servers I could find that supports Dynamic DNS updates were Knot or Bind9. I decided to go with Knot. This Docker image thus has Kea and Knot packaged together with some config files thrown in to show how things could be setup. 

At home I have this container running side by side to my Stubby-Unbound container. The former provides DHCP and local authoritative DNS, the former is for upstream DNS-over-TLS resolution. Yes, I feel very fancy about my setup. 😉

## Debian and Alpine?
Initially I based this image on Alpine but I realised that Kea takes ages to compile on it. If I do a `docker builds build` multi arch build for instance, it takes a crazy 17 hours! The same on a Debian based image is only 8 hours. Nearly half. 

I have no idea why this is the case. Since I had put in the effort for Alpine initially I decided to keep it around as the default but also add the Debian one as an alternative. Hence the additional `Dockerfile.debian` and two set of Docker images. 