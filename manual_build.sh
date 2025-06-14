#!/bin/bash
set -e # 如果任何命令失败，则立即退出

echo "Building flowise-components..."
cd packages/components
pnpm build
cd ../..

echo "Building flowise-api..."
cd packages/api-documentation
pnpm build
cd ../..

echo "Building flowise-ui..."
cd packages/ui
pnpm build
cd ../..

echo "Building flowise-server..."
cd packages/server
pnpm build
cd ../..

echo "All packages built successfully!"
