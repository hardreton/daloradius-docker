FROM ubuntu:20.04

LABEL org.opencontainers.image.ref.name="frauhottelmann/daloradius-docker" \
      org.opencontainers.image.created=$BUILD_RFC3339 \
      org.opencontainers.image.authors="frauhottelmann" \
      org.opencontainers.image.documentation="https://github.com/frauhottelmann/daloradius-docker/blob/master/README.md" \
      org.opencontainers.image.description="Docker image with freeradius, daloradius, apache2, php. You need to supply your own MariaDB-Server." \
      org.opencontainers.image.licenses="GPLv3" \
      org.opencontainers.image.source="https://github.com/frauhottelmann/daloradius-docker" \
      org.opencontainers.image.revision=$COMMIT \
      org.opencontainers.image.version=$VERSION \
      org.opencontainers.image.url="https://hub.docker.com/r/frauhottelmann/daloradius-docker"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG BUILD_RFC3339="1970-01-01T00:00:00Z"
ARG COMMIT
ARG VERSION

STOPSIGNAL SIGKILL

ENV MYSQL_USER radius
ENV MYSQL_PASSWORD dalodbpass
ENV MYSQL_HOST localhost
ENV MYSQL_PORT 3306
ENV MYSQL_DATABASE radius

ENV TZ Europe/Berlin

RUN apt-get update \
 && apt-get install --yes \
                    apt-utils \
                    tzdata \
                    apache2 \
                    libapache2-mod-php \
                    cron \
                    freeradius-config \
                    freeradius-utils \
                    freeradius \
                    freeradius-common \
                    freeradius-mysql \
                    net-tools \
                    php \
                    php-dev \
                    php-common \
                    php-gd \
                    php-curl \
                    php-mail \
                    php-mail-mime \
                    php-db \
                    php-mysql \
                    mariadb-client \
                    libmysqlclient-dev \
                    supervisor \
                    unzip \
                    wget \
                    vim \
 && rm -rf /var/lib/apt/lists/*
 
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
 && update-ca-certificates -f \
 && mkdir -p /tmp/pear/cache \
 && wget http://pear.php.net/go-pear.phar \
 && php go-pear.phar \
 && rm go-pear.phar \
 && pear channel-update pear.php.net \
 && pear install -a -f DB \
 && pear install -a -f Mail \
 && pear install -a -f Mail_Mime

ENV DALO_VERSION 1.3

RUN wget https://github.com/lirantal/daloradius/archive/"$DALO_VERSION".zip \
 && unzip "$DALO_VERSION".zip \
 && rm "$DALO_VERSION".zip \
 && rm -rf /var/www/html/index.html \
 && mv daloradius-"$DALO_VERSION"/* daloradius-"$DALO_VERSION"/.gitignore daloradius-"$DALO_VERSION"/.htaccess daloradius-"$DALO_VERSION"/.htpasswd /var/www/html \
 && mv /var/www/html/library/daloradius.conf.php.sample /var/www/html/library/daloradius.conf.php \
 && chown -R www-data:www-data /var/www/html \
 && chmod 644 /var/www/html/library/daloradius.conf.php

EXPOSE 1812 1813 80

COPY supervisor-apache2.conf /etc/supervisor/conf.d/apache2.conf
COPY supervisor-freeradius.conf /etc/supervisor/conf.d/freeradius.conf
COPY supervisor-dalocron.conf /etc/supervisor/conf.d/supervisor-dalocron.conf
COPY freeradius-default-site /etc/freeradius/3.0/sites-available/default

COPY init.sh /cbs/
COPY supervisor.conf /etc/

# Init freeradius config
RUN set -ex \
  # Enable SQL in freeradius
  && sed -i 's|driver = "rlm_sql_null"|driver = "rlm_sql_mysql"|' /etc/freeradius/3.0/mods-available/sql \
  && sed -i 's|dialect = "sqlite"|dialect = "mysql"|' /etc/freeradius/3.0/mods-available/sql \
  && sed -i 's|dialect = ${modules.sql.dialect}|dialect = "mysql"|' /etc/freeradius/3.0/mods-available/sqlcounter \
  && sed -i '/tls {/,/}/s/\(.*\)/#AUTO_COMMENT#&/' /etc/freeradius/3.0/mods-available/sql \
  && sed -i 's|#\s*read_clients = yes|read_clients = yes|' /etc/freeradius/3.0/mods-available/sql \
  && ln -s /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/sql \
  && ln -s /etc/freeradius/3.0/mods-available/sqlcounter /etc/freeradius/3.0/mods-enabled/sqlcounter \
  && sed -i 's|instantiate {|instantiate {\nsql|' /etc/freeradius/3.0/radiusd.conf \
  # Enable status in freeadius
  && ln -s /etc/freeradius/3.0/sites-available/status /etc/freeradius/3.0/sites-enabled/status

CMD ["sh", "/cbs/init.sh"]
