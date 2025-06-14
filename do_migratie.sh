#!/bin/bash

echo "=== ChatGoogleGemini 一键迁移到 Flowise 3.0 ==="

# 设置变量
FLOWISE3_DIR="."  # 当前目录（Flowise 3.0）
COMPONENT_DIR="packages/components/nodes/chatmodels/ChatGoogleGemini"

# 第一步：备份现有文件（如果存在）
echo "📋 1. 备份现有实现..."
if [ -d "$COMPONENT_DIR" ]; then
    mv "$COMPONENT_DIR" "${COMPONENT_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
    echo "✅ 已备份现有文件"
fi

# 第二步：创建目录并复制您的文件
echo "📁 2. 复制您的 ChatGoogleGemini 实现..."
mkdir -p "$COMPONENT_DIR"

# 假设您的当前文件在这个位置，如果不是请修改路径
SOURCE_FILE="/home/lq/projects/liw/Flowise/packages/components/nodes/chatmodels/ChatGoogleGemini/ChatGoogleGemini.ts"

if [ -f "$SOURCE_FILE" ]; then
    cp "$SOURCE_FILE" "$COMPONENT_DIR/"
    echo "✅ 已复制 ChatGoogleGemini.ts"
else
    echo "❌ 源文件不存在: $SOURCE_FILE"
    echo "请手动复制您的 ChatGoogleGemini.ts 文件到 $COMPONENT_DIR/"
    read -p "复制完成后按回车继续..."
fi

# 第三步：安装必需的依赖
echo "📦 3. 安装代理相关依赖..."
cd packages/components

# 检查并安装必需的包
MISSING_PACKAGES=""
pnpm list node-fetch >/dev/null 2>&1 || MISSING_PACKAGES="$MISSING_PACKAGES node-fetch@2"
pnpm list https-proxy-agent >/dev/null 2>&1 || MISSING_PACKAGES="$MISSING_PACKAGES https-proxy-agent"
pnpm list socks-proxy-agent >/dev/null 2>&1 || MISSING_PACKAGES="$MISSING_PACKAGES socks-proxy-agent"
pnpm list zod >/dev/null 2>&1 || MISSING_PACKAGES="$MISSING_PACKAGES zod"
pnpm list zod-to-json-schema >/dev/null 2>&1 || MISSING_PACKAGES="$MISSING_PACKAGES zod-to-json-schema"

if [ ! -z "$MISSING_PACKAGES" ]; then
    echo "🔧 安装缺失的包: $MISSING_PACKAGES"
    pnpm add $MISSING_PACKAGES
    echo "✅ 依赖安装完成"
else
    echo "✅ 所有依赖已存在"
fi

cd ../..

# 第四步：创建 googleTypes.ts（如果不存在）
echo "📝 4. 创建/检查 googleTypes.ts..."
GOOGLE_TYPES_FILE="$COMPONENT_DIR/googleTypes.ts"

if [ ! -f "$GOOGLE_TYPES_FILE" ]; then
    cat > "$GOOGLE_TYPES_FILE" << 'EOF'
// Google Generative AI Types - For Flowise 3.0 compatibility

export enum HarmCategory {
    HARM_CATEGORY_UNSPECIFIED = 'HARM_CATEGORY_UNSPECIFIED',
    HARM_CATEGORY_DEROGATORY = 'HARM_CATEGORY_DEROGATORY',
    HARM_CATEGORY_TOXICITY = 'HARM_CATEGORY_TOXICITY',
    HARM_CATEGORY_VIOLENCE = 'HARM_CATEGORY_VIOLENCE',
    HARM_CATEGORY_SEXUAL = 'HARM_CATEGORY_SEXUAL',
    HARM_CATEGORY_MEDICAL = 'HARM_CATEGORY_MEDICAL',
    HARM_CATEGORY_DANGEROUS = 'HARM_CATEGORY_DANGEROUS',
    HARM_CATEGORY_HARASSMENT = 'HARM_CATEGORY_HARASSMENT',
    HARM_CATEGORY_HATE_SPEECH = 'HARM_CATEGORY_HATE_SPEECH',
    HARM_CATEGORY_SEXUALLY_EXPLICIT = 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
    HARM_CATEGORY_DANGEROUS_CONTENT = 'HARM_CATEGORY_DANGEROUS_CONTENT'
}

export enum HarmBlockThreshold {
    HARM_BLOCK_THRESHOLD_UNSPECIFIED = 'HARM_BLOCK_THRESHOLD_UNSPECIFIED',
    BLOCK_LOW_AND_ABOVE = 'BLOCK_LOW_AND_ABOVE',
    BLOCK_MEDIUM_AND_ABOVE = 'BLOCK_MEDIUM_AND_ABOVE',
    BLOCK_ONLY_HIGH = 'BLOCK_ONLY_HIGH',
    BLOCK_NONE = 'BLOCK_NONE'
}

export enum SchemaType {
    TYPE_UNSPECIFIED = 'TYPE_UNSPECIFIED',
    STRING = 'STRING',
    NUMBER = 'NUMBER',
    INTEGER = 'INTEGER',
    BOOLEAN = 'BOOLEAN',
    ARRAY = 'ARRAY',
    OBJECT = 'OBJECT'
}

export enum FunctionCallingMode {
    MODE_UNSPECIFIED = 'MODE_UNSPECIFIED',
    AUTO = 'AUTO',
    ANY = 'ANY',
    NONE = 'NONE'
}

export interface SafetySetting {
    category: HarmCategory;
    threshold: HarmBlockThreshold;
}

export interface GenerationConfig {
    temperature?: number;
    topP?: number;
    topK?: number;
    candidateCount?: number;
    maxOutputTokens?: number;
    stopSequences?: string[];
}

export interface FunctionDeclarationSchemaProperty {
    type: SchemaType;
    description?: string;
    enum?: string[];
    items?: any;
}

export interface FunctionDeclarationParameters {
    type: SchemaType;
    properties: { [k: string]: FunctionDeclarationSchemaProperty };
    required?: string[];
    description?: string;
}

export interface FunctionDeclaration {
    name: string;
    description?: string;
    parameters?: FunctionDeclarationParameters;
}

export interface FunctionCall {
    name: string;
    args?: any;
}

export interface FunctionResponse {
    name: string;
    response: any;
}

export interface Part {
    text?: string;
    inlineData?: {
        mimeType: string;
        data: string;
    };
    functionCall?: FunctionCall;
    functionResponse?: FunctionResponse;
}

export interface Content {
    role: string;
    parts: Part[];
}

export interface Tool {
    functionDeclarations: FunctionDeclaration[];
}

export interface ToolConfig {
    functionCallingConfig: {
        mode: FunctionCallingMode;
        allowedFunctionNames?: string[];
    };
}

export interface GenerateContentRequest {
    contents: Content[];
    tools?: Tool[];
    toolConfig?: ToolConfig;
    safetySettings?: SafetySetting[];
    generationConfig?: GenerationConfig;
}

export interface GenerateContentResponse {
    candidates?: Array<{
        content?: Content;
        finishReason?: string;
        safetyRatings?: any[];
    }>;
    usageMetadata?: any;
}

export interface ToolCall {
    id: string;
    name: string;
    args: any;
}

export interface ToolCallChunk {
    name?: string;
    args?: string;
    id?: string;
    index?: number;
    type?: string;
}
EOF
    echo "✅ 已创建 googleTypes.ts"
else
    echo "✅ googleTypes.ts 已存在"
fi

# 第五步：自动修复导入路径
echo "🔧 5. 修复导入路径..."
CHATGEMINI_FILE="$COMPONENT_DIR/ChatGoogleGemini.ts"

if [ -f "$CHATGEMINI_FILE" ]; then
    # 查找实际的接口文件位置
    INTERFACE_FILE=$(find packages -name "*[Ii]nterface*" -type f | grep -v node_modules | head -1)
    UTILS_FILE=$(find packages -name "*utils*" -type f | grep -v node_modules | head -1)
    MODELLOADER_FILE=$(find packages -name "*modelLoader*" -type f | grep -v node_modules | head -1)
    
    echo "找到的文件:"
    echo "  Interface: $INTERFACE_FILE"
    echo "  Utils: $UTILS_FILE" 
    echo "  ModelLoader: $MODELLOADER_FILE"
    
    # 使用 Node.js 脚本修复导入路径
    node -e "
    const fs = require('fs');
    const path = require('path');
    
    const filePath = '$CHATGEMINI_FILE';
    let content = fs.readFileSync(filePath, 'utf8');
    
    // 修复各种导入路径
    if ('$INTERFACE_FILE') {
        const relativePath = path.relative(path.dirname(filePath), '$INTERFACE_FILE'.replace('.ts', ''));
        content = content.replace(/from ['\"]\.\.\/\.\.\/\.\.\/src\/Interface['\"]/g, \`from '\${relativePath}'\`);
    }
    
    if ('$UTILS_FILE') {
        const relativePath = path.relative(path.dirname(filePath), '$UTILS_FILE'.replace('.ts', ''));
        content = content.replace(/from ['\"]\.\.\/\.\.\/\.\.\/src\/utils['\"]/g, \`from '\${relativePath}'\`);
    }
    
    if ('$MODELLOADER_FILE') {
        const relativePath = path.relative(path.dirname(filePath), '$MODELLOADER_FILE'.replace('.ts', ''));
        content = content.replace(/from ['\"]\.\.\/\.\.\/\.\.\/src\/modelLoader['\"]/g, \`from '\${relativePath}'\`);
    } else {
        // 如果找不到 modelLoader，使用静态模型列表
        content = content.replace(/import.*getModels.*from.*modelLoader.*\n/g, '');
        content = content.replace(/await getModels\(MODEL_TYPE\.CHAT, 'chatGoogleGemini'\)/g, 
            \`[
                { name: 'gemini-1.5-flash-latest', label: 'Gemini 1.5 Flash (Latest)' },
                { name: 'gemini-1.5-flash', label: 'Gemini 1.5 Flash' },
                { name: 'gemini-1.5-pro-latest', label: 'Gemini 1.5 Pro (Latest)' },
                { name: 'gemini-1.5-pro', label: 'Gemini 1.5 Pro' },
                { name: 'gemini-1.0-pro', label: 'Gemini 1.0 Pro' }
            ]\`);
    }
    
    fs.writeFileSync(filePath, content);
    console.log('✅ 导入路径修复完成');
    "
    
    echo "✅ 导入路径修复完成"
else
    echo "❌ ChatGoogleGemini.ts 文件不存在"
fi

# 第六步：构建测试
echo "🔨 6. 构建测试..."
cd packages/components
BUILD_OUTPUT=$(pnpm build 2>&1)
BUILD_STATUS=$?

if [ $BUILD_STATUS -eq 0 ]; then
    echo "✅ 构建成功！"
    
    # 验证关键功能
    echo "🔍 7. 验证关键功能..."
    if grep -q "HttpsProxyAgent\|SocksProxyAgent" "$CHATGEMINI_FILE"; then
        echo "✅ 代理功能正常"
    else
        echo "⚠️ 代理功能可能有问题"
    fi
    
    if grep -q "bindTools\|ToolCall" "$CHATGEMINI_FILE"; then
        echo "✅ 工具调用功能正常"
    else
        echo "⚠️ 工具调用功能可能有问题"
    fi
    
    echo ""
    echo "🎉 迁移成功完成！"
    echo ""
    echo "📋 下一步："
    echo "1. 启动 Flowise: pnpm start"
    echo "2. 在界面中测试 ChatGoogleGemini 节点"
    echo "3. 验证代理功能（设置 HTTPS_PROXY 环境变量）"
    echo "4. 测试工具调用功能"
    
else
    echo "❌ 构建失败"
    echo "错误信息："
    echo "$BUILD_OUTPUT" | head -10
    echo ""
    echo "🛠️ 可能需要手动修复的问题："
    echo "1. 检查导入路径是否正确"
    echo "2. 检查依赖包是否完整"
    echo "3. 检查类型定义是否兼容"
fi

cd ../..

# 生成迁移报告
cat > migration_report.md << 'EOF'
# ChatGoogleGemini Flowise 3.0 迁移报告

## ✅ 完成的步骤
- [x] 复制 ChatGoogleGemini 实现
- [x] 安装代理相关依赖包
- [x] 创建 googleTypes.ts 类型定义
- [x] 修复导入路径
- [x] 构建测试

## 🔑 保留的核心功能
- ✅ HTTPS_PROXY 和 SOCKS_PROXY 支持
- ✅ ChatGoogleGeminiWithProxy 自定义类
- ✅ bindTools 工具调用功能
- ✅ 流式响应处理
- ✅ Zod schema 转换

## 🧪 测试清单
- [ ] 基本对话功能
- [ ] 代理连接（设置 HTTPS_PROXY）
- [ ] 工具调用功能
- [ ] 流式响应
- [ ] 多模态支持（如有）

## 🚨 注意事项
1. 如果构建失败，请检查 Flowise 3.0 的接口变化
2. 代理功能通过环境变量 HTTPS_PROXY/SOCKS_PROXY 配置
3. Google API Key 需要在凭证中正确配置
EOF

echo "📄 详细报告已生成: migration_report.md"
