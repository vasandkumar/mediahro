FROM alpine:3.20
RUN apk add --no-cache minidlna
COPY minidlna.conf /etc/minidlna.conf
COPY health.sh /usr/local/bin/minidlna-health
RUN chmod 755 /usr/local/bin/minidlna-health
CMD ["minidlnad", "-d", "-f", "/etc/minidlna.conf", "-R"]
