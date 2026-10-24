S$ = CHR$(219) + "ABC"
PRINT LEN(S$); LEFT$(S$, 1); MID$(S$, 2, 2); RIGHT$(S$, 2)
PRINT INSTR(S$, "B"); ASC(LEFT$(S$, 1))
T$ = "hello"
MID$(T$, 2, 1) = CHR$(176)
PRINT T$; LEN(T$)
