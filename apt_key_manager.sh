#!/bin/bash

LOG_FILE="apt_key_fix.log"
echo "$(date) - 金鑰修復腳本啟動" >> "$LOG_FILE"

# ======================== 自動修補 NO_PUBKEY ========================
function fix_missing_pubkeys() {
  echo "$(date) - 掃描 NO_PUBKEY 錯誤" >> "$LOG_FILE"
  sudo apt update 2>&1 | tee -a "$LOG_FILE" | grep "NO_PUBKEY" | awk '{print $NF}' | sort -u | while read -r key; do
    echo "$(date) - 嘗試導入缺失金鑰：$key" >> "$LOG_FILE"
    sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys "$key" >> "$LOG_FILE" 2>&1
  done
}

# ======================== 常見來源金鑰更新 ========================
function update_known_keys() {
  echo "$(date) - 檢查常見來源金鑰" >> "$LOG_FILE"

  # Docker 金鑰
  if [ -f "/etc/apt/sources.list.d/docker.list" ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "$(date) - 已更新 Docker 金鑰" >> "$LOG_FILE"
  fi

  # GitLab 金鑰
  if [ -f "/etc/apt/sources.list.d/gitlab_gitlab-ce.list" ]; then
    curl -fsSL https://packages.gitlab.com/gitlab/gitlab-ce/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/gitlab-keyring.gpg
    echo "$(date) - 已更新 GitLab 金鑰" >> "$LOG_FILE"
  fi

  # Google 金鑰
  if [ -f "/etc/apt/sources.list.d/google-chrome.list" ]; then
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | sudo tee /usr/share/keyrings/google-linux-signing-key.gpg > /dev/null
    echo "$(date) - 已更新 Google 金鑰" >> "$LOG_FILE"
  fi
}

# ======================== 執行邏輯 ========================
fix_missing_pubkeys
update_known_keys
echo "$(date) - 金鑰處理完成" >> "$LOG_FILE"
