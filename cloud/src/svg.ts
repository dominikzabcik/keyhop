/**
 * Shared drawing for the README images: one theme, one mark, one way of escaping text.
 * A name on a card is someone else's text, so nothing reaches the SVG unescaped.
 */

export type ThemeName = "dark" | "light";

export interface Theme {
  name: ThemeName;
  bg: string;
  text: string;
  muted: string;
  faint: string;
  stroke: string;
  strokeOpacity: string;
  mark: string;
}

export const THEMES: Record<ThemeName, Theme> = {
  dark: {
    name: "dark",
    bg: "#171717",
    text: "#EBEBEB",
    muted: "#8a8a8a",
    faint: "#6f6f6f",
    stroke: "#ffffff",
    strokeOpacity: "0.08",
    mark: "#EBEBEB",
  },
  light: {
    name: "light",
    bg: "#f6f6f6",
    text: "#171717",
    muted: "#5c5c5c",
    faint: "#6f6f6f",
    stroke: "#000000",
    strokeOpacity: "0.1",
    mark: "#171717",
  },
};

/** `theme=light` flips the chrome. Anything else, including no theme, stays the dark card. */
export function themeOf(value: string | undefined): Theme {
  return value === "light" ? THEMES.light : THEMES.dark;
}

export const SANS = "system-ui, -apple-system, Segoe UI, Roboto, sans-serif";
export const MONO = "ui-monospace, SFMono-Regular, Menlo, monospace";

export function esc(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

/** Keeps a line short enough to fit, with an ellipsis when it does not. */
export function fit(value: string, characters: number): string {
  return value.length <= characters ? value : `${value.slice(0, characters - 1).trimEnd()}…`;
}

export function shortTokens(tokens: number): string {
  if (tokens >= 1_000_000_000) return `${(tokens / 1_000_000_000).toFixed(tokens >= 10_000_000_000 ? 0 : 1)}B`;
  if (tokens >= 1_000_000) return `${(tokens / 1_000_000).toFixed(tokens >= 10_000_000 ? 0 : 1)}M`;
  if (tokens >= 1_000) return `${Math.round(tokens / 1000)}K`;
  return String(tokens);
}

export function dollars(micros: number): string {
  const amount = micros / 1_000_000;
  return amount >= 1000 ? `$${Math.round(amount).toLocaleString("en-US")}` : `$${amount.toFixed(2)}`;
}

export function grouped(value: number): string {
  return Math.round(value).toLocaleString("en-US");
}

/** Keyhop's mark, on the image's own scale. */
export function keyhopMark(x: number, y: number, size: number, fill: string): string {
  const unit = size / 24;
  const square = (left: number, top: number, width: number, height: number) =>
    `<rect x="${x + left * unit}" y="${y + top * unit}" width="${width * unit}" height="${height * unit}" rx="${1.5 * unit}" fill="${fill}"/>`;
  return square(2.5, 2.5, 6, 19.5) + square(9.6, 9.2, 6, 6) + square(16, 1, 6, 6) + square(16, 17, 6, 6);
}

export function svgOpen(width: number, height: number, label: string): string {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-label="${esc(label)}">`;
}

export function frame(width: number, height: number, theme: Theme): string {
  return `<rect width="${width}" height="${height}" rx="18" fill="${theme.bg}"/>
  <rect x="0.5" y="0.5" width="${width - 1}" height="${height - 1}" rx="17.5" fill="none" stroke="${theme.stroke}" stroke-opacity="${theme.strokeOpacity}"/>`;
}

/** Long enough to spare the database on a busy README, short enough to follow a day's usage. */
export function svgHeaders(c: { header: (name: string, value: string) => void }): void {
  c.header("Content-Type", "image/svg+xml; charset=utf-8");
  c.header("Cache-Control", "public, max-age=900");
}
