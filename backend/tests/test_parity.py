"""Verifica que a fusão em Python concorda com a fusão em Dart.

A lógica de fusão e decisão existe nos dois lados — o servidor precisa dela
porque é ele quem grava o resultado (auditoria HIGH-1), e o aplicativo precisa
dela para o modo de demonstração, que roda sem rede.

Duas implementações da mesma ideia divergem em silêncio. É o que este arquivo
impede.

Os casos vêm de `fusion_cases.json`, que é **gerado** por
`test/fusion_cases_test.dart` executando a implementação Dart de verdade.
Nenhum número aqui foi escrito à mão: se alguém mudar uma das implementações
sem mudar a outra, estes testes falham com o caso exato e os dois valores.

    flutter test test/fusion_cases_test.dart     # regenera
    python -m pytest tests/test_parity.py        # verifica
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import pytest

from app.fusion import (
    FusionStrategy,
    ViewPrediction,
    assess,
    fuse,
)

CASES_FILE = Path(__file__).parent / "fusion_cases.json"

# Tolerância de ponto flutuante entre Dart e Python.
#
# Os dois usam IEEE 754 de precisão dupla e as mesmas operações, então a
# diferença esperada é da ordem do épsilon da máquina. O JSON gerado arredonda
# em 4 casas, e é por isso que a tolerância é 1e-4 e não 1e-12: estamos
# comparando valores já arredondados, não os brutos.
TOL = 1e-4


def _carregar() -> list[dict]:
    if not CASES_FILE.exists():
        pytest.skip(
            f"{CASES_FILE.name} não existe. Gere com: "
            "flutter test test/fusion_cases_test.dart"
        )
    dados = json.loads(CASES_FILE.read_text(encoding="utf-8"))
    return dados["cases"]


def _montar_vistas(entrada: dict) -> list[ViewPrediction]:
    return [
        ViewPrediction(
            capture_type=v["type"],
            scores=dict(v["scores"]),
            model_version="parity-v1",
            quality_weight=v.get("weight", 1.0),
        )
        for v in entrada["views"]
    ]


CASOS = _carregar() if CASES_FILE.exists() else []


@pytest.mark.parametrize(
    "caso", CASOS, ids=[c["name"] for c in CASOS] or None
)
def test_paridade_com_dart(caso: dict) -> None:
    entrada = caso["input"]
    esperado = caso["expected"]

    vistas = _montar_vistas(entrada)
    estrategia = FusionStrategy(entrada["strategy"])

    fundido = fuse(vistas, strategy=estrategia)
    decisao = assess(fundido, combined_quality=entrada.get("quality"))

    f_esperado = esperado["fused"]
    c_esperado = esperado["confidence"]

    # -- Fusão ---------------------------------------------------------------
    assert fundido.view_count == f_esperado["viewCount"], "contagem de vistas"

    assert math.isclose(
        round(fundido.raw_top_score, 4), f_esperado["rawTopScore"], abs_tol=TOL
    ), (
        f"rawTopScore: Dart={f_esperado['rawTopScore']} "
        f"Python={round(fundido.raw_top_score, 4)}"
    )

    assert math.isclose(
        round(fundido.margin, 4), f_esperado["margin"], abs_tol=TOL
    ), f"margem: Dart={f_esperado['margin']} Python={round(fundido.margin, 4)}"

    # Ordem E valores do Top-3. A ordem importa: é ela que decide qual espécie
    # aparece como resposta.
    candidatos_esperados = f_esperado["candidates"]
    assert len(fundido.top_three) == len(candidatos_esperados), "tamanho do Top-3"
    for i, (sid, score) in enumerate(fundido.top_three):
        assert sid == candidatos_esperados[i]["speciesId"], (
            f"posição {i} do Top-3: Dart={candidatos_esperados[i]['speciesId']} "
            f"Python={sid}"
        )
        assert math.isclose(
            round(score, 4), candidatos_esperados[i]["confidence"], abs_tol=TOL
        ), (
            f"score na posição {i}: "
            f"Dart={candidatos_esperados[i]['confidence']} Python={round(score, 4)}"
        )

    # -- Consistência cruzada -------------------------------------------------
    cons_esperada = f_esperado["consistency"]
    assert fundido.consistency.agree_on_top1 == cons_esperada["agreeOnTop1"]
    assert math.isclose(
        round(fundido.consistency.top_k_overlap, 3),
        cons_esperada["topKOverlap"],
        abs_tol=1e-3,
    )
    assert math.isclose(
        round(fundido.consistency.distribution_agreement, 4),
        cons_esperada["distributionAgreement"],
        abs_tol=TOL,
    ), (
        "Jensen-Shannon divergiu: "
        f"Dart={cons_esperada['distributionAgreement']} "
        f"Python={round(fundido.consistency.distribution_agreement, 4)}"
    )

    # -- Decisão --------------------------------------------------------------
    # A mais importante das verificações. Score diferente por 0,0001 é
    # irrelevante; nível de decisão diferente significa que um dos lados
    # mostraria uma espécie que o outro recusaria.
    assert decisao.level.value == c_esperado["level"], (
        f"NÍVEL DE DECISÃO DIVERGIU — Dart={c_esperado['level']} "
        f"Python={decisao.level.value}"
    )

    assert sorted(r.value for r in decisao.reasons) == sorted(
        c_esperado["reasons"]
    ), (
        f"razões: Dart={sorted(c_esperado['reasons'])} "
        f"Python={sorted(r.value for r in decisao.reasons)}"
    )

    assert decisao.thresholds_calibrated == c_esperado["thresholdsCalibrated"], (
        "os dois lados precisam concordar sobre os limiares terem sido "
        "calibrados ou não"
    )


def test_arquivo_de_casos_existe_e_tem_conteudo() -> None:
    """Falha explicitamente se os casos sumirem.

    Sem isto, apagar `fusion_cases.json` faria a verificação de paridade
    inteira ser pulada — e o conjunto passaria em verde sem ter verificado
    nada, que é pior que falhar.
    """
    assert CASES_FILE.exists(), (
        "fusion_cases.json ausente. Gere com: "
        "flutter test test/fusion_cases_test.dart"
    )
    casos = _carregar()
    assert len(casos) >= 20, f"esperava pelo menos 20 casos, achei {len(casos)}"


def test_jensen_shannon_tem_as_propriedades_esperadas() -> None:
    """Confere a matemática por si, não só a paridade.

    Paridade garante que os dois lados concordam; não garante que ambos estão
    certos. Estas três propriedades são verificáveis contra a definição.
    """
    from app.fusion import jensen_shannon

    # Idêntica a si mesma: divergência zero.
    p = {"a": 0.7, "b": 0.3}
    assert math.isclose(jensen_shannon(p, p), 0.0, abs_tol=1e-12)

    # Disjuntas: divergência máxima, que em base 2 é exatamente 1.
    assert math.isclose(
        jensen_shannon({"a": 1.0}, {"b": 1.0}), 1.0, abs_tol=1e-12
    )

    # Simétrica — a razão de não usarmos Kullback-Leibler.
    q = {"b": 0.6, "c": 0.4}
    assert math.isclose(
        jensen_shannon(p, q), jensen_shannon(q, p), abs_tol=1e-12
    )
