import fengari from "https://esm.sh/fengari@0.1.4"

function ensure(type: string, lib: string, fun: string, stack: unknown, ...args: unknown[]): void {
  if (fengari[lib][fun](stack, ...args) !== fengari.lua[type]) {
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
  const rawCode = await fetch(new URL("./podium.lua", import.meta.url))
    .then(r => r.text())
    .then(r => r.replace("#!/usr/bin/env lua", ""))
  const luaCode = fengari.to_luastring(rawCode);
  ensure("LUA_OK", "lauxlib", "luaL_dostring", L, luaCode);
  ensure("LUA_TFUNCTION", "lua", "lua_getfield", L, -1, "process");
  lua.lua_pushliteral(L, backendName);
  lua.lua_pushliteral(L, source);
  ensure("LUA_OK", "lua", "lua_pcall", L, 2, 1, 0);
  const result = lua.lua_tojsstring(L, -1);
  lua.lua_close(L);
  return result;
}
