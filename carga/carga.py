from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg2
import requests
from psycopg2.extras import execute_values

BASE_URL = "https://api.cartola.globo.com"
ROOT = Path(__file__).resolve().parent
JSON_DIR = ROOT / "json"
USER_AGENT = "Mozilla/5.0 (compatible; LigaFACOMFantasy/1.0; educational project)"

POSITION_ID_TO_CODE = {1: "gol", 2: "lat", 3: "zag", 4: "mei", 5: "ata", 6: "tec"}
POSITION_NAME_TO_CODE = {
    "goleiro": "gol", "gol": "gol", "lateral": "lat", "lat": "lat",
    "zagueiro": "zag", "zag": "zag", "meia": "mei", "mei": "mei",
    "atacante": "ata", "ata": "ata", "tecnico": "tec", "técnico": "tec", "tec": "tec",
}
STATUS_ID_TO_CODE = {2: "duvida", 3: "suspenso", 5: "contundido", 6: "nulo", 7: "provavel"}


def slug(value: Any) -> str:
    return re.sub(r"[^a-z0-9]+", "_", str(value).lower()).strip("_")


def as_int(value: Any, default: int | None = None) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def position_code(position_id: Any, positions: dict[str, Any]) -> str:
    pid = as_int(position_id)
    if pid in POSITION_ID_TO_CODE:
        return POSITION_ID_TO_CODE[pid]
    item = positions.get(str(position_id), {}) if isinstance(positions, dict) else {}
    name = item.get("nome", "") if isinstance(item, dict) else str(item)
    code = POSITION_NAME_TO_CODE.get(slug(name).replace("_", "")) or POSITION_NAME_TO_CODE.get(str(name).lower())
    if not code:
        raise ValueError(f"ID de posição não reconhecido: {position_id!r} ({name!r})")
    return code


def status_code(status_id: Any, statuses: dict[str, Any]) -> str:
    sid = as_int(status_id)
    if sid in STATUS_ID_TO_CODE:
        return STATUS_ID_TO_CODE[sid]
    item = statuses.get(str(status_id), {}) if isinstance(statuses, dict) else {}
    name = item.get("nome", "") if isinstance(item, dict) else str(item)
    key = slug(name)
    if "prov" in key:
        return "provavel"
    if "duvid" in key:
        return "duvida"
    if "susp" in key:
        return "suspenso"
    if "contund" in key or "les" in key:
        return "contundido"
    if "nulo" in key or "sem" in key:
        return "nulo"
    return "nulo"


def save_json(name: str, payload: Any) -> None:
    JSON_DIR.mkdir(parents=True, exist_ok=True)
    path = JSON_DIR / f"{name}.json"
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


class CartolaAPI:
    def __init__(self) -> None:
        self.session = requests.Session()
        self.session.headers.update({"User-Agent": USER_AGENT, "Accept": "application/json"})
        self.last_request = 0.0

    def get(self, endpoint: str, filename: str) -> Any:
        wait = 1.0 - (time.monotonic() - self.last_request)
        if wait > 0:
            time.sleep(wait)
        response = self.session.get(f"{BASE_URL}{endpoint}", timeout=30)
        self.last_request = time.monotonic()
        response.raise_for_status()
        payload = response.json()
        save_json(filename, payload)
        return payload


def dict_values(data: Any) -> list[dict[str, Any]]:
    if isinstance(data, dict):
        return [v for v in data.values() if isinstance(v, dict)]
    if isinstance(data, list):
        return [v for v in data if isinstance(v, dict)]
    return []


def parse_rounds(text: str) -> list[int]:
    result: set[int] = set()
    for part in text.split(","):
        part = part.strip()
        if "-" in part:
            start, end = map(int, part.split("-", 1))
            result.update(range(start, end + 1))
        elif part:
            result.add(int(part))
    rounds = sorted(n for n in result if 1 <= n <= 38)
    if len(rounds) < 10:
        raise ValueError("Informe pelo menos 10 rodadas, por exemplo: --rodadas 1-10")
    return rounds


def parse_datetime(value: Any) -> datetime:
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value, tz=timezone.utc).replace(tzinfo=None)
    if isinstance(value, str):
        raw = value.replace("Z", "+00:00")
        parsed = datetime.fromisoformat(raw)
        if parsed.tzinfo:
            parsed = parsed.astimezone(timezone.utc).replace(tzinfo=None)
        return parsed
    raise ValueError(f"Data da partida ausente ou inválida: {value!r}")


def upsert_reference_data(cur, market: dict[str, Any], clubs_payload: Any, schemes_payload: Any) -> tuple[dict[str, Any], dict[str, Any]]:
    clubs = market.get("clubes") or clubs_payload
    positions = market.get("posicoes", {})
    statuses = market.get("status", {})

    if isinstance(clubs, dict):
        club_items = clubs.items()
    elif isinstance(clubs, list):
        club_items = ((str(c.get("id", "")), c) for c in clubs if isinstance(c, dict))
    else:
        club_items = []
    for key, club in club_items:
        club_id = as_int(club.get("id", key))
        if club_id is None:
            continue
        name = club.get("nome") or club.get("nome_fantasia") or f"Clube {club_id}"
        abbreviation = (club.get("abreviacao") or club.get("nome", "CLB")[:3]).upper()[:3]
        escudos = club.get("escudos") or {}
        crest = escudos.get("60x60") or escudos.get("45x45") or escudos.get("30x30") if isinstance(escudos, dict) else None
        cur.execute("""INSERT INTO liga_facom.clube (id, nome, abreviacao, escudo)
                       VALUES (%s, %s, %s, %s)
                       ON CONFLICT (id) DO UPDATE SET nome=EXCLUDED.nome,
                         abreviacao=EXCLUDED.abreviacao, escudo=EXCLUDED.escudo""",
                    (club_id, name, abbreviation, crest))

    if isinstance(positions, dict):
        for key in positions:
            position_code(key, positions)
    if isinstance(statuses, dict):
        for key in statuses:
            status_code(key, statuses)

    schemes = schemes_payload.get("esquemas", schemes_payload) if isinstance(schemes_payload, dict) else schemes_payload
    for scheme in dict_values(schemes):
        name = str(scheme.get("nome") or scheme.get("esquema") or "").strip()
        if not name:
            continue
        quantities = scheme.get("posicoes") or scheme.get("quantidades") or scheme
        def q(*keys: str, default: int = 0) -> int:
            for k in keys:
                if k in quantities:
                    return as_int(quantities[k], default) or 0
            return default
        cur.execute("""INSERT INTO liga_facom.esquema_tatico
            (nome, qtd_lateral, qtd_meia, qtd_atacante, qtd_tecnico, qtd_zagueiro, qtd_goleiro)
            VALUES (%s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT (nome) DO UPDATE SET qtd_lateral=EXCLUDED.qtd_lateral,
              qtd_meia=EXCLUDED.qtd_meia, qtd_atacante=EXCLUDED.qtd_atacante,
              qtd_tecnico=EXCLUDED.qtd_tecnico, qtd_zagueiro=EXCLUDED.qtd_zagueiro,
              qtd_goleiro=EXCLUDED.qtd_goleiro""",
            (name, q("lat", "lateral", "2"), q("mei", "meia", "4"),
             q("ata", "atacante", "5"), q("tec", "tecnico", "técnico", "6", default=1),
             q("zag", "zagueiro", "3"), q("gol", "goleiro", "1", default=1)))

    return positions, statuses


def upsert_market_athletes(cur, market: dict[str, Any], positions: dict[str, Any], statuses: dict[str, Any]) -> None:
    athletes = market.get("atletas", {})
    for key, athlete in (athletes.items() if isinstance(athletes, dict) else []):
        athlete_id = as_int(athlete.get("atleta_id", key))
        if athlete_id is None:
            continue
        pos = position_code(athlete.get("posicao_id"), positions)
        status = status_code(athlete.get("status_id"), statuses)
        full_name = athlete.get("nome") or athlete.get("nome_completo") or athlete.get("apelido") or f"Atleta {athlete_id}"
        nickname = athlete.get("apelido") or full_name
        cur.execute("""INSERT INTO liga_facom.atleta (id, nome_completo, apelido, posicao, situacao_atual)
                       VALUES (%s,%s,%s,%s,%s)
                       ON CONFLICT (id) DO UPDATE SET nome_completo=EXCLUDED.nome_completo,
                         apelido=EXCLUDED.apelido, posicao=EXCLUDED.posicao,
                         situacao_atual=EXCLUDED.situacao_atual""",
                    (athlete_id, full_name[:100], nickname[:50], pos, status))


def upsert_round(cur, round_number: int, matches_payload: dict[str, Any], pontuados_payload: dict[str, Any],
                 positions: dict[str, Any], statuses: dict[str, Any]) -> bool:
    matches = matches_payload.get("partidas", [])
    if not isinstance(matches, list):
        matches = []
    played = [m for m in matches if m.get("placar_oficial_mandante") is not None
              and m.get("placar_oficial_visitante") is not None]
    athletes = pontuados_payload.get("atletas", {})
    if not played or not athletes:
        print(f"Rodada {round_number}: sem placares ou sem atletas pontuados; ignorada.")
        return False
    cur.execute("""INSERT INTO liga_facom.rodada (numero, estado) VALUES (%s, 'consolidada')
                   ON CONFLICT (numero) DO UPDATE SET estado='consolidada'""", (round_number,))

    match_by_club: dict[int, int] = {}
    for match in matches:
        match_id = as_int(match.get("partida_id", match.get("id")))
        home = as_int(match.get("clube_casa_id", match.get("mandante_id")))
        away = as_int(match.get("clube_visitante_id", match.get("visitante_id")))
        if None in (match_id, home, away):
            continue
        date_value = match.get("partida_data") or match.get("data_hora")
        date_time = parse_datetime(date_value)
        home_score = match.get("placar_oficial_mandante")
        away_score = match.get("placar_oficial_visitante")
        valid = match.get("valida", True)
        cur.execute("""INSERT INTO liga_facom.partida
            (id, local, data_hora, placar_mandante, placar_visitante, valida,
             rodada_numero, mandante_id, visitante_id)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT (id) DO UPDATE SET local=EXCLUDED.local, data_hora=EXCLUDED.data_hora,
              placar_mandante=EXCLUDED.placar_mandante, placar_visitante=EXCLUDED.placar_visitante,
              valida=EXCLUDED.valida, rodada_numero=EXCLUDED.rodada_numero,
              mandante_id=EXCLUDED.mandante_id, visitante_id=EXCLUDED.visitante_id""",
            (match_id, match.get("local"), date_time, home_score, away_score, bool(valid), round_number, home, away))
        match_by_club[home] = match_id
        match_by_club[away] = match_id

    for key, athlete in (athletes.items() if isinstance(athletes, dict) else []):
        athlete_id = as_int(athlete.get("atleta_id", key))
        club_id = as_int(athlete.get("clube_id"))
        if athlete_id is None or club_id is None:
            continue
        pos = position_code(athlete.get("posicao_id"), positions)
        full_name = athlete.get("nome") or athlete.get("nome_completo") or athlete.get("apelido") or f"Atleta {athlete_id}"
        nickname = athlete.get("apelido") or full_name
        status = status_code(athlete.get("status_id"), statuses)
        cur.execute("""INSERT INTO liga_facom.atleta (id,nome_completo,apelido,posicao,situacao_atual)
                       VALUES (%s,%s,%s,%s,%s)
                       ON CONFLICT (id) DO NOTHING""",
                    (athlete_id, full_name[:100], nickname[:50], pos, status))
        cur.execute("""INSERT INTO liga_facom.atleta_clube_rodada (atleta_id,rodada_numero,clube_id)
                       VALUES (%s,%s,%s) ON CONFLICT (atleta_id,rodada_numero)
                       DO UPDATE SET clube_id=EXCLUDED.clube_id""",
                    (athlete_id, round_number, club_id))
        match_id = match_by_club.get(club_id)
        if match_id is None:
            continue
        entered = bool(athlete.get("entrou_em_campo", False))
        cur.execute("""INSERT INTO liga_facom.atleta_partida (atleta_id,partida_id,entrou_em_campo)
                       VALUES (%s,%s,%s) ON CONFLICT (atleta_id,partida_id)
                       DO UPDATE SET entrou_em_campo=EXCLUDED.entrou_em_campo""",
                    (athlete_id, match_id, entered))
        scouts = athlete.get("scout") or {}
        for scout_code, quantity in scouts.items():
            try:
                quantity_int = int(quantity)
            except (TypeError, ValueError):
                continue
            cur.execute(
                "INSERT INTO liga_facom.atleta_partida_scout "
                "(atleta_id,partida_id,sigla_scout,quantidade) VALUES (%s,%s,%s,%s) "
                "ON CONFLICT (atleta_id,partida_id,sigla_scout) "
                "DO UPDATE SET quantidade=EXCLUDED.quantidade",
                (athlete_id, match_id, str(scout_code), quantity_int),
            )
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Importa dados da API do Cartola para Liga FACOM Fantasy")
    parser.add_argument("--rodadas", default="1-10", help="Ao menos 10 rodadas, ex.: 1-10 ou 1-5,7-11")
    parser.add_argument("--dsn", default=os.getenv("DATABASE_URL"), help="String de conexão PostgreSQL; também aceita DATABASE_URL")
    args = parser.parse_args()
    if not args.dsn:
        parser.error("Defina DATABASE_URL ou informe --dsn com a conexão PostgreSQL.")
    rounds = parse_rounds(args.rodadas)
    api = CartolaAPI()
    conn = None
    try:
        print("Buscando dados gerais da API...")
        market = api.get("/atletas/mercado", "atletas_mercado")
        clubs_payload = api.get("/clubes", "clubes")
        schemes_payload = api.get("/esquemas", "esquemas")
        positions = market.get("posicoes", {})
        statuses = market.get("status", {})

        conn = psycopg2.connect(args.dsn)
        conn.autocommit = False
        with conn.cursor() as cur:
            upsert_reference_data(cur, market, clubs_payload, schemes_payload)
            upsert_market_athletes(cur, market, positions, statuses)
            conn.commit()

        imported = 0
        for number in rounds:
            print(f"Buscando rodada {number}...")
            matches = api.get(f"/partidas/{number}", f"partidas_rodada_{number}")
            points = api.get(f"/atletas/pontuados/{number}", f"pontuados_rodada_{number}")
            with conn.cursor() as cur:
                did_import = upsert_round(cur, number, matches, points, positions, statuses)
            conn.commit()
            imported += int(did_import)
        if imported < 10:
            raise ValueError(
                f"Apenas {imported} rodadas tinham placares e atletas pontuados. "
                "Informe pelo menos dez rodadas já encerradas em --rodadas."
            )
        print(f"Carga concluída. Rodadas efetivamente importadas: {imported}. JSONs salvos em {JSON_DIR}.")
        return 0
    except (requests.RequestException, psycopg2.Error, ValueError, KeyError) as exc:
        if conn:
            conn.rollback()
        print(f"ERRO NA CARGA: {exc}", file=sys.stderr)
        return 1
    finally:
        if conn:
            conn.close()


if __name__ == "__main__":
    raise SystemExit(main())