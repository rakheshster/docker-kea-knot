
# Install build deps on Alpine:
`apk add --update --no-cache git build-base libtool openssl-dev boost-dev log4cplus-dev automake`


# Install build deps on Debian: 
`apt install -y libboost-all-dev libssl-dev liblog4cplus-dev build-essential automake libtool`


# Other steps 
curl https://downloads.isc.org/isc/kea/1.7.10/kea-1.7.10.tar.gz -o /tmp/kea-1.7.10.tar.gz
tar xzf /tmp/kea-1.7.10.tar.gz -C /tmp
cd /tmp/kea-1.7.10
./configure
make && make install

It takes a long long time ... 


# For key verification
gpg --import 201920pgp.key <- this key is in the folder, COPY it into the container

curl https://downloads.isc.org/isc/kea/1.7.10/kea-1.7.10.tar.gz.asc /tmp/kea-1.7.10.tar.gz.asc
cd /tmp
gpg --verify kea.tar.gz.sha512.asc kea.tar.gz
check $? ... if 0, all good

---

I left this coz it takes a long time to build. 