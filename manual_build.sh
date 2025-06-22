#!/bin/bash
# filepath: /home/lq/projects/liw/Flowise3.0/manual_build.sh
set -e # 如果任何命令失败，则立即退出

# 项目信息
PROJECT_NAME="Flowise3.0"
BUILD_DIR="./build-package"
PACKAGE_NAME="flowise-3.0-portable"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PACKAGE_FILE="${PACKAGE_NAME}_${TIMESTAMP}.tar.gz"

echo "🚀 Starting Flowise 3.0 manual build and packaging..."

# 清理之前的构建
echo "🧹 Cleaning previous builds..."
rm -rf $BUILD_DIR
rm -f $PACKAGE_NAME*.tar.gz

# 创建构建目录
mkdir -p $BUILD_DIR/$PACKAGE_NAME

echo "📦 Building all packages..."

echo "Building flowise-components..."
cd packages/components
pnpm build
cd ../..

echo "Building flowise-api..."
if [ -d "packages/api-documentation" ]; then
    cd packages/api-documentation
    pnpm build
    cd ../..
else
    echo "⚠️  No api-documentation package found, skipping..."
fi

echo "Building flowise-ui..."
cd packages/ui
pnpm build
cd ../..

echo "Building flowise-server..."
cd packages/server
pnpm build
cd ../..

echo "All packages built successfully!"

echo "📋 Copying built files to package directory..."

# 复制构建产物和必要文件
echo "Copying package.json files..."
cp package.json $BUILD_DIR/$PACKAGE_NAME/
cp pnpm-workspace.yaml $BUILD_DIR/$PACKAGE_NAME/
cp pnpm-lock.yaml $BUILD_DIR/$PACKAGE_NAME/

# 复制各个包的构建产物和配置
echo "Copying packages..."
mkdir -p $BUILD_DIR/$PACKAGE_NAME/packages

# Components 包
mkdir -p $BUILD_DIR/$PACKAGE_NAME/packages/components
cp packages/components/package.json $BUILD_DIR/$PACKAGE_NAME/packages/components/
cp -r packages/components/dist $BUILD_DIR/$PACKAGE_NAME/packages/components/ 2>/dev/null || echo "⚠️  No dist folder in components"
cp -r packages/components/nodes $BUILD_DIR/$PACKAGE_NAME/packages/components/ 2>/dev/null || echo "⚠️  No nodes folder in components"
cp -r packages/components/credentials $BUILD_DIR/$PACKAGE_NAME/packages/components/ 2>/dev/null || echo "⚠️  No credentials folder in components"

# API Documentation 包 (如果存在)
if [ -d "packages/api-documentation" ]; then
    mkdir -p $BUILD_DIR/$PACKAGE_NAME/packages/api-documentation
    cp packages/api-documentation/package.json $BUILD_DIR/$PACKAGE_NAME/packages/api-documentation/
    cp -r packages/api-documentation/dist $BUILD_DIR/$PACKAGE_NAME/packages/api-documentation/ 2>/dev/null || echo "⚠️  No dist folder in api-documentation"
    cp -r packages/api-documentation/build $BUILD_DIR/$PACKAGE_NAME/packages/api-documentation/ 2>/dev/null || echo "⚠️  No build folder in api-documentation"
fi

# UI 包
mkdir -p $BUILD_DIR/$PACKAGE_NAME/packages/ui
cp packages/ui/package.json $BUILD_DIR/$PACKAGE_NAME/packages/ui/
cp -r packages/ui/dist $BUILD_DIR/$PACKAGE_NAME/packages/ui/ 2>/dev/null || echo "⚠️  No dist folder in ui"
cp -r packages/ui/build $BUILD_DIR/$PACKAGE_NAME/packages/ui/ 2>/dev/null || echo "⚠️  No build folder in ui"
cp -r packages/ui/public $BUILD_DIR/$PACKAGE_NAME/packages/ui/ 2>/dev/null || echo "⚠️  No public folder in ui"

# Server 包
mkdir -p $BUILD_DIR/$PACKAGE_NAME/packages/server
cp packages/server/package.json $BUILD_DIR/$PACKAGE_NAME/packages/server/
cp -r packages/server/dist $BUILD_DIR/$PACKAGE_NAME/packages/server/ 2>/dev/null || echo "⚠️  No dist folder in server"
# 复制可能的静态文件
cp -r packages/server/public $BUILD_DIR/$PACKAGE_NAME/packages/server/ 2>/dev/null || echo "ℹ️  No public folder in server"

# 复制配置文件
echo "Copying configuration files..."
cp README.md $BUILD_DIR/$PACKAGE_NAME/ 2>/dev/null || echo "ℹ️  No README.md found"
cp .gitignore $BUILD_DIR/$PACKAGE_NAME/ 2>/dev/null || echo "ℹ️  No .gitignore found"

# 复制 Flowise 数据目录
echo "📁 Copying Flowise data and runtime files..."

# 1. 复制主要数据目录
if [ -d "./.flowise" ]; then
    echo "📁 Found .flowise directory, copying data..."
    cp -r ./.flowise $BUILD_DIR/$PACKAGE_NAME/
    
    # 统计数据
    DATA_SIZE=$(du -sh $BUILD_DIR/$PACKAGE_NAME/.flowise | cut -f1)
    echo "✅ Data directory copied (${DATA_SIZE})"
    
    # 列出重要文件
    echo "📋 Important data files found:"
    [ -f "$BUILD_DIR/$PACKAGE_NAME/.flowise/database.sqlite" ] && echo "  ✓ Database file"
    [ -d "$BUILD_DIR/$PACKAGE_NAME/.flowise/uploads" ] && echo "  ✓ Upload files"
    [ -f "$BUILD_DIR/$PACKAGE_NAME/.flowise/secret.key" ] && echo "  ✓ Secret key"
    [ -f "$BUILD_DIR/$PACKAGE_NAME/.flowise/api.key" ] && echo "  ✓ API key"
else
    echo "⚠️  No .flowise directory found in current location"
    echo "🔍 Checking alternative locations..."
    
    # 检查用户主目录
    if [ -d "$HOME/.flowise" ]; then
        echo "📁 Found .flowise in home directory, copying..."
        cp -r "$HOME/.flowise" $BUILD_DIR/$PACKAGE_NAME/
    else
        echo "📁 Creating empty .flowise directory for fresh installation"
        mkdir -p $BUILD_DIR/$PACKAGE_NAME/.flowise
    fi
fi

# 2. 复制可能的其他数据文件
echo "🔍 Checking for additional data files..."

# 检查 packages/server 目录下的数据文件
for file in database.sqlite secret.key api.key; do
    if [ -f "packages/server/$file" ]; then
        echo "📁 Found $file in packages/server/, copying to .flowise/"
        mkdir -p $BUILD_DIR/$PACKAGE_NAME/.flowise
        cp "packages/server/$file" "$BUILD_DIR/$PACKAGE_NAME/.flowise/"
    fi
done

# 检查并复制上传文件目录
if [ -d "packages/server/uploads" ]; then
    echo "📁 Copying uploads directory..."
    mkdir -p $BUILD_DIR/$PACKAGE_NAME/.flowise
    cp -r packages/server/uploads $BUILD_DIR/$PACKAGE_NAME/.flowise/
fi

# 检查并复制日志文件
if [ -d "packages/server/logs" ]; then
    echo "📁 Copying logs directory..."
    mkdir -p $BUILD_DIR/$PACKAGE_NAME/.flowise
    cp -r packages/server/logs $BUILD_DIR/$PACKAGE_NAME/.flowise/
fi

echo "✅ Data copying completed"

# 创建环境配置模板 - 修复版本
echo "Creating environment configuration template..."
cat > $BUILD_DIR/$PACKAGE_NAME/packages/server/.env.template << 'EOF'
# Flowise Configuration Template
# Copy this file to .env and update the values

# Server Configuration
PORT=3000
CORS_ORIGINS=*
IFRAME_ORIGINS=*

# Database (相对于 packages/server 目录)
DATABASE_PATH=../../.flowise/database.sqlite
SECRETKEY_PATH=../../.flowise/secret.key
APIKEY_PATH=../../.flowise/api.key

# Logging Configuration (修复 Winston 问题)
LOG_LEVEL=info
LOG_PATH=../../.flowise/logs
DEBUG=false
WINSTON_EXIT_ON_ERROR=false
NODE_ENV=production

# File Upload
FLOWISE_FILE_SIZE_LIMIT=50MB
UPLOAD_PATH=../../.flowise/uploads

# Network (if behind proxy)
# HTTP_PROXY=http://127.0.0.1:8080
# HTTPS_PROXY=http://127.0.0.1:8080
# NO_PROXY=localhost,127.0.0.1

# API Keys (update with your actual keys)
# OPENAI_API_KEY=your_openai_key_here
# GROQ_API_KEY=your_groq_key_here
# GOOGLE_API_KEY=your_google_key_here
# HUGGINGFACEHUB_API_KEY=your_huggingface_key_here

# Security
FLOWISE_USERNAME=admin
FLOWISE_PASSWORD=1234
FLOWISE_SECRETKEY_OVERWRITE=mySecretKey

# Community Nodes
SHOW_COMMUNITY_NODES=true

# Additional Winston and Error Handling
SUPPRESS_NO_CONFIG_WARNING=true
NODE_NO_WARNINGS=1
EOF

# 创建故障排除脚本
cat > $BUILD_DIR/$PACKAGE_NAME/troubleshoot.sh << 'EOF'
#!/bin/bash
# Flowise 3.0 故障排除脚本

echo "🔧 Flowise 3.0 Troubleshooting..."

echo "📋 System Information:"
echo "  OS: $(uname -s) $(uname -r)"
echo "  Node.js: $(node -v 2>/dev/null || echo 'Not installed')"
echo "  npm: $(npm -v 2>/dev/null || echo 'Not installed')"
echo "  pnpm: $(pnpm -v 2>/dev/null || echo 'Not installed')"

echo ""
echo "📁 Directory Structure:"
ls -la | grep -E "(flowise|packages)"

echo ""
echo "🔍 Checking critical files:"
[ -f "packages/server/dist/index.js" ] && echo "  ✓ Server build exists" || echo "  ❌ Server build missing"
[ -f "packages/server/.env" ] && echo "  ✓ Environment config exists" || echo "  ❌ Environment config missing"
[ -d ".flowise" ] && echo "  ✓ Data directory exists" || echo "  ❌ Data directory missing"

echo ""
echo "🔧 Common fixes:"
echo "1. Reset environment:"
echo "   rm packages/server/.env"
echo "   cp packages/server/.env.template packages/server/.env"
echo ""
echo "2. Reinstall dependencies:"
echo "   rm -rf node_modules"
echo "   pnpm install --prod"
echo ""
echo "3. Check logs:"
echo "   tail -f .flowise/logs/server.log"
echo ""
echo "4. Manual start with debug:"
echo "   cd packages/server"
echo "   DEBUG=* node dist/index.js"

EOF

chmod +x $BUILD_DIR/$PACKAGE_NAME/troubleshoot.sh

# 创建启动脚本
echo "Creating startup scripts..."

# macOS 启动脚本 - 修复版本
cat > $BUILD_DIR/$PACKAGE_NAME/start-macos.sh << 'EOF'
#!/bin/bash
# Flowise 3.0 Startup Script for macOS (Fixed Winston Issues)

set -e

echo "🚀 Starting Flowise 3.0..."

# 检查 Node.js
if ! command -v node &> /dev/null; then
    echo "❌ Node.js not found. Please install Node.js 18+ first."
    echo "Download from: https://nodejs.org/"
    exit 1
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    echo "❌ Node.js version 18+ required. Current version: $(node -v)"
    exit 1
fi

# 检查 pnpm
if ! command -v pnpm &> /dev/null; then
    echo "📦 Installing pnpm..."
    npm install -g pnpm
fi

# 创建必要的目录和设置权限
echo "📁 Setting up directories and permissions..."
mkdir -p .flowise/logs .flowise/uploads packages/server/logs
chmod 755 .flowise .flowise/logs .flowise/uploads packages/server/logs 2>/dev/null || true

# 检查数据目录
if [ ! -d ".flowise" ]; then
    echo "📁 Creating Flowise data directory..."
    mkdir -p .flowise
fi

# 如果存在旧的数据库位置，迁移到新位置
if [ -f "packages/server/database.sqlite" ] && [ ! -f ".flowise/database.sqlite" ]; then
    echo "🔄 Migrating database to standard location..."
    cp packages/server/database.sqlite .flowise/database.sqlite
fi

# 检查并创建环境配置
if [ ! -f "packages/server/.env" ]; then
    echo "⚙️  Creating default environment configuration..."
    cp packages/server/.env.template packages/server/.env
    
    # 添加 Winston 和日志相关配置
    cat >> packages/server/.env << 'ENVEOF'

# Winston 和日志配置 (修复 exitOnError 问题)
LOG_LEVEL=info
LOG_PATH=../../.flowise/logs
WINSTON_EXIT_ON_ERROR=false
NODE_ENV=production
DEBUG=false
ENVEOF
    
    # 更新环境变量指向正确的数据路径
    if command -v sed &> /dev/null; then
        sed -i.bak 's|^DATABASE_PATH=.*|DATABASE_PATH=../../.flowise/database.sqlite|g' packages/server/.env
        sed -i.bak 's|^SECRETKEY_PATH=.*|SECRETKEY_PATH=../../.flowise/secret.key|g' packages/server/.env
        sed -i.bak 's|^APIKEY_PATH=.*|APIKEY_PATH=../../.flowise/api.key|g' packages/server/.env
        # 清理备份文件
        rm -f packages/server/.env.bak
    fi
    
    echo "📝 Please edit packages/server/.env with your API keys and configuration"
fi

# 设置关键环境变量来修复 Winston 问题
export LOG_LEVEL=info
export NODE_ENV=production
export WINSTON_EXIT_ON_ERROR=false
export NODE_OPTIONS="--unhandled-rejections=warn --max-old-space-size=4096"

# 额外的 Winston 修复环境变量
export SUPPRESS_NO_CONFIG_WARNING=true
export NODE_NO_WARNINGS=1

echo "⚙️  Environment variables set:"
echo "  LOG_LEVEL=$LOG_LEVEL"
echo "  NODE_ENV=$NODE_ENV"
echo "  WINSTON_EXIT_ON_ERROR=$WINSTON_EXIT_ON_ERROR"

# 安装生产依赖
echo "📥 Installing production dependencies..."
if ! pnpm install --prod --frozen-lockfile --ignore-scripts; then
    echo "❌ Installation failed. Trying alternative approach..."
    pnpm install --frozen-lockfile --ignore-scripts
fi

# 检查关键文件是否存在
if [ ! -f "packages/server/dist/index.js" ]; then
    echo "❌ Server build not found. Please run the build script first."
    exit 1
fi

# 启动服务前的最后检查
echo "🔍 Pre-startup checks..."
echo "  ✓ Node.js version: $(node -v)"
echo "  ✓ Data directory: .flowise/"
echo "  ✓ Server build: packages/server/dist/index.js"
echo "  ✓ Environment config: packages/server/.env"

# 启动服务
echo ""
echo "🎯 Starting Flowise server..."
echo "📱 Open your browser and go to: http://localhost:3000"
echo "🛑 Press Ctrl+C to stop the server"
echo "📋 Logs will be saved to: .flowise/logs/"
echo ""

cd packages/server

# 使用修复的启动命令
exec node \
  --unhandled-rejections=warn \
  --max-old-space-size=4096 \
  --trace-warnings \
  dist/index.js 2>&1 | tee ../../.flowise/logs/server.log

EOF

# 创建安装脚本
cat > $BUILD_DIR/$PACKAGE_NAME/install.sh << 'EOF'
#!/bin/bash
# Flowise 3.0 Installation Script

echo "📦 Installing Flowise 3.0..."

# 检查 Node.js
if ! command -v node &> /dev/null; then
    echo "❌ Node.js not found. Please install Node.js 18+ first."
    echo "Download from: https://nodejs.org/"
    exit 1
fi

# 检查 pnpm
if ! command -v pnpm &> /dev/null; then
    echo "📦 Installing pnpm..."
    npm install -g pnpm
fi

# 安装依赖
pnpm install --prod --frozen-lockfile --ignore-scripts

# 设置权限
chmod +x start-macos.sh
chmod +x packages/server/dist/index.js 2>/dev/null || true

# 创建必要的目录
mkdir -p .flowise/uploads .flowise/logs

echo "✅ Installation completed!"
echo ""
echo "Next steps:"
echo "1. Edit packages/server/.env with your configuration"
echo "2. Run: ./start-macos.sh"
echo ""

EOF

# 创建停止脚本
cat > $BUILD_DIR/$PACKAGE_NAME/stop.sh << 'EOF'
#!/bin/bash
# Flowise 3.0 Stop Script

echo "🛑 Stopping Flowise 3.0..."

# 查找并停止 Flowise 进程
pkill -f "node dist/index.js" || echo "No Flowise process found"
pkill -f "flowise" || echo "No flowise process found"

echo "✅ Flowise stopped"
EOF

# 创建使用说明
cat > $BUILD_DIR/$PACKAGE_NAME/README_DEPLOYMENT.md << 'EOF'
# Flowise 3.0 Portable Deployment

## 系统要求

- macOS 10.14+ 
- Node.js 18.20.0+
- npm (通常与 Node.js 一起安装)

## 安装步骤

1. **解压文件**
   ```bash
   tar -xzf flowise-3.0-portable_*.tar.gz
   cd flowise-3.0-portable
   ```

2. **安装依赖**
   ```bash
   ./install.sh
   ```

3. **配置环境变量**
   ```bash
   cp packages/server/.env.template packages/server/.env
   # 编辑 .env 文件，添加你的 API 密钥
   nano packages/server/.env
   ```

4. **启动服务**
   ```bash
   ./start-macos.sh
   ```

5. **访问应用**
   打开浏览器访问: http://localhost:3000

## 配置说明

主要配置文件: `packages/server/.env`

必需的 API 密钥:
- `OPENAI_API_KEY` - OpenAI API 密钥
- `GROQ_API_KEY` - Groq API 密钥  
- `GOOGLE_API_KEY` - Google/Gemini API 密钥
- `HUGGINGFACEHUB_API_KEY` - HuggingFace API 密钥

可选配置:
- `PORT` - 服务端口 (默认: 3000)
- `FLOWISE_USERNAME` - 管理员用户名
- `FLOWISE_PASSWORD` - 管理员密码

## 数据存储

- 数据库文件: `.flowise/database.sqlite`
- 上传文件: `.flowise/uploads/`
- 日志文件: `.flowise/logs/`
- 密钥文件: `.flowise/secret.key`, `.flowise/api.key`

## 管理命令

- **启动服务**: `./start-macos.sh`
- **停止服务**: `./stop.sh` 或按 `Ctrl+C`
- **重新安装**: `./install.sh`

## 故障排除

1. **端口占用**
   ```bash
   lsof -i :3000
   # 修改 .env 中的 PORT 配置
   ```

2. **权限问题**
   ```bash
   chmod +x start-macos.sh
   chmod +x install.sh
   chmod +x stop.sh
   ```

3. **依赖问题**
   ```bash
   rm -rf node_modules
   pnpm install --prod
   ```

4. **数据库问题**
   ```bash
   # 备份现有数据库
   cp .flowise/database.sqlite .flowise/database.sqlite.backup
   # 删除数据库重新开始
   rm .flowise/database.sqlite
   ```

5. **日志查看**
   ```bash
   # 查看错误日志
   tail -f .flowise/logs/error.log
   # 查看访问日志
   tail -f .flowise/logs/access.log
   ```

## 升级说明

要升级到新版本:
1. 备份 `.flowise` 目录
2. 解压新版本到新目录
3. 将备份的 `.flowise` 目录复制到新版本
4. 运行 `./install.sh`

EOF

# 设置脚本权限
chmod +x $BUILD_DIR/$PACKAGE_NAME/start-macos.sh
chmod +x $BUILD_DIR/$PACKAGE_NAME/install.sh
chmod +x $BUILD_DIR/$PACKAGE_NAME/stop.sh

# 创建包信息文件
cat > $BUILD_DIR/$PACKAGE_NAME/package-info.txt << EOF
Flowise 3.0 Portable Package
============================

Build Date: $(date)
Build Machine: $(uname -a)
Node Version: $(node --version)
pnpm Version: $(pnpm --version)

Package Contents:
- Built components, server, UI packages
- Configuration templates
- Startup scripts for macOS
- Documentation
- Flowise data directory (.flowise)

Target Platform: macOS
Required: Node.js 18+, pnpm

Data included:
$([ -d "$BUILD_DIR/$PACKAGE_NAME/.flowise" ] && echo "✓ Flowise data directory" || echo "✗ No data directory")
$([ -f "$BUILD_DIR/$PACKAGE_NAME/.flowise/database.sqlite" ] && echo "✓ Database file" || echo "✗ No database file")
$([ -d "$BUILD_DIR/$PACKAGE_NAME/.flowise/uploads" ] && echo "✓ Upload files" || echo "✗ No upload files")

EOF

echo "📦 Creating final package..."
cd $BUILD_DIR
tar -czf ../$PACKAGE_FILE $PACKAGE_NAME/
cd ..

# 显示包信息
PACKAGE_SIZE=$(du -h $PACKAGE_FILE | cut -f1)
echo ""
echo "✅ Package created successfully!"
echo "📦 Package file: $PACKAGE_FILE"
echo "📊 Package size: $PACKAGE_SIZE"
echo ""
echo "📋 Package contents summary:"
echo "  📁 Source code and built packages"
echo "  📁 Flowise data directory (.flowise)"
if [ -f "$BUILD_DIR/$PACKAGE_NAME/.flowise/database.sqlite" ]; then
    echo "  💾 Database with existing data"
else
    echo "  📝 Fresh installation setup"
fi
echo "  🔧 Installation and startup scripts"
echo "  📚 Documentation and configuration templates"
echo ""
echo "🚚 Deployment Instructions:"
echo "1. Copy $PACKAGE_FILE to target macOS machine"
echo "2. Extract: tar -xzf $PACKAGE_FILE"
echo "3. Run: cd $PACKAGE_NAME && ./install.sh"
echo "4. Configure: Edit packages/server/.env"
echo "5. Start: ./start-macos.sh"
echo ""

# 清理构建目录
rm -rf $BUILD_DIR

echo "🎉 Build and packaging completed!"