import { Hono } from "hono";
import { account } from "./account";
import { auth, sameOrigin, session } from "./auth";
import { card } from "./card";
import { randomToken } from "./crypto";
import type { AppEnv } from "./env";
import { limits, sweepLimits } from "./limits";
import { notFound, pages } from "./pages";
import { quests } from "./quests";
import { seasons } from "./seasons";
import { site } from "./site";
import { teams } from "./teams";
import { usage } from "./usage";
import { work } from "./work";

const app = new Hono<AppEnv>();

app.use("*", async (c, next) => {
  const nonce = randomToken(16);
  c.set("nonce", nonce);
  await next();
  c.header("X-Content-Type-Options", "nosniff");
  c.header("Referrer-Policy", "strict-origin-when-cross-origin");
  // Executable scripts are limited to the backdrop and only run with this response's nonce.
  c.header(
    "Content-Security-Policy",
    `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'unsafe-inline'; img-src 'self' data: https://avatars.githubusercontent.com; form-action 'self'; frame-ancestors 'none'; base-uri 'none'`,
  );
});
app.use("*", session);
app.use("*", sameOrigin);

app.route("/", site);
app.route("/", auth);
app.route("/", usage);
app.route("/", work);
app.route("/", limits);
app.route("/", card);
app.route("/", quests);
app.route("/", seasons);
app.route("/", teams);
app.route("/", account);
app.route("/", pages);

app.notFound((c) => (c.req.path.startsWith("/api/") ? c.json({ error: "Not found." }, 404) : notFound(c)));
app.onError((error, c) => {
  console.error({
    event: "request_error",
    method: c.req.method,
    path: c.req.path,
    message: error instanceof Error ? error.message : String(error),
  });
  return c.req.path.startsWith("/api/") ? c.json({ error: "Something went wrong." }, 500) : c.text("Something went wrong.", 500);
});

export default {
  fetch: app.fetch,
  /** The hourly trigger in wrangler.jsonc. */
  async scheduled(_controller: ScheduledController, env: AppEnv["Bindings"], ctx: ExecutionContext) {
    ctx.waitUntil(sweepLimits(env.DB));
  },
} satisfies ExportedHandler<AppEnv["Bindings"]>;
