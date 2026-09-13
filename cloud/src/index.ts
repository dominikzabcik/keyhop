import { Hono } from "hono";
import { account } from "./account";
import { auth, sameOrigin, session } from "./auth";
import { randomToken } from "./crypto";
import type { AppEnv } from "./env";
import { notFound, pages } from "./pages";
import { seasons } from "./seasons";
import { teams } from "./teams";
import { usage } from "./usage";

const app = new Hono<AppEnv>();

app.use("*", async (c, next) => {
  const nonce = randomToken(16);
  c.set("nonce", nonce);
  await next();
  c.header("X-Content-Type-Options", "nosniff");
  c.header("Referrer-Policy", "strict-origin-when-cross-origin");
  // The only script is the backdrop, and only with this response's nonce. Every page works without it.
  c.header(
    "Content-Security-Policy",
    `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'unsafe-inline'; img-src 'self' data: https://avatars.githubusercontent.com; form-action 'self'; frame-ancestors 'none'; base-uri 'none'`,
  );
});
app.use("*", session);
app.use("*", sameOrigin);

app.route("/", auth);
app.route("/", usage);
app.route("/", seasons);
app.route("/", teams);
app.route("/", account);
app.route("/", pages);

app.notFound((c) => (c.req.path.startsWith("/api/") ? c.json({ error: "Not found." }, 404) : notFound(c)));
app.onError((error, c) => {
  console.error(error);
  return c.req.path.startsWith("/api/") ? c.json({ error: "Something went wrong." }, 500) : c.text("Something went wrong.", 500);
});

export default app;
