export type BackendName = 'html' | 'markdown' | 'latex' | 'vimdoc';

export type PodiumProcessor = {
  process(self: PodiumProcessor, source: string): string
}

export type PodiumProcessorFactory = {
  ["new"](backend: unknown): PodiumProcessor;
}

export type Podium = {
  PodiumProcessor: PodiumProcessorFactory;
} & {
  [K in BackendName]: unknown
}

export interface PodiumOptions {
  wasmoonJsUrl: string;
  wasmoonWasmUrl: string;
  podiumUrl: string;
}

export async function createPodium(options: PodiumOptions): Promise<Podium> {
  const { LuaFactory } = await import(options.wasmoonJsUrl);
  const factory = new LuaFactory(options.wasmoonWasmUrl);
  const lua = await factory.createEngine();
  const podiumLua = await fetch(options.podiumUrl).then((r) => r.text());
  return await lua.doString(podiumLua.replace("#!/usr/bin/env lua", ""));
}
