FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        asterisk \
        ca-certificates \
        iproute2 \
        tini \
    && rm -rf /var/lib/apt/lists/*

COPY docker/entrypoint.sh /usr/local/bin/asterisk-entrypoint.sh

RUN chmod +x /usr/local/bin/asterisk-entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/asterisk-entrypoint.sh"]
CMD ["asterisk", "-f", "-vvv"]
