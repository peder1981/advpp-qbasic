CONST N = 4
DIM SHARED T(1 TO N)
CALL Fill
CALL SumArr(T(), S)
PRINT S
END
SUB Fill
  FOR I = 1 TO N
    T(I) = I * I
  NEXT
END SUB
SUB SumArr (A(), R)
  R = 0
  FOR J = 1 TO 4
    R = R + A(J)
  NEXT
END SUB
