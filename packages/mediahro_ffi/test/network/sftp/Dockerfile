FROM alpine:3.20
RUN apk add --no-cache openssh \
 && adduser -D -h /home/test -s /bin/sh test && echo 'test:testpass' | chpasswd \
 && mkdir -p /home/test/.ssh && chown test:test /home/test/.ssh && chmod 700 /home/test/.ssh \
 && ssh-keygen -A \
 && printf 'PasswordAuthentication yes\nKbdInteractiveAuthentication yes\nPubkeyAuthentication yes\nStrictModes no\nSubsystem sftp internal-sftp\n' >> /etc/ssh/sshd_config
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
