"""App Check: o pedido veio do aplicativo de verdade?

O ID token diz **quem** está chamando. O App Check diz **de onde**: que o pedido
saiu de uma instalação legítima do aplicativo, e não de um script com a
configuração pública do projeto. São perguntas diferentes, e a segunda é a que
protege o custo da inferência contra quem cria contas em série.

DESLIGADO POR PADRÃO, E POR QUÊ
-------------------------------
Exigir o App Check antes de o provedor estar registrado no console barraria o
próprio aplicativo. A ordem que funciona é:

1. registrar o provedor (Play Integrity, com o SHA-256 da chave de release);
2. publicar uma versão do aplicativo que envia o token;
3. só então definir `REQUIRE_APP_CHECK=1` aqui e ligar a exigência no console.

Enquanto a variável não estiver definida, este módulo não recusa ninguém — e não
finge que conferiu.
"""

from __future__ import annotations

from fastapi import Depends, Header, HTTPException, status
from firebase_admin import app_check as fb_app_check

from .auth import firebase_app
from .config import Settings, get_settings


async def verified_app(
    x_firebase_appcheck: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
) -> None:
    """Interrompe se a exigência está ligada e o token falta ou não confere."""
    if not settings.require_app_check:
        return

    # A mesma resposta para "sem token" e "token inválido": dizer qual dos dois
    # ajudaria quem está sondando, e não ajuda um aplicativo legítimo.
    recusa = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Aplicativo não reconhecido. Atualize o aplicativo e tente de novo.",
    )
    if not x_firebase_appcheck:
        raise recusa

    try:
        fb_app_check.verify_token(x_firebase_appcheck, app=firebase_app(settings))
    except Exception as erro:  # noqa: BLE001 - o detalhe do SDK não vai ao cliente
        raise recusa from erro
