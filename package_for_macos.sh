#!/bin/bash
# filepath: /home/lq/projects/liw/Flowise3.0/package_for_macos.sh

set -e

echo "🚀 开始打包 Flowise 3.0 for macOS..."

# 配置变量
FLOWISE_DIR="/home/lq/projects/liw/Flowise3.0"
FLOWISE_DATA_DIR="$HOME/.flowise"
PACKAGE_NAME="flowise-3.0-macos-$(date +%Y%m%d-%H%M%S)"
PACKAGE_DIR="/tmp/$PACKAGE_NAME"
ARCHIVE_NAME="$PACKAGE_NAME.tar.gz"

# 创建打包目录
echo "📁 创建打包目录..."
mkdir -p "$PACKAGE_DIR"
cd "$FLOWISE_DIR"

# 1. 构建项目
echo "🔨 构建项目..."
pnpm install --frozen-lockfile
pnpm run build

# 2. 创建生产环境包结构
echo "📦 创建生产环境包..."
mkdir -p "$PACKAGE_DIR/flowise"
mkdir -p "$PACKAGE_DIR/data"
mkdir -p "$PACKAGE_DIR/scripts"
mkdir -p "$PACKAGE_DIR/config"

# 3. 复制编译后的文件
echo "📋 复制编译后的文件..."

# 复制 server dist 文件
if [ -d "packages/server/dist" ]; then
    cp -r packages/server/dist "$PACKAGE_DIR/flowise/server-dist"
    echo "✅ 复制 server dist 文件"
else
    echo "❌ packages/server/dist 不存在"
    exit 1
fi

# 复制 components dist 文件
if [ -d "packages/components/dist" ]; then
    cp -r packages/components/dist "$PACKAGE_DIR/flowise/components-dist"
    echo "✅ 复制 components dist 文件"
else
    echo "❌ packages/components/dist 不存在"
    exit 1
fi

# 复制 UI 文件 - 检查 build 或 dist 目录
if [ -d "packages/ui/build" ]; then
    cp -r packages/ui/build "$PACKAGE_DIR/flowise/ui-dist"
    echo "✅ 复制 UI build 文件 (build -> ui-dist)"
elif [ -d "packages/ui/dist" ]; then
    cp -r packages/ui/dist "$PACKAGE_DIR/flowise/ui-dist"
    echo "✅ 复制 UI dist 文件"
else
    echo "❌ packages/ui/build 和 packages/ui/dist 都不存在"
    echo "🔍 检查 UI 目录内容："
    ls -la packages/ui/ || echo "UI 目录不存在"
    exit 1
fi

# 复制必要的配置文件
cp package.json "$PACKAGE_DIR/flowise/"
cp pnpm-workspace.yaml "$PACKAGE_DIR/flowise/"

# 复制 packages 的 package.json 和必要文件
mkdir -p "$PACKAGE_DIR/flowise/packages/server"
mkdir -p "$PACKAGE_DIR/flowise/packages/components"
mkdir -p "$PACKAGE_DIR/flowise/packages/ui"

cp packages/server/package.json "$PACKAGE_DIR/flowise/packages/server/"
cp packages/components/package.json "$PACKAGE_DIR/flowise/packages/components/"
cp packages/ui/package.json "$PACKAGE_DIR/flowise/packages/ui/"

# 复制静态资源
echo "📁 复制静态资源..."

# UI 静态资源
if [ -d "packages/ui/public" ]; then
    cp -r packages/ui/public "$PACKAGE_DIR/flowise/packages/ui/"
    echo "✅ 复制 UI public 文件"
fi

# Server 静态资源
if [ -d "packages/server/public" ]; then
    cp -r packages/server/public "$PACKAGE_DIR/flowise/packages/server/"
    echo "✅ 复制 server public 文件"
fi

# 复制组件的静态资源 (图标等)
echo "🖼️  复制组件图标资源..."
if [ -d "packages/components/nodes" ]; then
    # 创建目标目录结构
    mkdir -p "$PACKAGE_DIR/flowise/packages/components/nodes"
    
    # 查找并复制所有图标文件
    find packages/components/nodes -type f \( -name "*.svg" -o -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.ico" \) | while read file; do
        # 获取相对路径
        rel_path="${file#packages/components/}"
        dest_dir="$PACKAGE_DIR/flowise/packages/components/$(dirname "$rel_path")"
        mkdir -p "$dest_dir"
        cp "$file" "$dest_dir/"
    done
    echo "✅ 复制组件图标文件"
fi

# 复制 credentials 相关文件（如果存在）
if [ -d "packages/components/credentials" ]; then
    cp -r packages/components/credentials "$PACKAGE_DIR/flowise/packages/components/"
    echo "✅ 复制 credentials 文件"
fi

# 4. 复制用户数据
echo "💾 复制用户数据..."
if [ -d "$FLOWISE_DATA_DIR" ]; then
    cp -r "$FLOWISE_DATA_DIR"/* "$PACKAGE_DIR/data/" 2>/dev/null || echo "⚠️  用户数据目录为空或不存在"
    echo "✅ 复制用户数据"
else
    echo "⚠️  用户数据目录 $FLOWISE_DATA_DIR 不存在"
    mkdir -p "$PACKAGE_DIR/data"
fi

# 5. 创建代理配置文件
echo "🌐 创建代理配置文件..."
cat > "$PACKAGE_DIR/config/proxy.conf" << 'EOF'
# Flowise 代理配置
# 取消注释并修改以下配置来启用代理

# HTTP 代理
# export HTTP_PROXY=http://127.0.0.1:7890
# export http_proxy=http://127.0.0.1:7890

# HTTPS 代理
# export HTTPS_PROXY=http://127.0.0.1:7890
# export https_proxy=http://127.0.0.1:7890

# SOCKS 代理
# export SOCKS_PROXY=socks://127.0.0.1:7891

# Global Agent (推荐用于 Node.js 应用)
# export GLOBAL_AGENT_HTTP_PROXY=http://127.0.0.1:7890
# export GLOBAL_AGENT_HTTPS_PROXY=http://127.0.0.1:7890
# export GLOBAL_AGENT_SOCKS_PROXY=socks://127.0.0.1:7891

# 不走代理的域名 (逗号分隔)
# export NO_PROXY=localhost,127.0.0.1,.local,.internal

# Flowise 特定代理设置
# export FLOWISE_PROXY_HTTP=http://127.0.0.1:7890
# export FLOWISE_PROXY_HTTPS=http://127.0.0.1:7890
EOF

# 6. 创建启动脚本
echo "📜 创建启动脚本..."

# macOS 启动脚本
cat > "$PACKAGE_DIR/scripts/start-macos.sh" << 'EOF'
#!/bin/bash

# Flowise 3.0 macOS 启动脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOWISE_ROOT="$(dirname "$SCRIPT_DIR")"
FLOWISE_DATA_DIR="$HOME/.flowise"
CONFIG_DIR="$FLOWISE_ROOT/config"

echo "🚀 启动 Flowise 3.0..."
echo "📁 项目目录: $FLOWISE_ROOT"
echo "💾 数据目录: $FLOWISE_DATA_DIR"

# 激活 Node.js 18 (通过 nvm)
echo "🔧 激活 Node.js 18..."
if [ -s "$HOME/.nvm/nvm.sh" ]; then
    source "$HOME/.nvm/nvm.sh"
    nvm use 18 || {
        echo "⚠️  Node.js 18 未安装，尝试安装..."
        nvm install 18
        nvm use 18
    }
elif command -v fnm &> /dev/null; then
    fnm use 18 || {
        echo "⚠️  Node.js 18 未安装，尝试安装..."
        fnm install 18
        fnm use 18
    }
else
    echo "⚠️  nvm 或 fnm 未安装，使用系统 Node.js"
fi

# 加载代理配置
if [ -f "$CONFIG_DIR/proxy.conf" ]; then
    echo "🌐 加载代理配置..."
    source "$CONFIG_DIR/proxy.conf"
    
    # 显示代理状态
    if [ ! -z "$GLOBAL_AGENT_HTTPS_PROXY" ]; then
        echo "🔗 HTTPS 代理: $GLOBAL_AGENT_HTTPS_PROXY"
    fi
    if [ ! -z "$GLOBAL_AGENT_HTTP_PROXY" ]; then
        echo "🔗 HTTP 代理: $GLOBAL_AGENT_HTTP_PROXY"
    fi
    if [ ! -z "$GLOBAL_AGENT_SOCKS_PROXY" ]; then
        echo "🔗 SOCKS 代理: $GLOBAL_AGENT_SOCKS_PROXY"
    fi
fi

# 检查 pnpm
if ! command -v pnpm &> /dev/null; then
    echo "📦 安装 pnpm..."
    npm install -g pnpm
fi

cd "$FLOWISE_ROOT/flowise"

# 首次运行时安装依赖
if [ ! -d "node_modules" ]; then
    echo "📦 安装依赖..."
    pnpm install --prod --frozen-lockfile
fi

# 创建数据目录
mkdir -p "$FLOWISE_DATA_DIR"

# 复制初始数据（如果数据目录为空）
if [ ! "$(ls -A "$FLOWISE_DATA_DIR" 2>/dev/null)" ]; then
    echo "📋 复制初始数据..."
    cp -r "$FLOWISE_ROOT/data/"* "$FLOWISE_DATA_DIR/" 2>/dev/null || true
fi

# 设置环境变量
export FLOWISE_USERNAME="${FLOWISE_USERNAME:-admin}"
export FLOWISE_PASSWORD="${FLOWISE_PASSWORD:-1234}"
export PORT="${PORT:-3003}"
export FLOWISE_API_PORT="${FLOWISE_API_PORT:-3009}"

# 代理相关环境变量
export GLOBAL_AGENT_HTTPS_PROXY="${GLOBAL_AGENT_HTTPS_PROXY:-}"
export GLOBAL_AGENT_HTTP_PROXY="${GLOBAL_AGENT_HTTP_PROXY:-}"
export GLOBAL_AGENT_SOCKS_PROXY="${GLOBAL_AGENT_SOCKS_PROXY:-}"

# Flowise 特定配置
export DATABASE_PATH="$FLOWISE_DATA_DIR"
export APIKEY_PATH="$FLOWISE_DATA_DIR"
export LOG_PATH="$FLOWISE_DATA_DIR/logs"
export SECRETKEY_PATH="$FLOWISE_DATA_DIR"
export BLOB_STORAGE_PATH="$FLOWISE_DATA_DIR/storage"

# 功能开关
export DISABLE_FLOWISE_TELEMETRY=true
export DEBUG="${DEBUG:-false}"

echo "🌐 启动 Flowise 服务器..."
echo "📊 Web 界面: http://localhost:$PORT"
echo "🔌 API 端口: $FLOWISE_API_PORT"
echo "👤 用户名: $FLOWISE_USERNAME"
echo "🔑 密码: $FLOWISE_PASSWORD"
echo ""
echo "按 Ctrl+C 停止服务器"

# 启动服务器
node packages/server/dist/index.js
EOF

# 升级脚本
cat > "$PACKAGE_DIR/scripts/upgrade.sh" << 'EOF'
#!/bin/bash

# Flowise 3.0 升级脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOWISE_ROOT="$(dirname "$SCRIPT_DIR")"
FLOWISE_DATA_DIR="$HOME/.flowise"
BACKUP_DIR="$HOME/flowise-backup-$(date +%Y%m%d-%H%M%S)"

echo "🔄 Flowise 3.0 升级工具"
echo "📁 当前安装: $FLOWISE_ROOT"
echo "💾 数据目录: $FLOWISE_DATA_DIR"

# 检查参数
if [ $# -eq 0 ]; then
    echo "❌ 错误: 请提供新版本包的路径"
    echo "用法: $0 <新版本包路径>"
    echo "示例: $0 /path/to/flowise-3.0-macos-20250610-120000.tar.gz"
    exit 1
fi

NEW_PACKAGE="$1"

if [ ! -f "$NEW_PACKAGE" ]; then
    echo "❌ 错误: 文件不存在: $NEW_PACKAGE"
    exit 1
fi

echo "📦 新版本包: $NEW_PACKAGE"

# 1. 备份当前数据
echo "💾 备份用户数据..."
if [ -d "$FLOWISE_DATA_DIR" ]; then
    cp -r "$FLOWISE_DATA_DIR" "$BACKUP_DIR"
    echo "✅ 数据已备份到: $BACKUP_DIR"
else
    echo "⚠️  没有找到用户数据目录"
fi

# 2. 备份当前配置
if [ -f "$FLOWISE_ROOT/config/proxy.conf" ]; then
    cp "$FLOWISE_ROOT/config/proxy.conf" "$BACKUP_DIR/proxy.conf.backup"
    echo "✅ 代理配置已备份"
fi

# 3. 解压新版本
echo "📂 解压新版本..."
TEMP_DIR="/tmp/flowise-upgrade-$(date +%s)"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"
tar -xzf "$NEW_PACKAGE"

NEW_VERSION_DIR=$(find . -maxdepth 1 -type d -name "flowise-3.0-*" | head -1)
if [ -z "$NEW_VERSION_DIR" ]; then
    echo "❌ 错误: 无法找到新版本目录"
    exit 1
fi

echo "📁 新版本目录: $NEW_VERSION_DIR"

# 4. 停止当前服务（如果在运行）
echo "🛑 停止当前服务..."
pkill -f "flowise.*packages/server/dist/index.js" || echo "没有运行中的服务"

# 5. 备份当前安装
CURRENT_BACKUP="$FLOWISE_ROOT.backup.$(date +%Y%m%d-%H%M%S)"
echo "📦 备份当前安装到: $CURRENT_BACKUP"
cp -r "$FLOWISE_ROOT" "$CURRENT_BACKUP"

# 6. 替换程序文件
echo "🔄 更新程序文件..."
rm -rf "$FLOWISE_ROOT/flowise"
cp -r "$NEW_VERSION_DIR/flowise" "$FLOWISE_ROOT/"

# 7. 更新脚本
cp -r "$NEW_VERSION_DIR/scripts/"* "$FLOWISE_ROOT/scripts/"
chmod +x "$FLOWISE_ROOT/scripts/"*.sh

# 8. 合并配置
if [ -f "$NEW_VERSION_DIR/config/proxy.conf" ] && [ -f "$BACKUP_DIR/proxy.conf.backup" ]; then
    echo "🔧 合并代理配置..."
    # 保留用户的代理配置
    cp "$BACKUP_DIR/proxy.conf.backup" "$FLOWISE_ROOT/config/proxy.conf"
else
    cp -r "$NEW_VERSION_DIR/config" "$FLOWISE_ROOT/" 2>/dev/null || true
fi

# 9. 恢复数据
echo "📋 恢复用户数据..."
if [ -d "$BACKUP_DIR" ]; then
    # 创建数据目录结构
    mkdir -p "$FLOWISE_DATA_DIR"
    
    # 恢复除了备份文件外的所有数据
    find "$BACKUP_DIR" -type f ! -name "*.backup" -exec cp {} "$FLOWISE_DATA_DIR/" \; 2>/dev/null || true
    
    # 恢复目录结构
    if [ -d "$BACKUP_DIR/storage" ]; then
        cp -r "$BACKUP_DIR/storage" "$FLOWISE_DATA_DIR/" 2>/dev/null || true
    fi
    if [ -d "$BACKUP_DIR/logs" ]; then
        cp -r "$BACKUP_DIR/logs" "$FLOWISE_DATA_DIR/" 2>/dev/null || true
    fi
fi

# 10. 清理
echo "🧹 清理临时文件..."
rm -rf "$TEMP_DIR"

echo ""
echo "✅ 升级完成!"
echo "📁 程序目录: $FLOWISE_ROOT"
echo "💾 数据备份: $BACKUP_DIR"
echo "📦 程序备份: $CURRENT_BACKUP"
echo ""
echo "🚀 启动新版本:"
echo "cd $FLOWISE_ROOT && ./scripts/start-macos.sh"
echo ""
echo "🔄 如需回滚:"
echo "rm -rf $FLOWISE_ROOT && mv $CURRENT_BACKUP $FLOWISE_ROOT"
EOF

# 代理测试脚本
cat > "$PACKAGE_DIR/scripts/test-proxy.sh" << 'EOF'
#!/bin/bash

# 代理连接测试脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/config"

echo "🔍 代理连接测试"

# 加载代理配置
if [ -f "$CONFIG_DIR/proxy.conf" ]; then
    source "$CONFIG_DIR/proxy.conf"
else
    echo "❌ 代理配置文件不存在: $CONFIG_DIR/proxy.conf"
    exit 1
fi

# 测试 HTTP 代理
if [ ! -z "$GLOBAL_AGENT_HTTP_PROXY" ]; then
    echo "🔗 测试 HTTP 代理: $GLOBAL_AGENT_HTTP_PROXY"
    curl -s --proxy "$GLOBAL_AGENT_HTTP_PROXY" -o /dev/null -w "HTTP 代理状态: %{http_code}\n" "http://httpbin.org/ip" || echo "❌ HTTP 代理连接失败"
fi

# 测试 HTTPS 代理
if [ ! -z "$GLOBAL_AGENT_HTTPS_PROXY" ]; then
    echo "🔒 测试 HTTPS 代理: $GLOBAL_AGENT_HTTPS_PROXY"
    curl -s --proxy "$GLOBAL_AGENT_HTTPS_PROXY" -o /dev/null -w "HTTPS 代理状态: %{http_code}\n" "https://httpbin.org/ip" || echo "❌ HTTPS 代理连接失败"
fi

# 测试网络连接
echo "🌐 测试网络连接..."
curl -s --max-time 10 "https://api.openai.com" > /dev/null && echo "✅ OpenAI API 可访问" || echo "❌ OpenAI API 不可访问"
curl -s --max-time 10 "https://api.anthropic.com" > /dev/null && echo "✅ Anthropic API 可访问" || echo "❌ Anthropic API 不可访问"
curl -s --max-time 10 "https://generativelanguage.googleapis.com" > /dev/null && echo "✅ Google AI API 可访问" || echo "❌ Google AI API 不可访问"

echo "✅ 代理测试完成"
EOF

# 安装脚本
cat > "$PACKAGE_DIR/scripts/install.sh" << 'EOF'
#!/bin/bash

# Flowise 3.0 安装脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOWISE_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🚀 Flowise 3.0 安装向导"
echo "📁 安装目录: $FLOWISE_ROOT"

# 设置权限
echo "🔧 设置执行权限..."
chmod +x "$SCRIPT_DIR/"*.sh

# 配置代理（可选）
echo ""
echo "🌐 代理配置 (可选)"
echo "如果需要使用代理，请编辑配置文件:"
echo "nano $FLOWISE_ROOT/config/proxy.conf"
echo ""

read -p "是否现在配置代理? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command -v nano &> /dev/null; then
        nano "$FLOWISE_ROOT/config/proxy.conf"
    elif command -v vim &> /dev/null; then
        vim "$FLOWISE_ROOT/config/proxy.conf"
    else
        echo "请手动编辑: $FLOWISE_ROOT/config/proxy.conf"
        open "$FLOWISE_ROOT/config/proxy.conf" 2>/dev/null || true
    fi
fi

echo ""
echo "✅ 安装完成!"
echo ""
echo "🚀 启动 Flowise:"
echo "./scripts/start-macos.sh"
echo ""
echo "🔄 升级 Flowise:"
echo "./scripts/upgrade.sh <新版本包路径>"
echo ""
echo "🔍 测试代理:"
echo "./scripts/test-proxy.sh"
EOF

# 7. 创建调试脚本
cat > "$PACKAGE_DIR/scripts/debug.sh" << 'EOF'
#!/bin/bash

# Flowise 3.0 调试脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOWISE_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🔍 Flowise 3.0 调试信息"
echo "=========================="

echo "📁 目录结构:"
echo "项目根目录: $FLOWISE_ROOT"
echo "数据目录: $HOME/.flowise"

echo ""
echo "📦 文件检查:"
[ -d "$FLOWISE_ROOT/flowise" ] && echo "✅ flowise 目录存在" || echo "❌ flowise 目录不存在"
[ -d "$FLOWISE_ROOT/flowise/server-dist" ] && echo "✅ server-dist 存在" || echo "❌ server-dist 不存在"
[ -d "$FLOWISE_ROOT/flowise/components-dist" ] && echo "✅ components-dist 存在" || echo "❌ components-dist 不存在"
[ -d "$FLOWISE_ROOT/flowise/ui-dist" ] && echo "✅ ui-dist 存在" || echo "❌ ui-dist 不存在"
[ -f "$FLOWISE_ROOT/flowise/package.json" ] && echo "✅ package.json 存在" || echo "❌ package.json 不存在"

echo ""
echo "🔧 Node.js 环境:"
command -v node && echo "Node.js 版本: $(node -v)" || echo "❌ Node.js 未安装"
command -v npm && echo "npm 版本: $(npm -v)" || echo "❌ npm 未安装"
command -v pnpm && echo "pnpm 版本: $(pnpm -v)" || echo "❌ pnpm 未安装"

echo ""
echo "🌐 网络测试:"
ping -c 1 google.com &>/dev/null && echo "✅ 网络连接正常" || echo "❌ 网络连接异常"

echo ""
echo "💾 数据目录:"
if [ -d "$HOME/.flowise" ]; then
    echo "✅ 数据目录存在"
    echo "数据大小: $(du -sh "$HOME/.flowise" 2>/dev/null | cut -f1)"
    echo "文件数量: $(find "$HOME/.flowise" -type f 2>/dev/null | wc -l)"
else
    echo "❌ 数据目录不存在"
fi

echo ""
echo "🔧 权限检查:"
[ -x "$SCRIPT_DIR/start-macos.sh" ] && echo "✅ start-macos.sh 可执行" || echo "❌ start-macos.sh 不可执行"
[ -x "$SCRIPT_DIR/upgrade.sh" ] && echo "✅ upgrade.sh 可执行" || echo "❌ upgrade.sh 不可执行"

echo ""
echo "📋 系统信息:"
echo "系统: $(uname -s)"
echo "架构: $(uname -m)"
echo "内存: $(free -h 2>/dev/null | head -2 | tail -1 | awk '{print $2}' || echo '未知')"

echo ""
echo "=========================="
echo "🔍 调试完成"
EOF

# 8. 创建生产环境 package.json
echo "📄 创建生产环境配置..."

# 检查并读取依赖
if [ -f "packages/server/package.json" ]; then
    cat > "$PACKAGE_DIR/flowise/package.json" << EOF
{
  "name": "flowise-production",
  "version": "3.0.0",
  "description": "Flowise Production Build",
  "main": "packages/server/dist/index.js",
  "scripts": {
    "start": "node packages/server/dist/index.js",
    "start:prod": "NODE_ENV=production node packages/server/dist/index.js"
  },
  "dependencies": {
$(cat packages/server/package.json | jq -r '.dependencies | to_entries[] | "    \"" + .key + "\": \"" + .value + "\""' | paste -sd ',' -),
    "global-agent": "^3.0.0"
  },
  "engines": {
    "node": ">=18.15.0"
  }
}
EOF
else
    echo "⚠️  警告: packages/server/package.json 不存在，使用基本配置"
    cat > "$PACKAGE_DIR/flowise/package.json" << 'EOF'
{
  "name": "flowise-production",
  "version": "3.0.0",
  "description": "Flowise Production Build",
  "main": "packages/server/dist/index.js",
  "scripts": {
    "start": "node packages/server/dist/index.js",
    "start:prod": "NODE_ENV=production node packages/server/dist/index.js"
  },
  "engines": {
    "node": ">=18.15.0"
  }
}
EOF
fi

# 9. 创建安装指南
cat > "$PACKAGE_DIR/README.md" << 'EOF'
# Flowise 3.0 macOS 部署包

## 系统要求

- macOS 10.15+ 或 Linux
- Node.js 18+ (通过 nvm 管理)
- 8GB+ RAM (推荐)

## 快速安装

### 1. 解压并安装
```bash
tar -xzf flowise-3.0-macos-*.tar.gz
cd flowise-3.0-macos-*
./scripts/install.sh
```

### 2. 启动服务
```bash
./scripts/start-macos.sh
```

### 3. 访问应用
- Web 界面: http://localhost:3003
- API 端口: 3009
- 默认用户名: admin
- 默认密码: 1234

## 代理配置

编辑 `config/proxy.conf` 文件来配置代理:

```bash
# 启用 HTTPS 代理
export GLOBAL_AGENT_HTTPS_PROXY=http://127.0.0.1:7890

# 启用 HTTP 代理  
export GLOBAL_AGENT_HTTP_PROXY=http://127.0.0.1:7890

# SOCKS 代理
export GLOBAL_AGENT_SOCKS_PROXY=socks://127.0.0.1:7891
```

测试代理连接:
```bash
./scripts/test-proxy.sh
```

## 故障排除

### 调试信息
```bash
./scripts/debug.sh
```

### 常见问题

1. **UI 编译目录**: 脚本自动检测 `packages/ui/build` 或 `packages/ui/dist`
2. **依赖安装失败**: 确保网络连接正常，或配置代理
3. **端口冲突**: 修改 `PORT` 和 `FLOWISE_API_PORT` 环境变量

## 升级

```bash
# 下载新版本包后
./scripts/upgrade.sh /path/to/new-version.tar.gz
```

## 目录结构

```
flowise-3.0-macos-*/
├── flowise/           # 应用程序文件
│   ├── server-dist/   # 服务器编译文件
│   ├── components-dist/ # 组件编译文件
│   └── ui-dist/       # UI编译文件 (来自 build 或 dist)
├── data/             # 初始数据
├── config/           # 配置文件
├── scripts/          # 管理脚本
└── README.md         # 本文件
```
EOF

# 10. 创建环境配置模板
cat > "$PACKAGE_DIR/flowise/.env.example" << 'EOF'
# Flowise 配置示例
# 复制为 .env 文件并修改配置

# 服务器配置
PORT=3003
FLOWISE_API_PORT=3009
FLOWISE_USERNAME=admin
FLOWISE_PASSWORD=1234

# 数据库配置
DATABASE_PATH=~/.flowise
APIKEY_PATH=~/.flowise
LOG_PATH=~/.flowise/logs
SECRETKEY_PATH=~/.flowise
BLOB_STORAGE_PATH=~/.flowise/storage

# 代理配置
GLOBAL_AGENT_HTTPS_PROXY=http://127.0.0.1:7890
GLOBAL_AGENT_HTTP_PROXY=http://127.0.0.1:7890
GLOBAL_AGENT_SOCKS_PROXY=socks://127.0.0.1:7891

# 功能开关
DISABLE_FLOWISE_TELEMETRY=true
DEBUG=false
EOF

# 11. 设置脚本权限
chmod +x "$PACKAGE_DIR/scripts/"*.sh

# 12. 显示构建摘要
echo ""
echo "🏗️  构建摘要:"
echo "✅ Server: $([ -d "$PACKAGE_DIR/flowise/server-dist" ] && echo "已包含" || echo "缺失")"
echo "✅ Components: $([ -d "$PACKAGE_DIR/flowise/components-dist" ] && echo "已包含" || echo "缺失")"
echo "✅ UI: $([ -d "$PACKAGE_DIR/flowise/ui-dist" ] && echo "已包含" || echo "缺失")"
echo "✅ 用户数据: $([ -d "$PACKAGE_DIR/data" ] && echo "已包含" || echo "缺失")"
echo "✅ 脚本工具: $(ls "$PACKAGE_DIR/scripts/"*.sh 2>/dev/null | wc -l) 个"

# 13. 压缩打包
echo "🗜️  压缩打包..."
cd /tmp
tar -czf "$ARCHIVE_NAME" "$PACKAGE_NAME"

# 14. 清理临时目录
rm -rf "$PACKAGE_DIR"

echo "✅ 打包完成!"
echo "📦 包文件: /tmp/$ARCHIVE_NAME"
echo "📏 文件大小: $(du -h "/tmp/$ARCHIVE_NAME" | cut -f1)"

# 提供下载建议
echo ""
echo "🚀 部署指南:"
echo "1. 传输到 macOS: scp /tmp/$ARCHIVE_NAME user@mac:/tmp/"
echo "2. 解压: tar -xzf $ARCHIVE_NAME"
echo "3. 安装: cd $PACKAGE_NAME && ./scripts/install.sh"
echo "4. 启动: ./scripts/start-macos.sh"
echo ""
echo "🌐 访问地址:"
echo "   Web 界面: http://localhost:3003"
echo "   API 接口: http://localhost:3009"
echo ""
echo "🔧 代理配置: 编辑 config/proxy.conf"
echo "🔄 升级命令: ./scripts/upgrade.sh <新版本包>"
echo "🔍 调试工具: ./scripts/debug.sh"
