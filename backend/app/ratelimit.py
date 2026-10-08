"""Limite de chamadas por janela de tempo.

O QUE ISTO PROTEGE
------------------
A cota diária (`quota.py`) limita quantas **análises** uma conta pede. Ela não
dizia nada sobre os outros endpoints: exportar os próprios dados custa leituras
no Firestore a cada chamada, e toda chamada autenticada custa uma verificação
de token na rede. Sem um teto, um laço de pedidos gasta a cota do projeto.

São duas janelas, com propósitos diferentes:

- **por endereço**, antes da autenticação: barra a enxurrada de tokens inválidos
  antes de cada um custar uma verificação;
- **por conta**, depois: barra uma conta legítima em laço.

O QUE ISTO NÃO É
----------------
O contador vive na memória **deste processo**. Com mais de um processo, cada um
conta sozinho, e o limite efetivo é o configurado vezes o número de processos.
Para o porte atual — um processo num serviço gratuito — é o suficiente, e não
exige infraestrutura nova. Quando houver mais de um, o contador vai para um
armazenamento compartilhado, e esta interface não muda.

Atrás de um proxy que não repassa o endereço de origem, a janela por endereço
enxerga todos os clientes como um só. Por isso o limite dela é folgado: ela
existe para conter abuso grosseiro, não para ser a única barreira.
"""

from __future__ import annotations

import threading
import time
from collections import deque
from collections.abc import Callable

from fastapi import Depends, HTTPException, Request, status

from .auth import Caller, current_caller


class SlidingWindow:
    """No máximo `limit` chamadas por chave a cada `window_seconds`."""

    def __init__(
        self, limit: int, window_seconds: float, *, max_keys: int = 10_000
    ) -> None:
        self.limit = limit
        self.window_seconds = window_seconds
        self._max_keys = max_keys
        self._hits: dict[str, deque[float]] = {}
        self._lock = threading.Lock()

    def hit(self, key: str, now: float | None = None) -> float | None:
        """Registra uma chamada.

        Devolve `None` se ela cabe na janela, ou quantos segundos faltam para
        caber. Uma chamada recusada **não** é registrada: insistir não empurra
        a liberação para a frente.
        """
        agora = time.monotonic() if now is None else now
        corte = agora - self.window_seconds

        with self._lock:
            fila = self._hits.get(key)
            if fila is None:
                # O dicionário não pode crescer sem teto: cada endereço novo
                # seria uma entrada eterna. Ao encher, as chaves sem chamada
                # recente saem; se ainda assim não couber, sai a mais antiga.
                if len(self._hits) >= self._max_keys:
                    self._descartar_ociosas(corte)
                fila = self._hits[key] = deque()

            while fila and fila[0] <= corte:
                fila.popleft()

            if len(fila) >= self.limit:
                return max(fila[0] + self.window_seconds - agora, 0.0)

            fila.append(agora)
            return None

    def clear(self) -> None:
        with self._lock:
            self._hits.clear()

    def _descartar_ociosas(self, corte: float) -> None:
        ociosas = [k for k, f in self._hits.items() if not f or f[-1] <= corte]
        for chave in ociosas:
            del self._hits[chave]
        if len(self._hits) >= self._max_keys:
            del self._hits[next(iter(self._hits))]


_JANELAS: list[SlidingWindow] = []


def _janela(limit: int, window_seconds: float) -> SlidingWindow:
    janela = SlidingWindow(limit, window_seconds)
    _JANELAS.append(janela)
    return janela


def _recusar_se(espera: float | None) -> None:
    if espera is None:
        return
    raise HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail="Muitas solicitações em pouco tempo. Aguarde e tente de novo.",
        # Arredondado para cima: um cliente que respeita o cabeçalho e volta um
        # instante antes da hora seria recusado de novo.
        headers={"Retry-After": str(int(espera) + 1)},
    )


_POR_ENDERECO = _janela(120, 60)


def throttle_ip(request: Request) -> None:
    """Janela por endereço. Roda antes da autenticação."""
    endereco = request.client.host if request.client else "desconhecido"
    _recusar_se(_POR_ENDERECO.hit(endereco))


def per_user(limit: int, window_seconds: float) -> Callable[..., None]:
    """Cria uma janela por conta, para usar como dependência de um endpoint."""
    janela = _janela(limit, window_seconds)

    def dependencia(caller: Caller = Depends(current_caller)) -> None:
        _recusar_se(janela.hit(caller.uid))

    return dependencia


def reset() -> None:
    """Zera todas as janelas. Para os testes."""
    for janela in _JANELAS:
        janela.clear()
