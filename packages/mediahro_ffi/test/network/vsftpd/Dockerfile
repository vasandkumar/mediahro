FROM alpine:3.20
# Key and certificate in separate files, verified at build time.
RUN apk add --no-cache vsftpd openssl strace \
 && adduser -D -h /srv/media -s /bin/sh test && echo 'test:testpass' | chpasswd \
 && openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj '/CN=mediahro-test' \
      -keyout /etc/vsftpd/vsftpd.key -out /etc/vsftpd/vsftpd.crt \
 && chmod 600 /etc/vsftpd/vsftpd.key \
 && openssl x509 -in /etc/vsftpd/vsftpd.crt -noout \
 && openssl pkey -in /etc/vsftpd/vsftpd.key -noout \
 && mkdir -p /srv/media
COPY vsftpd.conf implicit.conf run.sh check.sh /etc/vsftpd/
# Both listeners must start: a broken config fails the build with a trace.
RUN chmod 755 /etc/vsftpd/run.sh /etc/vsftpd/check.sh \
 && /etc/vsftpd/check.sh /etc/vsftpd/vsftpd.conf 21 \
 && /etc/vsftpd/check.sh /etc/vsftpd/implicit.conf 990
EXPOSE 21 990
CMD ["/etc/vsftpd/run.sh", "/etc/vsftpd/vsftpd.conf"]
