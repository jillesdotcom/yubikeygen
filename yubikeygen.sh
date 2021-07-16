#!/bin/bash

echo
echo -e '\e[1;32mGPG Keygen v0.99 (2021-07-16) - by Jilles Groenendijk\e[0m'
echo WARNING: This script is work in progress, use at your own risk!

echo "Run this script on a live boot such as the ArchLinux ISO"
echo "Requires a Yubikey with Firmware >=5.2.3 because of EC25519 usage"
echo
echo "WARNING THIS WILL DESTROY YOUR CURRENT GPG SETUP!"

echo
echo -n "TYPE AGREE TO CONTINUE: "
read agree

if [ ! "$agree" == "AGREE" ];then
  exit
fi

while [ ! "${correct^^}" == "Y" ];do
  # Full username
  echo
  echo -n "Please enter your full name: "
  read fullname

  # Email address
  echo
  echo -n "Please enter your email address: "
  read email

  echo
  echo -n "Correct [Y/N/Q]: "
  read correct
  
  if [ "${correct^^}" == "Q" ];then
     exit
  fi
done

echo
echo -e '[\e[1;37m*\e[0m] \e[1;32mRemove old instances\e[0m'
tar -cvzf ~/$(date +%Y%m%d%H%M).tgz ~/.gnupg >/dev/null 2>&1
rm -rf ~/.gnupg
rm -rf /dev/shm/.* 
rm -rf /dev/shm/* 

echo -e '[\e[1;37m*\e[0m] \e[1;32mSet GNUPG homedir to shared memory\e[0m'

export GNUPGHOME=/dev/shm/.gnupg
export GPG_TTY=$(tty)
export SSH_AGENT_PID=""
export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)

echo -e '[\e[1;37m*\e[0m] \e[1;32mCreate GPG homedir in share memory\e[0m'
mkdir ${GNUPGHOME}
chmod 700 ${GNUPGHOME}

echo -e '[\e[1;37m*\e[0m] \e[1;32mCreate GPG passphrase\e[0m'
dd if=/dev/urandom bs=1M count=1 2>/dev/null| tr -dc '[:print:]'|cut -c-64>${GNUPGHOME}/passphrase

echo -e '[\e[1;37m*\e[0m] \e[1;32mCreate LUKS password\e[0m'
lukspwd=$(dd if=/dev/urandom bs=1M count=1 2>/dev/null| base64| tr -d '\n' | cut -c -100)

echo -e '[\e[1;37m*\e[0m] \e[1;32mCreate Master/Certification key\e[0m'
gpg --batch --pinentry-mode loopback --passphrase-file ${GNUPGHOME}/passphrase --quick-gen-key "${fullname} <${email}>" ed25519 cert 2>&1|sed 's/^/    /'
masterkey=$(ls ${GNUPGHOME}/openpgp-revocs.d/|cut -d\. -f1)

echo -e '[\e[1;37m*\e[0m] \e[1;32mCreate encryption key\e[0m'
gpg --batch --pinentry-mode loopback --passphrase-file ${GNUPGHOME}/passphrase --quick-add-key $masterkey cv25519 encr 2y

echo -e '[\e[1;37m*\e[0m] \e[1;32mCreate signing key\e[0m'
gpg --batch --pinentry-mode loopback --passphrase-file ${GNUPGHOME}/passphrase --quick-add-key $masterkey ed25519 sign 2y

echo -e '[\e[1;37m*\e[0m] \e[1;32mCreate authentication key\e[0m'
gpg --batch --pinentry-mode loopback --passphrase-file ${GNUPGHOME}/passphrase --quick-add-key $masterkey ed25519 auth 2y

echo -e '[\e[1;37m*\e[0m] \e[1;32mList all keys\e[0m'
gpg --list-keys 2>&1|sed 's/^/    /'

echo -e '[\e[1;37m*\e[0m] \e[1;32mCreate empty image\e[0m'
dd if=/dev/zero bs=1M count=30 of=/dev/shm/gpg-backup.img 2>/dev/null

echo -e '[\e[1;37m*\e[0m] \e[1;32mEncrypt image\e[0m'
echo -n "$lukspwd"|cryptsetup luksFormat /dev/shm/gpg-backup.img

echo -e '[\e[1;37m*\e[0m] \e[1;32mOpen encrypted image\e[0m'
echo -n "$lukspwd"|cryptsetup luksOpen /dev/shm/gpg-backup.img keyvault

echo -e '[\e[1;37m*\e[0m] \e[1;32mFormat encrypted image\e[0m'
mkfs.ext4 /dev/mapper/keyvault 2>&1|sed 's/^/    /'

echo -e '[\e[1;37m*\e[0m] \e[1;32mCreate mountpoint\e[0m'
rm -rf /dev/shm/keyvault
mkdir /dev/shm/keyvault

echo -e '[\e[1;37m*\e[0m] \e[1;32mMount encrypted image\e[0m'
mount /dev/mapper/keyvault /dev/shm/keyvault

echo -e '[\e[1;37m*\e[0m] \e[1;32mCopy GPG files to encrypted image\e[0m'
cp -r ${GNUPGHOME} /dev/shm/keyvault

echo -e '[\e[1;37m*\e[0m] \e[1;32mUnmount encrypted image\e[0m'
umount /dev/shm/keyvault

echo -e '[\e[1;37m*\e[0m] \e[1;32mRemove mountpoint\e[0m'
rm -rf /dev/shm/keyvault

echo -e '[\e[1;37m*\e[0m] \e[1;32mClose encrypted image\e[0m'
cryptsetup luksClose keyvault

echo -e '[\e[1;37m*\e[0m] \e[1;32mInfo encrypted image\e[0m'
(
file /dev/shm/gpg-backup.img
echo
sha1sum /dev/shm/gpg-backup.img
echo
ls -l /dev/shm/gpg-backup.img
echo
) 2>&1|sed 's/^/    /'

echo -e '[\e[1;37m*\e[0m] \e[1;32mClose encrypted image\e[0m'
rm ${GNUPGHOME}/openpgp-revocs.d/${masterkey}.rev

echo -e '[\e[1;37m*\e[0m] \e[1;32mRemove master/certification key\e[0m'
certkey=$(gpg --with-keygrip --list-key ${masterkey}|grep Keygrip | head -1 | cut -d= -f2 | tr -d \ )
rm ${GNUPGHOME}/private-keys-v1.d/${certkey}.key


echo -e '[\e[1;37m*\e[0m] \e[1;32mCreate tarbal backup\e[0m'
tar -cvzf /dev/shm/gnupg.tgz /dev/shm/.gnupg 2>&1 | sed 's/^/    /'

echo -e '[\e[1;37m*\e[0m] \e[1;32mShow restore instructions\e[0m'
echo
echo === Store this sensitive data in a password manager ===
echo 
echo "GPG Passphrase: \"$(cat ${GNUPGHOME}/passphrase)\""
echo
echo "DMCRYPT key: \"$lukspwd\""
echo
echo PUBLIC KEY:
echo ===========
gpg --armor --export ${email}
echo
echo "COPY THESE COMMANDS TO TEST THE RESTORABILITY"
echo "============================================="
echo
echo "echo -n \"$lukspwd\"|cryptsetup luksOpen /dev/shm/gpg-backup.img keyvault"
echo "mkdir /dev/shm/keyvault"
echo "mount /dev/mapper/keyvault /dev/shm/keyvault"
echo "ls -latR /dev/shm/keyvault"
echo "umount /dev/shm/keyvault"
echo "rmdir /dev/shm/keyvault"
echo "cryptsetup luksClose keyvault"
echo
echo move the /dev/shm/gnupg.tgz tarbal and the encrypted /dev/shm/gpg-backup.img to a safe place
echo
echo
echo "USE THESE COMMANDS TO CONFIGURE YUBIKEY"
echo "======================================="
cat << EOF

Install ykman
# pacman -S yubikey-manager
# pacman -S pcsc-tools
# systemctl start pcsc.service

$ gpg --card-status                          // Is your key mounted to your VM via USB?

# ykman config mode FIDO+CCID                // Disable the (autotyping) OTP
Set mode of YubiKey to FIDO+CCID? [y/N]: y
Mode set! You must remove and re-insert your YubiKey for this change to take effect.

$ gpg --card-edit                            // Reset the key

gpg/card> admin

gpg/card> factory-reset                      
Continue? (y/N) y
Really do a factory reset? (enter "yes") yes

# ykman openpgp keys set-touch enc on        // Require touch for encrypting
# ykman openpgp keys set-touch sig on        // Require touch for signing
# ykman openpgp keys set-touch aut on        // Require touch for authentication (ssh)
# ykman openpgp info

# gpg --card-edit                            // Change the default user, admin and reset pin

gpg/card> admin

gpg/card> passwd
1 - change PIN (default: 123456)
3 - change Admin PIN (defaut: 12345678)
4 - set the Reset Code

gpg/card> name                               // Change the user date
Cardholder's surname: lastname
Cardholder's given name: firstname

gpg/card> login
Login data (account name): emailaddress

gpg/card> lang
Language preferences: en

gpg/card> salutation
Salutation (M = Mr., F = Ms., or space): 

gpg/card> key-attr                           // Change the key type to EC

Changing card key attribute for: Signature key
   (2) ECC
   (1) Curve 25519

Changing card key attribute for: Encryption key
   (2) ECC
   (1) Curve 25519

Changing card key attribute for: Authentication key
   (2) ECC
   (1) Curve 25519

# gpg --list-key                             // Move the created keys to the YubiKey
# gpg --edit-key <key>

gpg> key 1 (select)
gpg> keytocard
   (2) Encryption key

gpg> key 1 (deselect)
gpg> key 2 (select)

gpg> keytocard
   (1) Signature key

gpg> key 2 (deselect)
gpg> key 3 (select)
gpg> keytocard
   (3) Authentication key

gpg> q

Save changes? (y/N) y                        // Saving the keys will remove them from the disk

# gpg --list-secret-keys

"ssb>" output indicates that the subkey is only available on the smartcard. 


========= Make sure you have copied and tested the restore of the backup at this point. ============


Quit the live boot

Mount the Yubikey to the new VM

$ gpg --card-status                          // Is your key mounted to your VM via USB?
$ vi ${email}-public.gpg                     // Create a file with your public key-attr

$ gpg --import ${email}-public.gpg           // Import the Public key as those are not on the YK
                                             // Upload your public key to keyservers
$ gpg --export ${email} | curl -T - https://keys.openpgp.org


Submit public key block via website to:
https://pgp.mit.edu/
http://keyserver.ubuntu.com/
https://pgp.surfnet.nl/
https://pgp.circl.lu/
http://pgp.rediris.es/
https://pgp.uni-mainz.de/pks-commands.html

Sending a signed and encrypted file
===================================
Ask person for public key, or download it from keyserver based on email address
$ curl http://www.textfiles.com/hacking/hacker -o secret.txt
$ vi {receipient email}-public.gpg
$ gpg --import {receipient email}-public.gpg
$ gpg --encrypt --sign --armor --recipient {receipient email} secret.txt

Encrypted file: secret.key.asc

Receiving a signed and encrypted file (secret.txt.asc)
======================================================
Ask person for public key, or download it from keyserver based on email address
$ vi {receipient email}-public.gpg
$ gpg --import {receipient email}-public.gpg
$ gpg --decrypt secret.txt.asc

Setup SSH Client
================
Put these commands in your .bashrc / .zshrc depending on the shell you run
export GPG_TTY=$(tty)
export SSH_AGENT_PID=""
export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)

Add this line to: ~/.gnupg/gpg-agent.conf
enable-ssh-support

Setup SSH Server
================
extract SSH Public key:
gpg --export-ssh-key ${email}
add this key to ~/.ssh/authorized_keys on the server
Make sure "PubkeyAuthentication yes" is in /etc/ssh/sshd_config

See also: 
=========
https://docs.fedoraproject.org/en-US/quick-docs/create-gpg-keys/
https://murgatroyd.za.net/?p=409
https://0day.work/using-a-yubikey-for-gpg-and-ssh/
https://zach.codes/ultimate-yubikey-setup-guide/
https://www.esev.com/blog/post/2015-01-pgp-ssh-key-on-yubikey-neo/
https://2fa.directory/

EOF

echo -e '[\e[1;37m*\e[0m] \e[1;32mRemove password from env and delete passphrase file\e[0m'
rm ${GNUPGHOME}/passphrase
lukespwd=""

echo -e '[\e[1;37m*\e[0m] \e[1;32mDone\e[0m'
echo

# eof

