# Debian base: its apr-util ships the DBM drivers mod_dav_fs's lock database
# needs. Alpine 3.22's apr-util has none, so every PROPFIND and MKCOL failed
# with HTTP 500 ("DBM driver could not be loaded").
FROM httpd:2.4.65
RUN htpasswd -bc /usr/local/apache2/conf/dav.passwd test testpass \
 && printf 'test:dav:%s\n' "$(printf 'test:dav:testpass' | md5sum | cut -d' ' -f1)" > /usr/local/apache2/conf/dav.digest \
 && mkdir -p /var/lib/davlock \
 && chown "$(awk '/^User /{print $2}' /usr/local/apache2/conf/httpd.conf)" /var/lib/davlock
COPY dav.conf /usr/local/apache2/conf/extra/dav.conf
RUN echo 'Include conf/extra/dav.conf' >> /usr/local/apache2/conf/httpd.conf
