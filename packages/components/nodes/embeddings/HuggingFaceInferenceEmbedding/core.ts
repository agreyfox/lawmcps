import { HfInference } from '@huggingface/inference'
import { Embeddings, EmbeddingsParams } from '@langchain/core/embeddings'
import { getEnvironmentVariable } from '../../../src/utils'
import fetch from 'node-fetch'
import { HttpsProxyAgent } from 'https-proxy-agent'
import { SocksProxyAgent } from 'socks-proxy-agent'

// 输出环境变量，用于调试
console.log(`[CONFIG] HTTP_PROXY=${process.env.HTTP_PROXY || '未设置'}`)
console.log(`[CONFIG] HTTPS_PROXY=${process.env.HTTPS_PROXY || '未设置'}`)
console.log(`[CONFIG] SOCKS_PROXY=${process.env.SOCKS_PROXY || '未设置'}`)
console.log(`[CONFIG] NO_PROXY=${process.env.NO_PROXY || '未设置'}`)
console.log(`[CONFIG] API KEY长度=${getEnvironmentVariable('HUGGINGFACEHUB_API_KEY')?.length || 0}`)

export interface HuggingFaceInferenceEmbeddingsParams extends EmbeddingsParams {
    apiKey?: string
    model?: string
    endpoint?: string
}

export class HuggingFaceInferenceEmbeddings extends Embeddings implements HuggingFaceInferenceEmbeddingsParams {
    apiKey?: string
    endpoint?: string
    model: string
    client: HfInference
    endpointClient: any // 存储endpoint客户端
    agent: any // 代理代理

    constructor(fields?: HuggingFaceInferenceEmbeddingsParams) {
        super(fields ?? {})

        this.model = fields?.model ?? 'sentence-transformers/distilbert-base-nli-mean-tokens'
        this.apiKey = fields?.apiKey ?? getEnvironmentVariable('HUGGINGFACEHUB_API_KEY')
        this.endpoint = fields?.endpoint ?? ''

        // 设置代理
        this.agent = this.setupProxy()

        // 创建基本客户端，如果有代理则使用自定义fetch
        if (this.agent) {
            console.log('[INFO] 使用代理配置创建HuggingFace客户端')
            // 创建使用代理的自定义fetch函数
            const customFetch = (url: string, options: any = {}) => {
                return fetch(url, {
                    ...options,
                    agent: this.agent
                })
            }

            // 使用自定义fetch创建客户端
            this.client = new HfInference(this.apiKey, {
                fetch: customFetch as any
            })
        } else {
            this.client = new HfInference(this.apiKey)
        }

        // 如果提供了endpoint，创建并存储endpoint客户端
        if (this.endpoint) {
            console.log(`[INFO] Configuring endpoint: ${this.endpoint}`)
            this.endpointClient = this.client.endpoint(this.endpoint)
        }
    }

    /**
     * 设置代理配置
     */
    private setupProxy(): any {
        const httpsProxy = process.env.HTTPS_PROXY || process.env.https_proxy
        const httpProxy = process.env.HTTP_PROXY || process.env.http_proxy
        const socksProxy = process.env.SOCKS_PROXY || process.env.socks_proxy

        if (socksProxy) {
            console.log(`[INFO] 使用SOCKS代理: ${socksProxy}`)
            return new SocksProxyAgent(socksProxy)
        } else if (httpsProxy) {
            console.log(`[INFO] 使用HTTPS代理: ${httpsProxy}`)
            return new HttpsProxyAgent(httpsProxy)
        } else if (httpProxy) {
            console.log(`[INFO] 使用HTTP代理: ${httpProxy}`)
            return new HttpsProxyAgent(httpProxy)
        }

        console.log('[INFO] 未配置代理')
        return null
    }

    /**
     * 使用代理支持的直接HTTP请求
     */
    private async makeProxyRequest(url: string, payload: any): Promise<any> {
        const fetchOptions: any = {
            method: 'POST',
            headers: {
                Authorization: `Bearer ${this.apiKey}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(payload)
        }

        // 如果有代理，添加到选项中
        if (this.agent) {
            fetchOptions.agent = this.agent
        }

        const response = await fetch(url, fetchOptions)

        if (!response.ok) {
            const errorText = await response.text()
            throw new Error(`HTTP ${response.status}: ${response.statusText}. Response: ${errorText}`)
        }

        return await response.json()
    }

    /**
     * 从各种响应格式中提取嵌入向量
     */
    private extractEmbeddings(response: any): number[][] {
        console.log('[DEBUG] 原始响应类型:', typeof response)

        try {
            // 尝试记录一些响应内容用于调试
            if (typeof response === 'object') {
                console.log('[DEBUG] 响应键:', Object.keys(response))
                console.log('[DEBUG] 响应片段:', JSON.stringify(response).substring(0, 200) + '...')
            } else {
                console.log('[DEBUG] 响应预览:', String(response).substring(0, 200) + '...')
            }
        } catch (e) {
            console.log('[DEBUG] 无法序列化响应进行日志记录')
        }

        // 处理OpenAI兼容格式
        if (response && response.data && Array.isArray(response.data)) {
            console.log('[INFO] 检测到OpenAI兼容的响应格式')

            // 格式: { data: [ { embedding: [...] }, ... ] }
            if (response.data[0] && response.data[0].embedding && Array.isArray(response.data[0].embedding)) {
                return response.data.map((item: any) => item.embedding)
            }

            // 格式: { data: [ [...], ... ] }
            if (Array.isArray(response.data[0])) {
                return response.data
            }
        }

        // 处理 { embeddings: [...] } 格式
        if (response && response.embeddings && Array.isArray(response.embeddings)) {
            console.log("[INFO] 在'embeddings'字段中找到嵌入")
            return response.embeddings
        }

        // 如果响应本身是嵌入数组
        if (Array.isArray(response)) {
            if (Array.isArray(response[0])) {
                return response
            } else if (typeof response[0] === 'number') {
                // 单个嵌入作为平面数组
                return [response]
            }
        }

        console.error('[ERROR] 无法从响应确定嵌入格式:', response)
        throw new Error('无效的嵌入响应格式')
    }

    async _embed(texts: string[]): Promise<number[][]> {
        // 替换换行符，这可能会对性能产生负面影响
        const clean = texts.map((text) => text.replace(/\n/g, ' '))

        console.log(
            'FLOWISE_DEBUG: Attempting fetch to:',
            clean.length > 5 ? `${clean.length} texts (first: "${clean[0].substring(0, 40)}...")` : clean
        )
        console.log('FLOWISE_DEBUG: Using endpoint:', this.endpoint || 'none (standard API)')
        console.log('FLOWISE_DEBUG: Using proxy:', this.agent ? 'yes' : 'no')

        try {
            let result: any

            if (this.endpoint) {
                console.log(`[INFO] Using custom endpoint: ${this.endpoint}`)

                // 如果有代理，使用直接HTTP请求而不是HF客户端
                if (this.agent) {
                    console.log('[INFO] 使用代理的直接HTTP请求到自定义端点')
                    result = await this.makeProxyRequest(this.endpoint, {
                        inputs: clean
                    })
                } else {
                    // 使用已存储的endpoint客户端（如果有）
                    let clientToUse = this.endpointClient || this.client.endpoint(this.endpoint)

                    // 使用request方法绕过类型检查
                    console.log('[INFO] 使用endpoint客户端的request方法')
                    result = await clientToUse.request({
                        inputs: clean
                    })
                }

                console.log('[DEBUG] 原始响应片段:', JSON.stringify(result).substring(0, 300))

                // 从服务器返回的任何格式中提取嵌入
                result = this.extractEmbeddings(result)
            } else {
                console.log(`[INFO] Using standard API with model: ${this.model}`)

                if (this.agent) {
                    console.log('[INFO] 使用代理的直接HTTP请求到HuggingFace API')
                    const apiUrl = `https://api-inference.huggingface.co/pipeline/feature-extraction/${this.model}`
                    result = await this.makeProxyRequest(apiUrl, {
                        inputs: clean
                    })
                } else {
                    // 对于标准HuggingFace API，使用类型化的featureExtraction方法
                    const obj = {
                        inputs: clean,
                        model: this.model // 标准API需要
                    }

                    // 使用普通方法，它强制类型检查
                    result = await this.caller.callWithOptions({}, this.client.featureExtraction.bind(this.client), obj)
                }
            }

            // 验证结果
            if (!result || !Array.isArray(result) || result.length === 0) {
                throw new Error('未返回嵌入')
            }

            // 记录成功
            console.log(`[SUCCESS] 获得嵌入，维度: ${result[0].length}`)
            return result as number[][]
        } catch (error) {
            console.error(`[ERROR] 获取嵌入失败: ${error.message}`)

            // 添加有用的调试信息
            if (this.endpoint) {
                console.error(`[INFO] 检查您在 ${this.endpoint} 的嵌入服务器是否返回正确的嵌入`)
                console.error(`[INFO] 您可以尝试直接curl请求:`)
                console.error(`curl -X POST ${this.endpoint} -H "Content-Type: application/json" -d '{"inputs": ["test text"]}'`)
            }

            // 代理相关的调试信息
            if (this.agent) {
                console.error('[INFO] 代理配置详情:')
                console.error(`- HTTPS_PROXY: ${process.env.HTTPS_PROXY || '未设置'}`)
                console.error(`- HTTP_PROXY: ${process.env.HTTP_PROXY || '未设置'}`)
                console.error(`- SOCKS_PROXY: ${process.env.SOCKS_PROXY || '未设置'}`)
            }

            throw error
        }
    }

    async embedQuery(document: string): Promise<number[]> {
        const res = await this._embed([document])
        return res[0]
    }

    async embedDocuments(documents: string[]): Promise<number[][]> {
        return this._embed(documents)
    }
}
