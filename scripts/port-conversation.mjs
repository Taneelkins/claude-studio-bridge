// Ports a Claude Code conversation transcript to another machine by rewriting
// the old absolute project paths to the new ones (so resume is clean). Parses
// each JSONL line as JSON and rewrites inside string values, so output stays
// valid JSON regardless of path separators / escaping.
//
//   node port-conversation.mjs <input.jsonl> <output.jsonl> "<old>=><new>" [more pairs...]
//
// Example on Windows (paths with backslashes are fine — pass them raw):
//   node port-conversation.mjs c9d04be8.jsonl c9d04be8.ported.jsonl ^
//     "/Users/taru/Documents/Steward=>C:\Users\you\Documents\Steward" ^
//     "/Users/taru/Studios/unknown game=>C:\Users\you\Studios\unknown game"
import fs from "node:fs";

const [input, output, ...pairs] = process.argv.slice(2);
if (!input || !output || pairs.length === 0) {
  console.error('Usage: node port-conversation.mjs <in.jsonl> <out.jsonl> "<old>=><new>" [...]');
  process.exit(1);
}
const reps = pairs.map((p) => {
  const i = p.indexOf("=>");
  if (i < 0) {
    console.error(`Bad pair (need old=>new): ${p}`);
    process.exit(1);
  }
  return { from: p.slice(0, i), to: p.slice(i + 2) };
});

function walk(v) {
  if (typeof v === "string") {
    let s = v;
    for (const { from, to } of reps) if (s.includes(from)) s = s.split(from).join(to);
    return s;
  }
  if (Array.isArray(v)) return v.map(walk);
  if (v && typeof v === "object") {
    const o = {};
    for (const k of Object.keys(v)) o[k] = walk(v[k]);
    return o;
  }
  return v;
}

const lines = fs.readFileSync(input, "utf8").split("\n");
let changed = 0;
const out = lines.map((line) => {
  if (!line.trim()) return line;
  try {
    const obj = walk(JSON.parse(line));
    const after = JSON.stringify(obj);
    if (after !== line) changed++;
    return after;
  } catch {
    return line; // leave any unparseable line untouched
  }
});
fs.writeFileSync(output, out.join("\n"));
console.log(`Ported ${input} -> ${output}`);
console.log(`  ${changed}/${lines.length} lines updated. Drop the output into your Windows`);
console.log(`  ~/.claude/projects/<project-folder>/ keeping the same filename.`);
