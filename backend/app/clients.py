"""Clientes do Google Cloud, criados uma vez por processo.

POR QUE ESTE ARQUIVO EXISTE
---------------------------
`current_caller` construía um `firestore.Client` a cada requisição — e com ele
uma credencial nova, derivada da service account por `from_service_account_info`.

Isso acontece em **toda** chamada autenticada da API. Construir o cliente abre
um canal gRPC e a credencial faz trabalho de criptografia assimétrica; nenhum
dos dois é barato, e nenhum dos dois muda entre requisições.

Pior que o custo: cada cliente abandonado deixa o canal gRPC para o coletor de
lixo fechar. Sob carga, isso é vazamento de descritor de arquivo — o tipo de
problema que não aparece em teste e aparece em produção às três da manhã.

SOBRE SEGURANÇA
---------------
Compartilhar o cliente **não** compartilha autorização. O cliente usa a service
account, que ignora as Security Rules — era assim antes e é assim agora. Quem
decide o que o chamador alcança é o código que monta o caminho a partir do uid
verificado, e isso não mudou.
"""

from __future__ import annotations

from functools import lru_cache

from .config import Settings


@lru_cache(maxsize=1)
def _credentials_cached(chave: str):
    """Credencial do Google, derivada da service account.

    A chave de cache é o `client_email`, não o dicionário — dicionário não é
    hasheável, e o e-mail identifica a credencial sem carregar a chave privada
    para dentro da tabela de cache.
    """
    from google.oauth2 import service_account

    from .config import get_settings

    del chave  # só serve como chave de cache
    return service_account.Credentials.from_service_account_info(
        get_settings().service_account
    )


def google_credentials(settings: Settings):
    """Credencial para os clientes do Google Cloud.

    Separada do `firebase_admin` porque `google-cloud-firestore` espera o tipo
    da biblioteca de autenticação do Google, não o do Firebase.
    """
    return _credentials_cached(settings.service_account["client_email"])


@lru_cache(maxsize=1)
def _firestore_cached(project_id: str, client_email: str):
    from google.cloud import firestore

    from .config import get_settings

    del client_email  # só serve como chave de cache
    settings = get_settings()
    return firestore.Client(
        project=project_id,
        credentials=google_credentials(settings),
    )


def firestore_client(settings: Settings):
    """O cliente Firestore do processo."""
    return _firestore_cached(
        settings.project_id, settings.service_account["client_email"]
    )


def storage_bucket(settings: Settings):
    """O bucket do Storage, pelo Admin SDK.

    Pelo `firebase_admin` e não pelo `google-cloud-storage` direto: o Admin SDK
    já resolve o nome do bucket padrão do projeto, e é ele que o resto do
    serviço inicializa.
    """
    from firebase_admin import storage as fb_storage

    from .auth import firebase_app

    app = firebase_app(settings)
    if settings.storage_bucket:
        return fb_storage.bucket(settings.storage_bucket, app=app)
    return fb_storage.bucket(app=app)


def reset_clients() -> None:
    """Descarta os clientes em cache. Para uso em teste.

    Sem isto, um teste que troca a configuração continuaria falando com o
    cliente da configuração anterior — e passaria, ou falharia, pelo motivo
    errado.
    """
    _credentials_cached.cache_clear()
    _firestore_cached.cache_clear()
