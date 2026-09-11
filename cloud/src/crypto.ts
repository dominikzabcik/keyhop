const encoder = new TextEncoder();

/** A random URL-safe token. 32 bytes by default. */
export function randomToken(bytes = 32): string {
  const data = crypto.getRandomValues(new Uint8Array(bytes));
  let text = "";
  for (const byte of data) text += String.fromCharCode(byte);
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(text));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

// No vowels, so codes never spell words, and no 0, O, 1 or I to misread.
const CODE_ALPHABET = "BCDFGHJKLMNPQRSTVWXZ23456789";

/** A short code a person reads from the app and checks in the browser, like BCDF-2345. */
export function userCode(): string {
  const chars: string[] = [];
  while (chars.length < 8) {
    const [byte] = crypto.getRandomValues(new Uint8Array(1));
    // Reject the top of the range so every character is equally likely.
    if (byte < 256 - (256 % CODE_ALPHABET.length)) chars.push(CODE_ALPHABET[byte % CODE_ALPHABET.length]);
  }
  return `${chars.slice(0, 4).join("")}-${chars.slice(4).join("")}`;
}
