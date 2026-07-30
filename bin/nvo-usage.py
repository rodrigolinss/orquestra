#!/usr/bin/env python3
"""nvo-usage — medidor de tokens do orquestra.

Le os transcritos JSONL que o Claude Code grava em ~/.claude/projects/,
agrega tokens por modelo e por agente, e estima o valor equivalente em API
(no plano Max nao ha cobranca por token; o valor serve como medida de
consumo). A "sessao" segue a janela rolante de 5h do plano: comeca na
primeira mensagem e reseta 5h depois.

O consumo por agente e atribuido pelo diretorio de trabalho (cwd) de cada
evento: sessoes rodando em orquestra/worktrees/<projeto>/<agente> sao
atribuidas a <agente>; as demais usam o nome do diretorio de trabalho.

Para evitar reprocessar todos os transcritos a cada chamada, o estado de
leitura (tamanho e mtime ja lidos por arquivo, mais os eventos ja
extraidos) fica em cache em ~/.claude/nvo-usage-cache.json; so os bytes
novos de arquivos que mudaram sao relidos.

Uso: nvo-usage.py [--json] [--kv]
"""
import glob
import json
import os
import re
import sys
import time
from datetime import datetime, timedelta

HOME = os.path.expanduser("~")
PROJECTS = os.path.join(HOME, ".claude", "projects")
STATE_PATH = os.path.join(HOME, ".claude", "nvo-usage-cache.json")

# USD por MTok (entrada, saida) — cache write = 1.25x in, cache read = 0.1x in
PRICES = [
    ("fable", 10.0, 50.0),
    ("mythos", 10.0, 50.0),
    ("opus", 5.0, 25.0),
    ("sonnet", 3.0, 15.0),
    ("haiku", 1.0, 5.0),
]
BLOCK_HOURS = 5


def price(model):
    m = (model or "").lower()
    for sub, i, o in PRICES:
        if sub in m:
            return i, o
    return 5.0, 25.0


def short_model(model):
    m = (model or "?").replace("claude-", "")
    for name in ("fable", "mythos", "opus", "sonnet", "haiku"):
        if name in m:
            return name
    return m[:12]


def cost_usd(ev):
    pi, po = price(ev["model"])
    return (ev["in"] * pi + ev["out"] * po
            + ev["cw"] * pi * 1.25 + ev["cr"] * pi * 0.1) / 1e6


def parse_ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except (ValueError, AttributeError):
        return None


def agent_name(cwd):
    """Nome do agente a partir do diretorio de trabalho da sessao.

    Sessoes em orquestra/worktrees/<projeto>/<agente> viram <agente>; as
    demais usam o nome do proprio diretorio de trabalho.
    """
    if not cwd:
        return "?"
    parts = cwd.rstrip("/").split("/")
    if "worktrees" in parts:
        i = parts.index("worktrees")
        if len(parts) > i + 2:
            return parts[-1]
    return os.path.basename(cwd.rstrip("/")) or cwd


def safe_key(name):
    return re.sub(r"[^A-Za-z0-9_]", "_", name)


def load_state():
    try:
        with open(STATE_PATH) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_state(state):
    tmp = STATE_PATH + ".tmp"
    try:
        with open(tmp, "w") as f:
            json.dump(state, f)
        os.replace(tmp, STATE_PATH)
    except OSError:
        pass


def parse_new_lines(path, start_byte):
    """Le e converte em eventos apenas os bytes novos de um arquivo,
    a partir de start_byte. Retorna (eventos, byte_ate_onde_leu).

    Para nao perder uma linha ainda sendo escrita, so avanca o offset ate
    a ultima quebra de linha completa.
    """
    with open(path, "rb") as f:
        f.seek(start_byte)
        data = f.read()
    if not data:
        return [], start_byte
    if data.endswith(b"\n"):
        end_byte = start_byte + len(data)
    else:
        idx = data.rfind(b"\n")
        if idx == -1:
            return [], start_byte
        end_byte = start_byte + idx + 1
        data = data[:idx + 1]

    events = []
    for raw in data.split(b"\n"):
        if not raw:
            continue
        try:
            obj = json.loads(raw.decode("utf-8", errors="ignore"))
        except json.JSONDecodeError:
            continue
        msg = obj.get("message") or {}
        usage = msg.get("usage")
        if not usage:
            continue
        ts = parse_ts(obj.get("timestamp", ""))
        if ts is None:
            continue
        events.append({
            "ts": ts,
            "model": msg.get("model", "?"),
            "in": usage.get("input_tokens", 0) or 0,
            "out": usage.get("output_tokens", 0) or 0,
            "cr": usage.get("cache_read_input_tokens", 0) or 0,
            "cw": usage.get("cache_creation_input_tokens", 0) or 0,
            "agent": agent_name(obj.get("cwd")),
            "id": msg.get("id"),
            "reqid": obj.get("requestId"),
        })
    return events, end_byte


def collect():
    now = time.time()
    state = load_state()
    new_state = {}
    events = []

    for path in glob.glob(os.path.join(PROJECTS, "*", "*.jsonl")):
        try:
            st = os.stat(path)
        except OSError:
            continue
        if st.st_mtime < now - 36 * 3600:
            continue

        cached = state.get(path)
        if cached and cached.get("mtime") == st.st_mtime \
                and cached.get("size") == st.st_size:
            new_state[path] = cached
            events.extend(cached.get("events", []))
            continue

        start = 0
        cached_events = []
        if cached and cached.get("size", 0) <= st.st_size:
            start = cached["size"]
            cached_events = cached.get("events", [])

        try:
            new_events, end_byte = parse_new_lines(path, start)
        except OSError:
            continue

        all_events = cached_events + new_events
        new_state[path] = {"size": end_byte, "mtime": st.st_mtime,
                            "events": all_events}
        events.extend(all_events)

    save_state(new_state)

    seen = set()
    deduped = []
    for e in events:
        key = (e.get("id"), e.get("reqid"))
        if key[0] and key in seen:
            continue
        seen.add(key)
        deduped.append(e)
    deduped.sort(key=lambda e: e["ts"])
    return deduped


def summarize(events):
    now = time.time()
    midnight = datetime.now().replace(hour=0, minute=0, second=0,
                                      microsecond=0).timestamp()

    # blocos rolantes de 5h: um novo bloco comeca quando uma mensagem
    # chega depois do fim do bloco anterior
    block_start = None
    for ev in events:
        if block_start is None or ev["ts"] >= block_start + BLOCK_HOURS * 3600:
            block_start = ev["ts"]
    block_active = block_start is not None and now < block_start + BLOCK_HOURS * 3600

    def agg(evs):
        total = {"in": 0, "out": 0, "cr": 0, "cw": 0, "cost": 0.0}
        by_model = {}
        by_agent = {}
        for e in evs:
            total["in"] += e["in"]
            total["out"] += e["out"]
            total["cr"] += e["cr"]
            total["cw"] += e["cw"]
            c = cost_usd(e)
            total["cost"] += c
            m = short_model(e["model"])
            by_model[m] = by_model.get(m, 0.0) + c
            a = e.get("agent") or "?"
            slot = by_agent.setdefault(a, {"cost": 0.0, "tokens": 0})
            slot["cost"] += c
            slot["tokens"] += e["in"] + e["out"] + e["cr"] + e["cw"]
        total["tokens"] = total["in"] + total["out"] + total["cr"] + total["cw"]
        return total, by_model, by_agent

    today, today_models, today_agents = agg(
        [e for e in events if e["ts"] >= midnight])
    if block_active:
        block, _, block_agents = agg(
            [e for e in events if e["ts"] >= block_start])
        reset = datetime.fromtimestamp(block_start + BLOCK_HOURS * 3600)
    else:
        block, block_agents = {"tokens": 0, "in": 0, "out": 0, "cr": 0,
                                "cw": 0, "cost": 0.0}, {}
        reset = None

    total_cost = sum(today_models.values()) or 1.0
    models = sorted(
        ({"name": k, "share": round(v / total_cost, 3),
          "cost": round(v, 2)} for k, v in today_models.items()),
        key=lambda m: -m["share"])

    agents_cost_total = sum(v["cost"] for v in block_agents.values()) or 1.0
    agents = sorted(
        ({"name": k, "cost": round(v["cost"], 2), "tokens": v["tokens"],
          "share": round(v["cost"] / agents_cost_total, 3)}
         for k, v in block_agents.items()),
        key=lambda a: -a["cost"])

    return {
        "block": {
            "active": block_active,
            "tokens": block["tokens"],
            "output_tokens": block["out"],
            "cost": round(block["cost"], 2),
            "reset": reset.strftime("%H:%M") if reset else None,
        },
        "today": {
            "tokens": today["tokens"],
            "output_tokens": today["out"],
            "cache_read": today["cr"],
            "cost": round(today["cost"], 2),
        },
        "models": models,
        "agents": agents,
    }


def human(n):
    if n >= 1_000_000:
        return f"{n / 1e6:.1f}M"
    if n >= 1_000:
        return f"{n / 1e3:.0f}k"
    return str(n)


def print_kv(data):
    b, t = data["block"], data["today"]
    print(f"block_active={1 if b['active'] else 0}")
    print(f"block_tokens={b['tokens']}")
    print(f"block_cost={b['cost']:.2f}")
    print(f"block_reset={b['reset'] or ''}")
    print(f"today_tokens={t['tokens']}")
    print(f"today_cost={t['cost']:.2f}")
    print(f"today_cache_read={t['cache_read']}")
    print(f"agents={','.join(a['name'] for a in data['agents'])}")
    for a in data["agents"]:
        k = safe_key(a["name"])
        print(f"agent_{k}_cost={a['cost']:.2f}")
        print(f"agent_{k}_tokens={a['tokens']}")
        print(f"agent_{k}_share={a['share']:.3f}")


def main():
    data = summarize(collect())
    if "--json" in sys.argv:
        print(json.dumps(data))
        return
    if "--kv" in sys.argv:
        print_kv(data)
        return
    b, t = data["block"], data["today"]
    print("nvo usage — consumo de tokens (Claude Code)")
    print()
    if b["active"]:
        print(f"  sessao (janela 5h): {human(b['tokens'])} tokens"
              f"  ·  ~${b['cost']:.2f} equiv. API  ·  reseta as {b['reset']}")
    else:
        print("  sessao (janela 5h): nenhuma atividade na janela atual")
    print(f"  hoje:               {human(t['tokens'])} tokens"
          f"  ·  ~${t['cost']:.2f} equiv. API"
          f"  ·  cache read {human(t['cache_read'])} (economia)")
    if data["models"]:
        parts = "  ".join(f"{m['name']} {m['share']*100:.0f}%"
                          for m in data["models"])
        print(f"  modelos (hoje):     {parts}")
    if data["agents"]:
        print()
        print("  por agente (sessao):")
        for a in data["agents"]:
            print(f"    {a['name']:<24} ~${a['cost']:.2f}"
                  f"  ·  {human(a['tokens'])} tokens")
    print()
    print("  dica: agentes com tarefas fechadas gastam menos; use sonnet/haiku")
    print("  para tarefas simples (nvo new nome \"tarefa\" claude sonnet)")


if __name__ == "__main__":
    main()
