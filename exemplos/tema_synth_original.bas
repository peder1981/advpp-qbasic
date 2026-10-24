' Tema original em estilo synth-pop dos anos 80 (composicao propria), em loop.
' Baixo em colcheias, depois melodia. Tecla qualquer para parar.
CLS
PRINT "Tema synth em loop. Pressione uma tecla para parar."
DO
    PLAY "T140 O2 L8 A A A A A A A A F F F F F F F F C C C C C C C C G G G G G G G G"
    PLAY "O4 L8 A C E A5 E C L4 D5 L8 C5 D5 E5 D5 C5 B4 A4 L2 G4 L4 P4"
LOOP UNTIL INKEY$ <> ""
END
