10 REM teste de ON ERROR GOTO + RESUME / RESUME NEXT
20 ON ERROR GOTO trata
30 OPEN "nao_existe_arquivo_qwerty.dat" FOR INPUT AS #1
40 PRINT "depois do open que falhou"
50 ON ERROR GOTO 0
60 PRINT "fim"
70 END
80 trata:
90 PRINT "erro capturado, err="; ERR
100 RESUME NEXT
