PRINT INSTR("hello world", "o"); INSTR(6, "hello world", "o"); INSTR("abc", "z")
PRINT LCASE$("ABC"); "|"; LTRIM$("  x"); "|"; RTRIM$("y   "); "|"
PRINT STRING$(3, "x"); STRING$(2, 65); SPACE$(2); "|"
PRINT HEX$(255); " "; OCT$(8); " "; ABS(-3.5); " "; SGN(-2); " "; FIX(-2.7); " "; INT(-2.7)
PRINT CINT(2.5); CINT(3.5); CINT(-2.5); SQR(16); LEN("")
PRINT MID$("abcdef", 3); MID$("abcdef", 2, 2); RIGHT$("abcdef", 2); LEFT$("abc", 10)
