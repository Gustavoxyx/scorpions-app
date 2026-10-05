"""Configuração do serviço, lida do ambiente.

REGRA QUE NÃO SE NEGOCIA (briefing de segurança §2, §21)
--------------------------------------------------------
Nada de credencial neste arquivo, nem em nenhum outro do repositório. Tudo que
é segredo chega por variável de ambiente, e quem a define é o ambiente de
execução — os secrets do Hugging Face Space, do Render, ou o `.env` local que
está no `.gitignore`.

A service account do Firebase Admin é o caso mais sensível: ela **ignora as
Security Rules**. Se vazar, entrega o banco inteiro. Por isso ela existe só
aqui no servidor, nunca no aplicativo Flutter, e é lida como JSON de uma
variável em vez de arquivo — arquivo é mais fácil de commitar por engano.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from functools import lru_cache


class ConfigError(RuntimeError):
    """Configuração ausente ou inválida. Falha no início, não no primeiro uso."""


@dataclass(frozen=True)
class Settings:
    """Tudo que o serviço precisa saber para subir."""

    project_id: str
    storage_bucket: str

    # Credencial do Admin SDK, já desserializada. Nunca registrada em log,
    # nunca devolvida numa resposta, nunca incluída numa mensagem de erro.
    service_account: dict = field(repr=False)

    # Quantas análises um usuário pode pedir por dia (§12 da Fase 5).
    # O limite real é conferido no Firestore; este é o número de referência.
    max_analyses_per_day: int = 60

    # Teto de bytes por imagem. Espelha `ImageLimits.maxBytes` do Flutter e a
    # regra do Storage — os três precisam concordar, e o servidor é quem tem
    # a palavra final.
    max_image_bytes: int = 8 * 1024 * 1024

    # Quanto tempo a inferência pode levar antes de o pedido ser abandonado.
    inference_timeout_seconds: float = 30.0

    # Origens autorizadas a chamar a API pelo navegador.
    #
    # Lista explícita, nunca `*`. O §16 do briefing de segurança é direto
    # nisso, e a razão é concreta: com `*`, qualquer página conseguiria
    # disparar pedidos usando o token do usuário.
    allowed_origins: tuple[str, ...] = ()

    @property
    def is_configured(self) -> bool:
        return bool(self.project_id and self.service_account)


def _require(nome: str) -> str:
    valor = os.environ.get(nome, "").strip()
    if not valor:
        raise ConfigError(
            f"Variável de ambiente {nome} ausente. "
            "O serviço não sobe sem ela — ver backend/README.md."
        )
    return valor


def _service_account_from_env() -> dict:
    """Lê a credencial do ambiente.

    Aceita o JSON cru ou codificado em base64, porque alguns provedores
    estragam quebras de linha em variáveis multilinha e a chave privada tem
    várias.
    """
    cru = _require("FIREBASE_SERVICE_ACCOUNT")

    if not cru.lstrip().startswith("{"):
        import base64

        try:
            cru = base64.b64decode(cru).decode("utf-8")
        except Exception as erro:  # noqa: BLE001 - a causa exata não importa
            raise ConfigError(
                "FIREBASE_SERVICE_ACCOUNT não é JSON nem base64 válido."
            ) from erro

    try:
        dados = json.loads(cru)
    except json.JSONDecodeError as erro:
        raise ConfigError("FIREBASE_SERVICE_ACCOUNT não é JSON válido.") from erro

    faltando = {"type", "project_id", "private_key", "client_email"} - set(dados)
    if faltando:
        # Os nomes dos campos ausentes não são segredo; os valores seriam.
        raise ConfigError(
            f"Credencial incompleta, faltam os campos: {sorted(faltando)}"
        )

    return dados


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Carrega uma vez e reusa.

    Em cache de propósito: ler e validar a credencial a cada requisição seria
    desperdício, e `lru_cache` dá ao teste um ponto único para limpar
    (`get_settings.cache_clear()`).
    """
    origens = os.environ.get("ALLOWED_ORIGINS", "").strip()

    return Settings(
        project_id=_require("FIREBASE_PROJECT_ID"),
        storage_bucket=os.environ.get(
            "FIREBASE_STORAGE_BUCKET", ""
        ).strip(),
        service_account=_service_account_from_env(),
        max_analyses_per_day=int(os.environ.get("MAX_ANALYSES_PER_DAY", "60")),
        allowed_origins=tuple(
            o.strip() for o in origens.split(",") if o.strip()
        ),
    )
