#!/bin/bash

# Script to install Postfix mail server for unixoidi.pro domain
# and create valid DKIM and SPF records
# This script:
# 1. Installs Postfix mail server
# 2. Configures Postfix for the unixoidi.pro domain
# 3. Sets up DKIM signing with OpenDKIM
# 4. Generates SPF record for the domain

# Exit on any error
set -e

# Variables
DOMAIN="unixoidi.pro"
HOSTNAME="mail.$DOMAIN"
ADMIN_EMAIL="admin@$DOMAIN"

# Function to print status messages
print_status() {
    echo "===> $1"
}

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Update system
print_status "Updating system packages"
apt update && apt upgrade -y

# Install Postfix and related packages
print_status "Installing Postfix and related packages"
debconf-set-selections <<< "postfix postfix/mailname string $HOSTNAME"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
apt install -y postfix mailutils

# Install OpenDKIM for DKIM signing
print_status "Installing OpenDKIM"
apt install -y opendkim opendkim-tools

# Configure Postfix
print_status "Configuring Postfix for $DOMAIN"
cat > /etc/postfix/main.cf <<EOF
# See /usr/share/postfix/main.cf.dist for a commented, more complete version

# Debian specific:  Specifying a file name will cause the first
# line of that file to be used as the name.  The Debian default
# is /etc/mailname.
#myorigin = /etc/mailname

smtpd_banner = \$myhostname ESMTP \$mail_name
biff = no

# appending .domain is the MUA's job.
append_dot_mydomain = no

# Uncomment the next line to generate "delayed mail" warnings
#delay_warning_time = 4h

readme_directory = no

# See http://www.postfix.org/COMPATIBILITY_README.html -- default to 2 on
# fresh installs.
compatibility_level = 2

# TLS parameters
smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
smtpd_tls_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
smtpd_tls_security_level=may

smtp_tls_CApath=/etc/ssl/certs
smtp_tls_security_level=may
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache

smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
myhostname = $HOSTNAME
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
myorigin = /etc/mailname
mydestination = $HOSTNAME, $DOMAIN, localhost.localdomain, localhost
relayhost = 
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
inet_protocols = all

# DKIM configuration
milter_default_action = accept
milter_protocol = 2
smtpd_milters = inet:localhost:12301
non_smtpd_milters = inet:localhost:12301
EOF

# Configure OpenDKIM
print_status "Configuring OpenDKIM"

# Create directory structure
mkdir -p /etc/opendkim/keys/$DOMAIN

# Configure OpenDKIM main configuration
cat > /etc/opendkim.conf <<EOF
# This is a basic configuration that can easily be adapted to suit a standard
# installation. For more advanced options, see opendkim.conf(5) and/or
# /usr/share/doc/opendkim/examples/opendkim.conf.sample.

# Log to syslog
Syslog                  yes
# Required to use local socket with MTAs that access the socket as a non-
# privileged user (e.g. Postfix)
UMask                   002

# Sign for example.com with key in /etc/dkimkeys/dkim.key using
# selector '2007' (e.g. 2007._domainkey.example.com)
Domain                  $DOMAIN
KeyFile                 /etc/opendkim/keys/$DOMAIN/mail.private
Selector                mail

# Commonly-used options; the commented-out versions show the defaults.
#Canonicalization       simple
#Mode                   sv
#SubDomains             no
#ADSPAction            continue

# Always oversign From (sign using actual From and a null From to prevent
# malicious signatures header fields (From and/or others) between the signer
# and the verifier)
OversignHeaders         From

# List domains to use for DKIM signing
SigningTable            refile:/etc/opendkim/signing.table
# Match keys and domains
KeyTable                refile:/etc/opendkim/key.table
# Hosts to ignore when verifying signatures
ExternalIgnoreList      refile:/etc/opendkim/trusted.hosts
InternalHosts           refile:/etc/opendkim/trusted.hosts
EOF

# Create signing table
echo "*@$DOMAIN mail._domainkey.$DOMAIN" > /etc/opendkim/signing.table

# Create key table
echo "mail._domainkey.$DOMAIN $DOMAIN:mail:/etc/opendkim/keys/$DOMAIN/mail.private" > /etc/opendkim/key.table

# Create trusted hosts
cat > /etc/opendkim/trusted.hosts <<EOF
127.0.0.1
localhost
$HOSTNAME
$DOMAIN
*.$DOMAIN
EOF

# Generate DKIM keys
print_status "Generating DKIM keys for $DOMAIN"
cd /etc/opendkim/keys/$DOMAIN
opendkim-genkey -b 2048 -d $DOMAIN -s mail
chown opendkim:opendkim mail.private

# Set permissions
chown -R opendkim:opendkim /etc/opendkim
chmod -R go-w /etc/opendkim

# Configure socket for OpenDKIM
mkdir -p /var/spool/postfix/opendkim
chown opendkim:postfix /var/spool/postfix/opendkim

# Configure OpenDKIM socket
sed -i 's|^#Socket.*|Socket inet:12301@localhost|' /etc/default/opendkim

# Add postfix user to opendkim group
usermod -a -G opendkim postfix

# Restart services
print_status "Restarting services"
systemctl restart opendkim
systemctl restart postfix

# Extract DKIM record
print_status "Extracting DKIM record for DNS configuration"
DKIM_RECORD=$(cat /etc/opendkim/keys/$DOMAIN/mail.txt | grep -o "v=DKIM1.*")

# Generate SPF record
SPF_RECORD="v=spf1 mx a ip4:$(curl -s ifconfig.me) ~all"

# Display DNS records to add
print_status "DKIM and SPF setup complete!"
echo ""
echo "Please add the following DNS records to your domain $DOMAIN:"
echo ""
echo "DKIM Record:"
echo "mail._domainkey.$DOMAIN. IN TXT \"$DKIM_RECORD\""
echo ""
echo "SPF Record:"
echo "$DOMAIN. IN TXT \"$SPF_RECORD\""
echo ""
echo "MX Record (if not already set):"
echo "$DOMAIN. IN MX 10 $HOSTNAME."
echo ""
echo "A Record (if not already set):"
echo "$HOSTNAME. IN A $(curl -s ifconfig.me)"
echo ""
print_status "Postfix installation and configuration completed successfully!"
print_status "Mail server is set up for domain: $DOMAIN"
