import { Hono } from "https://lib.deno.dev/x/hono@v3/mod.ts";
import { serveStatic } from "https://lib.deno.dev/x/hono@v3/middleware.ts";
import { serve } from "https://deno.land/std@0.191.0/http/server.ts";
import fengari from "https://esm.sh/fengari-web@0.1.4";

const podium = await fetch(new URL("../lua/podium.lua", import.meta.url)).then(
  (r) => r.text()
);

function process(source: string, target: string): string {
  const lauxlib = fengari.lauxlib;
  const lua = fengari.lua;
  const lualib = fengari.lualib
  const state = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(state);
  const code = fengari.to_luastring(podium.replace(/^#!.*\n/, ""));
  if (lauxlib.luaL_dostring(state, code) !== lua.LUA_OK) {
    const error = lua.lua_tojsstring(state, -1);
    lua.lua_close(state);
    throw new Error(error);
  }
  lua.lua_getfield(state, -1, "process");
  lua.lua_pushliteral(state, source);
  lua.lua_getfield(state, -3, target);
  lua.lua_pcall(state, 2, 1, 0);
  const result = lua.lua_tojsstring(state, -1);
  lua.lua_close(state);
  return result
}

const app = new Hono();

app.post("/:target{html|markdown|latex|vimdoc}", async (ctx) => {
  const source = await ctx.req.text();
  const target = ctx.req.param("target");
  const result = process(source, target);
  return ctx.text(result);
});

app.get("/podium.lua", (ctx) => {
  return ctx.text(podium);
});

const { pathname } = new URL(import.meta.url);
const dirname = pathname.substring(0, pathname.lastIndexOf("/"));
const root = dirname.replace(Deno.cwd(), "");
app.get("/*", serveStatic({ root }));

serve(app.fetch);
