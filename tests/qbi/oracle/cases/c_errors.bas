ON ERROR GOTO handler
x = 1 / 0
PRINT "depois"; ERR
END
handler:
PRINT "erro"; ERR
RESUME NEXT
