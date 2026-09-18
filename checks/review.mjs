/**
 * The second opinion: Jev reads what each screen says and answers typed questions about it.
 *
 * Jev takes text and structured data, not pictures, so it is never asked how a screen looks. It is
 * asked about the things a picture wouldn't settle anyway and an assertion can't express: whether
 * the writing is Keyhop's, whether a screen says what it is for, whether the words on it agree with
 * each other, and whether someone would know what to do next.
 *
 * Every answer lands in the report. None of them fail the run: a judgement is a second opinion, and
 * a run that fails on one would teach everybody to ignore it.
 */

import { choice, noul, score, TypeSafeClient } from "@typesafe-ai/sdk";

/** How sure Jev has to be before a judgement is worth reading. Below this it says so instead. */
const CERTAIN = 0.75;

/** The house style, as rules a reader can apply without seeing the screen. */
const VOICE = [
  "Plain words, short sentences, no marketing language and no exclamation marks.",
  "Never an em dash; a hyphen, a colon or two sentences instead.",
  "It says what Keyhop does, not how remarkable it is.",
  "It never promises more usage, more limits, or anything a provider's terms forbid.",
  "A wait, an error or an empty screen says what happened and what to do next.",
];

const QUESTIONS = {
  own_voice: noul(
    `Is every sentence here written in this voice?\n${VOICE.map((rule) => `- ${rule}`).join("\n")}`,
  ),
  says_its_purpose: noul(
    "From this screen alone, without prior knowledge of the product, is it clear what the screen is for?",
  ),
  agrees_with_itself: noul(
    "Do the words on this screen agree with each other: no claim contradicted elsewhere on it, no name or number used two different ways?",
  ),
  next_step_is_clear: noul(
    "If someone arrived here and could do one thing next, does the screen make that one thing obvious?",
  ),
  empty_or_waiting_explains: noul(
    "If any part of this screen is empty, loading, or reporting a problem, does it say what happened and what to do about it? Answer 1 if no part of the screen is empty, loading or failing.",
  ),
  clarity: score("How easily could a first-time reader tell what this screen offers and act on it?", {
    0: "Unreadable: the reader cannot tell what this is or do anything with it.",
    1: "Confusing: the purpose is guessable, but the wording or order works against it.",
    2: "Workable: understandable after a second read.",
    3: "Clear: purpose and next step are obvious on the first read.",
  }),
  weakest_part: choice("Which part of this screen would confuse a first-time reader most?", {
    headings: "The headings: what they name, or that they name the wrong thing.",
    body: "The explaining text: too much, too little, or unclear.",
    controls: "The buttons and links: what they do, or what they are called.",
    nothing: "Nothing here would confuse a first-time reader.",
  }),
};

/** A screen, trimmed to what Jev can judge: its own words and what it offers. */
function stateFor(reading) {
  return {
    screen: `${reading.target}/${reading.screen}`,
    where: reading.target === "site" ? "a page on keyhop.app" : "a section of Keyhop's window on a Mac",
    title: reading.title,
    description: reading.description,
    headings: reading.headings.map((h) => `h${h.level}: ${h.text}`),
    controls: [...new Set(reading.controls.map((c) => c.text).filter(Boolean))].slice(0, 40),
    text: reading.text.slice(0, 6000),
  };
}

/** True when an answer counts as passing, per question. */
function passed(name, answer) {
  switch (answer.type) {
    case "noul":
      return answer.noul >= 0.6;
    case "score":
      return answer.score >= 2;
    case "choice":
      return answer.choice === "nothing";
    default:
      return true;
  }
}

function describe(answer) {
  switch (answer.type) {
    case "noul":
      return answer.noul.toFixed(2);
    case "score":
      return `${answer.score}/3`;
    case "choice":
      return answer.choice;
    default:
      return JSON.stringify(answer);
  }
}

export async function review(readings) {
  if (!process.env.TYPESAFE_API_KEY) {
    console.log("No TYPESAFE_API_KEY, so nothing was sent to Jev. The checks above ran without it.");
    return [];
  }
  const client = new TypeSafeClient();
  const judgements = [];

  for (const reading of readings) {
    let answers;
    try {
      ({ answers } = await client.systemOne({ state: stateFor(reading), questions: QUESTIONS }));
    } catch (error) {
      judgements.push({
        screen: `${reading.target}/${reading.screen}`,
        question: "review",
        answer: "not asked",
        passed: true,
        note: `Jev couldn't be reached: ${error.message}`,
      });
      continue;
    }

    for (const [name, answer] of Object.entries(answers)) {
      // A choice or a score carries its own confidence; an unsure answer is reported as unsure
      // rather than as a fault, because acting on a coin flip is worse than not acting.
      const unsure = answer.confidence != null && answer.confidence < CERTAIN;
      judgements.push({
        screen: `${reading.target}/${reading.screen}`,
        question: name,
        answer: describe(answer),
        confidence: answer.confidence ?? null,
        passed: unsure ? true : passed(name, answer),
        note: unsure ? "Jev wasn't sure enough to call it" : undefined,
      });
    }
  }
  return judgements;
}
