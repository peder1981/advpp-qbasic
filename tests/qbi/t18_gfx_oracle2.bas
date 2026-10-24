' Oraculo grafico 2: eixo vertical do circulo (aspecto do modo) e preenchimento.
' Grava em GFXRES.TXT para comparar com o QBASIC original.
SCREEN 9
CIRCLE (320, 175), 60, 10
PAINT (320, 175), 12, 10
OPEN "GFXRES.TXT" FOR OUTPUT AS #1
FOR y = 100 TO 250
  IF POINT(320, y) = 10 THEN PRINT #1, "up"; y
NEXT y
FOR x = 240 TO 400
  IF POINT(x, 175) = 10 THEN PRINT #1, "lf"; x
NEXT x
PRINT #1, "in"; POINT(320, 175); POINT(320, 110); POINT(320, 240)
CLOSE #1
SCREEN 0
