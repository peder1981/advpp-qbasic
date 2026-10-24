# QBasic em AdvPL: escopo e fases

Objetivo: reconstruir o QBASIC.EXE (MS-DOS 6.x, 1995) como interpretador e IDE
em AdvPL, compilado pelo AdvPP (`advplc`, Go), portavel para qualquer SO.
Abordagem: clean-room. Referencias: `QBASIC.HLP`, os `.bas` originais e o
comportamento observado no QBASIC.EXE rodando no DOSBox-X (oraculo).

## Fase 0: inventario dos programas originais

Fonte: `nibbles.bas` (721 linhas, CRLF) e `gorilla.bas` (LF).
Palavras-chave usadas (ambos): IF, END, SUB, TO, THEN, CASE, FOR, NEXT,
PRINT, LOCATE, COLOR, DECLARE, ELSE, DO, LOOP, UNTIL, SELECT, OR, TYPE,
FUNCTION, CONST, WHILE, CLS, MOD, WEND, DIM, DEF SEG, INPUT, AND, PLAY, NOT,
TIMER, GOSUB, RETURN, STEP, SHARED, POKE, RESTORE, DATA, USING, RANDOMIZE,
PEEK, READ, VIEW, SCREEN, WIDTH.
Funcoes: CHR$, INKEY$, VAL, SPACE$, INT, TIMER, UCASE$, STR$, RND, MID$,
PEEK, LEN, RIGHT$, LEFT$.

Implicacao: SUB/FUNCTION/TYPE/SELECT CASE sao necessarios ja para o Nibbles;
graficos, COLOR, PLAY e PEEK/POKE pertencem as fases de tela e som.

## Fases

| Fase | Conteudo | Estado |
|---|---|---|
| 0 | Inventario e escopo (este documento) | feito |
| 1 | Nucleo: expressoes, PRINT/INPUT, IF, FOR, WHILE, DO, GOTO/GOSUB, DIM 1D/2D, DATA/READ, funcoes de string/numericas | feito (`qbi.prg`, 4/4 testes) |
| 1b | SUB, FUNCTION (STATIC), CALL, TYPE, SELECT CASE, CONST, DECLARE, DIM SHARED, parametros de array, rotulos textuais, DEF SEG/PEEK/POKE (memoria virtual), literais &H/&O | feito (`qbi.prg`, 8/8 testes) |
| 2 | Tela 80x25 em ANSI, cores, LOCATE/COLOR, teclado (INKEY$), PEEK/POKE em B800 | feito (`qbi.prg`, 10/10 testes; tty verificado via script) |
| 3 | IDE: editor, menus, F5/F8/F6, janela Immediate, ajuda F1 | feito (`qbi.prg`, 13/13 testes) |
| 4 | Graficos (SCREEN 1/2/9/12, PSET, LINE, CIRCLE, PAINT, GET/PUT, POINT, PALETTE), som (SOUND, PLAY, BEEP), DEF FN, ON ERROR/RESUME/ERR, REDIM, CINT | feito (`qbi.prg`, 12/12 testes) |
| 5 | Verificacao contra o original (DOSBox-X) e REA (`verify_reconstruction`) | pendente |

## Fase 1: como rodar e testar

    tests/qbi/run.sh                 # roda todos os casos e compara
    QB_FILE=prog.bas advplc run qbi.prg

Limitacoes conhecidas (Fases 1 e 1b):
- AND/OR/NOT operam sobre verdadeiro/falso (-1/0), nao bit a bit.
- Numeros em notacao cientifica (1E5) nao sao lidos pelo lexer.
- DATA aceita apenas valores sem espaco nas palavras nao citadas.
- INKEY$ devolve "" (sem teclado ainda) e PEEK le memoria virtual zerada.
- DEFINT/DEFSNG/... sao ignorados: variaveis seguem em ponto flutuante.
- Elemento de array passado como argumento (a(i)) e passado por valor.

## Smoke test do nibbles.bas original

Rodando `QB_FILE=nibbles.bas advplc run qbi.prg`, o interpretador passa de
`&H0`, rotulos textuais (`GOSUB ClearKeyLocks`), `RANDOMIZE TIMER`,
`DEF SEG` e `POKE`, e para em `COLOR` (linha 90, dentro de SUB Intro).
Os proximos bloqueios sao todos da Fase 2 (tela/teclado) e 4 (grafico/som):
COLOR, SCREEN, LINE, CIRCLE, PAINT, GET/PUT, PLAY, SOUND.

## Nota de implementacao (AdvPP)

O identificador `aS` (em maiusculas ou minusculas) e tratado de forma errada
pelo AdvPP: `aS[1][2]` devolve o array inteiro. Usar `aSt` ou outro nome.

## Fase 2: tela e teclado

- Buffer 80x25 (caractere e atributo CGA). PRINT/LOCATE/CLS/COLOR escrevem nele.
- `PEEK`/`POKE` com segmento B800 leem e escrevem o buffer (posicao par = caractere, impar = atributo).
- Em terminal (detectado por `stty </dev/tty`): saida com sequencias ANSI, modo raw, `INKEY$` nao bloqueante, setas como CHR$(0)+H/P/K/M.
- Em pipe: texto puro, sem ANSI. Para testes: `QB_DUMP=1` imprime o buffer ao fim.
- `SCREEN 0` e aceito; outros modos ficam para a Fase 4.
- Teste com pseudo-terminal: `script -qfc "advplc run qbi.prg" /dev/null`.

Limitacao observada (fora do interpretador): o runtime do advplc envia consultas
de terminal (OSC 11 e CSI 6n) no inicio e consome as primeiras teclas digitadas
nos primeiros segundos. Depois disso, `INKEY$` funciona.

Estado do Nibbles original: passa do menu, desenha o nivel 1 e aguarda a tecla
de espaco. A proxima etapa e de som e graficos (Fase 4).

## Fase 4: graficos e som

- Graficos: buffer de pixels `aPix` (indice de paleta). Modos 1, 2, 9 e 12. Renderizado no terminal com meio-bloco (U+2580), so celulas alteradas; texto da Fase 2 por cima.
- PSET/PRESET/LINE (Bresenham, B e BF)/CIRCLE (parametrico, aspecto 4/3*H/W)/PAINT (preenchimento por pilha)/GET/PUT (XOR padrao, PSET, PRESET, AND, OR)/POINT/PALETTE.
- Som: PLAY (MML: notas, #/+/-, O, <, >, L, T, P, MN/ML/MS, pontos), SOUND, BEEP. Amostras U8 8 kHz gravadas em hexadecimal e convertidas com `xxd -r -p`, tocadas com `aplay` (se existir). Sem aplay, o som e silencioso.
- Teste de som: `QB_SOUNDLOG=1` imprime as amostras de cada segmento.
- Depuracao grafica: `QB_PNG=arquivo.ppm` grava o quadro no fim (converter com um script para PNG).
- Tambem nesta fase: DEF FN (funcoes de uma linha), ON ERROR GOTO / RESUME / ERR (codigos do QBasic), REDIM, CINT/CLNG/CSNG/CDBL, notacao 1E5, sufixos de tipo nos literais, ATN.

Limitacoes desta fase:
- PLAY chama aplay de forma sincrona, a cada comando (um processo por chamada).
- Texto (PRINT) em modo grafico aparece sobreposto ao grafico, sem fonte de pixels proprios.
- VIEW e WAIT sao aceitos e ignorados. Escala de aspecto do CIRCLE aproximada.
- Gorilla original: menu, introducao e inicio da partida funcionam sob terminal; a partida completa em modo grafico ainda nao foi verificada ponta a ponta. Nibbles original: menu e nivel 1 funcionam.
- Fase 3 (IDE: editor, menus, F5/F8, Immediate) segue pendente.

## Fase 3: IDE

Abrir: `advplc run qbi.prg` (sem arquivo) abre a tela vazia. `QB_IDE=1 QB_FILE=x.bas` abre o arquivo para editar. Com `QB_FILE` e sem `QB_IDE`, o arquivo roda direto.

- Layout 80x25: menu (0), titulo do arquivo (1), editor (2-15), titulo Immediate (16), Immediate (17-23), barra de status (24) com linha:coluna.
- Editor: digitacao, Enter, Backspace, Del, setas, Home, End, PgUp, PgDn, Tab; rolagem.
- Menus: ESC ou F10 abre a barra; setas navegam; Enter executa. Itens: File (New, Open, Save, Save As, Exit), Edit (sem efeito nesta versao), View (SUBs, Immediate), Search (Find, Find Next), Run (Start, Continue), Debug (Step), Options, Help.
- Teclas: F1 ajuda, F2 proximo SUB/FUNCTION, F5 executar (tela do usuario; volta ao editor com uma tecla), F6 alterna editor/Immediate, F8 passo a passo.
- Immediate: executa uma linha no contexto do programa (variaveis preservadas) e mostra a saida na janela.
- Salvamento em hexadecimal via xxd, preservando bytes do arquivo (CRLF).

Teste: `tests/qbi/run.sh` (casos `*.ide` iniciam a IDE sem arquivo; teclas em `.stdin`, tela em `QB_DUMP`).

Recursos da IDE nesta versao (apos a revisao final):
- Edit: Cut, Copy, Paste e Clear sobre a linha atual (area de transferencia em memoria; selecao por linha, nao por caracteres).
- Breakpoints com F9 (marca e desmarca a linha). F5 com breakpoints executa passo a passo ate a linha marcada; F5 de novo continua. A saida vai para a janela Immediate nesse modo.
- Ajuda contextual com F1 sobre a palavra sob o cursor (tabela de comandos implementados).
- Menus: ESC ou F10 abre a barra; letra inicial (Alt+letra enviado como ESC+letra) escolhe o menu.
- Options > Tab width (4/8).
- INPUT durante o passo a passo ou o Immediate le a resposta pelo teclado da IDE.

Limitacoes restantes da IDE:
- Selecao de texto por caracteres (Shift+setas) nao implementada; Cut/Copy trabalham por linha.
- Breakpoints so funcionam no nivel do programa principal e passo a passo (no F5 normal nao ha parada).
- Ajuda F1 e um resumo dos comandos, nao o QBASIC.HLP.
- Disposicao da tela aproximada, nao identica ao MS-DOS QBasic.
- Ociosidade no terminal: a IDE dorme 30 ms por ciclo sem tecla (um processo sleep por ciclo).

## Validacao contra o QBASIC original

Oraculo: `tests/qbi/oracle/compare.sh caso.bas` roda o caso no QBASIC.EXE original (DOSBox-X) e compara a tela final de texto (caracteres) com o interpretador. Requer `QB_EXE` apontando para QBASIC.EXE.

Resultado (casos de texto t1..t9): todos identicos ao original.
Diferencas corrigidas pelo oraculo:
- Campos de TYPE com STRING * n agora tem tamanho fixo (preenchimento com espacos).
- PRINT nao imprime quando a expressao falha.
- O original nao limpa a tela ao iniciar; o oraculo insere CLS antes da primeira instrucao executavel.

Pendencias conhecidas do interpretador (encontradas pelo original, nao corrigidas):
- Nomes de campo que sao palavras reservadas (ex.: NAME) e STRING sem tamanho dentro de TYPE sao aceitos; o QBASIC rejeita.
- Atributos de cor nao sao comparados pelo oraculo (somente caracteres).
- Graficos e som nao tem oraculo automatico (validacao manual).

## Fechamento das pendencias (ultima rodada)

- Palavras reservadas como campo de TYPE e STRING sem tamanho sao rejeitados (erro na linha do campo), como no QBASIC.
- Breakpoints: a SUB agora e chamada sem recursao (CALL empilha o retorno, END SUB desfaz). Breakpoints e passo a passo entram dentro das SUBs. F5 sem breakpoints roda o programa inteiro na tela do usuario (sem paradas, por design).
- Edit: selecao por caracteres com Shift+setas; Cut, Copy e Paste atuam na selecao (sem selecao, na linha atual). Selecao aparece em video reverso.
- Ociosidade: a IDE usa leitura com espera de 0,1 s (stty min 0 time 1), sem processo por ciclo.
- E/S de arquivo: OPEN ... FOR OUTPUT|INPUT AS #n, PRINT #n, INPUT #n, LINE INPUT #n, EOF(n), CLOSE. Numeros em VAL, INPUT e READ seguem a regra do QBASIC (le o prefixo numerico).
- Oraculo de graficos: programas que gravam POINT() em GFXRES.TXT (t17, t18). Original e interpretador produzem resultados identicos (PSET, LINE, LINE BF, CIRCLE horizontal e vertical, PAINT, GET/PUT XOR, POINT).
- Oraculo de texto: t1..t9 identicos ao original.

Pendencias que continuam (nao ha como fechar automaticamente):
- Som: nao ha oraculo. O DOSBox-X aqui nao captura o audio do QBASIC original; PLAY e SOUND ficam com validacao manual.
- Ajuda F1: resumo dos comandos implementados, nao o QBASIC.HLP (formato de ajuda do Windows, nao lido aqui).
- Atributos de cor na comparacao de texto: o oraculo compara caracteres (o ATR.TXT ja e gerado pelo original, mas o interpretador ainda nao grava atributos no mesmo formato).
- Breakpoints so funcionam em execucao passo a passo ou com F5 quando ha marcas (F5 sem marcas nao para, por definicao).

## Rodada de divergencias (oraculo contra o QBASIC original)

Casos em tests/qbi/oracle/cases (c_*) e casos de texto t1..t9: 29 de 29 identicos ao original na regressao final (tela de caracteres e atributos; INPUT/INKEY$ por teclado injetado com xdotool).

Corrigido nesta rodada, cada item confirmado pela saida do original:
- Formato numerico (precisao simples 7 digitos, dupla 16, ".5", notacao E+nn, inteiros sem casas), tipos I/L/S/D pelo literal e pelo DEFINT/DEFSNG/...
- Atribuicao converte pelo tipo da variavel (DEFINT arredonda); overflow de inteiro/longo emite "Overflow".
- AND/OR/XOR/NOT bit a bit (16 bits, 32 se fora de faixa).
- TAB, SPC, INSTR, SWAP, LBOUND, UBOUND, HEX$, OCT$, MID$ como instrucao, PRINT USING (campos #, ., +, $$, **, virgula, ^^^^, sufixo -).
- RND com o gerador do QBASIC (semente 327680; x = x*1140671485+12820163 mod 2^24).
- ERR zera com RESUME.
- Tela: area de texto de 23 linhas (linha 24 em branco) com rolagem como no original; CHR$ 128-255 pelo mapa CP437; caracteres de controle ocupam celula.
- E/S de arquivo, VAL e INPUT numericos como no QBASIC, palavras reservadas e STRING sem tamanho rejeitados em TYPE.

Divergencias que continuam abertas (sem oraculo automatico ou fora de escopo):
- Som (PLAY, SOUND, BEEP): sem comparacao automatica; o DOSBox-X desta maquina nao captura o audio do original.
- Dialogos de erro: o QBASIC mostra caixa de dialogo com a mensagem; o interpretador mostra "? mensagem na linha N". A mensagem e a mesma; a apresentacao nao.
- Ajuda F1: resumo dos comandos implementados, nao o QBASIC.HLP.
- Precisao: literais e variaveis tratados por tipo, mas a aritmetica de precisao simples e arredondada por digitos decimais, nao pelo float de 32 bits (diferencas improvaveis, nao testadas em casos extremos).
- Strings com caracteres CP437 acima de 127: LEN conta caracteres, mas MID$/LEFT$/RIGHT$ operam sobre bytes UTF-8.
- Graficos: validados para PSET, LINE (linha e BF), CIRCLE, PAINT, GET/PUT (XOR) e POINT. PUT com AND/OR/PSET/PRESET, PALETTE, CIRCLE com arcos e os modos 1, 2 e 12 nao foram comparados com o original.
- IDE: disposicao aproximada; Options e menus com teclas aproximadas.

## Pendencias finais (ultima rodada)

| Item | Estado |
|---|---|
| Som (PLAY, SOUND, BEEP) | Oraculo de som implementado: captura do original com DX-CAPTURE /A (DOSBox-X), deteccao de notas por FFT (tests/qbi/oracle/compare_sound.sh). Oitava do PLAY corrigida (O2 = C4, como no original). BEEP = 904 Hz. Confere com o original em tom, duracao aproximada (tolerancia de 25% na duracao, pela janela de analise). |
| Dialogos de erro | Caixa de mensagem no estilo do QBASIC (bordas, texto centralizado, "< OK >"), espera Enter/Esc em terminal. A mensagem e identica; o fundo da IDE do original nao e reproduzido. |
| Ajuda F1 (QBASIC.HLP) | Concluido por integracao: `tests/qbi/tools/hlp_extract.py` descomprime o formato MS Advisor (LN) e o IDE carrega os topicos via `QB_HLP=caminho/QBASIC.HLP` (F1 abre o topico; setas/PgUp/PgDn/Home/End rolam; ESC fecha). Sem `QB_HLP`, usa o resumo interno. O texto do HLP nao e versionado. |
| Precisao de ponto flutuante | Corrigido: precisao simples arredondada para 24 bits binarios (float32), como o SINGLE do QBASIC. Oraculo c_f32 identico (ex.: 1/3*3 = 1). |
| CP437 em strings | Corrigido: CHR$/ASC/LEN/LEFT$/RIGHT$/MID$/INSTR/atribuicao de MID$ contam caracteres UTF-8. Oraculo c_strutf identico. |
| Graficos | Verificados com oraculo (POINT no original): PSET, LINE (linha e BF), CIRCLE (horizontal, vertical e arcos), PAINT, GET/PUT com XOR, AND, OR, PSET e PRESET, PALETTE, e modos 1, 2, 9 e 12. |
| IDE | Layout aproximado (menus, editor, Immediate, barra de status). Teclas de menu diferem em detalhes. Nao ha oraculo de tela da IDE. |

Regressao final: 36 casos identicos ao original (texto, atributos, numericos, graficos, teclado, som).
