TYPE Pt
  X AS INTEGER
  Nm AS STRING * 10
END TYPE
DIM P(1 TO 3) AS Pt
P(2).X = 7
P(2).Nm = "ab"
PRINT P(2).X; P(2).Nm; P(1).X
DIM SHARED G%(0 TO 2)
G%(0) = 5
PRINT G%(0) + G%(2)
