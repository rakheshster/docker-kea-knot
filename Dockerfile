################################### STUBBY ####################################
# This image is to only build Stubby
FROM alpine:latest AS alpinestubby

ENV GETDNS_VERSION 1.6.0
ENV STUBBY_VERSION 0.3.0

# I realized that the build process doesn't remove this intermediate image automatically so best to LABEL it here and then prune later
# Thanks to https://stackoverflow.com/a/55082473
LABEL stage="alpinestubby"
LABEL maintainer="Rakhesh Sasidharan"

# I need the arch later on when downloading s6. Rather than doing the check at that later stage, I introduce the ARG here itself so I can quickly validate and fail if needed.
# Use the --build-arg ARCH=xxx to pass an argument
ARG ARCH=armhf
RUN if ! [[ ${ARCH} = "amd64" || ${ARCH} = "x86" || ${ARCH} = "armhf" || ${ARCH} = "arm" || ${ARCH} = "aarch64" ]]; then \
    echo "Incorrect architecture specified! Must be one of amd64, x86, armhf (for Pi), arm, aarch64"; exit 1; \
    fi

# Get the build-dependencies for stubby & getdns
# See for the official list: https://github.com/getdnsapi/getdns#external-dependencies
# https://pkgs.alpinelinux.org/packages is a good way to search for alpine packages. Note it uses wildcards
RUN apk add --update --no-cache git build-base \ 
    libtool openssl-dev \
    unbound-dev yaml-dev \
    cmake libidn2-dev libuv-dev libev-dev check-dev \
    && rm -rf /var/cache/apk/*

# Download the source
# Official recommendation (for example: https://github.com/getdnsapi/getdns/releases/tag/v1.6.0) is to get the tarball from getdns than from GitHub
# Stubby is developed by the getdns team. libgetdns is a dependancy for Stubby, the getdns library provides all the core functionality for DNS resolution done by Stubby so it is important to build against the latest version of getdns.
# When building getdns one can also build stubby alongwith
ADD https://getdnsapi.net/dist/getdns-${GETDNS_VERSION}.tar.gz /tmp/

# Create a workdir called /src, extract the getdns source to that, build it
# Cmake steps from https://lektor.getdnsapi.net/quick-start/cmake-quick-start/ (v 1.6.0)
WORKDIR /src
RUN tar xzf /tmp/getdns-${GETDNS_VERSION}.tar.gz -C ./
WORKDIR /src/getdns-${GETDNS_VERSION}/build
RUN cmake -DBUILD_STUBBY=ON -DCMAKE_INSTALL_PREFIX:PATH=/usr/local .. && \
    make && \
    make install

################################## KEA DHCP ####################################
# This image is to only build Kea Dhcp
FROM alpine:latest AS alpinekea

ENV KEA_VERSION 1.7.10

# I realized that the build process doesn't remove this intermediate image automatically so best to LABEL it here and then prune later
# Thanks to https://stackoverflow.com/a/55082473
LABEL stage="alpinekea"
LABEL maintainer="Rakhesh Sasidharan"

# Get the build-dependencies for kea
# https://kea.readthedocs.io/en/kea-1.6.2/arm/install.html#build-requirements
RUN apk add --update --no-cache git build-base libtool openssl-dev boost-dev log4cplus-dev automake \
    && rm -rf /var/cache/apk/*

# Download the source
ADD https://downloads.isc.org/isc/kea/1.7.10/kea-${KEA_VERSION}.tar.gz  /tmp/

# Create a workdir called /src, extract the getdns source to that, build it
# Cmake steps from https://lektor.getdnsapi.net/quick-start/cmake-quick-start/ (v 1.6.0)
WORKDIR /src
RUN tar xzf /tmp/kea-${KEA_VERSION}.tar.gz -C ./
WORKDIR /src/kea-${KEA_VERSION}
RUN ./configure --prefix=/usr/local --with-openssl
RUN make && make install

################################### RUNTIME ENVIRONMENT FOR KEA & STUBBY ####################################
FROM alpine:latest AS alpineruntime

# Deps for Stubby & Kea
# Kea: https://kea.readthedocs.io/en/kea-1.6.2/arm/intro.html#required-software
# Stubby: I found these by running stubby and seeing what it complained about
RUN apk add --update --no-cache unbound ca-certificates \
    unbound-libs yaml libidn2 \
    drill \
    openssl log4cplus boost
RUN addgroup -S stubby && adduser -D -S stubby -G stubby
RUN addgroup -S kea && adduser -D -S kea -G kea
RUN mkdir -p /var/cache/stubby 
RUN chown stubby:stubby /var/cache/stubby 
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

# ... and copy the files from the alpinestubby & alpinekea images to the new image (so /usr/local/bin -> /bin etc.)
COPY --from=alpinestubby /usr/local/ /
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