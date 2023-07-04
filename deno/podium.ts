import type { LuaEngine } from "https://esm.sh/wasmoon@1";
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
  luaEngine: LuaEngine;
  podiumUrl: string;
}

export async function createPodium(options: PodiumOptions): Promise<Podium> {
  const podiumLua = await fetch(options.podiumUrl).then((r) => r.text());
  return await options.luaEngine.doString(podiumLua.replace("#!/usr/bin/env lua", ""));
}
