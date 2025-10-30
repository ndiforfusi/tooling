# Make sure HTTP vhost exists (proxying to Jenkins) and HTTP works
sudo tee /etc/nginx/sites-available/jenkins.conf >/dev/null <<'EOL'
server {
    listen 80;
    listen [::]:80;
    server_name jenkins.fusisoft.com;

    location / {
        proxy_pass         http://127.0.0.1:8080;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade           $http_upgrade;
        proxy_set_header   Connection        "upgrade";
    }
}
EOL

sudo rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/ln || true
sudo ln -sfn /etc/nginx/sites-available/jenkins.conf /etc/nginx/sites-enabled/jenkins.conf
sudo nginx -t && sudo systemctl reload nginx

# Wait for Jenkins (first boot can take ~60s)
for i in {1..30}; do curl -sI http://127.0.0.1:8080/login && break; echo "Waiting for Jenkins... ($i/30)"; sleep 2; done

# Issue cert and auto-create HTTPS + redirect
sudo apt-get update -y
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d jenkins.fusisoft.com -m fusisoft@gmail.com --agree-tos --no-eff-email --non-interactive --redirect

# Auto-renew
sudo systemctl enable --now certbot.timer || true
