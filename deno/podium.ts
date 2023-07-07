import {LuaFactory} from "https://jspm.dev/wasmoon@1.15.0"

export async function process(source: string, backendName: string): Promise<string>{
  const rawCode = await fetch(new URL("./podium.lua", import.meta.url))
    .then(r => r.text())
    .then(r => r.replace("#!/usr/bin/env lua", ""))
  const lua = await (new LuaFactory('https://unpkg.com/wasmoon@1.15.0/dist/glue.wasm')).createEngine()
  const podium = await lua.doString(rawCode)
  return podium.process(backendName, source)
}
