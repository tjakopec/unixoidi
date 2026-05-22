#!/bin/bash

####################################################################
#                        OSNOVNE VARIJABLE                         #
####################################################################
# Email administratora
EMAIL="tjakopec@gmail.com"

# Provjera je li uneseno ime domene kao argument
if [ -z "$1" ]; then
  echo "Morate unijeti ime domene kao argument. (npr. unixoidi.pro)"
  exit 1
fi

DOMENA="$1"
MAILSUBDOMENA="mail.$DOMENA"

# Generiranje nasumične lozinke za bazu podataka (za mail sustav i roundcube)
DB_MAIL_LOZINKA=$(openssl rand -base64 16)

#精度 dohvaćanje IP adrese
IP_ADRESE=$(ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d '/' -f 1)
IP_SERVERA=$(echo "$IP_ADRESE" | awk 'NR==1{print $1}')

if [ -z "$IP_SERVERA" ]; then
  echo "Nije moguće dohvatiti IP adresu."
  exit 1
fi


####################################################################
#                       OSNOVNA INSTALACIJA                        #
####################################################################
hostnamectl set-hostname $MAILSUBDOMENA
apt update

# Non-interactive odgovori za Postfix
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
debconf-set-selections <<< "postfix postfix/mailname string $DOMENA"

# Instalacija paketa (uključujući PHP ekstenzije potrebne za Roundcube)
apt install -y postfix postfix-mysql dovecot-imapd dovecot-pop3d dovecot-mysql \
apt install -y opendkim opendkim-tools apache2 mariadb-server php php-cli \
apt install -y php-fpm php-mysql php-mbstring php-xml php-intl php-zip php-curl php-gd


####################################################################
#                 BAZA PODATAKA (UPRAVLJANJE MAILOVIMA)            #
####################################################################
# Kreiramo strukturu baze za virtualne domene, korisnike i aliase
cat <<EOT > /tmp/mail_setup.sql
CREATE DATABASE IF NOT EXISTS servermail DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON servermail.* TO 'mailuser'@'localhost' IDENTIFIED BY '$DB_MAIL_LOZINKA';

USE servermail;

CREATE TABLE virtual_domains (
  id int(11) NOT NULL AUTO_INCREMENT,
  name varchar(50) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE virtual_users (
  id int(11) NOT NULL AUTO_INCREMENT,
  domain_id int(11) NOT NULL,
  password varchar(106) NOT NULL,
  email varchar(120) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY email (email),
  FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE virtual_aliases (
  id int(11) NOT NULL AUTO_INCREMENT,
  domain_id int(11) NOT NULL,
  source varchar(100) NOT NULL,
  destination varchar(100) NOT NULL,
  PRIMARY KEY (id),
  FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Inicijalni unos: Dodajemo našu domenu
INSERT INTO virtual_domains (name) VALUES ('$DOMENA');
-- Kreiramo prvog testnog korisnika: info@domena (Lozinka za mail pretinac je ista kao i za DB radi jednostavnosti ispisa)
INSERT INTO virtual_users (domain_id, password, email) 
VALUES (1, ENCRYPT('$DB_MAIL_LOZINKA', CONCAT('\$6\$', SUBSTRING(SHA2(RAND(), 256), 1, 16))), 'info@$DOMENA');
EOT

mariadb < /tmp/mail_setup.sql
rm /tmp/mail_setup.sql

# Kreiranje sistemskog korisnika (vmail) koji će fizički držati sve virtualne mailove
groupadd -g 5000 vmail
useradd -g vmail -u 5000 vmail -d /var/mail/vmail -m


####################################################################
#                            POSTFIX                               #
####################################################################
# Konfiguracijske datoteke preko kojih Postfix čita korisnike iz MariaDB
mkdir -p /etc/postfix/sql

cat <<EOT > /etc/postfix/sql/mysql_virtual_domains_maps.cf
user = mailuser
password = $DB_MAIL_LOZINKA
hosts = 127.0.0.1
dbname = servermail
query = SELECT name FROM virtual_domains WHERE name='%s'
EOT

cat <<EOT > /etc/postfix/sql/mysql_virtual_mailbox_maps.cf
user = mailuser
password = $DB_MAIL_LOZINKA
hosts = 127.0.0.1
dbname = servermail
query = SELECT 1 FROM virtual_users WHERE email='%s'
EOT

cat <<EOT > /etc/postfix/sql/mysql_virtual_alias_maps.cf
user = mailuser
password = $DB_MAIL_LOZINKA
hosts = 127.0.0.1
dbname = servermail
query = SELECT destination FROM virtual_aliases WHERE source='%s'
EOT

# Glavna Postfix konfiguracija prilagođena virtualnim korisnicima
cat <<EOT > /etc/postfix/main.cf
myhostname = $MAILSUBDOMENA
myorigin = /etc/mailname
mydestination = localhost
relayhost = 
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
inet_protocols = all

# TLS (Self-signed za bazu, preporučuje se Let's Encrypt naknadno)
smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
smtpd_tls_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
smtpd_use_tls=yes
smtpd_tls_security_level = may
smtpd_tls_auth_only = yes

# Korištenje Dovecot-a za dostavu pošte (LMTP)
virtual_transport = lmtp:unix:private/dovecot-lmtp

# Mapiranje virtualnih domena i korisnika iz baze
virtual_mailbox_domains = mysql:/etc/postfix/sql/mysql_virtual_domains_maps.cf
virtual_mailbox_maps = mysql:/etc/postfix/sql/mysql_virtual_mailbox_maps.cf
virtual_alias_maps = mysql:/etc/postfix/sql/mysql_virtual_alias_maps.cf

# Autentifikacija za slanje pošte van servera
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination
EOT

# Aktiviraj Submission port (587) u master.cf
sed -i '/^#submission/s/^#//' /etc/postfix/master.cf
sed -i '/^#  -o syslog_name=postfix\/submission/s/^#//' /etc/postfix/master.cf
sed -i '/^#  -o smtpd_tls_security_level=encrypt/s/^#//' /etc/postfix/master.cf
sed -i '/^#  -o smtpd_sasl_auth_enable=yes/s/^#//' /etc/postfix/master.cf

systemctl restart postfix


####################################################################
#                            DOVECOT                               #
####################################################################
sed -i 's/#protocols = imap pop3 lmtp/protocols = imap pop3 lmtp/' /etc/dovecot/dovecot.conf

# Konfiguracija lokacije virtualnih pretinaca pod vmail korisnikom
cat <<EOT > /etc/dovecot/conf.d/10-mail.conf
mail_location = maildir:/var/mail/vmail/%d/%n/Maildir
namespace inbox {
  inbox = yes
}
mail_privileged_group = vmail
EOT

# Autentifikacija preko MySQL-a
cat <<EOT > /etc/dovecot/conf.d/10-auth.conf
disable_plaintext_auth = yes
auth_mechanisms = plain login
!include auth-sql.conf.ext
EOT

cat <<EOT > /etc/dovecot/conf.d/auth-sql.conf.ext
passdb {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}
userdb {
  driver = static
  args = uid=vmail gid=vmail home=/var/mail/vmail/%d/%n
}
EOT

cat <<EOT > /etc/dovecot/dovecot-sql.conf.ext
driver = mysql
connect = host=127.0.0.1 dbname=servermail user=mailuser password=$DB_MAIL_LOZINKA
default_pass_scheme = SHA512-CRYPT
password_query = SELECT email as user, password FROM virtual_users WHERE email='%u';
EOT

# Sockets za Postfix (Dostava pošte i SASL provjera)
cat <<EOT > /etc/dovecot/conf.d/10-master.conf
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0660
    user = postfix
    group = postfix
  }
}
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
EOT

chown -R vmail:vmail /var/mail/vmail
systemctl restart dovecot


####################################################################
#                           OPENDKIM                               #
####################################################################
cat <<EOT > /etc/opendkim.conf
Syslog                  yes
RequiredHeaders         yes
UMask                   002
Domain                  $DOMENA
Selector                default
KeyFile                 /etc/dkim.key
OversignHeaders         From
Socket                  local:/var/spool/postfix/opendkim/opendkim.sock
EOT

mkdir -p /var/spool/postfix/opendkim
chown opendkim:opendkim /var/spool/postfix/opendkim

opendkim-genkey -b 2048 -d $DOMENA -s default
mv default.private /etc/dkim.key
chown opendkim:opendkim /etc/dkim.key

cat <<EOT >> /etc/postfix/main.cf
milter_protocol = 6
milter_default_action = accept
smtpd_milters = local:opendkim/opendkim.sock
non_smtpd_milters = local:opendkim/opendkim.sock
EOT

systemctl restart opendkim
systemctl restart postfix


####################################################################
#                           ROUNDCUBE                              #
####################################################################
# Preuzimanje stabilne inačice Roundcube klijenta
cd /tmp
wget https://github.com/roundcube/roundcubemail/releases/download/1.6.6/roundcubemail-1.6.6-complete.tar.gz
tar -xzvf roundcubemail-1.6.6-complete.tar.gz

# Premještanje u web direktorij namijenjen za mail
mkdir -p /var/www/roundcube
mv roundcubemail-1.6.6/* /var/www/roundcube/
rm -rf roundcubemail-1.6.6*

# Postavljanje baze podataka za potrebe Roundcube-a
mariadb -e "CREATE DATABASE roundcube DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mariadb -e "GRANT ALL PRIVILEGES ON roundcube.* TO 'roundcubeuser'@'localhost' IDENTIFIED BY '$DB_MAIL_LOZINKA';"
mariadb roundcube < /var/www/roundcube/SQL/mysql.initial.sql

# Kreiranje osnovne konfiguracije Roundcube-a
cat <<EOT > /var/www/roundcube/config/config.inc.php
<?php
\$config['db_dsnw'] = 'mysql://roundcubeuser:$DB_MAIL_LOZINKA@localhost/roundcube';
\$config['imap_host'] = 'localhost:143';
\$config['smtp_host'] = 'localhost:587';
\$config['smtp_user'] = '%u';
\$config['smtp_pass'] = '%p';
\$config['support_url'] = '';
\$config['plugins'] = array('archive', 'zipdownload');
\$config['des_key'] = '$(openssl rand -base64 24)';
EOT

# Dozvole za Apache poslužitelj
chown -R www-data:www-data /var/www/roundcube

# Kreiranje Apache VirtualHost-a za mail.$DOMENA
cat <<EOT > /etc/apache2/sites-available/mail.conf
<VirtualHost *:80>
    ServerName $MAILSUBDOMENA
    DocumentRoot /var/www/roundcube
    
    <Directory /var/www/roundcube>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/roundcube_error.log
    CustomLog \${APACHE_LOG_DIR}/roundcube_access.log combined
</VirtualHost>
EOT

a2ensite mail.conf
systemctl restart apache2


####################################################################
#                           FIREWALL                               #
####################################################################
ufw allow 25/tcp
ufw allow 587/tcp
ufw allow 143/tcp
ufw allow 993/tcp
ufw allow 80/tcp
ufw --force reload


####################################################################
#                    ISPIS DNS ZAPISA ZA KORISNIKA                 #
####################################################################

DKIM_KLJUC=$(awk -F'"' '{print $2$4}' default.txt)

cat << EOF
====================================================================
      INSTALACIJA WEBMAIL SUSTAVA JE ZAVRŠENA NA PODDOMENI
      Webmail URL: http://$MAILSUBDOMENA
====================================================================

Kako bi mailovi zapravo radili i ne bi odlazili u SPAM, MORATE
podesiti sljedeće DNS zapise kod Vašeg registrar-a (Cloudflare, i sl.):

1. A ZAPIS (Usmjeravanje mail poddomene na ovaj server):
   Tip: A  | Naziv: mail | Vrijednost: $IP_SERVERA

2. MX ZAPIS (Govori svijetu koji server prima poštu za Vašu domenu):
   Tip: MX | Naziv: @    | Vrijednost: $MAILSUBDOMENA | Prioritet: 10

3. SPF ZAPIS (Autorizira ovaj server da smije slati mailove u ime domene):
   Tip: TXT | Naziv: @    | Vrijednost: "v=spf1 ip4:$IP_SERVERA -all"

4. DKIM ZAPIS (Digitalni potpis koji jamči da mail nije modificiran):
   Tip: TXT | Naziv: default._domainkey | Vrijednost u nastavku:
$DKIM_KLJUC

====================================================================
PODACI ZA PRVU PRIJAVU NA WEBMAIL (ROUNDCUBE):
====================================================================
URL: http://$MAILSUBDOMENA
Korisničko ime: info@$DOMENA
Lozinka: $DB_MAIL_LOZINKA

*Za kreiranje novih e-mail adresa/korisnika, izvršite SQL unos:
INSERT INTO servermail.virtual_users (domain_id, password, email) 
VALUES (1, ENCRYPT('nova_lozinka', CONCAT('\$6\$', SUBSTRING(SHA2(RAND(), 256), 1, 16))), 'korisnik@$DOMENA');
====================================================================
EOF

rm default.txt