#!/bin/bash

# ======================== 基本設定 ========================
UBUNTU_VERSION=$(lsb_release -rs)
SOURCES_LIST="/etc/apt/sources.list"
SOURCES_LIST_D="/etc/apt/sources.list.d"
BACKUP_DIR="/etc/apt/backup"
LOG_FILE="apt_repair.log"
mkdir -p "$BACKUP_DIR"
echo "$(date) - 腳本開始執行" >> "$LOG_FILE"

# ======================== 還原模式 ========================
if [[ "$1" == "--restore" ]]; then
  echo "$(date) - 進入還原模式" | tee -a "$LOG_FILE"
  [ -f "$BACKUP_DIR/sources.list.bak" ] && sudo cp "$BACKUP_DIR/sources.list.bak" "$SOURCES_LIST"
  for file in "$SOURCES_LIST_D"/*.bak; do
    original="${file%.bak}"
    sudo cp "$file" "$original"
    echo "$(date) - 還原 $(basename "$original") 成功" >> "$LOG_FILE"
  done
  echo "$(date) - 還原完成" >> "$LOG_FILE"
  exit 0
fi

# ======================== 備份 ========================
sudo cp "$SOURCES_LIST" "$BACKUP_DIR/sources.list.bak"
for file in "$SOURCES_LIST_D"/*.list; do
  [ -f "$file" ] && sudo cp "$file" "$BACKUP_DIR/$(basename "$file").bak"
done

# ======================== 添加預設來源 ========================
function ensure_sources() {
  local url="http://archive.ubuntu.com/ubuntu"
  local lines=(
    "deb $url $UBUNTU_VERSION main restricted universe multiverse"
    "deb $url $UBUNTU_VERSION-updates main restricted universe multiverse"
    "deb $url $UBUNTU_VERSION-security main restricted universe multiverse"
    "deb $url $UBUNTU_VERSION-backports main restricted universe multiverse"
  )
  for line in "${lines[@]}"; do
    if ! grep -Fxq "$line" "$SOURCES_LIST"; then
      echo "$line" | sudo tee -a "$SOURCES_LIST" > /dev/null
      echo "$(date) - 新增來源：$line" >> "$LOG_FILE"
    fi
  done
}

# ======================== 移除未使用來源檔案 ========================
function remove_unused_sources() {
  echo "$(date) - 開始檢查未使用的 .list 檔案" >> "$LOG_FILE"
  installed_packages=$(dpkg -l | awk '{print $2}')

  declare -A keyword_map
  keyword_map=(
    [docker]="docker docker-ce docker.io containerd"
    [kubernetes]="kubelet kubectl containerd cri-o"
    [gitlab]="gitlab gitlab-runner"
    [google]="chrome google-cloud-sdk"
    [nodesource]="nodejs"
    [microsoft]="dotnet-sdk aspnetcore-runtime code"
  )

  for file in "$SOURCES_LIST_D"/*.list; do
    [ ! -f "$file" ] && continue
    filename=$(basename "$file" .list)
    echo "$(date) - 檢查 $filename.list" >> "$LOG_FILE"
    matched=0

    for key in "${!keyword_map[@]}"; do
      if [[ "$filename" == *"$key"* ]]; then
        for pkg in ${keyword_map[$key]}; do
          if grep -q "^$pkg$" <<< "$installed_packages"; then
            echo "$(date) - 發現關聯套件 $pkg，保留 $file" >> "$LOG_FILE"
            matched=1
            break
          fi
        done
      fi
    done

    if [ "$matched" -eq 0 ]; then
      echo "$(date) - 無關聯套件，移除 $file（已備份）" >> "$LOG_FILE"
      sudo cp "$file" "$file.bak"
      sudo rm -f "$file"
    fi
  done
}

# ======================== 嘗試更新 ========================
function try_update() {
  echo "$(date) - 執行 apt update 測試" >> "$LOG_FILE"
  update_output=$(sudo apt update 2>&1)
  echo "$update_output" >> "$LOG_FILE"
  return $?
}

# ======================== 註解錯誤來源 ========================
function comment_broken_sources() {
  echo "$(date) - 檢查 apt update 錯誤來源" >> "$LOG_FILE"
  grep -E "(404 Not Found|Release file is not valid yet|GPG error|Temporary failure)" "$LOG_FILE" | while read -r line; do
    echo "$(date) - 錯誤：$line" >> "$LOG_FILE"

    if [[ "$line" =~ $SOURCES_LIST_D/([^[:space:]]+\.list) ]]; then
      target_file="$SOURCES_LIST_D/${BASH_REMATCH[1]}"
      [ -f "$target_file" ] && sudo sed -i 's/^[^#]/#&/' "$target_file" && \
        echo "$(date) - 註解來源：$target_file" >> "$LOG_FILE"
    elif [[ "$line" =~ (http[s]?://[^[:space:]]+) ]]; then
      bad_url="${BASH_REMATCH[1]}"
      sudo sed -i "/$bad_url/s/^[^#]/#&/" "$SOURCES_LIST"
      echo "$(date) - 註解 $SOURCES_LIST 中包含 $bad_url 的行" >> "$LOG_FILE"
    fi
  done
}

# ======================== 執行流程 ========================
ensure_sources
remove_unused_sources

try_update
if [ $? -eq 0 ]; then
  echo "$(date) - apt update 成功，腳本結束" >> "$LOG_FILE"
  exit 0
fi

comment_broken_sources

try_update
if [ $? -eq 0 ]; then
  echo "$(date) - 第二次 apt update 成功，修復完成" >> "$LOG_FILE"
  exit 0
else
  echo "$(date) - 修復失敗，請檢查 $LOG_FILE 手動介入" >> "$LOG_FILE"
  exit 1
fi
