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
                    ca-certificates \
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
                    php-common \
                    php-gd \
                    php-cli \
                    php-curl \
                    php-mail \
                    php-dev \
                    php-mail-mime \
                    php-mbstring \
                    php-db \
                    php-mysql \
                    php-zip \
                    mariadb-client \
                    default-libmysqlclient-dev \
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


RUN wget https://github.com/lirantal/daloradius/archive/refs/heads/master.zip \
 && unzip master.zip \
 && rm master.zip \
 && rm -rf /var/www/html/index.html \
 && mv daloradius-master/contrib/docker/operators.conf /etc/apache2/sites-available/operators.conf \
 && mv daloradius-master/contrib/docker/users.conf /etc/apache2/sites-available/users.conf \
 && a2dissite 000-default.conf \
 && a2ensite users.conf operators.conf \
 && sed -i 's/Listen 80/Listen 80\nListen 8000/' /etc/apache2/ports.conf \
 && mkdir -p /var/www/daloradius \
 && mv daloradius-master/* daloradius-master/.gitignore daloradius-master/.htaccess master/.htpasswd /var/www/daloradius \
 && mv /var/www/daloradius/app/common/includes/daloradius.conf.php.sample /var/www/daloradius/app/common/includes/daloradius.conf.php \
 && chown -R www-data:www-data /var/www/daloradius \
 && rm -rf /var/www/html \
 && chmod 644 /var/www/daloradius/app/common/includes/daloradius.conf.php \
 && touch /tmp/daloradius.log && chown -R www-data:www-data /tmp/daloradius.log \
 && mkdir -p /var/log/apache2/daloradius && chown -R www-data:www-data /var/log/apache2/daloradius \
 && echo "Mutex posixsem" >> /etc/apache2/apache2.conf

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
