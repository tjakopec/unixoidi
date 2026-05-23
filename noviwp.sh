#!/bin/bash

# bash /root/noviwp.sh

KORISNIK=""
EMAIL=""
LOZINKA=""

while true; do
    echo "----------------------------------------------------"
    echo "Unesite podatke (bez razmaka, korisnik i email će biti mala slova):"
    
    read -p "Unesite korisničko ime: " KORISNIK_INPUT
    read -p "Unesite email adresu: " EMAIL_INPUT
    read -sp "Unesite lozinku: " LOZINKA_INPUT
    echo ""


    if [[ -z "$KORISNIK_INPUT" || -z "$EMAIL_INPUT" || -z "$LOZINKA_INPUT" ]]; then
        echo "[GREŠKA] Sva polja moraju biti popunjena!"
        continue
    fi


    if [[ "$KORISNIK_INPUT" =~ [[:space:]] || "$EMAIL_INPUT" =~ [[:space:]] || "$LOZINKA_INPUT" =~ [[:space:]] ]]; then
        echo "[GREŠKA] Unos ne smije sadržavati razmake!"
        continue
    fi


    KORISNIK="${KORISNIK_INPUT,,}"
    EMAIL="${EMAIL_INPUT,,}"
    LOZINKA="$LOZINKA_INPUT"


    break
done

echo "----------------------------------------------------"


adduser --disabled-password --gecos "" $KORISNIK
echo -e "$LOZINKA\n$LOZINKA" | (passwd $KORISNIK)
chmod +x /home/$KORISNIK
mkdir /home/$KORISNIK/www
chown -R $KORISNIK:www-data /home/$KORISNIK/www
echo "Hello WP $KORISNIK" > /home/$KORISNIK/www/index.html
cat <<EOT > /etc/apache2/sites-available/$KORISNIK-www.conf
<VirtualHost *:80>
    ServerName $KORISNIK.tzosnm.com
    ServerAlias www.$KORISNIK.tzosnm.com
    DocumentRoot "/home/$KORISNIK/www"
    ServerAdmin tzosnm.com
        <Directory "/home/$KORISNIK/www">
	  Options -Indexes +FollowSymLinks +MultiViews
          AllowOverride All
          Require all granted
        </Directory>
</VirtualHost>
EOT
a2ensite $KORISNIK-www.conf
service apache2 restart
certbot --non-interactive --agree-tos -m $EMAIL \
--apache --redirect -d $KORISNIK.tzosnm.com -d www.$KORISNIK.tzosnm.com




cat <<EOT >> skripta$KORISNIK.sql
CREATE DATABASE $KORISNIK DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER $KORISNIK@localhost IDENTIFIED BY '$LOZINKA';
GRANT ALL PRIVILEGES ON $KORISNIK.* TO $KORISNIK@localhost;
flush privileges;
EOT
mariadb < skripta$KORISNIK.sql
rm skripta$KORISNIK.sql



cd /home/$KORISNIK/www
wget https://wordpress.org/latest.tar.gz
tar -xzvf latest.tar.gz
cd /home/$KORISNIK/www/wordpress
mv * /home/$KORISNIK/www
cd ..; rmdir wordpress; rm latest.tar.gz
cat <<EOT >> /home/$KORISNIK/www/wp-config.php
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
chown -R www-data:www-data /home/$KORISNIK/www
find /home/$KORISNIK/www -type d -exec chmod 755 {} \;
find /home/$KORISNIK/www -type f -exec chmod 644 {} \;
curl "https://$KORISNIK.tzosnm.com/wp-admin/install.php?step=2" \
  --data-urlencode "weblog_title=$KORISNIK.tzosnm.com"\
  --data-urlencode "user_name=$KORISNIK" \
  --data-urlencode "admin_email=$EMAIL" \
  --data-urlencode "admin_password=$LOZINKA" \
  --data-urlencode "admin_password2=$LOZINKA" \
  --data-urlencode "pw_weak=1"  
rm /home/$KORISNIK/www/index.html

echo "----------------------------------------------------"
echo "----------------------------------------------------"
echo "----------------------------------------------------"
echo "GOTOV"
echo "https://$KORISNIK.tzosnm.com"
echo $KORISNIK
echo $LOZINKA
echo "----------------------------------------------------"