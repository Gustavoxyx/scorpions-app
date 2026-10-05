"""Limite de uso por usuário.

POR QUE ISTO EXISTE (MEDIUM-4 da auditoria, §16 e §17 do briefing)
------------------------------------------------------------------
`ImageLimits.maxIdentificationsPerDay = 60` existia no Flutter desde a Fase 4,
e o comentário dizia em voz alta que **ninguém o aplicava** — nem o aplicativo,
nem as Security Rules. Era decisão de produto registrada, não limite em vigor.

O modelo de ameaças marca isso como a pior lacuna conhecida (T-2 e T-8): um
usuário com conta legítima podia gerar análises sem fim e esgotar a cota do
projeto. Com inferência real, cada chamada passa a custar dinheiro ou tempo de
GPU, e o §17 chama isso de proteger o orçamento.

POR QUE NO SERVIDOR, E NÃO NO CLIENTE
-------------------------------------
Um freio no aplicativo custaria uma consulta por envio e um cliente adulterado
o ignoraria: pagaria o preço sem entregar a proteção. É literalmente o que o
comentário de `ImageLimits` previu.

POR QUE UMA TRANSAÇÃO, E NÃO LER-E-ESCREVER
-------------------------------------------
Dois pedidos simultâneos que leem 59, decidem "cabe" e gravam 60 deixam o
usuário com 61 análises. Com um aplicativo é raro; com um script, é o ataque.

`@firestore.transactional` resolve: o Firestore detecta que o documento mudou
entre a leitura e a escrita e repete a transação. É o único jeito de um contador
distribuído estar certo.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status

from .config import Settings


@dataclass(frozen=True)
class QuotaStatus:
    """Quanto foi usado hoje, e quanto resta."""

    used: int
    limit: int

    @property
    def remaining(self) -> int:
        return max(0, self.limit - self.used)

    @property
    def exceeded(self) -> bool:
        return self.used >= self.limit


def _hoje_utc() -> str:
    """A chave do dia, em UTC.

    UTC e não o fuso do usuário, de propósito: o fuso vem do cliente e o
    cliente não é confiável. Alguém que escolhesse o fuso teria um "novo dia" a
    cada troca, e com ele uma cota nova.

    O custo é que a virada acontece às 21h no horário de Brasília. Para um
    limite de abuso isso é irrelevante — ninguém planeja o dia em torno da cota
    de 60 análises.
    """
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def _doc_ref(settings: Settings, uid: str):
    """O documento do contador.

    Em `users/{uid}/quotas/{dia}`, subcoleção do próprio usuário: o caminho
    carrega o dono, igual ao do Storage. Um documento por dia, em vez de um
    campo que cresce — assim o registro antigo é apagável por prazo sem tocar no
    documento do perfil.
    """
    from .clients import firestore_client

    return (
        firestore_client(settings)
        .collection("users")
        .document(uid)
        .collection("quotas")
        .document(_hoje_utc())
    )


def peek(settings: Settings, uid: str) -> QuotaStatus:
    """Lê o consumo de hoje sem alterar nada.

    Para mostrar "restam N análises hoje" na tela. **Não serve para autorizar:**
    entre o `peek` e o uso, o número pode mudar. Quem autoriza é `consume`.
    """
    limite = settings.max_analyses_per_day
    try:
        doc = _doc_ref(settings, uid).get()
        usado = int((doc.to_dict() or {}).get("count", 0)) if doc.exists else 0
    except Exception:  # noqa: BLE001
        # Falhar **aberto** aqui, ao contrário de `consume`: esta função só
        # informa. Mostrar "restam 60" quando o contador está indisponível é
        # impreciso; recusar a tela por causa disso seria pior. Quem protege a
        # cota é `consume`, e lá a decisão é oposta.
        usado = 0
    return QuotaStatus(used=usado, limit=limite)


def consume(settings: Settings, uid: str, *, cost: int = 1) -> QuotaStatus:
    """Reserva [cost] unidades da cota de hoje, ou recusa com 429.

    # Cobrar antes, não depois
    O incremento acontece **antes** da inferência. Se ela falhar, a unidade foi
    gasta — e isso é deliberado: o custo de computação já foi pago pelo projeto,
    e devolver a unidade em caso de erro abriria o caminho de provocar erros de
    propósito para rodar de graça.

    # Falhar fechado
    Se o contador não puder ser lido ou escrito, a operação é **recusada** (503).
    O §44 é explícito: em caso de dúvida, negar. A alternativa — liberar quando
    o Firestore oscila — é um atacante esperando pela oscilação.
    """
    from google.cloud import firestore

    from .clients import firestore_client

    limite = settings.max_analyses_per_day

    # Tudo que pode falhar por infraestrutura fica DENTRO do `try`, inclusive
    # montar a referência e obter o cliente.
    #
    # Isto era um defeito, e um teste o pegou: com `_doc_ref` fora do bloco, uma
    # falha ali escapava crua e o usuário recebia o 500 genérico do tratador em
    # vez do 503 com `Retry-After`. O efeito é recusar de qualquer forma — o §44
    # continuava respeitado —, mas pela mensagem errada e sem dizer quando
    # voltar.
    try:
        ref = _doc_ref(settings, uid)
        cliente = firestore_client(settings)

        # A transação devolve **se concedeu**, separado do estado da cota.
        # Deduzir "foi recusado" comparando números depois seria repetir a
        # decisão fora da transação, com o risco de os dois lugares discordarem.
        @firestore.transactional
        def _incrementar(transacao) -> tuple[bool, QuotaStatus]:
            doc = ref.get(transaction=transacao)
            atual = int((doc.to_dict() or {}).get("count", 0)) if doc.exists else 0

            if atual + cost > limite:
                return False, QuotaStatus(used=atual, limit=limite)

            transacao.set(
                ref,
                {
                    "count": atual + cost,
                    "day": _hoje_utc(),
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                },
                merge=True,
            )
            return True, QuotaStatus(used=atual + cost, limit=limite)

        concedido, resultado = _incrementar(cliente.transaction())
    except Exception as erro:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Não foi possível verificar seu limite de uso. Tente novamente.",
            headers={"Retry-After": "60"},
        ) from erro

    if not concedido:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                f"Você atingiu o limite de {limite} análises por dia. "
                "O limite é renovado amanhã."
            ),
            headers={"Retry-After": str(_segundos_ate_amanha())},
        )

    return resultado


def _segundos_ate_amanha() -> int:
    """Quanto falta para a virada do dia em UTC.

    `Retry-After` com um número honesto, não um valor fixo: um cliente que
    respeita o cabeçalho volta na hora certa, em vez de bater de novo em 60
    segundos e levar outro 429.

    Piso de 60 segundos porque, perto da meia-noite, o número verdadeiro é 2 —
    e um cliente que volta em 2 segundos com o relógio adiantado leva outro 429.
    """
    agora = datetime.now(timezone.utc)
    amanha = (agora + timedelta(days=1)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    return max(60, int((amanha - agora).total_seconds()))
