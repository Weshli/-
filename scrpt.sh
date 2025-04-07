#!/bin/bash

set -e

echo "🔄 Updating system..."
dnf update -y
dnf install -y wget curl git firewalld epel-release python3-pip nano

echo "🔥 Enabling firewalld..."
systemctl enable --now firewalld

echo "👤 Creating Prometheus user..."
useradd --no-create-home --shell /bin/false prometheus

echo "⬇️ Downloading Prometheus..."
cd /opt
PROM_VERSION="2.52.0"
wget https://github.com/prometheus/prometheus/releases/download/v$PROM_VERSION/prometheus-$PROM_VERSION.linux-amd64.tar.gz
tar -xvf prometheus-$PROM_VERSION.linux-amd64.tar.gz
mv prometheus-$PROM_VERSION.linux-amd64 /etc/prometheus
cp /etc/prometheus/prometheus /usr/local/bin/
cp /etc/prometheus/promtool /usr/local/bin/

echo "📁 Setting up Prometheus directories..."
mkdir -p /var/lib/prometheus
chown prometheus: /var/lib/prometheus

echo "📝 Creating Prometheus config..."
cat <<EOF > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
  - job_name: 'fail2ban'
    static_configs:
      - targets: ['localhost:9191']
rule_files:
  - "alert.rules.yml"
EOF

echo "📝 Creating Prometheus alert rules..."
cat <<EOF > /etc/prometheus/alert.rules.yml
groups:
- name: fail2ban_alerts
  rules:
  - alert: HighSSHLoginFailures
    expr: rate(fail2ban_failures_total[1m]) > 5
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "High rate of SSH login failures"
EOF

echo "🛠 Creating Prometheus service..."
cat <<EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \\
  --config.file=/etc/prometheus/prometheus.yml \\
  --storage.tsdb.path=/var/lib/prometheus
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo "🚀 Starting Prometheus..."
systemctl daemon-reload
systemctl enable --now prometheus

echo "⬇️ Installing Node Exporter..."
NODE_VERSION="1.7.0"
cd /opt
wget https://github.com/prometheus/node_exporter/releases/download/v$NODE_VERSION/node_exporter-$NODE_VERSION.linux-amd64.tar.gz
tar -xvf node_exporter-$NODE_VERSION.linux-amd64.tar.gz
cp node_exporter-$NODE_VERSION.linux-amd64/node_exporter /usr/local/bin/

echo "🛠 Creating Node Exporter service..."
cat <<EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo "🚀 Starting Node Exporter..."
systemctl daemon-reload
systemctl enable --now node_exporter

echo "📦 Installing Grafana..."
cat <<EOF > /etc/yum.repos.d/grafana.repo
[grafana]
name=Grafana OSS
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
EOF

dnf install grafana -y
systemctl enable --now grafana-server

echo "🔐 Installing Fail2ban..."
dnf install fail2ban -y
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

echo "🛡 Configuring Fail2ban for SSH..."
cat <<EOF >> /etc/fail2ban/jail.local

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
maxretry = 3
bantime = 3600
EOF

systemctl enable --now fail2ban

echo "📤 Installing Fail2ban Exporter..."
pip3 install fail2ban-prometheus-exporter

echo "🛠 Creating Fail2ban Exporter service..."
cat <<EOF > /etc/systemd/system/fail2ban_exporter.service
[Unit]
Description=Fail2Ban Prometheus Exporter
After=network.target

[Service]
ExecStart=/usr/local/bin/fail2ban-exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now fail2ban_exporter

echo "✅ Setup complete!"
echo "Access Prometheus: http://<your-ip>:9090"
echo "Access Grafana: http://<your-ip>:3000 (admin/admin)"
