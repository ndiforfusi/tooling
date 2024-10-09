#!/bin/bash

# Update the package repository and install necessary dependencies
sudo apt update -y
sudo apt install -y wget unzip

# Install Amazon Corretto 17 (Java 17)
sudo apt install openjdk-17-jdk -y

# Install Maven 3.9.9
LATEST_MAVEN_VERSION=3.9.9
wget https://dlcdn.apache.org/maven/maven-3/${LATEST_MAVEN_VERSION}/binaries/apache-maven-${LATEST_MAVEN_VERSION}-bin.zip
unzip -o apache-maven-${LATEST_MAVEN_VERSION}-bin.zip -d /opt
sudo ln -sfn /opt/apache-maven-${LATEST_MAVEN_VERSION} /opt/maven

# Set up Maven environment variables globally
echo 'export M2_HOME=/opt/maven' | sudo tee -a /etc/profile.d/maven.sh
echo 'export PATH=$M2_HOME/bin:$PATH' | sudo tee -a /etc/profile.d/maven.sh

# Add environment variables for root user
echo 'export M2_HOME=/opt/maven' | sudo tee -a /root/.bashrc
echo 'export PATH=$M2_HOME/bin:$PATH' | sudo tee -a /root/.bashrc

# Source the profile script to load the new environment variables
source /etc/profile.d/maven.sh

# Verify Maven installation
echo "Verifying Maven installation..."
/opt/maven/bin/mvn -version

# Download and install SonarQube 10.5.1.90531
# Install Maven 3.9.6
LATEST_MAVEN_VERSION=3.9.6
wget https://dlcdn.apache.org/maven/maven-3/${LATEST_MAVEN_VERSION}/binaries/apache-maven-${LATEST_MAVEN_VERSION}-bin.zip
unzip -o apache-maven-${LATEST_MAVEN_VERSION}-bin.zip -d /opt
sudo ln -sfn /opt/apache-maven-${LATEST_MAVEN_VERSION} /opt/maven

unzip -o sonarqube-${SONARQUBE_VERSION}.zip -d /opt
sudo mv /opt/sonarqube-${SONARQUBE_VERSION} /opt/sonarqube

# Ensure the binaries have executable permissions
sudo chmod +x /opt/maven/bin/mvn
sudo chmod +x /opt/sonarqube/bin/linux-x86-64/sonar.sh

# Create sonarqube group and user if not exists
if ! getent group ddsonar > /dev/null; then
    sudo groupadd ddsonar
fi

if ! id -u ddsonar > /dev/null 2>&1; then
    sudo useradd -g ddsonar ddsonar
fi

sudo chown -R ddsonar:ddsonar /opt/sonarqube

# Install and use PostgreSQL


# Install PostgreSQL repository
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

# Install PostgreSQL
sudo apt update -y
sudo apt install postgresql postgresql-contrib -y

# Initialize the PostgreSQL database
sudo postgresql-setup initdb

# Enable and start PostgreSQL service
sudo systemctl enable postgresql
sudo systemctl start postgresql

# Set PostgreSQL to start on boot
sudo systemctl enable postgresql

# Verify PostgreSQL service status
sudo systemctl status postgresql

echo "PostgreSQL installation and setup completed."

#Create a database user named ddsonar.
sudo -i -u postgres
createuser ddsonar
psql
ALTER USER ddsonar WITH ENCRYPTED password 'Team@123';
CREATE DATABASE ddsonarqube OWNER ddsonar;
GRANT ALL PRIVILEGES ON DATABASE ddsonarqube to ddsonar;
\q
Exit

# # Configure SonarQube to use PostgreSQL
# sudo bash -c "cat <<EOF > /opt/sonarqube/conf/sonar.properties
# sonar.jdbc.username=ddsonar
# sonar.jdbc.password=Team@123
# sonar.jdbc.url=jdbc:postgresql://localhost:5432/ddsonarqube
# EOF"

# Set up SonarQube as a service
echo -e "[Unit]
Description=SonarQube service
After=syslog.target network.target

[Service]
Description=SonarQube service
After=syslog.target network.target
[Service]
Type=forking
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
User=ddsonar
Group=ddsonar
Restart=always
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/sonar.service

# Reload systemd and start SonarQube service
sudo systemctl daemon-reload
sudo systemctl enable sonar.service
sudo systemctl start sonar.service

# Check the status of the SonarQube service
sudo systemctl status sonar.service


#!/bin/bash

# Variables
DOMAIN="sonarqube.dominionsystem.org"
EMAIL="fusisoft@gmail.com"  # Change to your email for Let's Encrypt notifications

# Update package list and install dependencies
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx

# Start and enable NGINX service
sudo systemctl start nginx
sudo systemctl enable nginx

# Allow NGINX in firewall
sudo ufw allow 'Nginx Full'

# Create an NGINX server block configuration for the domain
sudo bash -c "cat > /etc/nginx/sites-available/$DOMAIN <<EOL
server {
    listen 80;
    server_name $DOMAIN;
    
    location / {
        proxy_pass http://127.0.0.1:9000; # Assuming SonarQube runs on port 9000
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ~ /.well-known/acme-challenge {
        allow all;
    }
}
EOL"

# Enable the new site by creating a symbolic link
sudo ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

# Test NGINX configuration
sudo nginx -t

# Reload NGINX to apply the changes
sudo systemctl reload nginx

# Obtain a Let's Encrypt SSL certificate for the domain using Certbot
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $EMAIL --redirect

# Verify Certbot automatic renewal process
sudo systemctl status certbot.timer
