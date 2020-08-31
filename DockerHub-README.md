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