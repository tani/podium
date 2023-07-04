import fengari from "https://esm.sh/fengari@0.1.4"

function ensure(type: string, fun: string, stack: unknown, ...args: unknown[]): void {
  if (fengari.lua[fun](stack, ...args) !== fengari.lua[type]) {
    fengari.lua.lua_close(stack);
    throw new Error(`${fun}(<stack>, ${args.join(", ")}) is not a ${type}`)
  }
}

export async function process(source: string, backendName: string): Promise<string>{
  const lua = fengari.lua
  const lauxlib = fengari.lauxlib
  const lualib = fengari.lualib
  const L = lauxlib.luaL_newstate()
  lualib.luaL_openlibs(L)
  const rawCode = await fetch(new URL("./podium.lua", import.meta.url)).then(r => r.text())
  const luaCode = fengari.to_luastring(rawCode.replace("#!/usr/bin/env lua", ""));
  if (lauxlib.luaL_dostring(L, luaCode) !== lua.LUA_OK) {
    lua.lua_close(L);
    throw new Error(lua.lua_tojsstring(L, -1))
  }
  ensure("LUA_TTABLE", "lua_getfield", L, -1, "PodiumProcessor")
  ensure("LUA_TFUNCTION", "lua_getfield", L, -1, "new")
  ensure("LUA_TTABLE", "lua_getfield", L, -3, backendName)
  ensure("LUA_OK", "lua_pcall", L, 1, 1, 0)
  lua.lua_setglobal(L, "processor")
  ensure("LUA_TTABLE", "lua_getglobal", L, "processor")
  ensure("LUA_TFUNCTION", "lua_getfield", L, -1, "process")
  ensure("LUA_TTABLE", "lua_getglobal", L, "processor")
  lua.lua_pushliteral(L, source)
  ensure("LUA_OK", "lua_pcall", L, 2, 1, 0)
  const result = lua.lua_tojsstring(L, -1)
  lua.lua_close(L);
  return result
}
