#!/usr/bin/env python3
"""nvo-usage — medidor de tokens do orquestra.

Le os transcritos JSONL que o Claude Code grava em ~/.claude/projects/,
agrega tokens por modelo e estima o valor equivalente em API (no plano
Max nao ha cobranca por token; o valor serve como medida de consumo).
A "sessao" segue a janela rolante de 5h do plano: comeca na primeira
mensagem e reseta 5h depois.

Uso: nvo-usage.py [--json]
"""
import glob
import json
import os
import sys
import time
from datetime import datetime, timedelta

HOME = os.path.expanduser("~")
PROJECTS = os.path.join(HOME, ".claude", "projects")

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


def collect():
    now = time.time()
    events, seen = [], set()
    for path in glob.glob(os.path.join(PROJECTS, "*", "*.jsonl")):
        try:
            if os.path.getmtime(path) < now - 36 * 3600:
                continue
            with open(path, errors="ignore") as f:
                for line in f:
                    try:
                        obj = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    msg = obj.get("message") or {}
                    usage = msg.get("usage")
                    if not usage:
                        continue
                    ts = parse_ts(obj.get("timestamp", ""))
                    if ts is None:
                        continue
                    key = (msg.get("id"), obj.get("requestId"))
                    if key[0] and key in seen:
                        continue
                    seen.add(key)
                    events.append({
                        "ts": ts,
                        "model": msg.get("model", "?"),
                        "in": usage.get("input_tokens", 0) or 0,
                        "out": usage.get("output_tokens", 0) or 0,
                        "cr": usage.get("cache_read_input_tokens", 0) or 0,
                        "cw": usage.get("cache_creation_input_tokens", 0) or 0,
                    })
        except OSError:
            continue
    events.sort(key=lambda e: e["ts"])
    return events


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
        for e in evs:
            total["in"] += e["in"]
            total["out"] += e["out"]
            total["cr"] += e["cr"]
            total["cw"] += e["cw"]
            c = cost_usd(e)
            total["cost"] += c
            by_model[short_model(e["model"])] = \
                by_model.get(short_model(e["model"]), 0.0) + c
        total["tokens"] = total["in"] + total["out"] + total["cr"] + total["cw"]
        return total, by_model

    today, today_models = agg([e for e in events if e["ts"] >= midnight])
    if block_active:
        block, _ = agg([e for e in events if e["ts"] >= block_start])
        reset = datetime.fromtimestamp(block_start + BLOCK_HOURS * 3600)
    else:
        block, reset = {"tokens": 0, "in": 0, "out": 0, "cr": 0, "cw": 0,
                        "cost": 0.0}, None

    total_cost = sum(today_models.values()) or 1.0
    models = sorted(
        ({"name": k, "share": round(v / total_cost, 3),
          "cost": round(v, 2)} for k, v in today_models.items()),
        key=lambda m: -m["share"])

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
    }


def human(n):
    if n >= 1_000_000:
        return f"{n / 1e6:.1f}M"
    if n >= 1_000:
        return f"{n / 1e3:.0f}k"
    return str(n)


def main():
    data = summarize(collect())
    if "--json" in sys.argv:
        print(json.dumps(data))
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
    print()
    print("  dica: agentes com tarefas fechadas gastam menos; use sonnet/haiku")
    print("  para tarefas simples (nvo new nome \"tarefa\" claude sonnet)")


if __name__ == "__main__":
    main()
