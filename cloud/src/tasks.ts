import type { WorkCommit } from "./work";

/**
 * A day, read as the things someone worked on rather than as a list of commits.
 *
 * Nobody thinks in commits. A day is three or four tasks, each one landed over a few commits, and
 * that is what a person wants to see when they look back at it. So the commits are grouped into
 * tasks here, and the page shows the tasks.
 *
 * The grouping is decided from the commits themselves, with no model in the loop: what repository
 * they touched, the scope a conventional commit already names, the words they share, and how close
 * together they landed. That means it is the same for everyone looking at the same day, it costs
 * nothing, it works offline, and it can never invent work that didn't happen.
 *
 * Jev can sharpen the edges later, through `sharpen`: it is asked "do these two belong to the
 * same task", one pair at a time, and those answers merge or split what is grouped below. It
 * cannot write a title, and nothing here waits on it. The page always shows the grouping below.
 */

export interface Task {
  /** What the work was, in words, taken from the commits rather than written about them. */
  title: string;
  /** Every repository this task touched. One piece of work often spans more than one. */
  repos: string[];
  commits: (WorkCommit & { repo: string })[];
  insertions: number;
  deletions: number;
  /** When the first and last commit of this task landed. */
  from: number;
  to: number;
  /** The zone those times belong to, taken from the commits themselves. */
  offset: number;
}

/** Words that carry no meaning about what was done. */
const STOP = new Set([
  "the", "and", "for", "with", "that", "this", "from", "into", "when", "what", "into", "onto", "its",
  "not", "but", "are", "was", "were", "has", "have", "had", "can", "will", "would", "should", "could",
  "add", "adds", "added", "use", "uses", "used", "make", "makes", "made", "let", "lets", "get", "gets",
  "set", "sets", "put", "puts", "say", "says", "said", "new", "old", "one", "two", "all", "any", "out",
  "off", "own", "now", "just", "only", "more", "less", "over", "under", "also", "than", "then", "them",
  "they", "you", "your", "our", "his", "her", "their", "there", "here", "where", "which", "while",
  "stop", "keep", "keeps", "fix", "fixes", "fixed", "update", "updates", "updated", "change", "changes",
  // Plain verbs and adverbs. A subject is full of these and none of them say which task it is.
  "does", "did", "done", "doing", "way", "ways", "thing", "things", "actually", "every", "same",
  "still", "really", "again", "about", "after", "before", "between", "through", "without", "within",
  "because", "since", "been", "being", "much", "many", "most", "such", "both", "each", "who", "whose",
  "goes", "went", "come", "comes", "came", "take", "takes", "took", "give", "gives", "gave", "sees",
  "saw", "know", "knows", "look", "looks", "tell", "tells", "told", "want", "wants", "need", "needs",
]);

/** The types a conventional commit starts with, which say nothing about which task it belongs to. */
const TYPES = new Set(["feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore", "revert", "wip"]);

interface Parsed {
  commit: WorkCommit;
  /** The scope a conventional commit named, like `auth` in `feat(auth): ...`. */
  scope: string;
  /** The subject with its `type(scope):` prefix taken off. */
  body: string;
  tokens: Set<string>;
}

/** Splits `feat(auth): let a token expire` into its scope and what it actually says. */
export function parseSubject(subject: string): { type: string; scope: string; body: string } {
  const match = subject.match(/^\s*([a-zA-Z]+)\s*(?:\(([^)]{1,40})\))?\s*!?\s*:\s*(.+)$/);
  if (!match || !TYPES.has(match[1].toLowerCase())) return { type: "", scope: "", body: subject.trim() };
  return { type: match[1].toLowerCase(), scope: (match[2] ?? "").trim().toLowerCase(), body: match[3].trim() };
}

/**
 * Enough of a stem to let one subject's "screen" meet another's "screens".
 *
 * Deliberately blunt: it only trims the endings English tacks on, and only on words long enough
 * that trimming still leaves something to match. Nothing here needs to be linguistically right,
 * only consistent, since both sides of a comparison go through it.
 */
function stem(word: string): string {
  if (word.length > 5 && word.endsWith("ies")) return `${word.slice(0, -3)}y`;
  if (word.length > 5 && (word.endsWith("ing") || word.endsWith("ies"))) return word.slice(0, -3);
  if (word.length > 4 && (word.endsWith("es") || word.endsWith("ed"))) return word.slice(0, -2);
  if (word.length > 3 && word.endsWith("s") && !word.endsWith("ss")) return word.slice(0, -1);
  return word;
}

function tokenize(text: string): Set<string> {
  const words = text
    .toLowerCase()
    .replace(/[^a-z0-9/_.\-]+/g, " ")
    .split(" ")
    .map((word) => word.replace(/^[-._/]+|[-._/]+$/g, ""))
    .filter((word) => word.length >= 3 && !STOP.has(word))
    .map(stem)
    // Checked again after stemming, since trimming an ending can land on a word that means nothing
    // on its own: "doing" becomes "do", "changes" becomes "change".
    .filter((word) => word.length >= 3 && !STOP.has(word));
  return new Set(words);
}

const shared = (a: Set<string>, b: Set<string>): number => [...a].filter((word) => b.has(word)).length;

function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) return 0;
  const both = shared(a, b);
  return both / (a.size + b.size - both);
}

/** Commits this far apart are unlikely to be the same sitting of work. */
const NEARBY_SECONDS = 3 * 3600;

/**
 * How telling each word is about this particular day.
 *
 * A word that turns up in most of a day's subjects says nothing about which task a commit belongs
 * to; one that turns up in two of them is very likely the name of the thing being worked on. So
 * "distinctive" is decided against the day itself rather than against a fixed list, which is what
 * lets the grouping work for any codebase without knowing a thing about it.
 */
function distinctiveWords(entries: Parsed[]): Set<string> {
  const seenIn = new Map<string, number>();
  for (const entry of entries) {
    for (const word of entry.tokens) seenIn.set(word, (seenIn.get(word) ?? 0) + 1);
  }
  const ceiling = Math.max(2, Math.ceil(entries.length / 3));
  return new Set([...seenIn].filter(([, count]) => count >= 2 && count <= ceiling).map(([word]) => word));
}

/**
 * What a group is actually about: the words most of it already agrees on.
 *
 * A group of one is about everything it says. Past that, a word has to run through at least half
 * the group, and through at least two of its commits, before it counts as what the group is about.
 */
function coreWords(group: Parsed[]): Set<string> {
  if (group.length === 1) return group[0].tokens;
  const seenIn = new Map<string, number>();
  for (const entry of group) {
    for (const word of entry.tokens) seenIn.set(word, (seenIn.get(word) ?? 0) + 1);
  }
  const needed = Math.max(2, Math.ceil(group.length / 2));
  return new Set([...seenIn].filter(([, count]) => count >= needed).map(([word]) => word));
}

/**
 * Whether a commit belongs with a group.
 *
 * A named scope settles it outright, since the author already said so. Otherwise the commit is
 * matched against what the group is about rather than against any one member of it. That is the
 * part that matters: matching any single member lets a morning's work collapse into one blob, each
 * commit dragged in by whichever neighbour it happened to share a word with. Matching the core
 * means a commit has to be about the same thing the group is about.
 */
function belongs(entry: Parsed, group: Parsed[], telling: Set<string>): boolean {
  const scoped = group.find((other) => other.scope);
  if (entry.scope && scoped) return entry.scope === scoped.scope;
  // A commit with no scope is not evidence against a scoped group, but it is not evidence for it.
  if (scoped && !entry.scope) return false;

  const core = coreWords(group);
  const both = [...entry.tokens].filter((word) => core.has(word));
  if (both.length === 0) return false;
  const near = group.some((other) => Math.abs(entry.commit.at - other.commit.at) <= NEARBY_SECONDS);
  if (both.length >= 2) return true;
  return near && both.some((word) => telling.has(word));
}

/** A scope, or a subject, turned into a title a person would write. */
function titleFor(group: Parsed[]): string {
  const scope = group.find((entry) => entry.scope)?.scope;
  if (scope) {
    const words = scope.replace(/[-_/]+/g, " ").trim();
    return words.charAt(0).toUpperCase() + words.slice(1);
  }
  // Otherwise the subject that best says what the whole group is about, which is the one sharing
  // the most with its core. A tie goes to the fuller subject, then to the one that landed first.
  const core = coreWords(group);
  const overlap = (entry: Parsed) => [...entry.tokens].filter((word) => core.has(word)).length;
  const best = [...group].sort(
    (a, b) => overlap(b) - overlap(a) || b.tokens.size - a.tokens.size || a.commit.at - b.commit.at,
  )[0];
  const body = best.body.replace(/\.$/, "");
  return body.charAt(0).toUpperCase() + body.slice(1);
}

/**
 * The tasks behind one person's day in one repository, largest first.
 *
 * Commits are walked oldest first so a task is built in the order it was worked on, and each one
 * joins the first group it belongs with, which lets a task started in the morning pick up the
 * commit that finished it in the afternoon.
 */
export function tasksFor(repo: string, commits: WorkCommit[]): Task[] {
  const parsed: Parsed[] = [...commits]
    .sort((a, b) => a.at - b.at)
    .map((commit) => {
      const { scope, body } = parseSubject(commit.subject);
      return { commit, scope, body, tokens: tokenize(`${scope} ${body}`) };
    });

  const telling = distinctiveWords(parsed);
  const groups: Parsed[][] = [];
  for (const entry of parsed) {
    const home = groups.find((group) => belongs(entry, group, telling));
    if (home) home.push(entry);
    else groups.push([entry]);
  }

  // One more pass, because two groups can end up related through a commit that joined the later
  // one after the earlier one had already closed over the same words.
  for (let i = 0; i < groups.length; i++) {
    for (let j = groups.length - 1; j > i; j--) {
      if (groups[j].some((entry) => belongs(entry, groups[i], telling))) {
        groups[i].push(...groups[j]);
        groups.splice(j, 1);
      }
    }
  }

  return groups
    .map((group) => taskFrom(group.map((entry) => ({ ...entry.commit, repo }))))
    .sort((a, b) => b.commits.length - a.commits.length || b.to - a.to);
}

function parseCommit(commit: WorkCommit): Parsed {
  const { scope, body } = parseSubject(commit.subject);
  return { commit, scope, body, tokens: tokenize(`${scope} ${body}`) };
}

/** Rebuilds a task from its commits, titles included, so a merge or a split never invents wording. */
function taskFrom(commits: (WorkCommit & { repo: string })[]): Task {
  const parsed = commits.map(parseCommit);
  const times = commits.map((entry) => entry.at);
  const repos: string[] = [];
  for (const entry of commits) if (!repos.includes(entry.repo)) repos.push(entry.repo);
  return {
    title: titleFor(parsed),
    repos,
    commits: [...commits].sort((a, b) => b.at - a.at),
    insertions: commits.reduce((sum, entry) => sum + entry.insertions, 0),
    deletions: commits.reduce((sum, entry) => sum + entry.deletions, 0),
    from: Math.min(...times),
    to: Math.max(...times),
    offset: commits[0].offset,
  };
}

const oldest = (task: Task) => [...task.commits].sort((a, b) => a.at - b.at)[0];
const newest = (task: Task) => [...task.commits].sort((a, b) => b.at - a.at)[0];

/**
 * Applies pairwise same/different answers to a heuristic grouping.
 *
 * Neighbouring commits inside a task whose subjects are not the same work are split apart.
 * Neighbouring tasks whose subjects are the same work are joined. Titles stay taken from the
 * commits. The day page never calls this: a caller that has no answers leaves the grouping as-is.
 */
export function sharpen(tasks: Task[], same: (left: string, right: string) => boolean): Task[] {
  if (tasks.length === 0) return [];
  const split: Task[] = [];
  for (const task of tasks) {
    const ordered = [...task.commits].sort((a, b) => a.at - b.at);
    let bucket = [ordered[0]];
    for (let i = 1; i < ordered.length; i++) {
      if (same(ordered[i - 1].subject, ordered[i].subject)) bucket.push(ordered[i]);
      else {
        split.push(taskFrom(bucket));
        bucket = [ordered[i]];
      }
    }
    split.push(taskFrom(bucket));
  }
  split.sort((a, b) => a.from - b.from || a.to - b.to);
  const joined: Task[] = [];
  for (const piece of split) {
    const prev = joined[joined.length - 1];
    if (prev && same(newest(prev).subject, oldest(piece).subject)) joined[joined.length - 1] = taskFrom([...prev.commits, ...piece.commits]);
    else joined.push(piece);
  }
  return joined.sort((a, b) => b.commits.length - a.commits.length || b.to - a.to);
}

/**
 * Every task across a person's repositories for a day, the biggest piece of work first.
 *
 * Tasks are found inside each repository, then the ones that turn out to be the same piece of work
 * are joined back together. One change often lands in two repositories on the same afternoon, and
 * showing that as two identical tasks would be exactly the list of commits this page exists to
 * replace. Two tasks are the same when they came out with the same title, which means either the
 * author scoped them the same way or their commits say the same thing.
 */
export function tasksForDay(repos: { repo: string; subjects: WorkCommit[] }[]): Task[] {
  const byTitle = new Map<string, Task>();
  for (const entry of repos) {
    for (const task of tasksFor(entry.repo, entry.subjects)) {
      const key = task.title.toLowerCase();
      const existing = byTitle.get(key);
      if (!existing) {
        byTitle.set(key, task);
        continue;
      }
      existing.commits = [...existing.commits, ...task.commits].sort((a, b) => b.at - a.at);
      existing.insertions += task.insertions;
      existing.deletions += task.deletions;
      existing.from = Math.min(existing.from, task.from);
      existing.to = Math.max(existing.to, task.to);
      for (const repo of task.repos) if (!existing.repos.includes(repo)) existing.repos.push(repo);
    }
  }
  return [...byTitle.values()].sort((a, b) => b.commits.length - a.commits.length || b.to - a.to);
}

/**
 * "09:12 to 13:40", or a single time when the whole task landed at once.
 *
 * Read in the zone the commits were authored in, not the viewer's. A day is already bucketed by the
 * author's own calendar, so showing a teammate's late evening as your own early morning would put
 * the clock and the date in different places.
 */
export function span(from: number, to: number, offset: number): string {
  const clock = (at: number) =>
    new Date((at + offset) * 1000).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", timeZone: "UTC" });
  const start = clock(from);
  const end = clock(to);
  return start === end ? start : `${start} to ${end}`;
}
