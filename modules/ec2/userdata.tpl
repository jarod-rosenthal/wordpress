#!/bin/bash
set -xe
exec > >(tee /var/log/userdata.log) 2>&1

# AUTOMATIC WORDPRESS INSTALLER IN AWS LINUX 2023 AMI
CERT_DIR="/mnt/efs/${domain}/letsencrypt/live"
BACKUP_DIR="/mnt/efs/${domain}/letsencrypt_backup"
timestamp=$(date "+%Y-%m-%d %H:%M:%S")

echo "Script started at $timestamp"

dnf update -y

# Setup CloudWatch logs
yum install -y amazon-cloudwatch-agent
echo "CloudWatch Agent installed."

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/userdata.log",
            "log_group_name": "${domain}-userdata",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          }
        ]
      }
    }
  }
}
EOF
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

mkdir -p /mnt/efs/
# Install EFS utilities and mount the EFS
yum install -y amazon-efs-utils
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 ${efs_file_system}:/ /mnt/efs
sudo echo "${efs_file_system}:/ /mnt/efs/ nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 0 0" | sudo tee -a /etc/fstab
mkdir -p /mnt/efs/${domain}

# Install the Apache web server, mod_ssl, and PHP
dnf install -y httpd mod_ssl wget php-fpm php-mysqli php-json php php-devel php-mysqlnd > /dev/null

mv /etc/httpd/conf.d/welcome.conf /etc/httpd/conf.d/welcome.conf.bak

cat > /etc/httpd/conf.d/${domain}.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@${domain}
    DocumentRoot /mnt/efs/${domain}
    ServerName ${domain}
    ServerAlias www.${domain}
    ErrorLog logs/${domain}-error_log
    CustomLog logs/${domain}-access_log common

    <Directory /mnt/efs/${domain}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

# Check if the certificates exist in EFS
if [ -d "$CERT_DIR" ]; then
    cat >> /etc/httpd/conf.d/${domain}.conf <<EOF
<VirtualHost *:443>
    ServerAdmin webmaster@${domain}
    DocumentRoot /mnt/efs/${domain}
    ServerName ${domain}
    ServerAlias www.${domain}
    ErrorLog logs/${domain}-error_log
    CustomLog logs/${domain}-access_log common

    SSLEngine on
    SSLCertificateFile $CERT_DIR/fullchain.pem
    SSLCertificateKeyFile $CERT_DIR/privkey.pem

    <Directory /mnt/efs/${domain}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
fi

# Start the Apache web server
systemctl start httpd
systemctl enable httpd

cd /mnt/efs/${domain}

# Check if the 'skip' file exists
if [ ! -f skip ]; then
    # If the 'skip' file doesn't exist, proceed with the installation

    wget https://wordpress.org/latest.tar.gz -o /dev/null
    tar -xzf latest.tar.gz
    mv wordpress/* .
    rm -f latest.tar.gz

    # First, copy the sample config to the actual config
    cp wp-config-sample.php wp-config.php

    # Now, modify the wp-config.php
    curl -s https://api.wordpress.org/secret-key/1.1/salt/ > /tmp/wp_salts
    sed -i "/define('AUTH_KEY'/,/define('NONCE_SALT'/d" wp-config.php
    cat /tmp/wp_salts >> wp-config.php
    rm /tmp/wp_salts

    stripped_domain=$(echo "${domain}" | sed 's/\.com//')
    sed -i "s/database_name_here/${db_name}/g" wp-config.php
    sed -i "s/username_here/${db_user}/g" wp-config.php
    sed -i "s/password_here/${db_password}/g" wp-config.php
    sed -i "s/localhost/${db_endpoint}/g" wp-config.php
    sed -i "s/\$table_prefix\s*=\s*'wp_';/\$table_prefix = '$${stripped_domain}_';/g" wp-config.php

    # Create the 'skip' file to indicate that the installation has been done
    touch skip
else
    echo "WordPress is already installed. Skipping installation."
fi

# Install Certbot and configure SSL
dnf install -y augeas-libs > /dev/null
python3 -m venv /opt/certbot/ 
/opt/certbot/bin/pip install --upgrade pip > /dev/null
/opt/certbot/bin/pip install certbot-apache > /dev/null
ln -s /opt/certbot/bin/certbot /usr/bin/certbot

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Check if the certificates exist in EFS
if [ ! -d "$CERT_DIR" ]; then
    # If not, then run certbot to obtain the certificates
    
    # Check if dry_run is set to true
    if [ "${dry_run}" == "true" ]; then
        # Dry run for certbot
        certbot certonly --apache -d ${domain} -m ${email} --agree-tos --no-eff-email --dry-run
    else
        # Actual run for certbot
        certbot --apache -d ${domain} -m ${email} --agree-tos --no-eff-email
    fi
    
    # Backup existing certificates before copying new ones
    if [ -d "/etc/letsencrypt/live/${domain}" ]; then
        TIMESTAMP=$(date "+%Y%m%d%H%M%S")
        mkdir -p "$BACKUP_DIR/$TIMESTAMP"  # Ensure the timestamped directory is created
        cp -Lr /etc/letsencrypt/live/${domain}/* "$BACKUP_DIR/$TIMESTAMP/"
        
        # Copy the certificates to EFS
        mkdir -p "$CERT_DIR"
        cp -Lr /etc/letsencrypt/live/${domain}/* "$CERT_DIR/"
    fi
else
    # If the certificates exist in EFS, ensure they are available to the new instance
    
    mkdir -p /etc/letsencrypt/live/${domain}
    ln -sf "$CERT_DIR/fullchain.pem" /etc/letsencrypt/live/${domain}/fullchain.pem
    ln -sf "$CERT_DIR/privkey.pem" /etc/letsencrypt/live/${domain}/privkey.pem
fi

systemctl reload httpd

# Certbot cron job
echo "0 0,12 * * * root python -c 'import random; import time; time.sleep(random.random() * 3600)' && certbot renew --quiet --post-hook 'systemctl reload httpd'" | sudo tee -a /etc/crontab > /dev/null

# Install additional PHP extensions and restart services
dnf install php-mbstring php-xml -y > /dev/null

cat > /mnt/efs/${domain}/health.php <<EOF
<?php
// Check database connectivity
$mysqli = new mysqli('${db_endpoint}', '${db_user}', '${db_password}', '${db_name}');

if ($mysqli->connect_error) {
    http_response_code(500);
    echo "Database connection failed: " . $mysqli->connect_error;
    exit;
}

// Check EFS health by writing and reading a file
$efs_test_file = '/mnt/efs/${domain}/efs_test.txt';
file_put_contents($efs_test_file, 'test content');

if (file_get_contents($efs_test_file) !== 'test content') {
    http_response_code(500);
    echo "EFS check failed: Unable to read/write to EFS.";
    exit;
}

unlink($efs_test_file);

http_response_code(200);
echo "All systems operational";
?>
EOF

chown -R ec2-user:apache /mnt/efs/${domain}
find /mnt/efs/${domain} -type d -exec chmod 755 {} \;
find /mnt/efs/${domain} -type f -exec chmod 644 {} \;

systemctl restart httpd
systemctl restart php-fpm

if [ -f "/var/log/letsencrypt/letsencrypt.log" ]; then
    cat /var/log/letsencrypt/letsencrypt.log >> /var/log/userdata.log
else
    echo "File /var/log/letsencrypt/letsencrypt.log does not exist." >> /var/log/userdata.log
fi

echo "PublicIp: $(curl ifconfig.me) username: ${db_user} password: ${db_password}" >> /var/log/userdata.log
echo "Installation Complete: $(date "+%Y-%m-%d %H:%M:%S")" >> /var/log/userdata.log
