FROM alpine:3.20
RUN apk add --no-cache vsftpd openssl \
 && adduser -D -h /srv/media -s /bin/sh test && echo 'test:testpass' | chpasswd \
 && openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj '/CN=mediahro-test' \
      -keyout /etc/vsftpd/vsftpd.pem -out /etc/vsftpd/vsftpd.pem
COPY vsftpd.conf implicit.conf /etc/vsftpd/
EXPOSE 21 990
CMD ["/usr/sbin/vsftpd", "/etc/vsftpd/vsftpd.conf"]
