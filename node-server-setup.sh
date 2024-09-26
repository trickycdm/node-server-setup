#!/bin/bash
# Add error handling function
function check_error {
    if [ $? -ne 0 ]; then
        echo "Error occurred in the last command. Exiting."
        exit 1
    fi
}

# Update OS check function
function checkOsSupport {
    if [ "$(lsb_release -is)" != "Ubuntu" ] && [ "$(lsb_release -is)" != "Debian" ]; then
        echo "${redText}Unsupported OS. This only works for Ubuntu and Debian.${defaultText}"
        exit 1
    fi
}

# Add firewall setup function
function setupFirewall {
    sudo ufw allow OpenSSH
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw --force enable
    check_error
}

function confirmInstall {
  printf "This will install Node and a server to run it. Do you want to contiune?\n";
  select yn in "Yes" "No"; do
      case $yn in
          Yes ) break;;
          No ) exit;;
      esac
  done
}
function prompForPort {
  read -p "Which port would you like node to listen on? " nodePort;
}
function setUpDefaults {
  sudo apt-get update;
  sudo apt-get -y install git;
}

# Modify setUpNode function
function setUpNode {
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    check_error
    sudo apt-get install -y nodejs
    check_error
    sudo apt-get install -y build-essential
    check_error
    sudo npm install -g pm2
    check_error

    echo "Node.js version: $(node --version)"
    echo "npm version: $(npm --version)"
    echo "PM2 version: $(pm2 --version)"
}

# Add PM2 startup script
function setupPM2 {
    sudo pm2 startup systemd
    check_error
    sudo pm2 save
    check_error
}

function checkForRoot {
  if [ "`whoami`" == "root" ];
  then
    printf "\e[31mLooks like you are running as root! Do you want to set up a new user?\n
    WARNING! This will copy your current ssh public key into the authorized_keys of the
    new user. It is reccomended you have a backup of this key and an alternative means of
    accessing the server should an error occur during the write.\n\n\e[39m"
      select yn in "Yes" "No"; do
          case $yn in
              Yes ) createNewUser; break;;
              No ) break;;
          esac
      done
  fi
}
function createNewUser {
  read -p "User name:" username;
  adduser $username;
  gpasswd -a $username sudo;
  rootKey=$(<~/.ssh/authorized_keys);
  if [ ! -d "/home/$username/.ssh" ]
  then
    sudo mkdir /home/$username/.ssh;
    sudo chmod 700 /home/$username/.ssh;
  fi
  cd /home/$username/.ssh;
  touch authorized_keys;
  echo $rootKey >> authorized_keys;
  chown -R $username:$username /home/$username/.ssh;
  chmod 600 authorized_keys;
}
function promtForServer {
  printf $greenText"Choose your server.\n"$defaultText;
  select yn in "Apache" "Nginx"; do
      case $yn in
          Apache ) setUpApache; break;;
          Nginx ) setUpNginx; break;;
      esac
  done
}
function setUpNginx {
  sudo apt-get -y install nginx;
  #set up the vhost $1 is the port number passed in by the original func call
  setUpNginxVhost;
}
function setUpNginxVhost {
  #this func will get 1 arg
  read -p "Domain root name (do NOT add www):" nginxDomain;
  printf "server {
      listen 80;

      server_name $nginxDomain;

      location / {
          proxy_pass http://127.0.0.1:$nodePort;
          proxy_http_version 1.1;
          proxy_set_header Upgrade \$http_upgrade;
          proxy_set_header Connection 'upgrade';
          proxy_set_header Host \$host;
          proxy_cache_bypass \$http_upgrade;
      }
  }" > "/etc/nginx/sites-available/default";
  sudo service nginx restart;
}
function setUpApache {
  sudo apt-get -y install apache2;
  sudo chmod 755 -R /var/www/;
  sudo a2enmod proxy;
  sudo a2enmod proxy_http;
  #$1 is the node port set in this script
  setUpApacheVhostProxy;
  sudo service apache2 restart;
}
function setUpApacheVhostProxy {
  subDomainPrefix="ServerAlias ";
  sitesAvailable='/etc/apache2/sites-available/';
  printf "$greenText Begin Vhost Setup\n$defaultText";
  read -p "Server admin email:" email;
  read -p "Domain root name (do NOT add www):" domain;
  printf "Do you want a subdomain?\n"
  select yn in "Yes" "No"; do
      case $yn in
          Yes ) read -p "Enter subdomin prefix: " subDomain; subDomain=$subDomainPrefix$subDomain; break;;
          No ) subDomain=""; break;;
      esac
  done

  newSiteConf="$sitesAvailable$domain.conf";
  sudo touch $newSiteConf;
  sudo printf "<VirtualHost *:80>
  ServerName $domain
  $subDomain
  ProxyRequests off
  ProxyPreserveHost On

      <Proxy *>
          Order deny,allow
          Allow from all
      </Proxy>

      <Location />
          ProxyPass http://localhost:$nodePort/
          ProxyPassReverse http://localhost:$nodePort/
      </Location>
  </VirtualHost>" > $newSiteConf;
    #Apache does not like full path when enabling a site, must just be the filename
    sudo a2ensite "$domain.conf";
    sudo service apache2 restart;
}

greenText="\e[32m";
redText="\e[31m";
defaultText="\e[39m";
nodePort=3000;

checkOsSupport;
confirmInstall;
setUpDefaults;
prompForPort;
setUpNode;
setupFirewall;
checkForRoot;
promtForServer;
exit;
