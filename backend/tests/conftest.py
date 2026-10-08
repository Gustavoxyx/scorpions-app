"""Preparação comum a todos os testes do backend."""

from __future__ import annotations

import os

import pytest

os.environ.setdefault("FIREBASE_PROJECT_ID", "demo-scorpions")
os.environ.setdefault(
    "FIREBASE_SERVICE_ACCOUNT",
    '{"type":"service_account","project_id":"demo-scorpions",'
    '"private_key":"nao-e-uma-chave","client_email":"teste@exemplo"}',
)


@pytest.fixture(autouse=True)
def _janelas_limpas():
    """Cada teste começa com as janelas de limite de chamadas vazias.

    Elas são estado do processo. Sem isto, o vigésimo teste a chamar um
    endpoint seria recusado por causa dos dezenove anteriores.
    """
    from app import ratelimit

    ratelimit.reset()
    yield
    ratelimit.reset()
