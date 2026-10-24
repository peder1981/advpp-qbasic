' Sequencia Eb Ab Db Gb Bb Eb em loop, oitava 4, seminimas a 120 BPM.
' Tecla qualquer para parar.
CLS
PRINT "Eb Ab Db Gb Bb Eb em loop. Pressione uma tecla para parar."
DO
    PLAY "T120 O4 L4 E- A- D- G- B- E-"
LOOP UNTIL INKEY$ <> ""
END
