"""Quem está chamando, e o que essa pessoa pode fazer.

O PRINCÍPIO (briefing de segurança §35)
---------------------------------------
    FRONTEND = NÃO CONFIÁVEL
    REQUEST  = NÃO CONFIÁVEL

O aplicativo manda um ID token do Firebase. O servidor **verifica a assinatura
dele** com a chave pública do Google — não decodifica e acredita. A diferença
é tudo: um token decodificado sem verificação é texto que o cliente escreveu.

E o `uid` sai **do token verificado**, nunca do corpo do pedido. Esse é o
achado HIGH-1 da auditoria aplicado na prática: se o cliente pudesse dizer de
quem é a análise, poderia pedir uma em nome de outra pessoa.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

import firebase_admin
from fastapi import Depends, Header, HTTPException, status
from firebase_admin import auth as fb_auth
from firebase_admin import credentials

from .config import Settings, get_settings


class Role(str, Enum):
    """Papéis do sistema (§4 do briefing de segurança).

    `user` é o padrão para todo mundo. Os outros são concedidos só pelo
    console ou por operação administrativa — nunca pelo aplicativo, e nunca a
    pedido do próprio interessado.
    """

    USER = "user"
    SPECIALIST = "specialist"
    REVIEWER = "reviewer"
    ADMIN = "admin"

    @classmethod
    def parse(cls, raw: str | None) -> "Role":
        """Qualquer coisa que não seja um papel conhecido vira `user`.

        Falhar para o menor privilégio, não para o maior: um campo corrompido
        no documento não pode virar promoção.
        """
        try:
            return cls(raw)
        except ValueError:
            return cls.USER


@dataclass(frozen=True)
class Caller:
    """Quem está do outro lado, segundo o token verificado."""

    uid: str
    email: str | None
    email_verified: bool
    role: Role

    #: Quando esta sessão foi autenticada, em segundos desde a época.
    #:
    #: Vem da claim `auth_time` do ID token, que o Firebase preenche com o
    #: momento do login — **não** com o momento em que o token foi renovado.
    #: É o que permite exigir reautenticação sem inventar um mecanismo de
    #: sessão próprio. Ver `requires_recent_auth`.
    auth_time: int = 0

    def requires(self, *permitidos: Role) -> None:
        """Interrompe se o papel não estiver entre os permitidos.

        A mensagem é a mesma para "não tem permissão" e "não existe": dizer
        qual dos dois é entrega informação sobre a estrutura interna a quem
        está sondando.
        """
        if self.role not in permitidos:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Operação não disponível para esta conta.",
            )

    def requires_verified_email(self) -> None:
        """Interrompe se o e-mail não foi verificado.

        Usado nas operações que dependem de o endereço pertencer de fato a
        quem o cadastrou — recuperar a conta, receber o aviso de exclusão. Sem
        isso, alguém cadastra `vitima@exemplo.com`, e a vítima perde o
        endereço para uma conta que não é dela (MEDIUM-3 da auditoria).
        """
        if not self.email_verified:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=(
                    "Confirme seu e-mail antes de continuar. "
                    "Enviamos um link quando você criou a conta."
                ),
            )

    def requires_recent_auth(self, max_age_seconds: int = 300) -> None:
        """Interrompe se o login não é recente.

        # O problema (MEDIUM-5 da auditoria)
        Um ID token do Firebase é renovado automaticamente a cada hora, sem
        pedir senha. Quem rouba o aparelho destravado, ou um token, continua
        autenticado indefinidamente. Para ler o próprio histórico isso é
        aceitável; para **apagar a conta**, não — é a operação irreversível por
        definição.

        # Por que `auth_time` resolve sem inventar nada
        A claim `auth_time` marca quando a **senha foi apresentada**, e não
        quando o token foi renovado. Ela não se move numa renovação silenciosa.
        Então exigir `auth_time` recente é exigir que a pessoa tenha digitado a
        senha agora — que é a definição de reautenticação.

        O cliente obtém isso chamando `reauthenticateWithCredential` e pedindo
        um token novo. Nenhum mecanismo de sessão próprio, nenhuma tabela de
        desafios, nada para manter.

        # Por que 5 minutos
        Tempo de ler o aviso, digitar a senha e confirmar, com folga para uma
        rede ruim. Mais que isso e a janela deixa de significar "agora".
        """
        import time

        idade = int(time.time()) - self.auth_time
        if self.auth_time <= 0 or idade > max_age_seconds:
            # 401 e não 403: o cliente **pode** fazer algo a respeito, que é
            # reautenticar. 403 diria "desista".
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=(
                    "Confirme sua senha para continuar. "
                    "Esta operação não pode ser desfeita."
                ),
                headers={"X-Reauth-Required": "true"},
            )


_app: firebase_admin.App | None = None


def firebase_app(settings: Settings) -> firebase_admin.App:
    """Inicializa o Admin SDK uma vez por processo."""
    global _app  # noqa: PLW0603 - o SDK é um singleton por natureza
    if _app is None:
        _app = firebase_admin.initialize_app(
            credentials.Certificate(settings.service_account),
            {"storageBucket": settings.storage_bucket}
            if settings.storage_bucket
            else None,
        )
    return _app


def _extract_bearer(authorization: str | None) -> str:
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Autenticação necessária.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    partes = authorization.split(" ", 1)
    if len(partes) != 2 or partes[0].lower() != "bearer" or not partes[1].strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Autenticação inválida.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return partes[1].strip()


async def current_caller(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
) -> Caller:
    """Verifica o token e carrega o papel do chamador.

    O papel vem do documento `users/{uid}` no Firestore, **não** de uma claim
    que o cliente poderia influenciar. É uma leitura a mais por requisição, e
    o custo é aceito: é o mesmo lugar que as Security Rules consultam, então
    servidor e regras nunca discordam sobre quem é admin.
    """
    from .clients import firestore_client

    token = _extract_bearer(authorization)
    app = firebase_app(settings)

    try:
        # `check_revoked=True` custa uma ida à rede e vale: sem isso, um token
        # de sessão encerrada continuaria sendo aceito até expirar sozinho.
        decodificado = fb_auth.verify_id_token(token, app=app, check_revoked=True)
    except fb_auth.RevokedIdTokenError as erro:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sessão encerrada. Entre novamente.",
        ) from erro
    except fb_auth.ExpiredIdTokenError as erro:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sessão expirada. Entre novamente.",
        ) from erro
    except Exception as erro:  # noqa: BLE001
        # A exceção do SDK carrega detalhe de infraestrutura. O §17 proíbe
        # devolver isso ao cliente — ele recebe a frase genérica, e o motivo
        # real vai para o log do servidor.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Autenticação inválida.",
        ) from erro

    uid = decodificado["uid"]

    perfil = firestore_client(settings).collection("users").document(uid).get()
    dados = perfil.to_dict() if perfil.exists else {}

    return Caller(
        uid=uid,
        email=decodificado.get("email"),
        email_verified=bool(decodificado.get("email_verified", False)),
        role=Role.parse(dados.get("role")),
        # `auth_time` pode faltar num token forjado ou muito antigo. Zero faz
        # `requires_recent_auth` recusar — falhar fechado.
        auth_time=int(decodificado.get("auth_time", 0) or 0),
    )
