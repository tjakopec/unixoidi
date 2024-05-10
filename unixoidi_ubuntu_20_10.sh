#!/bin/bash

####################################################################
#                        OSNOVNE VARIJABLE                         #
####################################################################
# naziv domene
DOMENA=unixoidi.xyz
# IP adresa
IP_SERVERA=138.197.183.226
# email vlasnika
EMAIL=tjakopec@gmail.com
# kreiraj slučajni niz znakova duljine 8 samo mala slova a-z
KORISNIK=$(tr -dc a-z </dev/urandom | head -c 8 ; echo '')
# generiraj lozinku duljine 16 znaova
LOZINKA=$(openssl rand -base64 16) #za sudo
# vrijednosti za generiranje porta
MIN_PORT=1025
MAX_PORT=9999
# odaberi broj SSH porta između min i max
PORT=$[ ( $RANDOM % ( $[ $MAX_PORT - $MIN_PORT ] + 1 ) ) + $MIN_PORT ]
# putanja SSHD config
SSH_CONFIG_DAT=/etc/ssh/sshd_config
KLJUC=/home/$KORISNIK/kljuc
SSH_DIR=/home/$KORISNIK/.ssh
# generiraj SALT prema wordpres preporuci
SALT_API=$(curl https://api.wordpress.org/secret-key/1.1/salt/)

####################################################################
#                       OSNOVNA INSTALACIJA                        #
####################################################################
#sed -i "/#\$nrconf{restart} = 'i';/s/.*/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf
# ažuriraj popis repozitorija
apt update
# instalacija webserver
apt install -y apache2 
# instalacija baza podataka
apt install -y mariadb-server 
# instalacija programski jezik PHP
apt install -y php 
# instalacija https verifikacije 
apt install -y certbot python3-certbot-apache
# FAST PHP MANAGER
apt install -y php-fpm
# Mysql/MariaDB PHP driver
apt install -y php-mysql


####################################################################
#                         POST INSTALACIJA                         #
####################################################################
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

# onemogući osnovni vhost
a2dissite 000-default.conf
# restart apache
service apache2 restart
# obriši vhost konfiguraciju
rm /etc/apache2/sites-available/000-default.conf
# kreiraj novu vhost konfiguraciju
cat <<EOT > /etc/apache2/sites-available/000-default.conf
<VirtualHost *:80>
    ServerName $DOMENA
    ServerAlias www.$DOMENA
    DocumentRoot "/var/www/html"
    ServerAdmin $EMAIL
        <Directory "/var/www/html">
	  Options -Indexes +FollowSymLinks +MultiViews
          AllowOverride All
          Require all granted
        </Directory>
</VirtualHost>
EOT
# omogući novi vhost
a2ensite 000-default.conf
# restart apache
service apache2 restart

####################################################################
#                              MARIADB                             #
####################################################################
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


####################################################################
#                            WORDPRESS                             #
####################################################################
# preuzmi wordpress
wget https://wordpress.org/latest.tar.gz
# raspakiraj wordpress
tar -xzvf latest.tar.gz
# prebazi datoteke na pravo mjesto
cd wordpress
mv * /var/www/html
# počisti za sobom
cd ..; rmdir wordpress; rm latest.tar.gz

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
\$table_prefix = 'wp_';
define( 'WP_DEBUG', false );
if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
EOT

# postavi www-data korisnika i grupu da se može
# putem web sučelja upravljati s wordpressom
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;
# instaliraj wordpress
curl "http://$DOMENA/wp-admin/install.php?step=2" \
  --data-urlencode "weblog_title=$DOMENA"\
  --data-urlencode "user_name=$KORISNIK" \
  --data-urlencode "admin_email=$EMAIL" \
  --data-urlencode "admin_password=$LOZINKA" \
  --data-urlencode "admin_password2=$LOZINKA" \
  --data-urlencode "pw_weak=1"  




####################################################################
#                               SSHD                               #
####################################################################
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


####################################################################
#                             FIREWALL                             #
####################################################################
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


####################################################################
#                             KORISNIK                             #
####################################################################
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


####################################################################
#                             CERTBOT                              #
####################################################################
# potpiši https - kasnije uključi
certbot --non-interactive --agree-tos -m $EMAIL \
--apache --redirect -d $DOMENA -d www.$DOMENA
#There were too many requests of a given type :: Error creating new order :: too many certificates already issued for exact set of domains: unixoidi.xyz,www.unixoidi.xyz: see https://letsencrypt.org/docs/rate-limits/


####################################################################
#                  ISPIS PODATAKA KORISNIKU                        #
####################################################################
# ispiši podatke u konzolu za copy/paste
echo "korisnik i lozinka isti za sve:"
echo "1. linux user"
echo "2. database user"
echo "3. wordpress user"
echo "korisnik: $KORISNIK"
echo "lozinka: $LOZINKA"
cat $KLJUC
# počisti za sobom
rm $KLJUC.pub
rm $KLJUC
# ispiši pomoć pri spajanju s linux sustava
echo ssh -i kljuc $KORISNIK@$IP_SERVERA -p$PORT

