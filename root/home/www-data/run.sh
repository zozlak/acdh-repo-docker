#!/bin/bash

# Preserve host user UID and GID
sed -i -E 's|www-data:(.*):/usr/sbin/nologin|www-data:\1:/bin/bash|g'  /etc/passwd
if [ "$USER_GID" != "" ]; then
    groupmod -g $USER_GID www-data 
    chgrp -R www-data /home/www-data
fi
if [ "$USER_UID" != "" ]; then
    usermod -u $USER_UID www-data
    chown -R www-data /home/www-data
fi
chown www-data:www-data /var/run/apache2 /var/run/postgresql /home/www-data/config

# Configuration initialization
if [ ! -d /home/www-data/config ] || [ -z "`ls -A /home/www-data/config`" ]; then
    echo -e "##########\n# Initializing configuration \n##########\n"
    ls -al /home/www-data/config
    if [ "$CFG_REPO_URL" == "" ]; then
        CFG_REPO_URL="https://github.com/acdh-oeaw/arche-docker-config.git"
    fi
    echo "cloning $CFG_REPO_URL"
    su -l www-data -c "git clone $CFG_REPO_URL /home/www-data/config"

    if [ "$CFG_BRANCH" != "" ]; then
        echo "changing branch to $CFG_BRANCH"
        su -l www-data -c "cd /home/www-data/config && git checkout $CFG_BRANCH"
    fi
fi

# Apache config from the configuration directory
if [ -d /home/www-data/config/sites-enabled ]; then
    rm -fR /etc/apache2/sites-enabled
    ln -s /home/www-data/config/sites-enabled /etc/apache2/sites-enabled
fi

# Repo config and composer.json from the configuration directory
if [ ! -L /home/www-data/docroot/api/config.yaml ]; then
    su -l www-data -c 'ln -s /home/www-data/config/config.yaml   /home/www-data/docroot/api/config.yaml'
    su -l www-data -c 'ln -s /home/www-data/vendor               /home/www-data/docroot/api/vendor'
    su -l www-data -c 'ln -s /home/www-data/config/composer.json /home/www-data/composer.json'
fi

# PHP libraries update
echo -e "##########\n# Updating PHP libraries\n##########\n"
su -l www-data -c 'cd /home/www-data && composer update --no-dev'
su -l www-data -c 'cp /home/www-data/vendor/acdh-oeaw/arche-core/index.php /home/www-data/docroot/api/index.php'
su -l www-data -c 'cp /home/www-data/vendor/acdh-oeaw/arche-core/.htaccess /home/www-data/docroot/api/.htaccess'

# Database connection config
if [ ! -z "$PG_HOST" ]; then
    export PG_EXTERNAL=1
else
    PG_USER=www-data
    PG_DBNAME=www-data
fi
export PG_HOST=${PG_HOST:=127.0.0.1}
export PG_PORT=${PG_PORT:=5432}
export PG_USER=${PG_USER:=postgres}
export PG_DBNAME=${PG_DBNAME:=postgres}
export PG_CONN="-h $PG_HOST -p $PG_PORT -U $PG_USER $PG_DBNAME"
su -l www-data -c 'echo "" > /home/www-data/.pgpass && chmod 600 /home/www-data/.pgpass'
if [ ! -z "$PG_EXTERNAL" ]; then
    echo "$PG_HOST:$PG_PORT:$PG_DBNAME:$PG_USER:$PG_PSWD" >> /home/www-data/.pgpass
    echo "$PG_HOST:$PG_PORT:$PG_USER:$PG_USER:$PG_PSWD" >> /home/www-data/.pgpass
fi

# Housekeeping
rm -f /home/www-data/postgresql/postmaster.pid

# User init scripts
for i in `ls -1 /home/www-data/config/run.d`; do
    if [ -x "/home/www-data/config/run.d/$i" ]; then
        echo -e "##########\n# Running /home/www-data/config/run.d/$i\n##########\n"
        /home/www-data/config/run.d/$i
    fi
done

# Running supervisord
echo -e "##########\n# Starting supervisord\n##########\n"
declare -px > /home/www-data/env
chown www-data:www-data /home/www-data/env
su -l www-data -w PG_HOST,PG_PORT,PG_USER,PG_DBNAME,PG_CONN,PG_EXTERNAL -c '/usr/bin/supervisord -c /home/www-data/supervisord.conf'

