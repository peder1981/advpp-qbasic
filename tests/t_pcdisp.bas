' PC-dispatch: GOTO para frente cruzando fronteira de bloco
x = 0
FOR i = 1 TO 3
    IF i = 2 THEN GOTO pulou
    PRINT "i="; i
NEXT i
pulou:
PRINT "depois"
' GOTO para tras cruzando bloco
n = 0
volta:
n = n + 1
IF n < 3 THEN
    FOR j = 1 TO 2
        IF j = 2 THEN GOTO volta
    NEXT j
END IF
PRINT "fim n="; n
END
