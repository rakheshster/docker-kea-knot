# Kea + Knot + Docker
![Buildx & Push [Debian]](https://github.com/rakheshster/docker-kea-knot/workflows/Buildx%20&%20Push%20%5BDebian%5D/badge.svg)
![Buildx & Push [Alpine]](https://github.com/rakheshster/docker-kea-knot/workflows/Buildx%20&%20Push%20%5BAlpine%5D/badge.svg)

Please note this is still WIP. 

## What is this?
This is a Docker image containing Kea (for DHCP) and Knot DNS (for authoritative DNS; *not* a resolver). 

Kea can provide load balanced DHCP while Knot supports dynamic updates from Kea DHCP.
