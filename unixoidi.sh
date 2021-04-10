#!/bin/bash

# naziv domene
DOMENA=unixoidi.xyz
EMAIL=tjakopec@ffos.hr


apt update
# instalacije potrebnih paketa
apt install -y php php-mysql apache2 mariadb-server \
certbot python3-certbot-apache


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


# kreiraj slučajni niz znakova duljine 8 samo mala slova a-z
KORISNIK=$(tr -dc a-z </dev/urandom | head -c 8 ; echo '')
# generiraj lozinku duljine 16 znaova
LOZINKA=$(openssl rand -base64 16) #za sudo
KLJUC=/home/$KORISNIK/kljuc
SSH_DIR=/home/$KORISNIK/.ssh
WWW_DIR=/home/$KORISNIK/www
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

# kreiraj direktorij za web sadržaj
mkdir $WWW_DIR
echo "Hello $KORISNIK" > $WWW_DIR/index.html
# postavi korisnika na www
chown -R $KORISNIK $WWW_DIR
# postavi grupu na www
chgrp -R $KORISNIK $WWW_DIR

# onemogući default apache konfiguraciju
a2dissite 000-default.conf
# potvrdi onemogućavanje default konfiguracije
service apache2 restart

# zapiši nginx konfiguraciju za korisnika
cat <<EOT >> /etc/apache2/sites-available/$DOMENA.conf
<VirtualHost *:80>
    ServerName $DOMENA
    ServerAlias $DOMENA
    DocumentRoot "$WWW_DIR"
    ErrorLog "/home/$KORISNIK/$DOMENA-error_log"
    CustomLog "/home/$KORISNIK/$DOMENA-access_log" common
    ServerAdmin $EMAIL
        <Directory "$WWW_DIR">
	      Options -Indexes +FollowSymLinks +MultiViews
          AllowOverride All
          Require all granted
        </Directory>
</VirtualHost>
EOT
# omogući novi virtual host
a2ensite $DOMENA.conf
# ponovo pokreni apache
service apache2 restart

# potpiši https - kasnije uključi
#certbot --non-interactive --agree-tos -m tjakopec@$EMAIL \
#--nginx --redirect -d $DOMENA -d www.$DOMENA
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


#WP: https://gist.github.com/ryanknights/e4f499324b916ddaba48