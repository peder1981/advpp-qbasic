FOR i = 1 TO 10
  IF i = 4 THEN EXIT FOR
  PRINT i;
NEXT i
PRINT
n = 0
DO WHILE n < 10
  n = n + 3
LOOP
PRINT n
GOSUB sub1
PRINT "volta"
x = 5
SELECT CASE x
  CASE 1 TO 3: PRINT "baixo"
  CASE 4, 5, 6: PRINT "medio"
  CASE ELSE: PRINT "alto"
END SELECT
END
sub1:
PRINT "sub"
RETURN
