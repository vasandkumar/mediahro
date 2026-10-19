FROM alpine:3.20
RUN apk add --no-cache samba samba-client \
 && adduser -D -H -s /sbin/nologin test \
 && (echo testpass; echo testpass) | smbpasswd -a -s test
COPY smb.conf /etc/samba/smb.conf
EXPOSE 445
CMD ["smbd", "--foreground", "--no-process-group", "--debug-stdout"]
