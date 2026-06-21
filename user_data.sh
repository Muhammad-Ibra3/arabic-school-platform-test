#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

echo "=== Bootstrap started at $(date -Is) ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get upgrade -y

# Utilities commonly needed when pulling images, managing compose files, and debugging stacks.
apt-get install -y \
  ca-certificates \
  curl \
  git \
  gnupg \
  jq \
  unzip \
  apache2-utils \
  htop \
  vim

# Docker Engine and Compose plugin (docker compose).
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" |
  tee /etc/apt/sources.list.d/docker.list >/dev/null

apt-get update -y
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

systemctl enable docker
systemctl start docker

# Allow the default login user to run docker without sudo after re-login.
usermod -aG docker ubuntu

# Workspace for future compose stacks (Chatwoot, n8n, Twenty, BookStack, Academico, Formbricks, etc.).
mkdir -p /opt/docker-apps
chown ubuntu:ubuntu /opt/docker-apps

# Shared network for multi-container / multi-stack setups later.
docker network create apps-net 2>/dev/null || true

touch /var/log/user-data-complete
echo "=== Bootstrap finished at $(date -Is) ==="
docker --version
docker compose version
