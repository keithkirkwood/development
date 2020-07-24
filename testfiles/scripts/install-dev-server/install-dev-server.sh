#!/bin/bash

# --------------
# Keith Kirkwood
#
# Installation script for internal development server - set configuration in the dev-server-config file
# Some minimum consideration given to security (GPG keys, generated hash salts, and WordPress settings)
#
# ***Not suitable for customer use***
# --------------

# --------------
# Utility function to check if package installed and do so
# Single parameter of package name
# --------------

check_install() {

    if [ $(dpkg-query -W -f='${Status}' $1 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
        echo "Can't find $1. Trying to install it..."
        apt-get -y install $1
    fi    
}

# --------------
# Utility function to check if repository string in apt sources and add/update if not
# Single parameter of repo string
# --------------

check_repository() {

    if [ $(cat /etc/apt/sources.list | grep -c "$1") -eq 0 ]; 
    then
	echo "Can't find $1. Adding apt repository..."
        add-apt-repository -u "deb [arch=amd64] $1"
    fi
}

# --------------
# Webmin function
# --------------

install_webmin() {

	# Add GPG key for Webmin repository
	wget -q http://www.webmin.com/jcameron-key.asc -O - | apt-key add -

	# Check for Webmin repository
	check_repository "http://download.webmin.com/download/repository sarge contrib"

	# Check and install Webmin
	check_install webmin

	# ALT
	# Install VirtualMin - using automated install script
	# wget -O /tmp/virtualmin-install.sh http://software.virtualmin.com/gpl/scripts/install.sh
	# /tmp/virtualmin-install.sh -m -h $WP_DOMAIN
	# rm /tmp/virtualmin-install.sh
	
	# Open firewall for Webmin
	# TODO: create application profile
	ufw allow 10000
}

# --------------
# Docker function
# --------------

install_docker() {

	# Add GPG key for docker CE repository
	wget -q https://download.docker.com/linux/ubuntu/gpg -O - | apt-key add -

	# Add Docker repository and update apt again
	check_repository "http://download.docker.com/linux/ubuntu bionic stable"

	# Check and install docker CE
	check_install docker-ce

	# Add users to docker user group
	usermod -aG docker keith
	#usermod -aG docker deploy

}

# --------------
# Jenkins function
# --------------

install_jenkins_local() {

	# Install java dependencies (JDK with JRE)
	check_install openjdk-8-jre-headless

	# Add GPG key for Jenkins repository 
	wget -q https://pkg.jenkins.io/debian/jenkins.io.key -O - | apt-key add -

	# Add Jenkins repository and update apt again
	check_repository "http://pkg.jenkins.io/debian-stable binary/"

	# Check and install Jenkins
	check_install jenkins
	
	# Open firewall for Jenkins
	# TODO: create application profile
	ufw allow 8080

}

# --------------
# LAMP function
# --------------

install_lamp() {

	# Check and install Apache, MySQL, and PHP with common modules
	for lamp_package in apache2 libapache2-mod-php mysql-server php php-mysql php-curl php-gd php-xml php-xmlrpc php-soap php-intl php-zip php-mbstring
	do
		check_install $lamp_package
	done
	
	# Configure MySQL (non-interactive)
	/bin/bash mysql-secure.sh $MYSQL_ROOT_PASSWORD
	
	# Open firewall for Apache
	ufw allow 'Apache Full'

}

# --------------
# Virtual host function
# --------------

create_virtual_host() {

# Delete existing directory if exists
rm -rf /var/www/$WP_DOMAIN # !!

# Create directory for virtual host and permissions (use WP domain name to define path)
export WP_PATH=/var/www/$WP_DOMAIN/html

mkdir -p $WP_PATH
chmod -R 755 /var/www/$WP_DOMAIN

# Disable virtual host if it already exists and delete file
a2dissite $WP_DOMAIN.conf
rm -f /etc/apache2/sites-available/$WP_DOMAIN.conf # !!

# Copy template virtual host file for apache 
cp ./templates/example.com.conf /etc/apache2/sites-available/$WP_DOMAIN.conf

# Edit virtual host template file to use config variables (again use WP domain as basis)
sed -i "s/\s*ServerAdmin\sadmin@example.com\s*/    ServerAdmin kkirkwoo@gmail.com/" /etc/apache2/sites-available/$WP_DOMAIN.conf
sed -i "s/\s*ServerName\sexample.com\s*/    ServerName $WP_DOMAIN/" /etc/apache2/sites-available/$WP_DOMAIN.conf
sed -i "s/\s*ServerAlias\swww.example.com\s*/    ServerAlias www.$WP_DOMAIN/" /etc/apache2/sites-available/$WP_DOMAIN.conf
sed -i "s/\s*DocumentRoot\s\/var\/www\/example.com\/html\s*/    DocumentRoot ${WP_PATH//\//\\/}/" /etc/apache2/sites-available/$WP_DOMAIN.conf
sed -i "s/\s*<Directory\s\/var\/www\/example.com\/html>s*/    <Directory ${WP_PATH//\//\\/}>/" /etc/apache2/sites-available/$WP_DOMAIN.conf
 
# Enable our new virtual host
a2ensite $WP_DOMAIN.conf

# Test the new apache config and reload configs
apache2ctl configtest
systemctl reload apache2

# Enable mod_rewrite for WP permalinks and restart apache
a2enmod rewrite
systemctl restart apache2

# Add new user using same as DB name
adduser --disabled-password --gecos "" $WP_DB_NAME
# Add group permissions for www-data (apache hosts)
usermod -aG www-data $WP_DB_NAME
}

# --------------
# WordPress function
# --------------

install_wordpress() {

	# Drop any existing database and user for WordPress
	mysql -u root -p$MYSQL_ROOT_PASSWORD <<END
DROP USER '$WP_DB_USERNAME'@'localhost';
DROP DATABASE $WP_DB_NAME;
END

	# Create database and user for WordPress
	mysql -u root -p$MYSQL_ROOT_PASSWORD <<END
CREATE USER '$WP_DB_USERNAME'@'localhost' IDENTIFIED BY '$WP_DB_PASSWORD';
CREATE DATABASE $WP_DB_NAME;
GRANT ALL ON $WP_DB_NAME.* TO '$WP_DB_USERNAME'@'localhost';
FLUSH PRIVILEGES;
END

	# Change to tmp directory
	cd /tmp

	# Get and extract WordPress 5.1.1 (en_GB)
	wget https://en-gb.wordpress.org/wordpress-5.1.1-en_GB.tar.gz
	tar xzf wordpress-5.1.1-en_GB.tar.gz
	rm wordpress-5.1.1-en_GB.tar.gz

	# ALT
	# Get and extract the latest version
	# wget https://en-gb.wordpress.org/latest-en_GB.tar.gz
	# tar xzf latest-en_GB.tar.gz
	# rm latest-en_GB.tar.gz

	# Adding dummy htaccess file
	touch /tmp/wordpress/.htaccess

	# Update sample config file with values
	cp /tmp/wordpress/wp-config-sample.php /tmp/wordpress/wp-config.php
	dos2unix /tmp/wordpress/wp-config.php # Only file with Windows line endings
	sed -i s/database_name_here/$WP_DB_NAME/ /tmp/wordpress/wp-config.php
	sed -i s/username_here/$WP_DB_USERNAME/ /tmp/wordpress/wp-config.php
	sed -i s/password_here/$WP_DB_PASSWORD/ /tmp/wordpress/wp-config.php

	# Specify filesystem access method (default but make sure)
	echo "define('FS_METHOD', 'direct');" >> /tmp/wordpress/wp-config.php

	# Do not allow editing themes and plugin files from admin portal
	echo "define('DISALLOW_FILE_EDIT', true);" >> /tmp/wordpress/wp-config.php

	# Uncomment to allow automatic updates
	# echo "add_filter( 'allow_dev_auto_core_updates', '__return_false' );" >> /tmp/wordpress/wp-config.php
	# echo "add_filter( 'allow_minor_auto_core_updates', '__return_true' );" >> /tmp/wordpress/wp-config.php
	# echo "add_filter( 'allow_major_auto_core_updates', '__return_true' );" >> /tmp/wordpress/wp-config.php
	# echo "add_filter( 'auto_update_plugin', '__return_true' );" >> /tmp/wordpress/wp-config.php
	# echo "add_filter( 'auto_update_theme', '__return_true' );" >> /tmp/wordpress/wp-config.php

	# Generate 64 characters unique strings for salts
	sed -i "s/define(\s*'AUTH_KEY',\s*'put your unique phrase here'\s*);/define( 'AUTH_KEY', '`pwgen -1 -s 64`' );/" /tmp/wordpress/wp-config.php
	sed -i "s/define(\s*'SECURE_AUTH_KEY',\s*'put your unique phrase here'\s*);/define( 'SECURE_AUTH_KEY', '`pwgen -1 -s 64`' );/" /tmp/wordpress/wp-config.php
	sed -i "s/define(\s*'LOGGED_IN_KEY',\s*'put your unique phrase here'\s*);/define( 'LOGGED_IN_KEY', '`pwgen -1 -s 64`' );/" /tmp/wordpress/wp-config.php
	sed -i "s/define(\s*'NONCE_KEY',\s*'put your unique phrase here'\s*);/define( 'NONCE_KEY', '`pwgen -1 -s 64`' );/" /tmp/wordpress/wp-config.php
	sed -i "s/define(\s*'AUTH_SALT',\s*'put your unique phrase here'\s*);/define( 'AUTH_SALT', '`pwgen -1 -s 64`' );/" /tmp/wordpress/wp-config.php
	sed -i "s/define(\s*'SECURE_AUTH_SALT',\s*'put your unique phrase here'\s*);/define( 'SECURE_AUTH_SALT', '`pwgen -1 -s 64`' );/" /tmp/wordpress/wp-config.php
	sed -i "s/define(\s*'LOGGED_IN_SALT',\s*'put your unique phrase here'\s*);/define( 'LOGGED_IN_SALT', '`pwgen -1 -s 64`' );/" /tmp/wordpress/wp-config.php
	sed -i "s/define(\s*'NONCE_SALT',\s*'put your unique phrase here'\s*);/define( 'NONCE_SALT', '`pwgen -1 -s 64`' );/" /tmp/wordpress/wp-config.php

	# ALT
	# Get unique salts from WP API and update config file
	# curl -s https://api.wordpress.org/secret-key/1.1/salt/

	# Copy all temp files to configured WP_PATH
	cp -a /tmp/wordpress/. $WP_PATH
	rm -rf /tmp/wordpress # !!

	# Set ownership and permissions
	chown -R www-data:www-data $WP_PATH
	find $WP_PATH -type d -exec chmod 750 {} \;
	find $WP_PATH -type f -exec chmod 640 {} \;

}

# --------------
# Delete virtual host function
# --------------

delete_virtual_host() {

# Delete existing directory if exists
rm -rf /var/www/$WP_DOMAIN # !!

# Disable virtual host if it exists and delete file
a2dissite $WP_DOMAIN.conf
rm -f /etc/apache2/sites-available/$WP_DOMAIN.conf # !!

# Test the new apache config and reload configs
apache2ctl configtest
systemctl reload apache2
 
# Delete group permissions for www-data (apache hosts)
deluser $WP_DB_NAME www-data
# Delete user using same as DB name
deluser --remove-home $WP_DB_NAME

}

# --------------
# Delete WordPress function
# --------------

delete_wordpress() {

# Drop any existing database and user for WordPress
mysql -u root -p$MYSQL_ROOT_PASSWORD <<END
DROP USER '$WP_DB_USERNAME'@'localhost';
DROP DATABASE $WP_DB_NAME;
END

}

# --------------
# Add admin user function
# --------------

add_admin_user() {

# Create user, no password for now
adduser --disabled-login --gecos "" $1

# Set temporary password and auto-expire - must specify at first login
echo "$1:temp1234" | chpasswd
chage -d 0 $1

# Add group permissions 
usermod -aG sudo $1

# Add ssh key access, copying the public key from root user
rsync --archive --chown=$1:$1 ./$1/.ssh /home/$1

# Add .gitconfig from repo 
rsync --archive --chown=$1:$1 ./$1/.gitconfig /home/$1

}

# --------------
# Main
# --------------

# Initialise flags for components to install/delete
# 0 - No; 
# 1 - Yes.

# Default all options to No
ONETIME_SETUP=0
INSTALL_WEBMIN=0
INSTALL_DOCKER=0
INSTALL_JENKINS=0
INSTALL_LAMP=0
INSTALL_WORDPRESS=0
DELETE_WORDPRESS=0

#
# Check that we are being run as root/sudo
#
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root/sudo" 1>&2
   exit 1
fi

# Function for usage string
usage() { echo "$0 usage:" && grep " .)\ #" $0; exit 0; }

# Check that there is at least one option (need to do something)
[ $# -eq 0 ] && usage

# Extract options and act on arguments
while getopts ":homdjl:w:x:" arg; do
  case $arg in
    o) # Perform one time setup 
      ONETIME_SETUP=1
      ;;
    m) # Install WebMin.
      INSTALL_WEBMIN=1
      ;;
    d) # Install Docker.
      INSTALL_DOCKER=1
      ;;
    j) # Install Jenkins (locally).
      INSTALL_JENKINS=1
      ;;
    l) # Install LAMP stack, specify config file for MySQL root password.
      CONFIG=${OPTARG}
      if [ -e $CONFIG ] 
	  then 
	    echo "Found install config $CONFIG"
		# Environment variables from config file specified
		source $CONFIG
		# Set option to install
      		INSTALL_LAMP=1
      else		
        echo "Specify a valid configuration file based on template dev-server-config."
		exit 0
      fi  

      ;;	  
    w) # Install WordPress instance, specify config file for MySQL database.
      CONFIG=${OPTARG}
      if [ -e $CONFIG ] 
	  then 
	    echo "Found install config $CONFIG"
		# Environment variables from config file specified
		source $CONFIG
		# Set option to install
		INSTALL_WORDPRESS=1
      else		
        echo "Specify a valid configuration file based on template dev-server-config."
		exit 0
      fi  
      ;;
    x) # Delete WordPress instance, specify config file for MySQL database.
      CONFIG=${OPTARG}
      if [ -e $CONFIG ] 
	  then 
	    echo "Found delete config $CONFIG"
		# Environment variables for delete from config file specified
		source $CONFIG
		# Set option to delete WordPress and virtual host
		DELETE_WORDPRESS=1
      else		
        echo "Specify a valid configuration file based on template dev-server-config."
		exit 0
      fi  
      ;;
    h | *) # Display help.
      usage
      exit 0
      ;;
  esac
done

# Check for common dependencies (if we are doing any form of package install)
if [ $INSTALL_WEBMIN -eq 1 ] || [ $INSTALL_DOCKER -eq 1 ] || [ $INSTALL_JENKINS -eq 1 ] || [ $INSTALL_LAMP -eq 1 ]
then
    # Quick update on apt
    apt-get update
    # Check and install script deps
    for common_package in software-properties-common apt-transport-https ca-certificates wget pwgen dos2unix
    do
        check_install $common_package
    done
fi
  
# --------------
# Perform one-time setup, e.g. create admin users
# --------------

if [ $ONETIME_SETUP -eq 1 ]
then	
  add_admin_user keith

  # --------------
  # UFW (firewall)
  # --------------

  # Setup firewall to allow ssh and enable
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 'OpenSSH'
  ufw enable
fi

# --------------
# Install components if options set
# --------------

if [ $INSTALL_WEBMIN -eq 1 ] 
then
  echo "# --------------"
  echo "# Checking and installing Webmin..."
  echo "# --------------" 
  
  install_webmin
fi

if [ $INSTALL_DOCKER -eq 1 ] 
then
  echo "# --------------"
  echo "# Checking and installing Docker..."
  echo "# --------------" 
  
  install_docker
fi

if [ $INSTALL_JENKINS -eq 1 ] 
then
  echo "# --------------"
  echo "# Checking and installing Jenkins..."
  echo "# --------------" 
  
  install_jenkins_local
fi

if [ $INSTALL_LAMP -eq 1 ] 
then
  echo "# --------------"
  echo "# Checking and installing LAMP stack..."
  echo "# --------------" 
  
  install_lamp
fi

if [ $INSTALL_WORDPRESS -eq 1 ] 
then
  echo "# --------------"
  echo "# Creating virtual host (deleting existing host if present)..."
  echo "# --------------"

  create_virtual_host

  echo "# --------------"
  echo "# Checking and installing WordPress instance (deleting existing if present)..."
  echo "# --------------" 
  
  install_wordpress
fi

if [ $DELETE_WORDPRESS -eq 1 ] 
then
  echo "# --------------"
  echo "# Deleting virtual host (if present)..."
  echo "# --------------"

  delete_virtual_host

  echo "# --------------"
  echo "# Deleting WordPress instance (if present)..."
  echo "# --------------" 
  
  delete_wordpress
fi
