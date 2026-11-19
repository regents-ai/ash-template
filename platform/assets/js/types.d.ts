declare module "phoenix" {
  export const Socket: unknown
}

declare module "phoenix_live_view" {
  // The exact surface this application uses from phoenix_live_view 1.2.7.
  export class LiveSocket {
    constructor(path: string, socket: unknown, options: Record<string, unknown>)
    connect(): void
    getSocket(): {connect: () => void}
  }
}

declare module "gifenc" {
  // The exact surface the splats page's GIF (splats/gif.ts) uses from gifenc 1.0.3.
  type FrameOptions = {
    palette?: number[][]
    delay?: number
    repeat?: number
    transparent?: boolean
    transparentIndex?: number
    dispose?: number
    colorDepth?: number
  }
  export function GIFEncoder(): {
    writeFrame(index: Uint8Array, width: number, height: number, options: FrameOptions): void
    finish(): void
    bytes(): Uint8Array<ArrayBuffer>
  }
}

declare module "phoenix-colocated/ash_template" {
  export const hooks: Record<string, Record<string, (...args: unknown[]) => unknown>>
}

declare module "*.css"

// The WebMCP draft's document.modelContext. Browsers without it have no such
// property; app.ts checks `"modelContext" in document` before loading public_tools.ts.
type ModelContextTool = {
  name: string
  title: string
  description: string
  inputSchema: object
  annotations: object
  execute(input: unknown, client: {signal?: AbortSignal}): Promise<unknown>
}

interface ModelContext {
  registerTool(tool: ModelContextTool, options: {signal: AbortSignal}): Promise<void>
  getTools(): Promise<Array<{name: string}>>
}

interface Document {
  readonly modelContext: ModelContext
}

interface Window {
  liveSocket: import("phoenix_live_view").LiveSocket
  // The agent's browser host posting the feedback tool's text to Patchbay
  // (feedback_tool.ts), answering {thread_id, url} or {error}; regents browser gives a
  // page this, ordinary browsers do not.
  regentsFeedback?: (input: {title: string; body_markdown: string; client_request_id: string; public: true}) => Promise<unknown>
}
