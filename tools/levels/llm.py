"""A thin client for the OpenAI chat API, reading the key from Local.xcconfig as the app does."""
import json, os, re, time, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODEL = "gpt-6.1-terra"


def key():
    k = os.environ.get("OPENAI_API_KEY")
    if k:
        return k
    for line in open(os.path.join(ROOT, "Local.xcconfig")):
        m = re.match(r"\s*OPENAI_API_KEY\s*=\s*(\S+)", line)
        if m:
            return m.group(1)
    raise SystemExit("No OpenAI key: set OPENAI_API_KEY or fill in Local.xcconfig.")


def chat(messages, schema=None, effort="low", tries=5):
    body = {"model": MODEL, "reasoning_effort": effort, "messages": messages}
    if schema:
        body["response_format"] = {"type": "json_schema", "json_schema": {"name": "out", "strict": True, "schema": schema}}
    data = json.dumps(body).encode()
    for attempt in range(tries):
        req = urllib.request.Request(
            "https://api.openai.com/v1/chat/completions", data=data,
            headers={"Authorization": "Bearer " + key(), "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                out = json.load(r)["choices"][0]["message"]["content"]
                return json.loads(out) if schema else out
        except urllib.error.HTTPError as e:
            if e.code in (408, 409, 429) or e.code >= 500:
                time.sleep(2 ** attempt * 1.5)
                continue
            raise SystemExit(f"OpenAI: {e.code} {e.read().decode()[:300]}")
        except (urllib.error.URLError, TimeoutError):
            time.sleep(2 ** attempt * 1.5)
    raise SystemExit("OpenAI kept failing.")
