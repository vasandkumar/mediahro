FROM httpd:2.4.65-alpine
RUN apk add --no-cache apache2-utils \
 && htpasswd -bc /usr/local/apache2/conf/dav.passwd test testpass \
 && printf 'test:dav:%s\n' "$(printf 'test:dav:testpass' | md5sum | cut -d' ' -f1)" > /usr/local/apache2/conf/dav.digest \
 && mkdir -p /var/lib/davlock && chown daemon:daemon /var/lib/davlock
COPY dav.conf /usr/local/apache2/conf/extra/dav.conf
RUN echo 'Include conf/extra/dav.conf' >> /usr/local/apache2/conf/httpd.conf
