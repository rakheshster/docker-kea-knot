################################### COMMON BUILDIMAGE ####################################
# This image is to be a base where all the build dependencies are installed. 
# I can use this in the subsequent stages to build stuff
FROM alpine:3.12 AS alpinebuild

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
FROM alpine:latest AS alpineruntime

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

################################### S6 & FINALIZE ####################################
# This pulls in the previous stage, adds S6. This is my final stage. 
FROM alpineruntime

# I take the arch (for s6) as an argument. Options are amd64, x86, armhf (for Pi), arm, aarch64. See https://github.com/just-containers/s6-overlay#releases
ARG ARCH=armhf 
LABEL maintainer="Rakhesh Sasidharan"
ENV S6_VERSION 2.0.0.1

# Download s6, but it is arch specific. 
# Option 1: Pass the arch it via --build-arg ARCH=xxx (options are amd64, x86, armhf (for Pi), arm, aarch64. See https://github.com/just-containers/s6-overlay#releases)
# Option 2: If I am doing a mutli-arch build, the TARGETPLATFORM variable contains the architecture. This is normalized as per https://github.com/containerd/containerd/blob/master/platforms/platforms.go#L80
# though, and that doesn't match what s6 expects so I map that to the ARCH variable. If doing a multi-arch build there's no need to specify the ARCH argument.
RUN case ${TARGETPLATFORM} in \
    arm64) \
        ARCH="amd64" \
        ;; \
    arm | arm/v7) \
        ARCH="armhf" \
        ;; \
    arm/v6) \
        ARCH="arm" \
        ;; \
    arm64 | arm/v8) \
        ARCH="aarch64" \
        ;; \
    386) \
        ARCH="x86" \
        ;; \
    amd64) \
        ARCH="amd64" \
        ;; \
    *) \
        if ! [[ ${ARCH} = "amd64" || ${ARCH} = "x86" || ${ARCH} = "armhf" || ${ARCH} = "arm" || ${ARCH} = "aarch64" ]]; then \
            echo "Incorrect architecture specified! Must be one of amd64, x86, armhf (for Pi), arm, aarch64"; exit 1; \
        fi \
        ;; \
    esac ; \
    # The default instructions give the impression one must do a 2-stage extract. That's only to target this issue - https://github.com/just-containers/s6-overlay#known-issues-and-workarounds
    wget https://github.com/just-containers/s6-overlay/releases/download/v${S6_VERSION}/s6-overlay-${ARCH}.tar.gz -P /tmp/ && \
    tar xzf /tmp/s6-overlay-${ARCH}.tar.gz -C / && \
    rm  -f /tmp/s6-overlay-${ARCH}.tar.gz

# Copy the config files & s6 service files to the correct location
COPY root/ /

# NOTE: s6 overlay doesn't support running as a different user.

EXPOSE 53/udp 53/tcp 8080/tcp
# Knot DNS runs on 53. 
# Kea requires 8080 for HA

# HEALTHCHECK --interval=5s --timeout=3s --start-period=5s \
#     CMD drill @127.0.0.1 -p 53 google.com || exit 1

ENTRYPOINT ["/init"]
