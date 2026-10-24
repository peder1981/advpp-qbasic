10 REM teste de PRINT#/INPUT#/EOF/FREEFILE
20 f$ = "t_fileio.tmp"
30 n% = FREEFILE
40 OPEN f$ FOR OUTPUT AS #n%
50 PRINT #n%, "alfa", 42, 3.5
60 PRINT #n%, "segunda linha"
70 CLOSE #n%
80 OPEN f$ FOR INPUT AS #2
90 INPUT #2, a$, b%, c
100 PRINT "lidos:"; a$; b%; c
110 LINE INPUT #2, l$
120 PRINT "linha:"; l$
130 PRINT "eof:"; EOF(2)
140 CLOSE
150 KILL f$
