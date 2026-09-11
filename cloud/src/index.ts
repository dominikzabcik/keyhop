import { Hono } from "hono";
import { account } from "./account";
import { auth, sameOrigin, session } from "./auth";
import type { AppEnv } from "./env";
import { notFound, pages } from "./pages";
import { teams } from "./teams";
import { usage } from "./usage";

const app = new Hono<AppEnv>();

app.use("*", async (c, next) => {
  await next();
  c.header("X-Content-Type-Options", "nosniff");
  c.header("Referrer-Policy", "strict-origin-when-cross-origin");
  // Pages ship no JavaScript at all.
  c.header(
    "Content-Security-Policy",
    "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data: https://avatars.githubusercontent.com; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
  );
});
app.use("*", session);
app.use("*", sameOrigin);

app.route("/", auth);
app.route("/", usage);
app.route("/", teams);
app.route("/", account);
app.route("/", pages);

app.notFound((c) => (c.req.path.startsWith("/api/") ? c.json({ error: "Not found." }, 404) : notFound(c)));
app.onError((error, c) => {
  console.error(error);
  return c.req.path.startsWith("/api/") ? c.json({ error: "Something went wrong." }, 500) : c.text("Something went wrong.", 500);
});

export default app;
