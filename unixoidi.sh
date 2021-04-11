#!/bin/bash

# naziv domene
DOMENA=unixoidi.xyz
# email vlasnika
EMAIL=tjakopec@ffos.hr
# kreiraj slučajni niz znakova duljine 8 samo mala slova a-z
KORISNIK=$(tr -dc a-z </dev/urandom | head -c 8 ; echo '')
# generiraj lozinku duljine 16 znaova
LOZINKA=$(openssl rand -base64 16) #za sudo
KLJUC=/home/$KORISNIK/kljuc
SSH_DIR=/home/$KORISNIK/.ssh


apt update
# instalacija webserver
apt install -y apache2 
# instalacija baza podataka
apt install -y mariadb-server
# instalacija programski jezik PHP
apt install -y php php-fpm libapache2-mod-php php-mysql 
# instalacija https verifikacije 
apt install -y certbot python3-certbot-apache

# POST INSTALCIJA
# omogući URL rewrite
a2enmod rewrite
# FAST CGI
a2enmod proxy_fcgi setenvif
# omogući PHP FPM
a2enconf php7.4-fpm
# potvrdi onemogućavanje default konfiguracije
service apache2 restart

# počisti default index.html
rm /var/www/html/index.html

# kreiraj bazu i korisnika
cat <<EOT >> skripta.sql
CREATE DATABASE $KORISNIK DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER $KORISNIK@localhost IDENTIFIED BY '$LOZINKA';
GRANT ALL PRIVILEGES ON $KORISNIK.* TO $KORISNIK@localhost;
flush privileges;
EOT
# izvedi naredbe na MariaDB serveru
mariadb < skripta.sql
# počisti za sobom
rm skripta.sql


# preuzmi wordpress
wget https://wordpress.org/latest.tar.gz
# raspakiraj wordpress
tar -xzvf latest.tar.gz
# prebazi datoteke na pravo mjesto
cd wordpress
mv * /var/www/html
# počisti za sobom
cd ..; rmdir wordpress; rm latest.tar.gz
# postavi www-data kogirsnika i grupu da se može
# putem web sučelja upravljati s wordpressom
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;

# generiraj SALT prema wordpres preporuci
SALT_API=$(curl https://api.wordpress.org/secret-key/1.1/salt/)

# kreiraj wp-config datoteku
cat <<EOT >> /var/www/html/wp-config.php
<?php
define( 'DB_NAME', '$KORISNIK' );
define( 'DB_USER', '$KORISNIK' );
define( 'DB_PASSWORD', '$LOZINKA' );
define( 'DB_HOST', 'localhost' );
define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', 'utf8mb4_unicode_ci' );
$SALT_API
$table_prefix = 'wp_';
define( 'WP_DEBUG', false );
if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
EOT

curl "http://$DOMENA/wp-admin/install.php?step=2" \
  --data-urlencode "weblog_title=$DOMENA"\
  --data-urlencode "user_name=$KORISNIK" \
  --data-urlencode "admin_email=$EMAIL" \
  --data-urlencode "admin_password=$LOZINKA" \
  --data-urlencode "admin_password2=$LOZINKA" \
  --data-urlencode "pw_weak=1"  



SSH_CONFIG_DAT=/etc/ssh/sshd_config
MIN_PORT=1025
MAX_PORT=9999
# odaberi broj SSH porta između min i max
PORT=$[ ( $RANDOM % ( $[ $MAX_PORT - $MIN_PORT ] + 1 ) ) + $MIN_PORT ]

# ako postoji ssh config datoteka obriši ju
if test -f "$SSH_CONFIG_DAT"; then
    rm $SSH_CONFIG_DAT
fi
# zapiši SSH konfiguraciju
cat <<EOT >> $SSH_CONFIG_DAT
Include /etc/ssh/sshd_config.d/*.conf
Port $PORT
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp  /usr/lib/openssh/sftp-server
EOT
# ponovo pokreni sshd
/etc/init.d/ssh restart

# postavi firewall - non interaktive
ufw disable
# sve poništi
ufw --force reset
# 1. onemogući sve
ufw default deny incoming
# omogući SSH
ufw allow $PORT
# omogući webserver
ufw allow proto tcp from any to any port 80,443
# upogoni UFW
ufw --force enable



# dodaj korisnika
adduser --disabled-password --gecos "" $KORISNIK
# postavi korisniku lozinku (treba mu za sudo)
echo -e "$LOZINKA\n$LOZINKA" | (passwd $KORISNIK)
# dodaj korisnika u sudo grupu
usermod -aG sudo $KORISNIK
# napravi .ssh direktorij
mkdir $SSH_DIR
# napravi datoteku za postavljanje ssh javnih ključeva
touch $SSH_DIR/authorized_keys
# postavi korisnika na .ssh
chown -R $KORISNIK $SSH_DIR
# postavi grupu na .ssh
chgrp -R $KORISNIK $SSH_DIR
# generiraj par javni/privatni ključ na danoj putanji $KLJUC
ssh-keygen -b 2048 -t rsa -f $KLJUC -q -N ""
# postavi javni ključ u datoteku javnih ključeva
cat $KLJUC.pub >> $SSH_DIR/authorized_keys



# potpiši https - kasnije uključi
#certbot --non-interactive --agree-tos -m tjakopec@$EMAIL \
#--apache --redirect -d $DOMENA -d www.$DOMENA
#There were too many requests of a given type :: Error creating new order :: too many certificates already issued for exact set of domains: unixoidi.xyz,www.unixoidi.xyz: see https://letsencrypt.org/docs/rate-limits/

# ispiši podatke u konzolu za copy/paste
echo "korisnik: $KORISNIK"
echo "lozinka: $LOZINKA"
cat $KLJUC
# počisti za sobom
rm $KLJUC.pub
rm $KLJUC
# ispiši pomoć pri spajanju s linux sustava
echo ssh -i kljuc $KORISNIK@178.62.249.38 -p$PORT

