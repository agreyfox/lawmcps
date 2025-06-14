// --- Core Langchain/Flowise Imports ---
import { Agent } from 'http' // Needed for proxy agent type
import { BaseChatModel, type BaseChatModelCallOptions } from '@langchain/core/language_models/chat_models'
import {
    BaseMessage,
    AIMessage,
    HumanMessage,
    SystemMessage,
    ToolMessage,
    AIMessageChunk,
    type MessageContent
} from '@langchain/core/messages'
import { isAIMessage, isHumanMessage, isSystemMessage, isToolMessage } from '@langchain/core/messages'
import type { ToolCallChunk } from '@langchain/core/messages/tool'
import { CallbackManagerForLLMRun } from '@langchain/core/callbacks/manager'
import { ChatResult, ChatGenerationChunk } from '@langchain/core/outputs'
import type { Runnable } from '@langchain/core/runnables'
import { zodToJsonSchema } from 'zod-to-json-schema'
import * as z from 'zod'

// --- Fetch and Proxy Imports ---
import fetch from 'node-fetch'
import { HttpsProxyAgent } from 'https-proxy-agent'
import { SocksProxyAgent } from 'socks-proxy-agent'

// --- Core Langchain Imports for bindTools ---
import type { StructuredToolInterface } from '@langchain/core/tools'

// --- Types for the Node Configuration (using @langchain/google-genai for base class) ---
import { ChatGoogleGenerativeAI } from '@langchain/google-genai'
import type { GoogleGenerativeAIChatInput } from '@langchain/google-genai'

// --- Updated imports from googleTypes.ts ---
import { HarmBlockThreshold, HarmCategory, SchemaType } from '@google/generative-ai'

import type {
    SafetySetting,
    GenerateContentRequest,
    GenerateContentResponse,
    GenerationConfig,
    Content,
    Part,
    Tool,
    ToolConfig,
    FunctionDeclaration,
    FunctionCall,
    FunctionResponse,
    FunctionDeclarationSchema
} from '@google/generative-ai'

import { FunctionCallingMode } from './googleTypes'

// --- Flowise Node Imports ---
import { ICommonObject, INode, INodeData, INodeParams, INodeOptionsValue } from '../../../src/Interface'
import { convertMultiOptionsToStringArray, getBaseClasses, getCredentialData, getCredentialParam } from '../../../src/utils'
import { getModels, MODEL_TYPE } from '../../../src/modelLoader'

// --- Define ToolCall interface ---
interface ToolCall {
    id?: string
    name: string
    args: any
}

// --- Define BindToolsInput type ---
type BindToolsInput = StructuredToolInterface

// -------------------------------- Custom Proxy-Aware Class --------------------------------

interface ChatGoogleGeminiCallOptions extends BaseChatModelCallOptions {
    tool_choice?: string
}

class ChatGoogleGeminiWithProxy extends BaseChatModel<ChatGoogleGeminiCallOptions> {
    // --- Model Configuration ---
    modelName: string
    apiKey: string
    temperature?: number
    maxOutputTokens?: number
    topP?: number
    topK?: number
    stopSequences?: string[]
    safetySettings?: SafetySetting[]
    streaming: boolean
    baseURL?: string

    // --- Proxy Configuration ---
    agent?: Agent

    // --- Internal State ---
    private GcpVertex = false

    // --- Tool Calling Configuration ---
    googleTools?: Tool[]
    toolConfig?: ToolConfig

    // --- Gemini 2.0+ features ---
    responseMimeType?: string
    systemInstruction?: string
    enableCodeExecution?: boolean
    enableGoogleSearch?: boolean

    // --- Constructor ---
    constructor(
        fields: Partial<GoogleGenerativeAIChatInput> & {
            apiKey: string
            agent?: Agent
            baseURL?: string
            googleTools?: Tool[]
            toolConfig?: ToolConfig
            modelName?: string
            responseMimeType?: string
            systemInstruction?: string
            enableCodeExecution?: boolean
            enableGoogleSearch?: boolean
            safetySettings?: SafetySetting[]
            temperature?: number
            maxOutputTokens?: number
            topP?: number
            topK?: number
            stopSequences?: string[]
            streaming?: boolean
        }
    ) {
        super(fields as any)
        this.apiKey = fields.apiKey
        this.modelName = fields.modelName ?? 'gemini-2.0-flash-exp'
        this.temperature = fields.temperature
        this.maxOutputTokens = fields.maxOutputTokens
        this.topP = fields.topP
        this.topK = fields.topK
        this.stopSequences = fields.stopSequences
        this.safetySettings = fields.safetySettings
        this.streaming = fields.streaming ?? true
        this.baseURL = fields.baseURL
        this.agent = fields.agent
        this.googleTools = fields.googleTools
        this.toolConfig = fields.toolConfig

        if (this.baseURL?.includes('googleapis.com') && this.baseURL.includes('aiplatform')) {
            this.GcpVertex = true
            console.log('[ChatGoogleGeminiWithProxy] Detected Vertex AI endpoint.')
        }

        // Assign Gemini 2.0+ fields
        this.responseMimeType = fields.responseMimeType
        this.systemInstruction = fields.systemInstruction
        this.enableCodeExecution = fields.enableCodeExecution
        this.enableGoogleSearch = fields.enableGoogleSearch
    }

    _llmType(): string {
        return 'chatGoogleGemini_with_proxy'
    }

    get identifyingParams(): ICommonObject {
        return {
            model: this.modelName,
            temperature: this.temperature,
            maxOutputTokens: this.maxOutputTokens,
            topP: this.topP,
            topK: this.topK,
            stopSequences: this.stopSequences,
            safetySettings: this.safetySettings,
            streaming: this.streaming,
            baseURL: this.baseURL,
            GcpVertex: this.GcpVertex,
            responseMimeType: this.responseMimeType,
            systemInstruction: this.systemInstruction,
            enableCodeExecution: this.enableCodeExecution,
            enableGoogleSearch: this.enableGoogleSearch
        }
    }

    // --- Core Logic (_generate, _streamResponseChunks) - 保持所有现有功能 ---

    async _generate(
        messages: BaseMessage[],
        options: this['ParsedCallOptions'],
        runManager?: CallbackManagerForLLMRun | undefined
    ): Promise<ChatResult> {
        if (this.streaming) {
            // Use streaming and aggregate
            const stream = this._streamResponseChunks(messages, options, runManager)
            let finalResult: ChatResult | undefined
            let aggregatedContent = ''
            let aggregatedToolCalls: { name?: string; args: string; id?: string; index?: number }[] = []
            let firstChunk = true

            for await (const chunk of stream) {
                aggregatedContent += chunk.text

                if (
                    chunk.message instanceof AIMessageChunk &&
                    chunk.message.tool_call_chunks &&
                    Array.isArray(chunk.message.tool_call_chunks)
                ) {
                    chunk.message.tool_call_chunks.forEach((tcChunk: ToolCallChunk) => {
                        let existingCall = aggregatedToolCalls.find((tc) => tc.id && tcChunk.id && tc.id === tcChunk.id)
                        if (existingCall) {
                            existingCall.args += tcChunk.args ?? ''
                            if (!existingCall.name && tcChunk.name) {
                                existingCall.name = tcChunk.name
                            }
                        } else if (tcChunk.id) {
                            aggregatedToolCalls.push({
                                name: tcChunk.name,
                                args: tcChunk.args ?? '',
                                id: tcChunk.id,
                                index: tcChunk.index
                            })
                        }
                    })
                }

                if (firstChunk) {
                    finalResult = {
                        generations: [
                            {
                                text: '',
                                message: new AIMessage({
                                    content: '',
                                    additional_kwargs: chunk.message.additional_kwargs ?? {},
                                    response_metadata: chunk.generationInfo?.response_metadata ?? {},
                                    tool_calls: []
                                })
                            }
                        ],
                        llmOutput: chunk.generationInfo?.llmOutput ?? {}
                    }
                    firstChunk = false
                } else if (finalResult) {
                    if (chunk.message.additional_kwargs) {
                        Object.assign(finalResult.generations[0].message.additional_kwargs, chunk.message.additional_kwargs)
                    }
                    if (chunk.generationInfo?.response_metadata) {
                        Object.assign(
                            (finalResult.generations[0].message as AIMessage).response_metadata,
                            chunk.generationInfo.response_metadata
                        )
                    }
                    if (chunk.generationInfo?.llmOutput) {
                        Object.assign(finalResult.llmOutput ?? {}, chunk.generationInfo.llmOutput)
                    }
                }
            }

            if (!finalResult) {
                throw new Error('Streaming finished without producing any chunks.')
            }

            finalResult.generations[0].text = aggregatedContent
            ;(finalResult.generations[0].message as AIMessage).content = aggregatedContent

            const finalParsedToolCalls: ToolCall[] = aggregatedToolCalls
                .filter((tc) => tc.name && tc.id)
                .map((tc) => {
                    try {
                        return {
                            name: tc.name!,
                            args: JSON.parse(tc.args || '{}'),
                            id: tc.id!
                        }
                    } catch (e) {
                        console.warn(`[ChatGoogleGemini _generate] Failed to parse aggregated tool call args for ID ${tc.id}: ${tc.args}`)
                        return { name: tc.name!, args: {}, id: tc.id! }
                    }
                })
            ;(finalResult.generations[0].message as AIMessage).tool_calls = finalParsedToolCalls

            return finalResult
        } else {
            // Non-streaming
            const requestBody = this.createRequestBody(messages, false)
            const url = this.buildApiUrl(false)
            const headers = this.buildHeaders()

            console.log(`[ChatGoogleGeminiWithProxy _generate] Request to ${url}`)

            const response = await fetch(url, {
                method: 'POST',
                headers: headers,
                body: JSON.stringify(requestBody),
                agent: this.agent
            } as any)

            if (!response.ok) {
                const errorBody = await response.text()
                console.error(`[ChatGoogleGeminiWithProxy _generate] API Error ${response.status}: ${errorBody}`)
                throw new Error(`Google API Error ${response.status}: ${errorBody}`)
            }

            const responseData = (await response.json()) as GenerateContentResponse

            const candidate = responseData.candidates?.[0]
            if (!candidate) {
                throw new Error('No candidate found in Google API response.')
            }

            let content = ''
            let toolCalls: ToolCall[] = []

            if (candidate.content?.parts) {
                for (const part of candidate.content.parts) {
                    if (part.text) {
                        content += part.text
                    } else if (part.functionCall) {
                        const funcCall = part.functionCall
                        const toolCallId = `${funcCall.name}_${Date.now()}_${Math.random().toString(36).substring(2, 15)}`
                        toolCalls.push({
                            id: toolCallId,
                            name: funcCall.name,
                            args: funcCall.args ?? {}
                        })
                    }
                }
            }

            const generation: ChatResult['generations'][0] = {
                text: content,
                message: new AIMessage({
                    content: content,
                    tool_calls: toolCalls,
                    additional_kwargs: {},
                    response_metadata: {
                        finishReason: candidate.finishReason,
                        safetyRatings: candidate.safetyRatings
                    }
                })
            }

            const llmOutput: ChatResult['llmOutput'] = {}

            return { generations: [generation], llmOutput }
        }
    }

    async *_streamResponseChunks(
        messages: BaseMessage[],
        options: this['ParsedCallOptions'],
        runManager?: CallbackManagerForLLMRun | undefined
    ): AsyncGenerator<ChatGenerationChunk> {
        const requestBody = this.createRequestBody(messages, true)
        const url = this.buildApiUrl(true)
        const headers = this.buildHeaders()

        console.log(`[ChatGoogleGeminiWithProxy _stream] Request to ${url}`)

        const response = await fetch(url, {
            method: 'POST',
            headers: headers,
            body: JSON.stringify(requestBody),
            agent: this.agent
        } as any)

        if (!response.ok || !response.body) {
            const errorBody = await response.text()
            console.error(`[ChatGoogleGeminiWithProxy _stream] API Error ${response.status}: ${errorBody}`)
            throw new Error(`Google API Error ${response.status}: ${errorBody}`)
        }

        const decoder = new TextDecoder()
        let buffer = ''
        let currentToolCallChunks: ToolCallChunk[] = []

        // Fix: Use proper Node.js ReadableStream handling
        for await (const chunk of response.body as any) {
            buffer += decoder.decode(chunk as any, { stream: true })

            let newlineIndex
            while ((newlineIndex = buffer.indexOf('\n')) !== -1) {
                const line = buffer.substring(0, newlineIndex).trim()
                buffer = buffer.substring(newlineIndex + 1)

                let jsonData = null
                if (line.startsWith('data: ')) {
                    jsonData = line.substring(5).trim()
                } else if (line.startsWith('{') && line.endsWith('}')) {
                    jsonData = line
                }

                if (jsonData) {
                    try {
                        const chunkData = JSON.parse(jsonData) as GenerateContentResponse
                        const candidate = chunkData.candidates?.[0]
                        if (!candidate) continue

                        let chunkText = ''
                        let functionCallPart: Part | undefined

                        if (candidate.content?.parts) {
                            for (const part of candidate.content.parts) {
                                if (part.text) {
                                    chunkText += part.text
                                } else if (part.functionCall) {
                                    functionCallPart = part
                                }
                            }
                        }

                        let toolCallChunkForYield: ToolCallChunk[] | undefined = undefined

                        if (functionCallPart?.functionCall) {
                            const funcCall = functionCallPart.functionCall
                            const toolCallId = `${funcCall.name}_${Date.now()}_${Math.random().toString(36).substring(2, 15)}`
                            const argsStringChunk = JSON.stringify(funcCall.args ?? {})

                            const currentChunk: ToolCallChunk = {
                                name: funcCall.name,
                                args: argsStringChunk,
                                id: toolCallId,
                                index: currentToolCallChunks.length,
                                type: 'tool_call_chunk' as const
                            }
                            currentToolCallChunks.push(currentChunk)
                            toolCallChunkForYield = [currentChunk]

                            console.log(
                                '[ChatGoogleGeminiWithProxy _stream] Parsed Tool Call Chunk:',
                                JSON.stringify(toolCallChunkForYield, null, 2)
                            )
                        }

                        if (chunkText || toolCallChunkForYield) {
                            const generationChunk = new ChatGenerationChunk({
                                text: chunkText,
                                message: new AIMessageChunk({
                                    content: chunkText,
                                    tool_call_chunks: toolCallChunkForYield,
                                    additional_kwargs: {},
                                    response_metadata: {
                                        finishReason: candidate.finishReason,
                                        safetyRatings: candidate.safetyRatings
                                    }
                                }),
                                generationInfo: {
                                    response_metadata: {
                                        finishReason: candidate.finishReason,
                                        safetyRatings: candidate.safetyRatings
                                    }
                                }
                            })

                            yield generationChunk
                            if (chunkText) {
                                await runManager?.handleLLMNewToken(generationChunk.text)
                            }
                        }
                    } catch (e) {
                        console.error('[ChatGoogleGeminiWithProxy _stream] Error parsing stream chunk:', e, 'Line:', line)
                    }
                }
            }
        }

        if (buffer.trim()) {
            console.warn('[ChatGoogleGeminiWithProxy _stream] Processing remaining buffer:', buffer.trim())
        }
    }

    // --- Helper Methods - 保持所有现有功能 ---

    private buildApiUrl(streaming: boolean): string {
        const streamSuffix = streaming ? ':streamGenerateContent?alt=sse' : ':generateContent'
        const defaultBase = 'https://generativelanguage.googleapis.com/v1beta/models/'
        const base = this.baseURL || defaultBase
        const resolvedBase = base === defaultBase || base.endsWith('/') ? base : `${base}/`
        return `${resolvedBase}${this.modelName}${streamSuffix}`
    }

    private buildHeaders(): Record<string, string> {
        return {
            'Content-Type': 'application/json',
            'x-goog-api-key': this.apiKey
        }
    }

    private createRequestBody(messages: BaseMessage[], streaming: boolean): GenerateContentRequest {
        const contents: Content[] = messages.map((msg) => this.messageToContent(msg))

        const generationConfig: Partial<GenerationConfig> = {}
        if (this.temperature !== undefined) generationConfig.temperature = this.temperature
        if (this.maxOutputTokens !== undefined) generationConfig.maxOutputTokens = this.maxOutputTokens
        if (this.topP !== undefined) generationConfig.topP = this.topP
        if (this.topK !== undefined) generationConfig.topK = this.topK
        if (this.stopSequences !== undefined) generationConfig.stopSequences = this.stopSequences
        if (this.responseMimeType !== undefined) generationConfig.responseMimeType = this.responseMimeType

        const requestBody: GenerateContentRequest = {
            contents: contents,
            ...(Object.keys(generationConfig).length > 0 && { generationConfig: generationConfig as GenerationConfig }),
            ...(this.safetySettings && { safetySettings: this.safetySettings }),
            ...(this.systemInstruction && { systemInstruction: { role: 'user', parts: [{ text: this.systemInstruction }] } }),
            ...(this.googleTools && this.googleTools.length > 0 && { tools: this.googleTools }),
            ...(this.toolConfig && { toolConfig: this.toolConfig })
        }

        // Add tools for code execution and Google search
        if (this.enableCodeExecution || this.enableGoogleSearch) {
            const additionalTools: Tool[] = []

            if (this.enableCodeExecution) {
                additionalTools.push({
                    functionDeclarations: [],
                    codeExecution: {}
                })
            }

            if (this.enableGoogleSearch) {
                additionalTools.push({
                    functionDeclarations: [],
                    googleSearchRetrieval: {}
                })
            }

            requestBody.tools = [...(requestBody.tools || []), ...additionalTools]
        }

        return requestBody
    }

    private messageToContent(message: BaseMessage): Content {
        if (isToolMessage(message)) {
            console.log('[ChatGoogleGeminiWithProxy messageToContent] Converting ToolMessage:', message)

            let toolName = (message as any).name
            if (!toolName && message.additional_kwargs && typeof message.additional_kwargs.name === 'string') {
                toolName = message.additional_kwargs.name
            }
            if (!toolName) {
                if (message.tool_call_id && typeof message.tool_call_id === 'string') {
                    const match = message.tool_call_id.match(/^([^_]+)_/)
                    if (match && match[1]) {
                        toolName = match[1]
                        console.warn(`[ChatGoogleGemini messageToContent] Inferred tool name "${toolName}" from tool_call_id.`)
                    }
                }
            }
            if (!toolName) {
                console.error(
                    '[ChatGoogleGeminiWithProxy messageToContent] Could not determine tool name from ToolMessage. Using "unknown_function". Message:',
                    message
                )
                toolName = 'unknown_function'
            }

            return {
                role: 'function',
                parts: [
                    {
                        functionResponse: {
                            name: toolName,
                            response: {
                                content: message.content
                            }
                        }
                    }
                ]
            }
        }

        let role: 'user' | 'model'
        if (isHumanMessage(message)) {
            role = 'user'
        } else if (isAIMessage(message)) {
            role = 'model'
            const aiMessage = message as AIMessage
            const toolCalls = aiMessage.tool_calls
            if (
                toolCalls &&
                Array.isArray(toolCalls) &&
                toolCalls.length > 0 &&
                typeof toolCalls[0] === 'object' &&
                toolCalls[0] !== null &&
                'name' in toolCalls[0] &&
                'args' in toolCalls[0]
            ) {
                const parts: Part[] = toolCalls.map((tc) => {
                    let argsObject: Record<string, any>
                    try {
                        argsObject = typeof tc.args === 'string' ? JSON.parse(tc.args) : tc.args ?? {}
                    } catch (e) {
                        console.error(
                            `[ChatGoogleGemini messageToContent] Failed to parse tool call args for history: ${JSON.stringify(tc.args)}`,
                            e
                        )
                        argsObject = {}
                    }
                    return {
                        functionCall: {
                            name: tc.name!,
                            args: argsObject
                        }
                    }
                })
                if (aiMessage.content && typeof aiMessage.content === 'string' && aiMessage.content.trim() !== '') {
                    parts.unshift({ text: aiMessage.content })
                }
                return { role: role, parts: parts }
            }
        } else if (isSystemMessage(message)) {
            console.warn('[ChatGoogleGeminiWithProxy] System messages are treated as user messages for Google Gemini.')
            role = 'user'

            // 修复：正确处理不同类型的 MessageContent
            const systemMessage = message as SystemMessage
            const messageContent = systemMessage.content
            const contentText =
                typeof messageContent === 'string'
                    ? messageContent
                    : Array.isArray(messageContent)
                    ? messageContent
                          .map((item) => {
                              if (typeof item === 'string') {
                                  return item
                              } else if (item.type === 'text') {
                                  return item.text || ''
                              } else if (item.type === 'image_url') {
                                  return '[Image]' // 或者其他表示图片的文本
                              } else {
                                  return ''
                              }
                          })
                          .join(' ')
                    : String(messageContent)

            const systemPart: Part = { text: `System Instruction: ${contentText}` }
            return { role: role, parts: [systemPart] }
        } else {
            console.warn(`[ChatGoogleGeminiWithProxy] Unsupported message type. Treating as user.`)
            role = 'user'
        }

        let parts: Part[] = []
        if (typeof message.content === 'string') {
            parts = [{ text: message.content }]
        } else if (Array.isArray(message.content)) {
            const mappedParts = message.content
                .map((item) => {
                    if (typeof item === 'string') {
                        return { text: item } as Part
                    } else if (item.type === 'text') {
                        return { text: item.text } as Part
                    } else if (item.type === 'image_url' && item.image_url?.url) {
                        const url = item.image_url.url
                        if (url.startsWith('data:image/')) {
                            const [mimeTypePart, base64Data] = url.split(';base64,')
                            const mimeType = mimeTypePart.split(':')[1]
                            return { inlineData: { mimeType, data: base64Data } } as Part
                        } else {
                            console.warn(`[ChatGoogleGemini messageToContent] Skipping non-data URI image URL: ${url}`)
                            return null
                        }
                    }
                    console.warn(`[ChatGoogleGemini messageToContent] Skipping unsupported content part type: ${item.type}`)
                    return null
                })
                .filter((part): part is Part => part !== null)
            parts = mappedParts
        } else {
            console.warn(
                `[ChatGoogleGeminiWithProxy] Unsupported message content type: ${typeof message.content}. Using empty parts array.`
            )
        }

        return { role: role, parts: parts }
    }

    // --- bindTools Implementation - 保持所有现有功能 ---
    bindTools(
        tools: BindToolsInput[],
        kwargs?: Partial<ChatGoogleGeminiCallOptions>
    ): Runnable<any, AIMessageChunk, ChatGoogleGeminiCallOptions> {
        console.log('[ChatGoogleGemini bindTools INCOMING_TOOLS]:', JSON.stringify(tools, null, 2)) // <--- 添加日志

        // 修复：将所有工具合并到一个 Tool 对象中
        const functionDeclarations: FunctionDeclaration[] = tools
            .map((tool): FunctionDeclaration | null => {
                if (tool && typeof tool === 'object' && 'schema' in tool && tool.schema instanceof z.ZodType) {
                    const structuredTool = tool as StructuredToolInterface
                    const functionDeclaration: FunctionDeclaration = {
                        name: structuredTool.name,
                        description: structuredTool.description || '',
                        parameters: this.convertZodSchemaToGoogleSchema(structuredTool.schema)
                    }
                    console.log(`[ChatGoogleGemini bindTools] Created function declaration for: ${structuredTool.name}`)
                    return functionDeclaration
                } else {
                    console.warn(`[ChatGoogleGemini bindTools] Skipping tool without a valid Zod schema:`, tool)
                    return null
                }
            })
            .filter((func): func is FunctionDeclaration => func !== null)

        const formattedTools: Tool[] = functionDeclarations.length > 0 ? [{ functionDeclarations }] : []

        console.log(`[ChatGoogleGemini bindTools] Total function declarations: ${functionDeclarations.length}`)
        console.log(`[ChatGoogleGemini bindTools FORMATTED_FOR_GEMINI]:`, JSON.stringify(formattedTools, null, 2)) // <--- 已有的日志，也很有用

        let toolConfig: ToolConfig | undefined = this.toolConfig
        const toolChoice = kwargs?.tool_choice
        if (toolChoice) {
            let mode: FunctionCallingMode
            let allowedFunctionNames: string[] | undefined = undefined

            if (toolChoice === 'any') {
                mode = FunctionCallingMode.ANY
            } else if (toolChoice === 'auto') {
                mode = FunctionCallingMode.AUTO
            } else if (toolChoice === 'none') {
                mode = FunctionCallingMode.NONE
            } else if (typeof toolChoice === 'string') {
                mode = FunctionCallingMode.ANY
                allowedFunctionNames = [toolChoice]
            } else {
                console.warn(`[ChatGoogleGeminiWithProxy bindTools] Unsupported object tool_choice: ${JSON.stringify(toolChoice)}`)
                mode = FunctionCallingMode.AUTO
            }

            toolConfig = {
                functionCallingConfig: {
                    mode: mode,
                    ...(allowedFunctionNames && { allowedFunctionNames: allowedFunctionNames })
                }
            }
        } else if (!toolConfig && formattedTools.length > 0) {
            toolConfig = { functionCallingConfig: { mode: FunctionCallingMode.AUTO } }
        }

        const newFields = {
            ...this.invocationParams(kwargs),
            apiKey: this.apiKey,
            agent: this.agent,
            googleTools: formattedTools,
            toolConfig: toolConfig,
            modelName: this.modelName,
            temperature: this.temperature,
            maxOutputTokens: this.maxOutputTokens,
            topP: this.topP,
            topK: this.topK,
            stopSequences: this.stopSequences,
            safetySettings: this.safetySettings,
            streaming: this.streaming,
            baseURL: this.baseURL,
            responseMimeType: this.responseMimeType,
            systemInstruction: this.systemInstruction,
            enableCodeExecution: this.enableCodeExecution,
            enableGoogleSearch: this.enableGoogleSearch
        }

        delete newFields.stop
        delete newFields.timeout
        delete newFields.signal
        delete newFields.callbacks
        delete newFields.tags
        delete newFields.metadata
        delete newFields.runName
        delete newFields.tool_choice

        const constructor = this.constructor as typeof ChatGoogleGeminiWithProxy
        return new constructor(newFields) as Runnable<any, AIMessageChunk, ChatGoogleGeminiCallOptions>
    }

    // --- Schema Conversion Helper - 保持所有现有功能 ---
    private convertZodSchemaToGoogleSchema(schema: z.ZodTypeAny): FunctionDeclarationSchema {
        try {
            const jsonSchema = zodToJsonSchema(schema, {
                target: 'jsonSchema7',
                $refStrategy: 'none',
                // 移除无效的 strictNullChecks 选项
                definitions: {}
            })

            const topLevelDescription = (schema as any)?._def?.description ?? 'Function parameters'

            if (typeof jsonSchema !== 'object' || jsonSchema === null) {
                console.warn('[convertZodSchemaToGoogleSchema] zodToJsonSchema did not return a valid object:', jsonSchema)
                return { type: SchemaType.OBJECT, properties: {}, required: [], description: topLevelDescription }
            }

            const originalProperties =
                typeof (jsonSchema as any).properties === 'object' && (jsonSchema as any).properties !== null
                    ? (jsonSchema as any).properties
                    : {}

            const googleProperties: { [k: string]: any } = {}

            for (const key in originalProperties) {
                if (Object.prototype.hasOwnProperty.call(originalProperties, key)) {
                    const propSchema = originalProperties[key]

                    if (typeof propSchema === 'object' && propSchema !== null) {
                        let googlePropType: SchemaType | undefined = undefined

                        // 处理联合类型（如 string | null）
                        let actualType = propSchema.type
                        if (Array.isArray(propSchema.type)) {
                            // 如果是数组类型，取非 null 的类型
                            actualType = propSchema.type.find((t: string) => t !== 'null') || propSchema.type[0]
                        }

                        if (typeof actualType === 'string') {
                            const jsonSchemaType = actualType.toLowerCase()

                            switch (jsonSchemaType) {
                                case 'string':
                                    googlePropType = SchemaType.STRING
                                    break
                                case 'number':
                                    googlePropType = SchemaType.NUMBER
                                    break
                                case 'integer':
                                    googlePropType = SchemaType.INTEGER
                                    break
                                case 'boolean':
                                    googlePropType = SchemaType.BOOLEAN
                                    break
                                case 'array':
                                    googlePropType = SchemaType.ARRAY
                                    break
                                case 'object':
                                    googlePropType = SchemaType.OBJECT
                                    break
                                default:
                                    console.warn(
                                        `[convertZodSchemaToGoogleSchema] Unhandled JSON schema type "${jsonSchemaType}" for property '${key}'. Defaulting to STRING.`
                                    )
                                    googlePropType = SchemaType.STRING
                            }

                            googleProperties[key] = {
                                type: googlePropType,
                                description: propSchema.description || `Parameter ${key}`,
                                ...(propSchema.enum && { enum: propSchema.enum }),
                                ...(propSchema.items && googlePropType === SchemaType.ARRAY && { items: propSchema.items })
                            }
                        } else {
                            console.warn(
                                `[convertZodSchemaToGoogleSchema] Invalid or missing type for property '${key}'. Assigning default STRING type. Original schema:`,
                                propSchema
                            )
                            googleProperties[key] = { type: SchemaType.STRING, description: `Parameter ${key} (type inferred)` }
                        }
                    }
                }
            }

            // 改进的必需字段处理
            let finalRequired: string[] = []
            if (schema._def?.typeName === 'ZodObject') {
                const shape = schema._def.shape()

                // 只有非可选字段才设为必需
                const requiredFields = Object.keys(shape).filter((key) => {
                    const field = shape[key]
                    const isOptional =
                        field._def.typeName === 'ZodOptional' ||
                        field._def.typeName === 'ZodNullable' ||
                        field._def.typeName === 'ZodDefault' ||
                        (field._def.typeName === 'ZodUnion' && field._def.options?.some((opt: any) => opt._def.typeName === 'ZodNull')) ||
                        field.isOptional?.() ||
                        field.isNullable?.()

                    if (isOptional && googleProperties[key]) {
                        // 为可选字段添加说明，但不设为必需
                        googleProperties[key].description += ' (optional)'
                    }

                    return !isOptional
                })

                finalRequired = requiredFields
            } else {
                // 从 JSON schema 中获取 required 字段
                finalRequired = (jsonSchema as any).required ?? []
            }

            const googleParamsSchema: FunctionDeclarationSchema = {
                type: SchemaType.OBJECT,
                description: topLevelDescription,
                properties: googleProperties,
                required: finalRequired
            }

            console.log('[convertZodSchemaToGoogleSchema] Generated Google Params Schema:', JSON.stringify(googleParamsSchema, null, 2))
            return googleParamsSchema
        } catch (err) {
            console.error('[convertZodSchemaToGoogleSchema] Error converting Zod schema:', err, 'Input Schema:', schema)
            return { type: SchemaType.OBJECT, properties: {}, required: [], description: 'Error converting schema' }
        }
    }
}

// -------------------------------- Flowise Node Class - 保持所有现有功能 --------------------------------

class ChatGoogleGemini_ChatModels implements INode {
    label: string
    name: string
    version: number
    type: string
    icon: string
    category: string
    description: string
    baseClasses: string[]
    credential: INodeParams
    inputs: INodeParams[]

    constructor() {
        this.label = 'ChatGoogleGemini'
        this.name = 'chatGoogleGemini'
        this.version = 2.5
        this.type = 'ChatGoogleGemini'
        this.icon = 'GoogleGemini.svg'
        this.category = 'Chat Models'
        this.description = 'Wrapper around Google Gemini with Proxy Support and Tool Handling'
        this.baseClasses = [this.type, ...getBaseClasses(ChatGoogleGenerativeAI)]
        this.credential = {
            label: 'Connect Credential',
            name: 'credential',
            type: 'credential',
            credentialNames: ['googleGenerativeAI'],
            optional: false,
            description: 'Google Gemini AI credential.'
        }
        this.inputs = [
            { label: 'Cache', name: 'cache', type: 'BaseCache', optional: true },
            {
                label: 'Model Name',
                name: 'modelName',
                type: 'asyncOptions',
                loadMethod: 'listModels',
                default: 'gemini-2.0-flash',
                description: 'Choose from the latest Gemini models including 2.0 series'
            },
            {
                label: 'Custom Model Name',
                name: 'customModelName',
                type: 'string',
                placeholder: 'gemini-2.0-flash-exp',
                description: 'Overrides model selected. Use latest model names like gemini-2.0-flash-exp',
                additionalParams: true,
                optional: true
            },
            { label: 'Temperature', name: 'temperature', type: 'number', step: 0.1, default: 0.9, optional: true },
            { label: 'Streaming', name: 'streaming', type: 'boolean', default: true, optional: true },
            { label: 'Max Output Tokens', name: 'maxOutputTokens', type: 'number', step: 1, optional: true, additionalParams: true },
            { label: 'Top Probability', name: 'topP', type: 'number', step: 0.1, optional: true, additionalParams: true },
            { label: 'Top K', name: 'topK', type: 'number', step: 1, optional: true, additionalParams: true },
            {
                label: 'Stop Sequences',
                name: 'stopSequences',
                type: 'string',
                optional: true,
                additionalParams: true,
                description: 'Comma-separated list of sequences to stop generation.'
            },
            {
                label: 'Response MIME Type',
                name: 'responseMimeType',
                type: 'options',
                options: [
                    { name: 'text/plain', label: 'Plain Text' },
                    { name: 'application/json', label: 'JSON' },
                    { name: 'text/markdown', label: 'Markdown' }
                ],
                optional: true,
                additionalParams: true,
                description: 'Gemini 2.0+ feature: Specify response format'
            },
            {
                label: 'System Instruction',
                name: 'systemInstruction',
                type: 'string',
                rows: 4,
                optional: true,
                additionalParams: true,
                description: 'Gemini 1.5+ feature: System-level instructions for the model'
            },
            {
                label: 'Enable Code Execution',
                name: 'enableCodeExecution',
                type: 'boolean',
                optional: true,
                additionalParams: true,
                description: 'Gemini 2.0+ feature: Allow model to execute code'
            },
            {
                label: 'Enable Google Search',
                name: 'enableGoogleSearch',
                type: 'boolean',
                optional: true,
                additionalParams: true,
                description: 'Gemini 2.0+ feature: Allow model to search Google'
            },
            {
                label: 'Harm Category',
                name: 'harmCategory',
                type: 'multiOptions',
                description: 'Refer to <a target="_blank" href="https://ai.google.dev/docs/safety_setting_gemini">official guide</a>',
                options: Object.values(HarmCategory)
                    .filter((val) => typeof val === 'string')
                    .map((c) => ({ label: c, name: c })),
                optional: true,
                additionalParams: true
            },
            {
                label: 'Harm Block Threshold',
                name: 'harmBlockThreshold',
                type: 'multiOptions',
                description: 'Refer to <a target="_blank" href="https://ai.google.dev/docs/safety_setting_gemini">official guide</a>',
                options: Object.values(HarmBlockThreshold)
                    .filter((val) => typeof val === 'string')
                    .map((t) => ({ label: t, name: t })),
                optional: true,
                additionalParams: true
            },
            {
                label: 'Base URL',
                name: 'baseURL',
                type: 'string',
                optional: true,
                additionalParams: true,
                description: 'Optional. Custom API endpoint base URL. If using Vertex AI, include the project ID and region.'
            }
        ]
    }

    loadMethods = {
        async listModels(): Promise<INodeOptionsValue[]> {
            console.log('Loading models for ChatGoogleGemini same as chatGoogleGenerativeAI')
            try {
                return await getModels(MODEL_TYPE.CHAT, 'chatGoogleGenerativeAI')
            } catch (e) {
                console.error('Error loading models:', e)
                return [
                    { name: 'gemini-2.0-flash-exp', label: 'Gemini 2.0 Flash (Experimental)' },
                    { name: 'gemini-2.0-flash-thinking-exp', label: 'Gemini 2.0 Flash Thinking (Experimental)' },
                    { name: 'gemini-1.5-flash', label: 'Gemini 1.5 Flash' },
                    { name: 'gemini-1.5-flash-latest', label: 'Gemini 1.5 Flash (Latest)' },
                    { name: 'gemini-1.5-flash-002', label: 'Gemini 1.5 Flash 002' },
                    { name: 'gemini-1.5-flash-8b', label: 'Gemini 1.5 Flash 8B' },
                    { name: 'gemini-1.5-flash-8b-latest', label: 'Gemini 1.5 Flash 8B (Latest)' },
                    { name: 'gemini-1.5-pro', label: 'Gemini 1.5 Pro' },
                    { name: 'gemini-1.5-pro-latest', label: 'Gemini 1.5 Pro (Latest)' },
                    { name: 'gemini-1.5-pro-002', label: 'Gemini 1.5 Pro 002' },
                    { name: 'gemini-pro', label: 'Gemini Pro (Legacy)' },
                    { name: 'gemini-pro-vision', label: 'Gemini Pro Vision (Legacy)' }
                ]
            }
        }
    }

    async init(nodeData: INodeData, _: string, options: ICommonObject): Promise<any> {
        const credentialData = await getCredentialData(nodeData.credential ?? '', options)
        const apiKey = getCredentialParam('googleGenerativeAPIKey', credentialData, nodeData)

        if (!apiKey) {
            throw new Error('Google Generative AI API key not found in credentials!')
        }

        const modelNameInput = nodeData.inputs?.modelName as string
        const customModelName = nodeData.inputs?.customModelName as string
        const temperature = nodeData.inputs?.temperature as string
        const maxOutputTokens = nodeData.inputs?.maxOutputTokens as string
        const topP = nodeData.inputs?.topP as string
        const topK = nodeData.inputs?.topK as string
        const stopSequencesStr = nodeData.inputs?.stopSequences as string
        const harmCategory = nodeData.inputs?.harmCategory as string | string[]
        const harmBlockThreshold = nodeData.inputs?.harmBlockThreshold as string | string[]
        const streaming = nodeData.inputs?.streaming as boolean
        const baseURL = nodeData.inputs?.baseURL as string | undefined
        const responseMimeType = nodeData.inputs?.responseMimeType as string
        const systemInstruction = nodeData.inputs?.systemInstruction as string
        const enableCodeExecution = nodeData.inputs?.enableCodeExecution as boolean
        const enableGoogleSearch = nodeData.inputs?.enableGoogleSearch as boolean

        const configFields: {
            apiKey: string
            baseURL?: string
            modelName?: string
            streaming?: boolean
            responseMimeType?: string
            systemInstruction?: string
            enableCodeExecution?: boolean
            enableGoogleSearch?: boolean
            maxOutputTokens?: number
            topP?: number
            topK?: number
            temperature?: number
            stopSequences?: string[]
            safetySettings?: SafetySetting[]
        } = {
            apiKey: apiKey,
            modelName: customModelName || modelNameInput || 'gemini-2.0-flash-exp',
            streaming: streaming ?? true,
            baseURL: baseURL
        }

        if (responseMimeType) configFields.responseMimeType = responseMimeType
        if (systemInstruction) configFields.systemInstruction = systemInstruction
        if (enableCodeExecution) configFields.enableCodeExecution = enableCodeExecution
        if (enableGoogleSearch) configFields.enableGoogleSearch = enableGoogleSearch

        if (maxOutputTokens) configFields.maxOutputTokens = parseInt(maxOutputTokens, 10)
        if (topP) configFields.topP = parseFloat(topP)
        if (topK) configFields.topK = parseInt(topK, 10)
        if (temperature) configFields.temperature = parseFloat(temperature)
        if (stopSequencesStr) {
            configFields.stopSequences = stopSequencesStr
                .split(',')
                .map((s) => s.trim())
                .filter((s) => s)
        }

        let harmCategories: string[] = Array.isArray(harmCategory) ? harmCategory : convertMultiOptionsToStringArray(harmCategory)
        let harmBlockThresholds: string[] = Array.isArray(harmBlockThreshold)
            ? harmBlockThreshold
            : convertMultiOptionsToStringArray(harmBlockThreshold)

        if (harmCategories.length === harmBlockThresholds.length && harmCategories.length > 0) {
            const validSettings: SafetySetting[] = []
            for (let i = 0; i < harmCategories.length; i++) {
                const categoryStr = harmCategories[i]
                const thresholdStr = harmBlockThresholds[i]

                if (
                    Object.values(HarmCategory).includes(categoryStr as HarmCategory) &&
                    Object.values(HarmBlockThreshold).includes(thresholdStr as HarmBlockThreshold)
                ) {
                    validSettings.push({
                        category: categoryStr as HarmCategory,
                        threshold: thresholdStr as HarmBlockThreshold
                    })
                } else {
                    console.warn(
                        `[ChatGoogleGemini Init] Invalid safety setting skipped: Category='${categoryStr}', Threshold='${thresholdStr}'`
                    )
                }
            }
            if (validSettings.length > 0) {
                configFields.safetySettings = validSettings
            }
        } else if (harmCategories.length !== harmBlockThresholds.length) {
            console.warn(
                `[ChatGoogleGemini Init] Harm Category (${harmCategories.length}) & Harm Block Threshold (${harmBlockThresholds.length}) lengths differ. Ignoring safety settings.`
            )
        }

        let agent: Agent | undefined
        const proxyUrl = process.env.HTTPS_PROXY || process.env.ALL_PROXY || process.env.https_proxy || process.env.all_proxy
        const socksProxyUrl = process.env.SOCKS_PROXY || process.env.socks_proxy

        if (socksProxyUrl) {
            try {
                agent = new SocksProxyAgent(socksProxyUrl)
                console.log(`[ChatGoogleGemini Init] Using SOCKS proxy: ${socksProxyUrl}`)
            } catch (e) {
                console.error(`[ChatGoogleGemini Init] Error creating SOCKS proxy agent: ${e}`)
            }
        } else if (proxyUrl) {
            try {
                agent = new HttpsProxyAgent(proxyUrl)
                console.log(`[ChatGoogleGemini Init] Using HTTPS proxy: ${proxyUrl}`)
            } catch (e) {
                console.error(`[ChatGoogleGemini Init] Error creating HTTPS proxy agent: ${e}`)
            }
        } else {
            console.log('[ChatGoogleGemini Init] No proxy configured.')
        }

        try {
            console.log('[ChatGoogleGemini Init] Creating custom ChatGoogleGeminiWithProxy client.')
            const model = new ChatGoogleGeminiWithProxy({ ...configFields, agent: agent })
            return model
        } catch (error: any) {
            console.error('[ChatGoogleGemini Init] Error initializing ChatGoogleGeminiWithProxy client:', error)
            throw error
        }
    }
}

module.exports = { nodeClass: ChatGoogleGemini_ChatModels }
