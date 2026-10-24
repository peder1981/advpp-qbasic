' Overflow tratado: o original e o interpretador devem seguir a partir do ON ERROR
ON ERROR GOTO ErrH
DEFINT A-Z
a = 200
PRINT a * a
PRINT 32767 + 1
PRINT -32768 - 1
PRINT 2147483647 + 1
PRINT "fim"
END
ErrH:
PRINT "erro"; ERR
RESUME NEXT
