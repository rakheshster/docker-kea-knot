################################### COMMON BUILDIMAGE ####################################
# This image is to be a base where all the build dependencies are installed. 
# I can use this in the subsequent stages to build stuff
FROM alpine:latest AS alpinebuild

# I realized that the build process doesn't remove this intermediate image automatically so best to LABEL it here and then prune later
# Thanks to https://stackoverflow.com/a/55082473
LABEL stage="alpinebuild"
LABEL maintainer="Rakhesh Sasidharan"

# I need the arch later on when downloading s6. Rather than doing the check at that later stage, I introduce the ARG here itself so I can quickly validate and fail if needed.
# Use the --build-arg ARCH=xxx to pass an argument
ARG ARCH=armhf
RUN if ! [[ ${ARCH} = "amd64" || ${ARCH} = "x86" || ${ARCH} = "armhf" || ${ARCH} = "arm" || ${ARCH} = "aarch64" ]]; then \
    echo "Incorrect architecture specified! Must be one of amd64, x86, armhf (for Pi), arm, aarch64"; exit 1; \
    fi

# Get the build-dependencies for everything I plan on building later
# common stuff: git build-base libtool xz cmake
# kea: (https://kea.readthedocs.io/en/kea-1.6.2/arm/install.html#build-requirements) build-base libtool openssl-dev boost-dev log4cplus-dev automake
# knot dns: pkgconf gnutls-dev userspace-rcu-dev libedit-dev libidn2-dev fstrm-dev protobuf-c-dev
# knot resolver: (https://knot-resolver.readthedocs.io/en/latest/build.html) samurai luajit-dev libuv-dev gnutls-dev lmdb-dev ninja
RUN apk add --update --no-cache \
    git build-base libtool xz cmake \
    openssl-dev boost-dev log4cplus-dev automake \
    pkgconf gnutls-dev userspace-rcu-dev libedit-dev libidn2-dev fstrm-dev protobuf-c-dev \
    samurai meson luajit-dev libuv-dev lmdb-dev ninja
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
RUN ./configure --prefix=/usr/local --with-openssl
RUN make && make install

################################## BUILD KNOT DNS ####################################
# This image is to only build Knot DNS
FROM alpinebuild AS alpineknotd

ENV KNOTDNS_VERSION 2.9.5

LABEL stage="alpineknotd"
LABEL maintainer="Rakhesh Sasidharan"

# Download the source & build it
ADD https://secure.nic.cz/files/knot-dns/knot-${KNOTDNS_VERSION}.tar.xz /tmp/
WORKDIR /src
RUN tar xf /tmp/knot-${KNOTDNS_VERSION}.tar.xz -C ./
WORKDIR /src/knot-${KNOTDNS_VERSION}
RUN ./configure --prefix=/usr/local --enable-dnstap --disable-systemd
RUN make && make install

################################## BUILD KNOT RESOLVER ####################################
# This image is to only build Knot Resolver
# It builds upon the Knot DNS image as we need its libraries
FROM alpineknotd AS alpineknotr

ENV KNOTRESOLVER_VERSION 5.1.2

LABEL stage="alpineknotr"
LABEL maintainer="Rakhesh Sasidharan"

ADD https://secure.nic.cz/files/knot-resolver/knot-resolver-${KNOTRESOLVER_VERSION}.tar.xz /tmp/
WORKDIR /src
RUN tar xf /tmp/knot-resolver-${KNOTRESOLVER_VERSION}.tar.xz -C ./
WORKDIR /src/knot-resolver-${KNOTRESOLVER_VERSION}
RUN meson build_dir --prefix=/usr/local --default-library=static
RUN ninja -C build_dir
RUN ninja -C build_dir install


################################### RUNTIME ENVIRONMENT FOR KEA & STUBBY ####################################
# This image has all the runtime dependencies and nothing else. I also create the groups and assign folder permissions etc. 
FROM alpine:latest AS alpineruntime

# Get the runtimes deps for all
# Kea: (https://kea.readthedocs.io/en/kea-1.6.2/arm/intro.html#required-software)
# Knot: (https://knot-resolver.readthedocs.io/en/latest/build.html) libuv luajit lmdb gnutls userspace-rcu libedit libidn2
RUN apk add --update --no-cache ca-certificates \
    drill \
    openssl log4cplus boost \
    libuv luajit lmdb gnutls userspace-rcu libedit libidn2 fstrm protobuf-c
RUN rm -rf /var/cache/apk/*
RUN addgroup -S kea && adduser -D -S kea -G kea
RUN mkdir -p /var/lib/kea/
RUN chown kea:kea /var/lib/kea
RUN mkdir -p /var/run/kea/
RUN chown kea:kea /var/run/kea
RUN mkdir -p /var/log/
RUN touch /var/log/kea-dhcp4.log && touch /var/log/kea-dhcp6.log
RUN chown kea:kea /var/log/kea-dhcp4.log && chown kea:kea /var/log/kea-dhcp6.log


################################### S6 & FINALIZE ####################################
# This pulls in Kea & Stubby, adds s6 and copies some files over
# Create a new image based on alpinebound ...
FROM alpineruntime

# ... and copy the files from the alpineknotr & alpinekea images to the new image (so /usr/local/bin -> /bin etc.)
COPY --from=alpineknotr /usr/local/ /
COPY --from=alpinekea /usr/local/ /

# I take the arch (for s6) as an argument. Options are amd64, x86, armhf (for Pi), arm, aarch64. See https://github.com/just-containers/s6-overlay#releases
ARG ARCH=armhf 
LABEL maintainer="Rakhesh Sasidharan"
ENV S6_VERSION 2.0.0.1

# Copy the config files & s6 service files to the correct location
COPY root/ /

# Add s6 overlay. NOTE: the default instructions give the impression one must do a 2-stage extract. That's only to target this issue - https://github.com/just-containers/s6-overlay#known-issues-and-workarounds
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_VERSION}/s6-overlay-${ARCH}.tar.gz /tmp/
RUN tar xzf /tmp/s6-overlay-${ARCH}.tar.gz -C / && \
    rm  -f /tmp/s6-overlay-${ARCH}.tar.gz

# NOTE: s6 overlay doesn't support running as a different user, but I set the stubby service to run under user "stubby" in its service definition.
# Similarly Unbound runs under its own user & group via the config file. 

EXPOSE 8053/udp 53/udp 53/tcp

HEALTHCHECK --interval=5s --timeout=3s --start-period=5s \
    CMD drill @127.0.0.1 -p 8053 google.com || exit 1

ENTRYPOINT ["/init"]