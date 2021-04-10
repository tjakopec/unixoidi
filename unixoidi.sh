#!/bin/bash

# naziv domene
DOMENA=unixoidi.xyz

# potrebno za PHP 8.0
apt install -y software-properties-common
add-apt-repository -y ppa:ondrej/php
apt update
# instalacije potrebnih paketa
apt install -y php8.0 php8.0-fpm php8.0-mysql nginx mariadb-server \
certbot python3-certbot-nginx

# ponovno pokreni PHP FPM - potrebno
systemctl restart php8.0-fpm.service 

# pokreni nginx po reboot-u stroja
systemctl start nginx
systemctl enable nginx

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

# onemogući default nginx konfiguraciju
rm /etc/nginx/sites-enabled/default
# potvrdi onemogućavanje default konfiguracije
systemctl restart nginx

# zapiši nginx konfiguraciju za korisnika
cat <<EOT >> /etc/nginx/sites-available/$DOMENA
server {
        listen 80;
        listen [::]:80;
        root $WWW_DIR;
        index index.php index.html index.htm index.nginx-debian.html;
        server_name $DOMENA www.$DOMENA;
        location / {
                try_files \$uri /index.php\\\$is_args\$args;
        }
        location ~ \\.php\$ {
                include snippets/fastcgi-php.conf;
                fastcgi_pass unix:/run/php/php8.0-fpm.sock;
        }
                location ~ /\\.ht {
                deny all;
        }
        location ~ ^/\\.php(/\$) {
                fastcgi_pass unix:/run/php/php8.0-fpm.sock;
                fastcgi_split_path_info ^(.+\\.php)(/.*)\$;
                include fastcgi_params;
                fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
                fastcgi_param DOCUMENT_ROOT \$realpath_root;
                internal;
        }
        location ~ \\.php\$ {
                return 404;
        }
}
EOT
# postavi simbolički link u omogućene domene
ln -s /etc/nginx/sites-available/$DOMENA /etc/nginx/sites-enabled/
# ponovo pokreni nginx
systemctl restart nginx

# potpiši https
certbot --non-interactive --agree-tos -m tjakopec@ffos.hr \
--nginx --redirect -d $DOMENA -d www.$DOMENA


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