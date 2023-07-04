import { Hono } from "https://lib.deno.dev/x/hono@v3/mod.ts";
import { serveStatic } from "https://lib.deno.dev/x/hono@v3/middleware.ts";
import { serve } from "https://deno.land/std@0.191.0/http/server.ts";
import { process } from "./podium.ts";

const app = new Hono();

app.post("/:backend{html|markdown|latex|vimdoc}", async (ctx) => {
  const source = await ctx.req.text();
  const backend = ctx.req.param("backend");
  const result = await process(source, backend);
  return ctx.text(result);
});

const { pathname } = new URL(import.meta.url);
const dirname = pathname.substring(0, pathname.lastIndexOf("/"));
const root = dirname.replace(Deno.cwd(), "");
app.get("/*", serveStatic({ root }));

serve(app.fetch);
