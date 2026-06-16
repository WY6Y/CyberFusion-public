FROM alpine

RUN apk add --update --no-cache \
    cmake \
    make \
    g++ \
    git \
    libmosquitto-dev \
    linux-headers \
  && rm -rf /var/cache/apk/*

ADD ./ /MMDVM-Host
WORKDIR /MMDVM-Host
RUN make \
&& cp MMDVM-Host /usr/local/bin

VOLUME /MMDVM-Host
WORKDIR /MMDVM-Host

CMD ["MMDVM-Host", "/MMDVM-Host/MMDVM-Host.ini"]

