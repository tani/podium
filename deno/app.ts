import { Hono } from "https://lib.deno.dev/x/hono@v3/mod.ts";
import { serveStatic } from "https://lib.deno.dev/x/hono@v3/middleware.ts";
import { serve } from "https://deno.land/std@0.191.0/http/server.ts";
import { createPodium, BackendName } from "./podium.ts";
import { LuaFactory } from "https://esm.sh/wasmoon@1.15.0?bundle"

const luaFactory = new LuaFactory("https://esm.sh/wasmoon@1.15.0/dist/glue.wasm");
const luaEngine = await luaFactory.createEngine();

const podium = await createPodium({
  luaEngine: luaEngine,
  podiumUrl: (new URL("./podium.lua", import.meta.url)).toString(),
})

const app = new Hono();

app.post("/:target{html|markdown|latex|vimdoc}", async (ctx) => {
  const source = await ctx.req.text();
  const target = ctx.req.param("target");
  const processor = podium.PodiumProcessor.new(podium[target as BackendName]);
  const result = processor.process(processor, source);
  return ctx.text(result);
});

const { pathname } = new URL(import.meta.url);
const dirname = pathname.substring(0, pathname.lastIndexOf("/"));
const root = dirname.replace(Deno.cwd(), "");
app.get("/*", serveStatic({ root }));

serve(app.fetch);
