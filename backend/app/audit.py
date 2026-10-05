"""Registro de auditoria das operações críticas.

POR QUE ISTO EXISTE (LOW-4 da auditoria, FASE 24 do briefing)
-------------------------------------------------------------
Até aqui, um acesso indevido bem-sucedido **não deixava rastro nenhum**. O
modelo de ameaças registra a consequência em T-4: uma conta administrativa
comprometida leria dados de usuários e ninguém saberia — nem durante, nem
depois.

Um plano de resposta a incidentes sem audit log tem uma etapa de investigação
sem dados. É a lacuna que este arquivo fecha.

AUDIT LOG NÃO É LOG TÉCNICO
---------------------------
O §23 do briefing pede que sejam separados, e a razão não é organização:

| | log técnico | audit log |
|---|---|---|
| para quê | achar defeito | saber quem fez o quê |
| onde | saída padrão do provedor | Firestore, coleção `auditLogs` |
| quanto tempo | 90 dias | 24 meses |
| quem lê | eu, depurando | uma investigação, meses depois |

Um log que rola e desaparece não serve para investigar o que aconteceu em
março.

O QUE NUNCA ENTRA AQUI (§24, §27)
---------------------------------
O briefing é explícito: *"Não armazenar dados sensíveis desnecessários no audit
log."* Então a entrada registra **que** algo aconteceu e **sobre qual recurso**,
nunca o conteúdo:

- ✅ `uid` do autor — é o ponto inteiro do registro
- ✅ ação, recurso, resultado, horário do servidor
- ✅ contagens (quantas imagens, quantos documentos)
- ❌ e-mail, nome, senha, token, URL de imagem, bytes
- ❌ o conteúdo do documento alterado

A ironia de um audit log vazar dado pessoal não é teórica: ele é justamente o
lugar que concentra atividade de todos os usuários, e por isso é o alvo mais
valioso do banco. Guardar menos é guardá-lo melhor.
"""

from __future__ import annotations

import logging
from enum import Enum

from .config import Settings

log = logging.getLogger("scorpions.audit")


class AuditAction(str, Enum):
    """As ações que geram registro.

    Lista fechada de propósito: uma string livre viraria `"delete"`,
    `"deleted"`, `"account_delete"` e `"accountDeletion"` em seis meses, e
    nenhuma consulta encontraria todas.
    """

    ACCOUNT_DELETED = "account.deleted"
    ACCOUNT_DELETE_FAILED = "account.delete_failed"
    DATA_EXPORTED = "account.data_exported"
    QUOTA_EXCEEDED = "quota.exceeded"
    ROLE_READ_FAILED = "auth.role_read_failed"
    REVIEW_QUEUE_ACCESSED = "review.queue_accessed"
    ANALYSIS_REQUESTED = "analysis.requested"


class AuditOutcome(str, Enum):
    SUCCESS = "success"
    DENIED = "denied"
    FAILED = "failed"


def record(
    settings: Settings,
    *,
    action: AuditAction,
    actor_uid: str,
    outcome: AuditOutcome,
    request_id: str,
    resource: str | None = None,
    counts: dict[str, int] | None = None,
) -> None:
    """Grava uma entrada de auditoria.

    # Nunca derruba a operação que está auditando
    Se o Firestore estiver indisponível, a exclusão de conta que o usuário
    pediu **não** pode falhar por causa do registro. O usuário tem direito de
    apagar os dados dele; perder a linha de auditoria é ruim, negar o direito é
    pior.

    Então a falha é registrada no log técnico, onde pelo menos fica o rastro de
    que houve um registro que não foi gravado. Silêncio total seria a pior das
    três opções.

    # Horário do servidor, não do cliente
    `SERVER_TIMESTAMP`. Um carimbo vindo do cliente poderia ser recuado para
    esconder quando algo aconteceu — e numa investigação a ordem dos eventos é
    metade da resposta.
    """
    try:
        from google.cloud import firestore

        from .clients import firestore_client

        entrada: dict[str, object] = {
            "action": action.value,
            "actorUid": actor_uid,
            "outcome": outcome.value,
            "requestId": request_id,
            "at": firestore.SERVER_TIMESTAMP,
        }
        if resource is not None:
            entrada["resource"] = resource
        if counts:
            entrada["counts"] = counts

        firestore_client(settings).collection("auditLogs").add(entrada)
    except Exception as erro:  # noqa: BLE001
        # Sem `uid` nem detalhe aqui: esta linha vai para o log técnico, que
        # não é o lugar de dado pessoal (§27).
        log.error(
            "audit log não gravado",
            extra={"request_id": request_id, "action": action.value},
            exc_info=erro,
        )
