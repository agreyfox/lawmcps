// Google Generative AI Types - For Flowise 3.0 compatibility

// Direct imports from Google's package
import { HarmBlockThreshold, HarmCategory, SchemaType } from '@google/generative-ai'

import type {
    SafetySetting,
    GenerateContentRequest,
    GenerateContentResponse,
    GenerationConfig as BaseGenerationConfig,
    Content,
    Part as BasePart,
    Tool,
    ToolConfig,
    FunctionDeclaration,
    FunctionCall,
    FunctionResponse
} from '@google/generative-ai'

// Import LangChain's ToolCallChunk instead of defining our own
import type { ToolCallChunk } from '@langchain/core/messages/tool'

// Keep these custom types for LangChain compatibility
export interface ToolCall {
    id: string
    name: string
    args: any
}

// Keep your custom FunctionCallingMode if it differs from Google's
export enum FunctionCallingMode {
    AUTO = 'AUTO',
    ANY = 'ANY',
    NONE = 'NONE'
}

// 在现有枚举后添加 Gemini 2.0+ 新特性
export enum ModalityType {
    TEXT = 'TEXT',
    IMAGE = 'IMAGE',
    AUDIO = 'AUDIO',
    VIDEO = 'VIDEO'
}

// 扩展 GenerationConfig 接口，添加新字段
export interface GenerationConfig extends BaseGenerationConfig {
    // Gemini 2.0+ 新增
    responseMimeType?: string
    responseSchema?: any
    presencePenalty?: number
    frequencyPenalty?: number
    seed?: number
}

// 如果 BasePart 类型太复杂，直接定义新的 Part 类型
export interface Part {
    // 基本的 Part 属性（根据 Google 文档）
    text?: string
    inlineData?: {
        mimeType: string
        data: string
    }
    functionCall?: FunctionCall
    functionResponse?: FunctionResponse

    // Gemini 2.0+ 新增
    fileData?: {
        mimeType: string
        fileUri: string
    }
    videoMetadata?: {
        startOffset?: string
        endOffset?: string
    }
    executableCode?: {
        language: string
        code: string
    }
    codeExecutionResult?: {
        outcome: string
        output?: string
    }
}

// 新增 Gemini 2.0+ 接口
export interface SearchGround {
    webSearchQueries?: string[]
    searchEntryPoint?: {
        renderedContent: string
    }
}

export interface GroundingMetadata {
    webSearchQueries?: string[]
    searchEntryPoint?: {
        renderedContent: string
    }
    groundingChunks?: Array<{
        web?: {
            uri: string
            title: string
        }
    }>
}

export interface CitationSource {
    startIndex?: number
    endIndex?: number
    uri?: string
    license?: string
}

export interface CitationMetadata {
    citationSources: CitationSource[]
}

// 重新导出其他需要的类型
export type {
    SafetySetting,
    GenerateContentRequest,
    GenerateContentResponse,
    Content,
    Tool,
    ToolConfig,
    FunctionDeclaration,
    FunctionCall,
    FunctionResponse,
    ToolCallChunk // Re-export LangChain's ToolCallChunk
}

export { HarmBlockThreshold, HarmCategory, SchemaType }
