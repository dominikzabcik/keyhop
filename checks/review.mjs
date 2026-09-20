/**
 * The second opinion: Jev reads what each screen says and answers typed questions about it.
 *
 * Jev takes text and structured data, not pictures, so it is never asked how a screen looks. It is
 * asked what a picture wouldn't settle anyway and an assertion can't express: whether the writing
 * is Keyhop's, whether the screen says what it is for, and whether it contradicts itself.
 *
 * Every question here asks one thing. A question that asks two ("does it agree with itself and say
 * what to do next") comes back near 0.5 whatever the screen, which says nothing. Each one also
 * declares the answer that means the screen is fine, and anything in the middle is reported as too
 * close to call rather than as a fault: acting on a coin flip is worse than not acting.
 *
 * Every answer lands in the report. None of them fail the run: a judgement is a second opinion, and
 * a run that fails on one would teach everybody to ignore it.
 */

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { choice, noul, score, TypeSafeClient } from "@typesafe-ai/sdk";

/** The key can sit in checks/.env, which is never committed, instead of the shell's environment. */
function loadKeyFile() {
  if (process.env.TYPESAFE_API_KEY) return;
  try {
    const file = readFileSync(join(dirname(fileURLToPath(import.meta.url)), ".env"), "utf8");
    for (const line of file.split("\n")) {
      const match = line.match(/^\s*(?:export\s+)?([A-Z_]+)\s*=\s*"?([^"\n]*)"?\s*$/);
      if (match) process.env[match[1]] ??= match[2];
    }
  } catch {}
}

/** Answers between these are too close to call: the model gave yes and no similar weight. */
const UNSURE = [0.3, 0.7];
/** A choice or a score below this confidence is reported as unsure too. */
const CERTAIN = 0.75;

/** Every tool Keyhop switches, so a list that has gone stale can be spotted. */
const TOOLS = "Claude Code, Cursor, Codex, Gemini CLI, OpenCode, Pi, GitHub Copilot, Windsurf and Codebuff";

/** Each question, and the answer that means the screen is fine. */
const QUESTIONS = {
  sells_itself: {
    wants: "no",
    question: noul(
      "Does any sentence praise the product rather than describe it, with words such as powerful, seamless, effortless, revolutionary, amazing or best?",
    ),
  },
  promises_more_usage: {
    wants: "no",
    question: noul(
      "Does the text offer more usage, higher limits, or a way around a provider's limits, rather than only moving between accounts someone already owns?",
    ),
  },
  contradicts_itself: {
    wants: "no",
    question: noul("Do two statements on this screen give different values or facts for the same thing?", {
      true: "Two places state something incompatible, such as different totals, names or counts for one thing.",
      false: "Everything stated is consistent, or there is nothing to compare.",
    }),
  },
  tool_list_is_short: {
    wants: "no",
    question: noul(
      `Does this screen set out to list the tools Keyhop works with and leave one out? Keyhop works with ${TOOLS}. Answer no if the screen does not set out to list them.`,
    ),
  },
  heading_says_the_subject: {
    wants: "yes",
    question: noul("Does the main heading name what this screen is about?"),
  },
  an_action_is_offered: {
    wants: "yes",
    question: noul("Is there at least one control here whose name says what pressing it will do?"),
  },
  empty_parts_say_why: {
    wants: "yes",
    question: noul("Does every empty list or missing figure on this screen say what would fill it?", {
      true: "Each empty part explains what would put something there, or nothing on the screen is empty.",
      false: "Something is empty and the screen does not say what would fill it.",
    }),
  },
  a_stranger_could_use_it: {
    wants: "yes",
    question: noul("Could someone who has never seen Keyhop tell what to do on this screen without help?"),
  },
  clarity: {
    wants: "score",
    question: score("How easily could a first-time reader tell what this screen offers and act on it?", [
      "Unreadable: the reader cannot tell what this is or do anything with it.",
      "Confusing: the purpose is guessable, but the wording or order works against it.",
      "Workable: understandable after a second read.",
      "Clear: purpose and next step are obvious on the first read.",
    ]),
  },
  weakest_part: {
    wants: "nothing",
    question: choice("Which part of this screen would confuse a first-time reader most?", {
      headings: "The headings: what they name, or that they name the wrong thing.",
      body: "The explaining text: too much, too little, or unclear.",
      controls: "The buttons and links: what they do, or what they are called.",
      nothing: "Nothing here would confuse a first-time reader.",
    }),
  },
};

/** A screen, trimmed to what Jev can judge: its own words and what it offers. */
function stateFor(reading) {
  const where = {
    site: "a page on keyhop.app, the website for Keyhop, which switches between AI coding accounts you own",
    account: "a page on keyhop.app shown to someone who is signed in",
    app: "a section of Keyhop's window, a Mac app that switches between AI coding accounts you own",
    phone: "a screen of Keyhop's iPhone companion, which shows limits, seasons and standings read from a computer",
  };
  return {
    screen: `${reading.target}/${reading.screen}`,
    where: where[reading.target] ?? where.site,
    title: reading.title,
    headings: reading.headings.map((h) => `h${h.level}: ${h.text}`),
    controls: [...new Set(reading.controls.map((c) => c.text).filter(Boolean))].slice(0, 40),
    text: reading.text.slice(0, 6000),
  };
}

/** How an answer reads, and whether it is fine, a fault, or too close to call. */
function verdict(wants, answer) {
  switch (answer.type) {
    case "noul": {
      const [low, high] = UNSURE;
      if (answer.noul > low && answer.noul < high) return { text: answer.noul.toFixed(2), passed: true, unsure: true };
      const yes = answer.noul >= high;
      return { text: answer.noul.toFixed(2), passed: wants === "yes" ? yes : !yes, unsure: false };
    }
    case "score": {
      const unsure = (answer.confidence ?? 1) < CERTAIN;
      return { text: `${answer.score}/3`, passed: unsure ? true : answer.score >= 2, unsure };
    }
    case "choice": {
      const unsure = (answer.confidence ?? 1) < CERTAIN;
      return { text: answer.choice, passed: unsure ? true : answer.choice === wants, unsure };
    }
    default:
      return { text: JSON.stringify(answer), passed: true, unsure: true };
  }
}

export async function review(readings) {
  loadKeyFile();
  if (!process.env.TYPESAFE_API_KEY) {
    console.log("No TYPESAFE_API_KEY, so nothing was sent to Jev. The checks above ran without it.");
    return [];
  }
  const client = new TypeSafeClient();
  const questions = Object.fromEntries(Object.entries(QUESTIONS).map(([name, entry]) => [name, entry.question]));
  const judgements = [];

  for (const reading of readings) {
    const screen = `${reading.target}/${reading.screen}`;
    let answers;
    try {
      ({ answers } = await client.systemOne({ state: stateFor(reading), questions }));
    } catch (error) {
      judgements.push({ screen, question: "review", answer: "not asked", passed: true, note: `Jev couldn't be reached: ${error.message}` });
      continue;
    }

    // Which part is weakest is a forced choice between four: on a page that is mostly prose, the
    // body wins whatever its quality. It is only worth raising about a screen that reads poorly,
    // so the two answers are combined here rather than reported apart.
    const readsPoorly = (answers.clarity?.score ?? 3) < 2.5;

    for (const [name, answer] of Object.entries(answers)) {
      let { text, passed, unsure } = verdict(QUESTIONS[name].wants, answer);
      if (name === "weakest_part" && !readsPoorly) passed = true;
      judgements.push({
        screen,
        question: name,
        answer: text,
        confidence: answer.confidence ?? null,
        passed,
        note: unsure ? "too close to call" : undefined,
      });
    }
  }
  return judgements;
}
