/** What a visitor or the app may read. D1's free-tier stop is a quota, and it lifts at midnight UTC. */
export function publicError(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  if (message.includes("exceeded D1's free tier")) {
    return "Keyhop cloud hit its daily database limit. It clears at midnight UTC.";
  }
  return "Something went wrong.";
}
