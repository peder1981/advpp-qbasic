# advpp-qbasic

Ambiente de compatibilidade QBasic sobre o [AdvPP](https://github.com/... ) —
runtime + transpilador `.bas` → AdvPL/TLPP, escrito em AdvPL.

## Componentes

| Arquivo | Papel |
|---|---|
| `qbasic.prg` | Runtime (API QBasic: tela ANSI, teclado, memória, som, arquivos binários) + runner que transpila e executa um `.bas` |
| `bas2prg.prg` | Transpilador `.bas` → `.prg` gerado (`<nome>_qb.prg`) |
| `cp437.prg` | Tabela CP437 → Unicode |
| `gorilla.prg` / `nibbles.prg` | Portes manuais dos jogos em AdvPL puro |
| `tests/t_*.bas` | Fixtures de teste da compatibilidade |

## Uso

```sh
# transpila e executa um .bas direto (sem modificar a fonte)
QB_FILE=gorilla.bas advplc run qbasic.prg

# só gera o .prg para depurar
QB_FILE=gorilla.bas QB_ACTION=gen advplc run qbasic.prg
```

Sem tty (pipe/smoke test): a 1a linha do stdin é o nome do `.bas` e o
restante vira o teclado do programa.

## Compatibilidade

- `ON ERROR GOTO` / `RESUME` / `RESUME NEXT` / `RESUME <label>` com número de erro real em `ERR` — implementado via Try/Catch do AdvPP (o runtime respeita a semântica da VM: Throw adiado para fora do Catch).
- PC-dispatch geral para GOTO arbitrário, ativado só nas rotinas que exigem.
- Arquivos: `OPEN` INPUT/OUTPUT/APPEND/RANDOM/BINARY, `PRINT #`, `INPUT #`, `LINE INPUT #`, `WRITE #`, `FIELD`, `GET`/`PUT` binários com `MKI$/MKL$/MKS$/MKD$`/`CVI/CVL/CVS/CVD`, `SEEK`, `LOC`, `LOF`, `EOF`, `FREEFILE`, `KILL`, `NAME`.
- Tela: grade física 80x50 de meio-blocos (▀) ANSI-256; SCREEN, LOCATE, COLOR, PRINT/TAB, PSET, LINE, CIRCLE, PAINT, GET/PUT gráficos, POINT.
- `PEEK`/`POKE`/`DEF SEG` sobre memória virtual + região de vídeo B800.
- `PLAY` (MML) via ffplay em background; `SOUND`/`BEEP`.

Aproximações documentadas: vídeo é ANSI (não VGA real), som é ffplay sine,
`TIMER` custa 1ms/leitura como num PC da época.

## Licença

Portes AdvPL/runtime/transpilador: ver headers dos arquivos.
`gorilla.bas` e `nibbles.bas` são fontes originais Microsoft/IBM mantidas
intactas para demonstração/teste da camada de compatibilidade.
