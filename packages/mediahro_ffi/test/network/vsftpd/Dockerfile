FROM alpine:3.20
# Key and certificate in separate files (writing both to one path with
# `openssl req -keyout X -out X` can leave the key out); checked at build.
RUN apk add --no-cache vsftpd openssl \
 && adduser -D -h /srv/media -s /bin/sh test && echo 'test:testpass' | chpasswd \
 && openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj '/CN=mediahro-test' \
      -keyout /etc/vsftpd/vsftpd.key -out /etc/vsftpd/vsftpd.crt \
 && chmod 600 /etc/vsftpd/vsftpd.key \
 && openssl x509 -in /etc/vsftpd/vsftpd.crt -noout \
 && openssl pkey -in /etc/vsftpd/vsftpd.key -noout \
 && mkdir -p /var/run/vsftpd/empty
COPY vsftpd.conf implicit.conf run.sh /etc/vsftpd/
RUN chmod 755 /etc/vsftpd/run.sh
EXPOSE 21 990
# run.sh reports vsftpd's exit status and any "500 OOPS" on stderr, so
# `docker compose logs <service>` shows why a listener stopped.
CMD ["/etc/vsftpd/run.sh", "/etc/vsftpd/vsftpd.conf"]
