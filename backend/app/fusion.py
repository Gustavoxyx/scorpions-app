"""Fusão multi-view e decisão de confiança.

POR QUE ESTA LÓGICA EXISTE DUAS VEZES
-------------------------------------
Ela está aqui, em Python, e em `lib/data/services/multi_view_fusion_service.dart`
e `confidence_engine.dart`, em Dart. Duplicação é dívida, e esta é assumida de
olhos abertos pelos dois lados precisarem dela:

- **O servidor** é a autoridade. É o resultado que ele calcula que vai para o
  Firestore, porque o cliente não pode escrever `confidence` (auditoria
  HIGH-1).
- **O aplicativo** precisa da mesma lógica para o modo de demonstração — sem
  rede, sem backend, sem conta — que é como o projeto roda numa apresentação
  cujo Wi-Fi não se pode garantir.

A alternativa seria o aplicativo não fundir nada e sempre esperar o servidor.
Isso tornaria a demonstração impossível de fazer fora de linha, e foi
descartado por isso.

O QUE IMPEDE AS DUAS DE DIVERGIREM
----------------------------------
`tests/test_parity.py` roda os **mesmos casos** que o teste Dart, lidos de
`fusion_cases.json` — um arquivo **gerado** pelo teste Dart a partir da
implementação dele, não escrito à mão. Se as duas implementações discordarem
em qualquer caso, o CI quebra.

É o mesmo padrão de `contract_shapes_test.dart`, que já pegou um bug real no
projeto: enquanto o teste inventa o dado, ele testa a si mesmo.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from enum import Enum


# =============================================================================
# Limiares — espelham lib/core/constants/decision_thresholds.dart
# =============================================================================
# NENHUM destes valores foi calibrado. Não vêm de conjunto de validação,
# porque ainda não existe modelo nem dataset. São pontos de partida, e
# `CALIBRATED` diz isso em toda resposta da API.

CALIBRATED = False

REJECT_BELOW = 0.35
HIGH_SCORE = 0.75
MEDIUM_SCORE = 0.50

DECISIVE_MARGIN = 0.20
AMBIGUOUS_MARGIN = 0.08

CONSISTENT_VIEWS = 0.70
CONFLICTING_VIEWS = 0.40

POOR_QUALITY_WEIGHT = 0.35
ACCEPTABLE_QUALITY_WEIGHT = 0.75
GOOD_QUALITY_WEIGHT = 1.0


class FusionStrategy(str, Enum):
    AVERAGE = "average"
    MAXIMUM = "maximum"
    CONFIDENCE_WEIGHTED = "confidence_weighted"
    QUALITY_WEIGHTED = "quality_weighted"


class DecisionLevel(str, Enum):
    HIGH_CONFIDENCE = "high_confidence"
    MEDIUM_CONFIDENCE = "medium_confidence"
    LOW_CONFIDENCE = "low_confidence"
    REJECT = "reject"
    HUMAN_REVIEW = "human_review"

    @property
    def shows_species(self) -> bool:
        return self in (DecisionLevel.HIGH_CONFIDENCE, DecisionLevel.MEDIUM_CONFIDENCE)


class DecisionReason(str, Enum):
    SCORE_BELOW_REJECTION = "score_below_rejection"
    SCORE_LOW = "score_low"
    MARGIN_AMBIGUOUS = "margin_ambiguous"
    MARGIN_NARROW = "margin_narrow"
    VIEWS_CONFLICT = "views_conflict"
    VIEWS_DISAGREE = "views_disagree"
    POOR_IMAGE_QUALITY = "poor_image_quality"
    SINGLE_VIEW_ONLY = "single_view_only"
    NOT_EVALUATED = "not_evaluated"
    UNCALIBRATED_THRESHOLDS = "uncalibrated_thresholds"


@dataclass(frozen=True)
class ViewPrediction:
    """O que o classificador respondeu para uma das vistas."""

    capture_type: str
    scores: dict[str, float]
    model_version: str
    quality_weight: float = 1.0

    @property
    def is_empty(self) -> bool:
        return not self.scores

    @property
    def top(self) -> tuple[str, float] | None:
        if not self.scores:
            return None
        return max(self.scores.items(), key=lambda kv: kv[1])

    @property
    def margin(self) -> float:
        """Distância entre o primeiro e o segundo lugar."""
        if not self.scores:
            return 0.0
        if len(self.scores) == 1:
            return 1.0
        ordenado = sorted(self.scores.values(), reverse=True)
        return ordenado[0] - ordenado[1]


@dataclass(frozen=True)
class CrossViewConsistency:
    agree_on_top1: bool
    top_k_overlap: float
    distribution_agreement: float

    @property
    def is_conflicting(self) -> bool:
        return not self.agree_on_top1 and self.top_k_overlap < 0.5

    @staticmethod
    def single_view() -> "CrossViewConsistency":
        return CrossViewConsistency(True, 1.0, 1.0)

    def to_dict(self) -> dict:
        return {
            "agreeOnTop1": self.agree_on_top1,
            "topKOverlap": round(self.top_k_overlap, 3),
            "distributionAgreement": round(self.distribution_agreement, 4),
        }


@dataclass(frozen=True)
class FusedPrediction:
    candidates: list[tuple[str, float]]
    raw_top_score: float
    strategy: FusionStrategy
    consistency: CrossViewConsistency
    view_count: int
    model_versions: list[str] = field(default_factory=list)

    @property
    def was_evaluated(self) -> bool:
        return bool(self.candidates)

    @property
    def top(self) -> tuple[str, float] | None:
        return self.candidates[0] if self.candidates else None

    @property
    def margin(self) -> float:
        if not self.candidates:
            return 0.0
        if len(self.candidates) == 1:
            return 1.0
        return self.candidates[0][1] - self.candidates[1][1]

    @property
    def top_three(self) -> list[tuple[str, float]]:
        return self.candidates[:3]

    def to_dict(self) -> dict:
        return {
            "strategy": self.strategy.value,
            "viewCount": self.view_count,
            "modelVersions": self.model_versions,
            "margin": round(self.margin, 4),
            "rawTopScore": round(self.raw_top_score, 4),
            "consistency": self.consistency.to_dict(),
            "candidates": [
                {"speciesId": sid, "confidence": round(score, 4)}
                for sid, score in self.top_three
            ],
        }


# =============================================================================
# Consistência
# =============================================================================


def _normalize(origem: dict[str, float], chaves: set[str]) -> dict[str, float]:
    """Completa com zeros e reescala para somar 1.

    A reescala é necessária porque o modelo devolve apenas o Top-N: a soma dos
    scores entregues é menor que 1, e comparar distribuições de massas
    diferentes mediria a diferença de corte, não a de opinião.
    """
    soma = sum(origem.get(c, 0.0) for c in chaves)
    if soma <= 0:
        uniforme = 1.0 / len(chaves)
        return {c: uniforme for c in chaves}
    return {c: origem.get(c, 0.0) / soma for c in chaves}


def jensen_shannon(p: dict[str, float], q: dict[str, float]) -> float:
    """Divergência de Jensen-Shannon em base 2, no intervalo [0, 1].

    Kullback-Leibler seria a escolha de manual e está errada aqui: é
    assimétrica — e nenhuma das vistas é a referência da outra — e explode
    quando uma distribuição dá massa zero ao que a outra considera, o que
    acontece sempre, já que o modelo devolve só o Top-3.
    """
    chaves = set(p) | set(q)
    if not chaves:
        return 0.0

    pn = _normalize(p, chaves)
    qn = _normalize(q, chaves)

    divergencia = 0.0
    for chave in chaves:
        pi = pn[chave]
        qi = qn[chave]
        mi = (pi + qi) / 2
        if mi <= 0:
            continue
        if pi > 0:
            divergencia += 0.5 * pi * (math.log(pi / mi) / math.log(2))
        if qi > 0:
            divergencia += 0.5 * qi * (math.log(qi / mi) / math.log(2))

    return min(1.0, max(0.0, divergencia))


def consistency_between(
    a: ViewPrediction, b: ViewPrediction, k: int = 3
) -> CrossViewConsistency:
    if a.is_empty or b.is_empty:
        return CrossViewConsistency.single_view()

    top_a = {s for s, _ in sorted(a.scores.items(), key=lambda kv: -kv[1])[:k]}
    top_b = {s for s, _ in sorted(b.scores.items(), key=lambda kv: -kv[1])[:k]}

    uniao = top_a | top_b
    overlap = 1.0 if not uniao else len(top_a & top_b) / len(uniao)

    return CrossViewConsistency(
        agree_on_top1=a.top[0] == b.top[0],
        top_k_overlap=overlap,
        distribution_agreement=1.0 - jensen_shannon(a.scores, b.scores),
    )


# =============================================================================
# Fusão
# =============================================================================


def _pesos(vistas: list[ViewPrediction], modo: FusionStrategy) -> list[float]:
    if modo is FusionStrategy.CONFIDENCE_WEIGHTED:
        brutos = [max(v.margin, 0.1) for v in vistas]
    elif modo is FusionStrategy.QUALITY_WEIGHTED:
        brutos = [max(v.quality_weight, 0.1) for v in vistas]
    else:
        brutos = [1.0] * len(vistas)

    soma = sum(brutos)
    if soma <= 0:
        return [1.0 / len(vistas)] * len(vistas)
    return [p / soma for p in brutos]


def fuse(
    predictions: list[ViewPrediction],
    strategy: FusionStrategy = FusionStrategy.CONFIDENCE_WEIGHTED,
) -> FusedPrediction:
    usaveis = [p for p in predictions if not p.is_empty]

    if not usaveis:
        return FusedPrediction(
            candidates=[],
            raw_top_score=0.0,
            strategy=strategy,
            consistency=CrossViewConsistency.single_view(),
            view_count=0,
        )

    acordo = (
        CrossViewConsistency.single_view()
        if len(usaveis) < 2
        else consistency_between(usaveis[0], usaveis[1])
    )

    # União do que foi citado. Ausente de uma vista conta como zero ali, não
    # como "não considerada" — do contrário, o que aparece em apenas uma lista
    # teria a média sobre um divisor menor e sairia na frente sem merecer.
    ids = {s for v in usaveis for s in v.scores}
    pesos = _pesos(usaveis, strategy)

    combinado: dict[str, float] = {}
    for sid in ids:
        if strategy is FusionStrategy.MAXIMUM:
            combinado[sid] = max(v.scores.get(sid, 0.0) for v in usaveis)
        else:
            combinado[sid] = sum(
                v.scores.get(sid, 0.0) * pesos[i] for i, v in enumerate(usaveis)
            )

    # Desempate por nome para que a saída seja determinística: dois scores
    # iguais precisam sair sempre na mesma ordem, aqui e no Dart.
    ordenados = sorted(combinado.items(), key=lambda kv: (-kv[1], kv[0]))

    raw_top = ordenados[0][1] if ordenados else 0.0

    soma = sum(score for _, score in ordenados)
    renormalizado = (
        [(sid, score / soma) for sid, score in ordenados] if soma > 0 else ordenados
    )

    return FusedPrediction(
        candidates=renormalizado,
        raw_top_score=raw_top,
        strategy=strategy,
        consistency=acordo,
        view_count=len(usaveis),
        model_versions=sorted({v.model_version for v in usaveis}),
    )


# =============================================================================
# Decisão
# =============================================================================


@dataclass(frozen=True)
class ConfidenceAssessment:
    level: DecisionLevel
    reasons: list[DecisionReason]
    score: float
    margin: float
    view_agreement: float
    view_count: int
    thresholds_calibrated: bool = CALIBRATED

    def to_dict(self) -> dict:
        return {
            "level": self.level.value,
            "reasons": [r.value for r in self.reasons],
            "score": round(self.score, 4),
            "margin": round(self.margin, 4),
            "viewAgreement": round(self.view_agreement, 4),
            "viewCount": self.view_count,
            "thresholdsCalibrated": self.thresholds_calibrated,
        }


def weight_for(quality: str | None) -> float:
    return {
        "good": GOOD_QUALITY_WEIGHT,
        "acceptable": ACCEPTABLE_QUALITY_WEIGHT,
        "poor": POOR_QUALITY_WEIGHT,
        "invalid": POOR_QUALITY_WEIGHT,
    }.get(quality or "good", GOOD_QUALITY_WEIGHT)


def assess(
    prediction: FusedPrediction, combined_quality: str | None = None
) -> ConfidenceAssessment:
    """Decide o que fazer com a predição.

    O score sozinho mente em três situações que este sistema vai encontrar:
    empate com aparência de vitória, vistas em desacordo, e convicção sobre
    imagem ruim. Por isso a decisão olha quatro coisas, e a mais restritiva
    vence.
    """
    if not prediction.was_evaluated:
        return ConfidenceAssessment(
            level=DecisionLevel.LOW_CONFIDENCE,
            reasons=[DecisionReason.NOT_EVALUATED],
            score=0.0,
            margin=0.0,
            view_agreement=0.0,
            view_count=0,
        )

    score = prediction.top[1]
    margin = prediction.margin
    acordo = prediction.consistency.distribution_agreement
    razoes: list[DecisionReason] = []

    def montar(nivel: DecisionLevel, motivos: list[DecisionReason]):
        completas = list(motivos)
        if not CALIBRATED:
            completas.append(DecisionReason.UNCALIBRATED_THRESHOLDS)
        return ConfidenceAssessment(
            level=nivel,
            reasons=completas,
            score=score,
            margin=margin,
            view_agreement=acordo,
            view_count=prediction.view_count,
        )

    # Rejeição olha o score CRU, não o renormalizado. Reescalar para somar 1
    # infla um modelo indeciso: um par de hipóteses em 0,295 vira 0,50 cada, e
    # o limiar nunca dispararia justamente quando mais precisa.
    if prediction.raw_top_score < REJECT_BELOW:
        return montar(DecisionLevel.REJECT, [DecisionReason.SCORE_BELOW_REJECTION])

    if prediction.consistency.is_conflicting or (
        prediction.view_count >= 2 and acordo < CONFLICTING_VIEWS
    ):
        razoes.append(DecisionReason.VIEWS_CONFLICT)
    if margin < AMBIGUOUS_MARGIN:
        razoes.append(DecisionReason.MARGIN_AMBIGUOUS)
    if razoes:
        return montar(DecisionLevel.HUMAN_REVIEW, razoes)

    if score < MEDIUM_SCORE:
        razoes.append(DecisionReason.SCORE_LOW)
    if margin < DECISIVE_MARGIN:
        razoes.append(DecisionReason.MARGIN_NARROW)
    if prediction.view_count >= 2 and acordo < CONSISTENT_VIEWS:
        razoes.append(DecisionReason.VIEWS_DISAGREE)
    if combined_quality == "poor":
        razoes.append(DecisionReason.POOR_IMAGE_QUALITY)
    if prediction.view_count < 2:
        razoes.append(DecisionReason.SINGLE_VIEW_ONLY)

    if not razoes and score >= HIGH_SCORE:
        nivel = DecisionLevel.HIGH_CONFIDENCE
    elif score >= MEDIUM_SCORE and len(razoes) <= 2:
        nivel = DecisionLevel.MEDIUM_CONFIDENCE
    else:
        nivel = DecisionLevel.LOW_CONFIDENCE

    return montar(nivel, razoes)
