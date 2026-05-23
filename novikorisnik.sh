#!/bin/bash

####################################################################
#                        OSNOVNE VARIJABLE                         #
####################################################################
# Dohvaćanje IP adrese servera
IP_ADRESE=$(ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d '/' -f 1)
IP_SERVERA=$(echo "$IP_ADRESE" | awk 'NR==1{print $1}')

if [ -z "$IP_SERVERA" ]; then
  echo "Nije moguće dohvatiti IP adresu."
  exit 1
fi

# Kreiraj slučajni niz znakova duljine 8 (samo mala slova a-z)
KORISNIK=$(tr -dc a-z </dev/urandom | head -c 8 ; echo '')

# Generiraj lozinku duljine 16 znakova (za sudo)
LOZINKA=$(openssl rand -base64 16)

# SSH konfiguracijske putanje
KLJUC="/home/$KORISNIK/kljuc"
SSH_DIR="/home/$KORISNIK/.ssh"

# Ovdje definirajte port (promijeniti ako ne koristite defaultni 22)
PORT=22


####################################################################
#                             KORISNIK                             #
####################################################################
# Dodaj novog sistemskog korisnika bez interaktivnog traženja lozinke
adduser --disabled-password --gecos "" $KORISNIK

# Postavi korisniku lozinku (potrebna mu je za izvođenje sudo naredbi)
echo -e "$LOZINKA\n$LOZINKA" | (passwd $KORISNIK)

# Dodaj korisnika u sudo grupu za administratorske ovlasti
usermod -aG sudo $KORISNIK

# Izrada .ssh direktorija i postavljanje točnih prava (700)
mkdir -p $SSH_DIR
chmod 700 $SSH_DIR

# Napravi datoteku za autorizirane ključeve i postavi prava (600)
touch $SSH_DIR/authorized_keys
chmod 600 $SSH_DIR/authorized_keys

# Generiraj par javni/privatni ključ na putanji $KLJUC (RSA 2048 bez passphrase-a)
ssh-keygen -b 2048 -t rsa -f $KLJUC -q -N ""

# Dodaj generirani javni ključ u authorized_keys datoteku novog korisnika
cat $KLJUC.pub >> $SSH_DIR/authorized_keys

# Postavi vlasništvo nad cijelim .ssh direktorijem na novog korisnika i njegovu grupu
chown -R $KORISNIK:$KORISNIK $SSH_DIR


####################################################################
#                    ISPIS PODATAKA KORISNIKU                      #
####################################################################
clear

# Spremanje privatnog ključa u varijablu prije brisanja datoteke s diska
PRIVATNI_KLJUC=$(cat $KLJUC)

# Brisanje ključeva s diska poslužitelja radi sigurnosti (ostaju u authorized_keys)
rm $KLJUC.pub
rm $KLJUC

cat << EOF
====================================================================
          NOVI KORISNIK JE USPJEŠNO KREIRAN NA POSLUŽITELJU
====================================================================

Podaci o korisničkom računu:
Korisničko ime: $KORISNIK
Lozinka (Sudo): $LOZINKA

--------------------------------------------------------------------
PRIVATNI SSH KLJUČ (Kopirajte sadržaj ispod i spremite u datoteku 'kljuc'):
--------------------------------------------------------------------
$PRIVATNI_KLJUC

--------------------------------------------------------------------
Upute za spajanje s klijentskog računala (Linux / macOS):
--------------------------------------------------------------------
1. Spremite ključ u datoteku: nano kljuc
2. Postavite sigurnosna prava: chmod 400 kljuc
3. Povežite se naredbom:
ssh -i kljuc $KORISNIK@$IP_SERVERA -p$PORT

====================================================================
EOF