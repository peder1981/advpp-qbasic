' Solo original em re maior (composicao propria), em loop.
' Tecla qualquer para parar.
CLS
PRINT "Solo original em loop. Pressione uma tecla para parar."
DO
    PLAY "T120 O4 L8 F# E D E F# A L4 G L8 F# E D E L2 D P8 L8 A B O5 C# D O4 B A F# E D L2 F# O5 D C# L4 D L2 P4"
LOOP UNTIL INKEY$ <> ""
END
