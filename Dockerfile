# I am pulling in my alpine-s6 image as the base here so I can reuse it for the common buildimage and later in the runtime. 
# Initially I used to pull this separately at each stage but that gave errors with docker buildx for the BASE_VERSION argument.
ARG BASE_VERSION=3.12-2.0.0.1
FROM rakheshster/alpine-s6:${BASE_VERSION} AS mybase

################################### COMMON BUILDIMAGE ####################################
# This image is to be a base where all the build dependencies are installed. 
# I can use this in the subsequent stages to build stuff
FROM mybase AS alpinebuild

# I realized that the build process doesn't remove this intermediate image automatically so best to LABEL it here and then prune later
# Thanks to https://stackoverflow.com/a/55082473
LABEL stage="alpinebuild"
LABEL maintainer="Rakhesh Sasidharan"

# Get the build-dependencies for everything I plan on building later
# common stuff: git build-base libtool xz cmake
# kea: (https://kea.readthedocs.io/en/kea-1.6.2/arm/install.html#build-requirements) build-base libtool openssl-dev boost-dev log4cplus-dev automake
# knot dns: pkgconf gnutls-dev userspace-rcu-dev libedit-dev libidn2-dev fstrm-dev protobuf-c-dev
RUN apk add --update --no-cache \
    git build-base libtool xz cmake \
    openssl-dev boost-dev log4cplus-dev automake \
    pkgconf gnutls-dev userspace-rcu-dev libedit-dev libidn2-dev fstrm-dev protobuf-c-dev
RUN rm -rf /var/cache/apk/*

################################## KEA DHCP ####################################
# This image is to only build Kea Dhcp
FROM alpinebuild AS alpinekea

ENV KEA_VERSION 1.7.10

LABEL stage="alpinekea"
LABEL maintainer="Rakhesh Sasidharan"

# Download the source & build it
ADD https://downloads.isc.org/isc/kea/${KEA_VERSION}/kea-${KEA_VERSION}.tar.gz /tmp/
WORKDIR /src
RUN tar xzf /tmp/kea-${KEA_VERSION}.tar.gz -C ./
WORKDIR /src/kea-${KEA_VERSION}
# Configure kea to expect everything in / (--prefix=/) but when installing put everything into /usr/local (via DESTDIR=) (I copy the contents of this to / in the final image)
RUN ./configure --prefix=/ --with-openssl
RUN make && DESTDIR=/usr/local make install

# Disable keactrl as its broken under alpine (ps -p does not work) and also it conflicts with s6 if I try to stop etc. 
# The only thing I need keactrl for is to reload the config, for that use the included kea-dhcpx-reload script which I provide.
RUN chmod -x /usr/local/sbin/keactrl

################################## BUILD KNOT DNS ####################################
# This image is to only build Knot DNS
FROM alpinebuild AS alpineknot

ENV KNOTDNS_VERSION 2.9.5

LABEL stage="alpineknot"
LABEL maintainer="Rakhesh Sasidharan"

# Download the source & build it
ADD https://secure.nic.cz/files/knot-dns/knot-${KNOTDNS_VERSION}.tar.xz /tmp/
WORKDIR /src
RUN tar xf /tmp/knot-${KNOTDNS_VERSION}.tar.xz -C ./
WORKDIR /src/knot-${KNOTDNS_VERSION}
# Configure knot to expect everything in / (--prefix=/) but when installing put everything into /usr/local (via DESTDIR=) (I copy the contents of this to / in the final image)
RUN ./configure --prefix=/ --enable-dnstap --disable-systemd
RUN make && DESTDIR=/usr/local make install


################################### RUNTIME ENVIRONMENT FOR KEA & KNOT ####################################
# This image has all the runtime dependencies, the built files from the previous stage, and I also create the groups and assign folder permissions etc. 
# I got to create the folder after copying the stuff from previous stage so the permissions don't get overwritten
FROM mybase AS alpineruntime

# Get the runtimes deps for all
# Kea: (https://kea.readthedocs.io/en/kea-1.6.2/arm/intro.html#required-software)
# Knot: (https://knot-resolver.readthedocs.io/en/latest/build.html) libuv luajit lmdb gnutls userspace-rcu libedit libidn2
RUN apk add --update --no-cache ca-certificates \
    drill \
    openssl log4cplus boost \
    libuv luajit lmdb gnutls userspace-rcu libedit libidn2 fstrm protobuf-c \
    nano
RUN rm -rf /var/cache/apk/*

# /usr/local/bin -> /bin etc.
COPY --from=alpineknot /usr/local/ /
COPY --from=alpinekea /usr/local/ /

RUN addgroup -S knot && adduser -D -S knot -G knot
RUN mkdir -p /var/lib/knot && chown knot:knot /var/lib/knot
RUN mkdir -p /var/run/knot && chown knot:knot /var/run/knot

RUN addgroup -S knot-res && adduser -D -S knot-res -G knot-res
RUN mkdir -p /var/lib/knot-resolver && chown knot-res:knot-res /var/lib/knot-resolver
RUN mkdir -p /var/cache/knot-resolver && chown knot-res:knot-res /var/cache/knot-resolver

################################### FINALIZE ####################################
# This pulls in the previous stage, adds S6. This is my final stage. 
FROM alpineruntime

LABEL maintainer="Rakhesh Sasidharan"

# Copy the config files & s6 service files to the correct location
COPY root/ /

# NOTE: s6 overlay doesn't support running as a different user. However, Knot is configured to run as a non-root user in its config. Kea needs to run as root. 

EXPOSE 53/udp 53/tcp 8080/tcp
# Knot DNS runs on 53. 
# Kea requires 8080 for HA

# HEALTHCHECK --interval=5s --timeout=3s --start-period=5s \
#     CMD drill @127.0.0.1 -p 53 google.com || exit 1

ENTRYPOINT ["/init"]
