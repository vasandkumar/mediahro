FROM alpine:3.20
RUN apk add --no-cache minidlna
COPY minidlna.conf /etc/minidlna.conf
CMD ["minidlnad", "-d", "-f", "/etc/minidlna.conf", "-R"]
