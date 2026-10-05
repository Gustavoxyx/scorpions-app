"""Exclusão e exportação da conta do titular.

POR QUE ISTO EXISTE (HIGH-2 da auditoria, Art. 18 da LGPD)
----------------------------------------------------------
Não havia **nenhum** caminho para alguém apagar os próprios dados. Nem pelo
aplicativo, nem pedindo — porque não havia a quem pedir. Dos nove direitos do
Art. 18, cinco não tinham caminho, e o mais grave era o VI: eliminação.

Isto também destrava a política de retenção: sem exclusão em cascata, nenhum
prazo é aplicável, porque não existe o mecanismo que apaga.

POR QUE AQUI, E NÃO NUMA CLOUD FUNCTION
---------------------------------------
A cascata precisa de privilégio que o cliente não tem: apagar imagens de outra
pessoa — mesmo que essa pessoa seja ele — exige o Admin SDK, que ignora as
Security Rules. Cloud Functions exigiriam o plano Blaze, que não foi aprovado.
Este serviço já tem o Admin SDK e já verifica o token. Fazer aqui tira o direito
do titular da fila de uma decisão administrativa.

A ORDEM DA CASCATA NÃO É NEGOCIÁVEL
-----------------------------------
    1. imagens no Storage
    2. documentos em identifications
    3. subcoleções de users/{uid}
    4. o documento users/{uid}
    5. a conta no Firebase Authentication   ← por último

Se a conta fosse apagada primeiro e a cascata falhasse no meio, sobrariam
imagens órfãs: dado pessoal sem dono, e sem regra que o proteja, porque as
regras autorizam comparando com `request.auth.uid` e esse uid deixou de existir.
Pior que não ter começado.

Com esta ordem, uma falha no meio deixa a conta **ainda existindo** — o usuário
pode entrar e tentar de novo, e o audit log registra que a tentativa falhou.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field

from fastapi import HTTPException, status

from .audit import AuditAction, AuditOutcome, record
from .auth import Caller
from .config import Settings

log = logging.getLogger("scorpions.account")

#: Quantos documentos apagar por lote.
#:
#: O Firestore aceita até 500 operações por `batch`. 400 deixa margem para o
#: caso de um documento precisar de mais de uma operação, e mantém cada ida à
#: rede curta o suficiente para não estourar o tempo da requisição.
_TAMANHO_DO_LOTE = 400

#: Subcoleções de `users/{uid}` que a cascata precisa varrer.
#:
#: Lista explícita, não descoberta automática: `list_collections()` existe, mas
#: depender dele significaria que uma subcoleção nova passa a ser apagada sem
#: ninguém ter decidido isso. Preferir que a lista precise ser atualizada à mão
#: e que o esquecimento apareça num teste.
_SUBCOLECOES = ("quotas",)


@dataclass
class DeletionReport:
    """O que a cascata apagou. Vira contagem no audit log."""

    images: int = 0
    identifications: int = 0
    subcollection_docs: int = 0
    profile_deleted: bool = False
    auth_deleted: bool = False
    errors: list[str] = field(default_factory=list)

    def as_counts(self) -> dict[str, int]:
        """Só números — nunca caminho, nunca URL (§24, §27)."""
        return {
            "images": self.images,
            "identifications": self.identifications,
            "subcollectionDocs": self.subcollection_docs,
        }


def export_data(settings: Settings, caller: Caller, request_id: str) -> dict:
    """Devolve os dados do titular em JSON (Art. 18, V — portabilidade).

    # O que entra
    O perfil e as identificações. **Não** as imagens: um JSON com megabytes de
    base64 dentro é inútil para quem precisa levar os dados para outro lugar. O
    que vai é a referência, e o titular baixa cada imagem pelo aplicativo, com
    a regra do Storage autorizando normalmente.

    # O que nunca entra
    Nada de outro usuário. A consulta filtra por `userId == caller.uid`, e esse
    uid vem do token verificado — não do corpo do pedido.
    """
    from .clients import firestore_client

    cliente = firestore_client(settings)

    perfil = cliente.collection("users").document(caller.uid).get()
    dados_perfil = perfil.to_dict() if perfil.exists else {}

    identificacoes = [
        {"id": doc.id, **(doc.to_dict() or {})}
        for doc in cliente.collection("identifications")
        .where(filter=_igual("userId", caller.uid))
        .stream()
    ]

    record(
        settings,
        action=AuditAction.DATA_EXPORTED,
        actor_uid=caller.uid,
        outcome=AuditOutcome.SUCCESS,
        request_id=request_id,
        counts={"identifications": len(identificacoes)},
    )

    return {
        "exportedAt": _agora_iso(),
        "profile": _serializavel(dados_perfil),
        "identifications": [_serializavel(i) for i in identificacoes],
        "note": (
            "As imagens não vão neste arquivo, por tamanho. Cada identificação "
            "traz a referência da sua, acessível pelo aplicativo."
        ),
    }


def delete_account(
    settings: Settings, caller: Caller, request_id: str
) -> DeletionReport:
    """Apaga tudo do titular, na ordem segura (Art. 18, VI).

    O chamador **precisa** ter reautenticado — quem exige isso é o endpoint,
    com `caller.requires_recent_auth()`, antes de chegar aqui.
    """
    from .clients import firestore_client, storage_bucket

    relatorio = DeletionReport()
    cliente = firestore_client(settings)

    # --- 1. Imagens -----------------------------------------------------------
    # Primeiro, porque é o dado mais sensível e o único que, órfão, fica sem
    # nenhuma regra protegendo.
    try:
        bucket = storage_bucket(settings)
        prefixo = f"users/{caller.uid}/"
        for blob in bucket.list_blobs(prefix=prefixo):
            blob.delete()
            relatorio.images += 1
    except Exception as erro:  # noqa: BLE001
        relatorio.errors.append("storage")
        log.error(
            "cascata: falha ao apagar imagens",
            extra={"request_id": request_id},
            exc_info=erro,
        )

    # --- 2. Identificações ----------------------------------------------------
    try:
        relatorio.identifications = _apagar_em_lotes(
            cliente,
            cliente.collection("identifications").where(
                filter=_igual("userId", caller.uid)
            ),
        )
    except Exception as erro:  # noqa: BLE001
        relatorio.errors.append("identifications")
        log.error(
            "cascata: falha ao apagar identificações",
            extra={"request_id": request_id},
            exc_info=erro,
        )

    # --- 3. Subcoleções do perfil ---------------------------------------------
    # Apagar um documento no Firestore **não** apaga as subcoleções dele: elas
    # continuam existindo, acessíveis por caminho direto. Um contador de cota
    # sobrevivente é pouco, mas é dado de um titular que pediu para ser apagado.
    perfil_ref = cliente.collection("users").document(caller.uid)
    for nome in _SUBCOLECOES:
        try:
            relatorio.subcollection_docs += _apagar_em_lotes(
                cliente, perfil_ref.collection(nome)
            )
        except Exception as erro:  # noqa: BLE001
            relatorio.errors.append(f"subcollection:{nome}")
            log.error(
                "cascata: falha ao apagar subcoleção",
                extra={"request_id": request_id, "subcollection": nome},
                exc_info=erro,
            )

    # --- 4. O documento do perfil ---------------------------------------------
    try:
        perfil_ref.delete()
        relatorio.profile_deleted = True
    except Exception as erro:  # noqa: BLE001
        relatorio.errors.append("profile")
        log.error(
            "cascata: falha ao apagar perfil",
            extra={"request_id": request_id},
            exc_info=erro,
        )

    # --- 5. A conta de autenticação, por último -------------------------------
    #
    # Se algo acima falhou, a conta **não** é apagada. Deixar o login
    # funcionando é o que permite ao titular tentar de novo; apagar a conta
    # sobre uma cascata incompleta deixaria dados sem dono e sem caminho de
    # correção.
    if relatorio.errors:
        record(
            settings,
            action=AuditAction.ACCOUNT_DELETE_FAILED,
            actor_uid=caller.uid,
            outcome=AuditOutcome.FAILED,
            request_id=request_id,
            counts=relatorio.as_counts(),
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=(
                "Não foi possível concluir a exclusão. Nada da sua conta foi "
                "perdido pela metade: sua conta continua ativa e você pode "
                "tentar novamente."
            ),
            headers={"X-Request-Id": request_id},
        )

    try:
        import firebase_admin.auth as fb_auth

        from .auth import firebase_app

        fb_auth.delete_user(caller.uid, app=firebase_app(settings))
        relatorio.auth_deleted = True
    except Exception as erro:  # noqa: BLE001
        relatorio.errors.append("auth")
        log.error(
            "cascata: falha ao apagar a conta de autenticação",
            extra={"request_id": request_id},
            exc_info=erro,
        )
        record(
            settings,
            action=AuditAction.ACCOUNT_DELETE_FAILED,
            actor_uid=caller.uid,
            outcome=AuditOutcome.FAILED,
            request_id=request_id,
            counts=relatorio.as_counts(),
        )
        # Aqui os dados já foram apagados e só a conta sobrou. Dizer isso é
        # mais honesto que uma frase genérica: o titular precisa saber que o
        # login continua existindo, e que não há mais nada por trás dele.
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=(
                "Seus dados foram apagados, mas o login não pôde ser removido. "
                "Entre em contato para concluir."
            ),
            headers={"X-Request-Id": request_id},
        ) from erro

    record(
        settings,
        action=AuditAction.ACCOUNT_DELETED,
        actor_uid=caller.uid,
        outcome=AuditOutcome.SUCCESS,
        request_id=request_id,
        counts=relatorio.as_counts(),
    )
    return relatorio


# -- Interno -------------------------------------------------------------------


def _igual(campo: str, valor: str):
    """`FieldFilter` de igualdade.

    Numa função porque a forma antiga (`.where("campo", "==", v)`) está
    descontinuada e avisa a cada chamada. Um lugar só para mudar quando a API
    mudar de novo.
    """
    from google.cloud.firestore_v1.base_query import FieldFilter

    return FieldFilter(campo, "==", valor)


def _apagar_em_lotes(cliente, consulta) -> int:
    """Apaga tudo que a consulta devolve, em lotes. Devolve quantos.

    Em lotes e em laço, não de uma vez: uma consulta sem teto que devolve
    milhares de documentos carrega todos na memória antes de apagar o primeiro.
    `limit()` com repetição mantém o uso de memória constante, qualquer que seja
    o tamanho.
    """
    total = 0
    while True:
        documentos = list(consulta.limit(_TAMANHO_DO_LOTE).stream())
        if not documentos:
            return total

        lote = cliente.batch()
        for doc in documentos:
            lote.delete(doc.reference)
        lote.commit()
        total += len(documentos)

        # Lote incompleto significa que acabou. Sem isto, a última volta faria
        # uma consulta a mais para descobrir o que já se sabe.
        if len(documentos) < _TAMANHO_DO_LOTE:
            return total


def _agora_iso() -> str:
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).isoformat()


def _serializavel(valor):
    """Converte o que o Firestore devolve em algo que vira JSON.

    `DatetimeWithNanoseconds`, `DocumentReference` e `GeoPoint` não são
    serializáveis por padrão, e um deles no meio da exportação faria o pedido
    falhar com erro de serialização **depois** de já ter lido tudo.
    """
    from datetime import date, datetime

    if isinstance(valor, dict):
        return {k: _serializavel(v) for k, v in valor.items()}
    if isinstance(valor, (list, tuple)):
        return [_serializavel(v) for v in valor]
    if isinstance(valor, (datetime, date)):
        return valor.isoformat()
    if isinstance(valor, (str, int, float, bool)) or valor is None:
        return valor
    # Qualquer outro tipo do SDK vira texto em vez de derrubar a exportação.
    return str(valor)
