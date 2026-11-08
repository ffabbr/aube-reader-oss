"""A thin client for OpenAI's Responses API, reading the key from OPENAI_API_KEY or Local.xcconfig."""
import json, os, re, time, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODEL = "gpt-6.1-terra"  # the app's OpenAI.keyModel


def key():
    k = os.environ.get("OPENAI_API_KEY")
    if k:
        return k
    path = os.path.join(ROOT, "Local.xcconfig")
    if os.path.exists(path):
        with open(path) as f:
            for line in f:
                m = re.match(r"\s*OPENAI_API_KEY\s*=\s*(\S+)", line)
                if m:
                    return m.group(1)
    raise SystemExit("No OpenAI key: set OPENAI_API_KEY or fill in Local.xcconfig.")


def chat(messages, schema=None, effort="low", tries=5):
    """Asks the model through the Responses API, as the app does. `messages` are
    chat messages; system messages become the request's instructions."""
    body = {
        "model": MODEL,
        "store": False,
        "reasoning": {"effort": effort},
        "instructions": "\n\n".join(m["content"] for m in messages if m["role"] == "system"),
        "input": [{"role": m["role"], "content": m["content"]} for m in messages if m["role"] != "system"],
    }
    if schema:
        body["text"] = {"format": {"type": "json_schema", "name": "out", "strict": True, "schema": schema}}
    data = json.dumps(body).encode()
    auth = "Bearer " + key()
    for attempt in range(tries):
        req = urllib.request.Request(
            "https://api.openai.com/v1/responses", data=data,
            headers={"Authorization": auth, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                out = text(json.load(r))
                return json.loads(out) if schema else out
        except urllib.error.HTTPError as e:
            if e.code in (408, 409, 429) or e.code >= 500:
                time.sleep(2 ** attempt * 1.5)
                continue
            raise SystemExit(f"OpenAI: {e.code} {e.read().decode()[:300]}")
        except (urllib.error.URLError, TimeoutError):
            time.sleep(2 ** attempt * 1.5)
    raise SystemExit("OpenAI kept failing.")


def text(response):
    """The words of a Responses API answer: its message's output text, joined."""
    return "".join(
        part.get("text", "")
        for item in response.get("output", []) if item.get("type") == "message"
        for part in item.get("content", []) if part.get("type") == "output_text")
