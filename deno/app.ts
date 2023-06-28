import { Hono} from "https://lib.deno.dev/x/hono@v3/mod.ts";
import { serveStatic } from "https://lib.deno.dev/x/hono@v3/middleware.ts";
import { serve } from "https://deno.land/std@0.191.0/http/server.ts";
import fengari from "https://esm.sh/fengari-web@0.1.4"

const podium = await fetch(new URL('podium.lua', import.meta.url)).then(r => r.text());

function process(source: string, target: string): string {
  const script = `
    _G.SOURCE = [===[${source}]===]
    _G.TARGET = [===[${target}]===]
    ${podium.replace(/^#!.*\n/, '')}
  `
  return fengari.load(script)();
}

const app = new Hono();

app.post("/:target{html|markdown|latex|vimdoc}", async (ctx) => {
  const source = await ctx.req.text();
  const target = ctx.req.param("target");
  const result = process(source, target);
  return ctx.text(result);
})

const csd = new URL(import.meta.url).pathname.replace('/app.ts', '')
const root = csd.replace(Deno.cwd(), '')
app.get("/*", serveStatic({ root }));

serve(app.fetch);
