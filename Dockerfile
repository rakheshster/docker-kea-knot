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
# Configure kea to expect everything in / (--prefix=/) but when installing put everything into /usr/local (via DESTDIR=) (I copy the contents of this to / in the final image)
RUN ./configure --prefix=/ --with-openssl
RUN make && DESTDIR=/usr/local make install

# Disable keactrl as its broken under alpine (ps -p does not work) and also it conflicts with s6 if I try to stop etc. 
# The only thing I need keactrl for is to reload the config, for that use the included kea-dhcpx-reload script which I provide.
RUN chmod -x /usr/local/sbin/keactrl

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
# Configure knot to expect everything in / (--prefix=/) but when installing put everything into /usr/local (via DESTDIR=) (I copy the contents of this to / in the final image)
RUN ./configure --prefix=/ --enable-dnstap --disable-systemd
RUN make && DESTDIR=/usr/local make install

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
RUN meson build_dir --prefix=/ --sysconfdir=etc
RUN ninja -C build_dir
RUN DESTDIR=/usr/local ninja -C build_dir install

# I figured the above options via trial and error. 
# `meson build_dir --prefix=/`  tells it to look for stuff in /. this does not actually install in the / folder. 
# I also add --sysconfdir=etc to tell it to install stuff in the /etc folder. By default it ignores the --prefix, that's why I specify it manually. 
# `DESTDIR=/usr/local ninja -C build_dir install` is what does the actual install. DESTDIR makes it install to /usr/local.
# Later when I copy this to the runtime image all these become /usr/local/sbin -> /sbin etc. And this is where the --prefix kicks in coz all the programs expect the libraries to be at the prefix specified here, which is /.  


################################### RUNTIME ENVIRONMENT FOR KEA & STUBBY ####################################
# This image has all the runtime dependencies, the built files from the previous stage, and I also create the groups and assign folder permissions etc. 
# I got to create the folder after copying the stuff from previous stage so the permissions don't get overwritten
FROM alpine:latest AS alpineruntime

# Get the runtimes deps for all
# Kea: (https://kea.readthedocs.io/en/kea-1.6.2/arm/intro.html#required-software)
# Knot: (https://knot-resolver.readthedocs.io/en/latest/build.html) libuv luajit lmdb gnutls userspace-rcu libedit libidn2
RUN apk add --update --no-cache ca-certificates \
    drill \
    openssl log4cplus boost \
    libuv luajit lmdb gnutls userspace-rcu libedit libidn2 fstrm protobuf-c
RUN rm -rf /var/cache/apk/*

# /usr/local/bin -> /bin etc.
COPY --from=alpineknotr /usr/local/ /
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

# Copy the config files & s6 service files to the correct location
COPY root/ /

# Add s6 overlay. NOTE: the default instructions give the impression one must do a 2-stage extract. That's only to target this issue - https://github.com/just-containers/s6-overlay#known-issues-and-workarounds
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_VERSION}/s6-overlay-${ARCH}.tar.gz /tmp/
RUN tar xzf /tmp/s6-overlay-${ARCH}.tar.gz -C / && \
    rm  -f /tmp/s6-overlay-${ARCH}.tar.gz

# NOTE: s6 overlay doesn't support running as a different user, but I set the stubby service to run under user "stubby" in its service definition.
# Similarly Unbound runs under its own user & group via the config file. 

EXPOSE 8053/udp 53/udp 53/tcp 443/tcp 853/tcp 8080/tcp
# Knot DNS runs on 8053. Knot Resolver on 53. Kea requires 8080 for HA
# Not sure why I am exposing 853. Remove later if I can't figure out. 

HEALTHCHECK --interval=5s --timeout=3s --start-period=5s \
    CMD drill @127.0.0.1 -p 8053 google.com || exit 1

ENTRYPOINT ["/init"]