' FIELD/LSET/GET/PUT RANDOM + MK$/CV$ + LOF/SEEK
OPEN "t_binfile.tmp" FOR RANDOM LEN = 12 AS #1
FIELD #1, 2 AS ai$, 10 AS an$
LSET ai$ = MKI$(-1)
LSET an$ = "ABCDEFGHIJ"
PUT #1, 1
LSET ai$ = MKI$(300)
RSET an$ = "xy"
PUT #1, 2
PRINT "lof="; LOF(1)
GET #1, 1
PRINT "i1="; CVI(ai$)
PRINT "s1=["; an$; "]"
GET #1, 2
PRINT "i2="; CVI(ai$)
PRINT "s2=["; an$; "]"
SEEK #1, 1
GET #1
PRINT "loc="; LOC(1); " i="; CVI(ai$)
CLOSE #1
KILL "t_binfile.tmp"
PRINT "fim"
END
