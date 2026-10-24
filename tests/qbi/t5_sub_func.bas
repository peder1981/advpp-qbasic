DECLARE SUB Show (N%)
DECLARE FUNCTION Twice (X)
CONST LIMIT = 3
CALL Show(LIMIT)
Show 2
PRINT Twice(4)
END
SUB Show (N%)
  FOR I = 1 TO N%
    PRINT "s"; I;
  NEXT
  PRINT
END SUB
FUNCTION Twice (X)
  Twice = X * 2
END FUNCTION
