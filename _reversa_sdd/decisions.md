# Detective — Regras implícitas e ADRs retroativos

## Máquinas de estado 🟢
- **gorillas**: INTRO → INPUTS → MENU(V/P) → [por rodada: CITY → TURNOS(até acerto) → DANCE] → GAME OVER → AGAIN?
- **nibbles**: INTRO → INPUTS → FIELD → [por rodada: PAUSE → LOOP(spawn/eat/move/collide) → DEATH] → GAME OVER → AGAIN?

## Regras implícitas extraídas 🟢
1. Colisão por **cor renderizada** (QBasic POINT) ≡ colisão por **material** — invariante dos 2 ports
2. Sprites nunca cruzam fronteiras de estado sem restaurar (banana transient ≠ aScr permanente)
3. Escopo `DIM SHARED` ≡ `Private` em Main (dinâmico descendente) — padrão portável p/ globais
4. Toda espera de tecla no legado assume `INKEY$` não-bloqueante → divisão: turno (ConIn) vs tempo-real (stream)

## ADRs retroativos
- **ADR-001** — Render por grade material + célula ANSI em vez de canvas: advpl não expõe pixel buffer; célula=pixel mínimo viável. Status: aceito (ambos os ports).
- **ADR-002** — Key-stream em arquivo + processo externo para INKEY$: StartJob isola memória; IPC de semáforo não carrega dado; arquivo é o único canal observável bidirecional. Status: aceito.
- **ADR-003** — Espaço físico virtual (640×350 / 80×50) desacoplado do terminal: preserva fórmulas do legado e adapta a qualquer nW×nH. Status: aceito.
- **ADR-004** — Preservar bugs do legado (dead code) como comportamento documentado, não corrigir: paridade de spec > correção. Status: aceito; exceção única: self-hit do gorilla (documentada).

## Lacunas 🔴
- Síntese sonora real (notas do PLAY): sem equivalente — só bell. Requer player externo se for requisito.
- Setas em nibbles funcionam via escape; terminais sem `read -sn1`+`/dev/tty` ficam sem P1 (fallback: remapear para outras letras).
