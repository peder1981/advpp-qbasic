ON ERROR GOTO h
x = 0
OPEN "nao_existe_zzz.tmp" FOR INPUT AS #1
PRINT "nao chega"
END
h:
PRINT "erro="; ERR
RESUME fim
fim:
PRINT "ok"
END
