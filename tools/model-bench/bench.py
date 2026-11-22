#!/usr/bin/env python3
"""
Compare local GGUF models for Wordbridge's tasks (translation, word-in-context, grammar fixes).

For each model it starts llama-server, runs the same prompts, records the answers,
speed and memory, then stops the server. Results go to results.json and results.md.

Usage:
  python3 bench.py --server /path/to/llama-server --models /path/to/models [--only name ...]
"""
import argparse
import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

PORT = 8091
HERE = Path(__file__).resolve().parent

# --- Test cases --------------------------------------------------------------

TRANSLATE_SYSTEM = (
    "You are a professional translator. Translate the user's text from {src} to {dst}. "
    "Keep the meaning, tone and formatting. Output only the translation, nothing else."
)

WORD_SYSTEM = (
    "You help a Hebrew speaker learn English. The user gives a sentence and a word or phrase from it. "
    "Reply in Hebrew with the meaning of that word or phrase *as used in this sentence*: "
    "first the Hebrew translation (1-4 words), then ' — ' and a very short explanation (max 12 words). "
    "One line only."
)

GRAMMAR_SYSTEM = (
    "You are an English writing assistant. Fix spelling, grammar, capitalization and punctuation "
    "in the user's sentence, and make it sound natural, but keep the meaning and keep it short. "
    "Reply with JSON only: {\"corrected\": \"...\", \"changes\": [{\"from\": \"...\", \"to\": \"...\", \"why\": \"...\"}]}"
)

CASES = [
    # English -> Hebrew
    ("translate_en_he", "English", "Hebrew", "Can you send me the report by the end of the day? I need to review it before the meeting."),
    ("translate_en_he", "English", "Hebrew", "We're running out of time, so let's cut to the chase."),
    ("translate_en_he", "English", "Hebrew", "The deployment failed because the environment variable wasn't set."),
    ("translate_en_he", "English", "Hebrew", "I'm looking forward to hearing from you."),
    # Hebrew -> English
    ("translate_he_en", "Hebrew", "English", "אני אבדוק את זה ואחזור אליך עד מחר בבוקר."),
    ("translate_he_en", "Hebrew", "English", "תוכל להסביר לי שוב מה בדיוק הבעיה? לא הבנתי עד הסוף."),
    ("translate_he_en", "Hebrew", "English", "יאללה, בוא נסגור את זה היום ונעבור לפרויקט הבא."),
    ("translate_he_en", "Hebrew", "English", "השרת נפל באמצע הלילה ואף אחד לא קיבל התראה."),
    # Word in context
    ("word", None, None, "Sentence: \"She runs a small design company in Berlin.\"\nWord: runs"),
    ("word", None, None, "Sentence: \"Let's table this discussion until next week.\"\nWord: table"),
    ("word", None, None, "Sentence: \"The new feature is still a bit rough around the edges.\"\nPhrase: rough around the edges"),
    ("word", None, None, "Sentence: \"Please make sure the build passes before you merge.\"\nWord: passes"),
    # Grammar
    ("grammar", None, None, "please fix that santence"),
    ("grammar", None, None, "i didnt received you're email yesterday"),
    ("grammar", None, None, "can you explain me how it work?"),
    ("grammar", None, None, "we was discuss about this in the meeting and decide to postpone it"),
    ("grammar", None, None, "Its very importent to check the logs befor deploying."),
]


def build_messages(kind, src, dst, text):
    if kind.startswith("translate"):
        return [{"role": "system", "content": TRANSLATE_SYSTEM.format(src=src, dst=dst)},
                {"role": "user", "content": text}]
    if kind == "word":
        return [{"role": "system", "content": WORD_SYSTEM}, {"role": "user", "content": text}]
    return [{"role": "system", "content": GRAMMAR_SYSTEM}, {"role": "user", "content": text}]


# --- llama-server helpers ------------------------------------------------------

def http(path, payload=None, timeout=300):
    req = urllib.request.Request(
        f"http://127.0.0.1:{PORT}{path}",
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def rss_mb(pid):
    out = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    return int(out) / 1024 if out else 0.0


def start_server(server, model):
    proc = subprocess.Popen(
        [server, "-m", str(model), "--port", str(PORT), "-ngl", "99", "-c", "4096",
         "--no-webui", "--log-disable"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    t0 = time.time()
    while time.time() - t0 < 300:
        if proc.poll() is not None:
            raise RuntimeError("llama-server exited during startup")
        try:
            if http("/health", timeout=2).get("status") == "ok":
                return proc, time.time() - t0
        except Exception:
            pass
        time.sleep(0.5)
    proc.kill()
    raise RuntimeError("llama-server did not become ready")


def chat(messages):
    t0 = time.time()
    r = http("/v1/chat/completions", {
        "messages": messages,
        "temperature": 0.2,
        "max_tokens": 300,
        "chat_template_kwargs": {"enable_thinking": False},
    })
    elapsed = time.time() - t0
    text = r["choices"][0]["message"]["content"].strip()
    tokens = r.get("usage", {}).get("completion_tokens", 0)
    timings = r.get("timings", {})
    return text, elapsed, tokens, timings.get("predicted_per_second")


# --- Main --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", required=True)
    ap.add_argument("--models", required=True)
    ap.add_argument("--only", nargs="*")
    args = ap.parse_args()

    # Skip macOS "._" metadata files that appear on exFAT/FAT drives.
    models = sorted(m for m in Path(args.models).glob("*.gguf") if not m.name.startswith("._"))
    if args.only:
        models = [m for m in models if any(o in m.name for o in args.only)]

    results = []
    for model in models:
        print(f"\n=== {model.name}", flush=True)
        entry = {"model": model.name, "size_gb": round(model.stat().st_size / 1e9, 2), "cases": []}
        try:
            proc, load_s = start_server(args.server, model)
        except Exception as e:
            entry["error"] = str(e)
            results.append(entry)
            print("  ERROR:", e)
            continue
        entry["load_seconds"] = round(load_s, 1)
        peak = rss_mb(proc.pid)
        try:
            for kind, src, dst, text in CASES:
                out, secs, toks, tps = chat(build_messages(kind, src, dst, text))
                peak = max(peak, rss_mb(proc.pid))
                entry["cases"].append({"kind": kind, "input": text, "output": out,
                                       "seconds": round(secs, 2), "tokens": toks,
                                       "tokens_per_sec": round(tps, 1) if tps else None})
                print(f"  [{kind}] {secs:.1f}s  {out[:90]!r}", flush=True)
        except Exception as e:
            entry["error"] = str(e)
            print("  ERROR:", e)
        finally:
            proc.terminate()
            proc.wait(timeout=30)
        entry["peak_rss_mb"] = round(peak)
        speeds = [c["tokens_per_sec"] for c in entry["cases"] if c["tokens_per_sec"]]
        entry["avg_tokens_per_sec"] = round(sum(speeds) / len(speeds), 1) if speeds else None
        entry["avg_seconds"] = round(sum(c["seconds"] for c in entry["cases"]) / max(1, len(entry["cases"])), 2)
        results.append(entry)

    (HERE / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2))
    write_markdown(results)
    print("\nWrote results.json and results.md")


def write_markdown(results):
    lines = ["# Model comparison results", "",
             "| Model | File GB | Load s | Peak RAM MB | Avg tok/s | Avg s/answer |",
             "|---|---|---|---|---|---|"]
    for r in results:
        lines.append(f"| {r['model']} | {r['size_gb']} | {r.get('load_seconds','-')} | {r.get('peak_rss_mb','-')} "
                     f"| {r.get('avg_tokens_per_sec','-')} | {r.get('avg_seconds','-')} |")
    for i, (kind, _, _, text) in enumerate(CASES):
        lines += ["", f"## {i + 1}. {kind}", "", "```", text, "```", ""]
        for r in results:
            if i < len(r["cases"]):
                out = r["cases"][i]["output"].replace("\n", " ")
                lines.append(f"- **{r['model']}**: {out}")
    (HERE / "results.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    sys.exit(main())
