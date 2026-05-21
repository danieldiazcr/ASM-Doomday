
.model small
.stack 100h

.data
    ; --- Mensajes ---
    debugMsg    db 13, 10, 'Debug: ', '$'
    promptYear  db 'Ingrese el Ano (YYYY): $'
    promptMonth db 13, 10, 'Ingrese el Mes (1-12 o ''n'' para todo el ano): $'
    invalidYear db 13, 10, 'Ano invalido. Intente de nuevo.$'
    invalidMonth db 13, 10, 'Mes invalido. Intente de nuevo.$'
    newLine     db 13, 10, '$'
    space       db ' $'
    dayHeader   db 'Do Lu Ma Mi Ju Vi Sa', 13, 10, '$' ;
    negativeYear db ' A.C. $'
    isGregorianCalendarActive db 1 ; 1 si el año/mes actual usa el calendario Gregoriano, 0 si Juliano
    
    ; --- Nombres de Meses ---
    monthNames  dw offset month1, offset month2, offset month3, offset month4
                dw offset month5, offset month6, offset month7, offset month8
                dw offset month9, offset month10, offset month11, offset month12
    month1      db 'Enero$'
    month2      db 'Febrero$'
    month3      db 'Marzo$'
    month4      db 'Abril$'
    month5      db 'Mayo$'
    month6      db 'Junio$'
    month7      db 'Julio$'
    month8      db 'Agosto$'
    month9      db 'Septiembre$'
    month10     db 'Octubre$'
    month11     db 'Noviembre$'
    month12     db 'Diciembre$'

    ; --- Variables ---
    inputYear   dw ?          ; Año ingresado por el usuario
    inputMonth  dw ?          ; Mes ingresado por el usuario
    isLeap      db 0          ; Flag: 1 si es bisiesto, 0 si no
    numDays     dw ?          ; Número de días en el mes
    firstDayOfWeek dw ?       ; Día de la semana del primer día (0=Do, 1=Lu, ..., 6=Sa)
    isNegativeFlag db 0       ; Flag para números negativos (0=positivo, 1=negativo)
    printFullYearFlag db 0    ; 0 = imprimir un solo mes, 1 = imprimir año completo
    currentMonthInLoop dw ?   ; Para el bucle de impresión de año completo

    ; --- Tabla para Sakamoto ---
    sakamotoTable db 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4

    ; --- Tabla de días por mes (no bisiesto) ---
    daysInMonth dw 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31

    ; --- Buffer para entrada de números ---
    buffer      db 8          ; Max chars + CR + LF
    actualLen   db ?
    inputStr    db 8 dup(?)

.code
; ==================================================================
; Procedimiento Principal
; ==================================================================
main proc
    mov ax, @data       ; Inicializar DS
    mov ds, ax

    call GetUserInput   ; Solicitar y validar año y mes (o 'n')

    ; Verificar si se debe imprimir el año completo
    cmp byte ptr [printFullYearFlag], 1
    jne printSingleMonth_M

    ; --- Bucle para imprimir el año completo ---
    mov word ptr [currentMonthInLoop], 1 ; Empezar con Enero

printYearLoop_M:
    mov ax, [currentMonthInLoop]
    mov [inputMonth], ax    ; Establecer el mes actual para los cálculos

    call CheckLeapYear      ; Esto se podría optimizar para llamarlo una vez por año
                            ; si CheckLeapYear solo depende de inputYear y no de inputMonth
                            ; (Tu CheckLeapYear actual SÍ usa inputMonth para 1582)
    call GetDaysInMonth
    call CalculateDayOfWeek
    call PrintCalendar

    ; Opcional: Imprimir una línea extra o dos para separar los meses
    lea dx, newLine
    call PrintString
    ; call PrintString ; (si quieres más espacio)

    inc word ptr [currentMonthInLoop]
    cmp word ptr [currentMonthInLoop], 13 ; ¿Hemos impreso los 12 meses?
    jne printYearLoop_M     ; Si no, continuar con el siguiente mes
    jmp endMain_M           ; Año completo impreso, terminar

printSingleMonth_M:
    ; --- Imprimir un solo mes (flujo original) ---
    call CheckLeapYear
    call GetDaysInMonth
    call CalculateDayOfWeek
    call PrintCalendar

endMain_M:
    ; Terminar el programa
    mov ah, 4Ch
    int 21h
main endp

; ==================================================================
; Solicita y valida año y mes del usuario
; ==================================================================
GetUserInput proc
    ; --- Solicitar Año ---
getYearLoop:
    lea dx, promptYear
    call PrintString
    call ReadNumber     ; Lee número, resultado en AX, CF=1 si error
    call PrintNumber ; Imprime el año ingresado (para depuración)
    jc invalidYearMsg   ; Si hubo error de conversión
    push ax             ; Guardar AX (año ingresado)
    mov al, [isNegativeFlag]
    cmp al, 1
    pop ax
    jne checkYearPosRange
    cmp ax, 5777        ; Validar rango (ej. > 5777)
    jg invalidYearMsg
checkYearPosRange:
    cmp ax, 7777        ; Validar rango (ej. < 7777)
    jg invalidYearMsg
    cmp ax, 0
    je invalidYearMsg
    mov inputYear, ax   ; Guardar año válido
    jmp getMonthLoop    ; Ir a solicitar mes

invalidYearMsg:
    lea dx, invalidYear
    call PrintString
    jmp getYearLoop

    ; --- Solicitar Mes ---
getMonthLoop:
    lea dx, promptMonth
    call PrintString
    ; ReadNumber limpiará isNegativeFlag, lo cual está bien aquí.
    call ReadNumber     ; Lee número, resultado en AX, CF=1 si error

    ; Verificar si el usuario ingresó 'n' o 'N' DESPUÉS del fallo de ReadNumber
    jc checkN_after_RN_fail ; Si ReadNumber falló (CF=1)

    ; ReadNumber tuvo éxito (CF=0), AX tiene el número de mes
    cmp ax, 1           ; Validar mes >= 1
    jl invalidMonthMsg_GUI
    cmp ax, 12          ; Validar mes <= 12
    jg invalidMonthMsg_GUI
    mov inputMonth, ax  ; Guardar mes válido
    mov byte ptr [printFullYearFlag], 0 ; Asegurar que no es año completo
    ret

checkN_after_RN_fail:
    ; ReadNumber falló (CF=1). AX probablemente es 0.
    ; Vamos a ver qué hay en el buffer que ReadNumber intentó leer.
    ; buffer[0] = max len, buffer[1] = actual len, buffer[2] = primer char.
    mov bl, [buffer+1]  ; BL = longitud real de la cadena leída por ReadNumber
    cmp bl, 1           ; ¿La longitud es 1?
    jne invalidMonthMsg_GUI_actual_fail ; Si no es 1, fue un error genuino, no 'n'

    mov al, [buffer+2]  ; AL = primer y único carácter ingresado
    cmp al, 'n'
    je setPrintFullYear_GUI
    cmp al, 'N'
    je setPrintFullYear_GUI

    ; Si no es 'n' o 'N', pero ReadNumber falló, es un error de mes inválido.
invalidMonthMsg_GUI_actual_fail:
    lea dx, invalidMonth
    call PrintString
    jmp getMonthLoop

setPrintFullYear_GUI:
    mov byte ptr [printFullYearFlag], 1
    ; Limpiar el carry flag que ReadNumber pudo haber dejado, ya que 'n' es válido aquí
    clc
    ret                 ; Salir, indicando que se imprimirá el año completo

invalidMonthMsg_GUI:    ; Esta etiqueta es para cuando el número está fuera de rango 1-12
    lea dx, invalidMonth
    call PrintString
    jmp getMonthLoop
GetUserInput endp

; ==================================================================
; Verifica si el año en inputYear es bisiesto
; Pone 1 en isLeap si es bisiesto, 0 si no.
; ==================================================================
CheckLeapYear proc

    mov al, [isNegativeFlag]
    cmp al, 1
    mov ax, inputYear
    je checkIfJulianNegative     ; Si es negativo, es juliano
    cmp ax, 1582
    jle checkIfJulian     ; Si es menor o igual a 1582, es juliano
    jmp checkIfGregorian ; Si es mayor a 1582, es gregoriano
checkIfJulianNegative:
    mov [isGregorianCalendarActive], 0 ; Marcar como calendario Juliano
    sub ax, 1
    jmp applyJulianRule
checkIfJulian:
    cmp ax, 1582
    je checkMonth  ; Si es menor o igual a 1582, es juliano
    mov [isGregorianCalendarActive], 0 ; Marcar como calendario Juliano
    jmp applyJulianRule
checkMonth:
    mov cx, inputMonth
    cmp cx, 10
    jg setGregorian ; Si el mes es mayor a 10, es Gregoriano
    mov [isGregorianCalendarActive], 0 ; Marcar como calendario Juliano
    jmp applyJulianRule
    
setGregorian:
    mov [isGregorianCalendarActive], 1 ; Marcar como calendario Gregoriano
    jmp applyJulianRule

applyJulianRule:
    mov dx, 0
    mov bx, 4
    div bx              ; AX = year / 4, DX = year % 4
    cmp dx, 0
    je setLeap  ; Si divisible por 4, verificar si es Gregoriano
    jne notLeap ; Si no divisible por 4, no es bisiesto
checkIfGregorian:
    mov [isGregorianCalendarActive], 1 ; Marcar como calendario Gregoriano
    mov dx, 0
    mov bx, 400
    div bx              ; AX = year / 400, DX = year % 400
    cmp dx, 0
    je setLeap          ; Si divisible por 400, es bisiesto

    mov ax, inputYear
    mov dx, 0
    mov bx, 100
    div bx              ; AX = year / 100, DX = year % 100
    cmp dx, 0
    je notLeap          ; Si divisible por 100 pero no por 400, no es bisiesto

    mov ax, inputYear
    mov dx, 0
    mov bx, 4
    div bx              ; AX = year / 4, DX = year % 4
    cmp dx, 0
    je setLeap          ; Si divisible por 4 pero no por 100, es bisiesto

notLeap:
    mov isLeap, 0
    ret

setLeap:
    mov isLeap, 1
    ret
CheckLeapYear endp

; ==================================================================
; Determina el número de días en inputMonth
; Guarda el resultado en numDays
; ==================================================================
GetDaysInMonth proc
    mov bx, inputMonth
    dec bx              ; Ajustar mes a índice 0-11
    shl bx, 1           ; Multiplicar por 2 (tamaño de word)
    mov ax, daysInMonth[bx] ; Obtener días del mes base

    cmp word ptr [inputYear], 1582
    jne CheckFebLeap_GDM
    cmp byte ptr [isNegativeFlag], 1 ; Si es negativo, no es 1582 D.C.
    je CheckFebLeap_GDM
    cmp word ptr [inputMonth], 10
    jne CheckFebLeap_GDM
    ; Es Octubre de 1582 D.C.
    mov ax, 31 ; Octubre 1582 tuvo 21 días
    jmp saveDays
CheckFebLeap_GDM:
    cmp inputMonth, 2   ; Es Febrero?
    jne saveDays        ; Si no, usar el valor base

    cmp isLeap, 1       ; Es año bisiesto?
    jne saveDays        ; Si no es bisiesto, usar 28 (valor base)

    inc ax              ; Si es Febrero y bisiesto, días = 29

saveDays:
    mov numDays, ax
    ret
GetDaysInMonth endp

; ==================================================================
; Calcula el día de la semana (0=Do..6=Sa) para el día 1
; del mes/año dados, usando el algoritmo de Sakamoto. REVISADO
; Guarda el resultado en firstDayOfWeek.
; ==================================================================
CalculateDayOfWeek proc
    push ax
    push bx
    push cx
    push dx
    push si

    ; Variables locales en la pila si es necesario o usar registros.
    ; y = año, m = mes, d = día (siempre 1 para esta función)

    mov ax, [inputYear]     ; ax = año original
    mov bx, [inputMonth]    ; bx = mes original (1-12)
    mov cx, 1               ; cx = día (siempre 1)

    ; Ajustar mes y año para el algoritmo (Ene/Feb son meses 13/14 del año anterior)
    ; Este ajuste es común para Zeller y Sakamoto.
    cmp bx, 3               ; Si mes (bx) >= Marzo
    jge CDoW_MonthOk
    dec ax                  ; año = año - 1
    add bx, 12              ; mes = mes + 12 (Ene->13, Feb->14)
CDoW_MonthOk:
    ; Ahora: ax = y (año ajustado), bx = m (mes ajustado 3-14), cx = d (día = 1)

    ; Guardar y (año ajustado) en SI
    mov si, ax

    ; --- Decidir si aplicar fórmula Juliana o Gregoriana ---
    ; CheckLeapYear ya estableció isGregorianCalendarActive
    ; PERO, esa bandera se refería al año bisiesto.
    ; Aquí necesitamos ser más precisos para la fecha exacta (año, mes, día).

    mov [isGregorianCalendarActive], 0 ; Por defecto Juliano
    mov ax, [inputYear]     ; Año original
    mov dx, 0
    mov dl, [isNegativeFlag] ; DX = 1 si A.C., 0 si D.C.

    cmp dx, 1               ; ¿Es A.C.?
    je CDoW_UseJulian       ; A.C. usa Juliano

    ; Es D.C.
    cmp ax, 1582
    jl CDoW_UseJulian       ; < 1582 D.C. -> Juliano
    jg CDoW_UseGregorian    ; > 1582 D.C. -> Gregoriano

    ; Es el año 1582 D.C.
    mov dx, [inputMonth]    ; Mes original (1-12)
    cmp dx, 10              ; ¿Mes < Octubre?
    jl CDoW_UseJulian

    cmp dx, 10              ; ¿Mes > Octubre? (ya sabemos que no es < Oct)
    jg CDoW_UseGregorian    ; Nov, Dic 1582 -> Gregoriano

    ; Es Octubre de 1582. ¿Día < 15? (recordar que cx aquí es el día, que es 1)
    ; Como estamos calculando para el día 1 de Octubre 1582, es Juliano.
    ; Si el día fuera >= 15, sería Gregoriano.
    ; Para el día 1 del mes:
    cmp cx, 15              ; cx es el día (que es 1 para esta función)
    jl CDoW_UseJulian       ; Día 1 de Octubre 1582 es Juliano
    ; (Este salto siempre se tomará ya que cx=1)

CDoW_UseGregorian:
    mov [isGregorianCalendarActive], 1
    ; --- Fórmula Gregoriana (Sakamoto, año 'si' ya ajustado) ---
    ; dow = (y + y/4 - y/100 + y/400 + t[m-1_orig] + d) % 7
    ; y está en SI. d (día) está en CX (es 1). m_orig está en inputMonth.

    mov ax, si          ; ax = y (año ajustado para Ene/Feb)

    push dx             ; Guardar dx (que tiene mes original o basura)
    mov dx, 0
    mov cx, 4
    div cx              ; ax = y/4
    mov bp, ax          ; bp = y/4

    mov ax, si
    mov dx, 0
    mov cx, 100
    div cx              ; ax = y/100
    mov di, ax          ; di = y/100

    mov ax, si
    mov dx, 0
    mov cx, 400
    div cx              ; ax = y/400
                        ; Suma:
    mov cx, si          ; cx = y (año ajustado) ; Reutilizar CX temporalmente
    add cx, bp          ; cx = y + y/4
    sub cx, di          ; cx = y + y/4 - y/100
    add cx, ax          ; cx = y + y/4 - y/100 + y/400 (Suma de términos de año)

    pop dx              ; Restaurar dx

    ; Obtener t[m-1] de la tabla de Sakamoto (usar mes original inputMonth)
    mov bx, [inputMonth] ; Mes original (m = 1-12)
    dec bx               ; Índice (0-11)
    push si              ; Guardar SI (año ajustado)
    lea si, sakamotoTable
    add si, bx           ; SI apunta a t[m-1]
    mov bl, [si]         ; bl = valor de t[m-1]
    mov bh, 0            ; bx = t[m-1]
    pop si               ; Restaurar SI

    add cx, bx           ; Suma_años + t[m-1]
    inc cx               ; Suma_años + t[m-1] + d (d=1)

    mov ax, cx           ; Mover resultado a AX para el módulo
    mov dx, 0
    mov bx, 7
    div bx               ; DX = residuo (día de la semana Gregoriano, 0=Dom)
    jmp CDoW_SaveResult

CDoW_UseJulian:
    ; --- Fórmula Juliana ---
    ; h = (d + floor( (13*(m+1))/5 ) + y + floor(y/4) + C_julian) % 7
    ;   donde m es 1..12. Ene/Feb son del año anterior.
    ;   Ajuste para Zeller-like: meses 3(Mar)..12(Dic), 13(Ene), 14(Feb).
    ;   Año 'y' (en SI) y mes 'm' (en BX al inicio de CDoW_MonthOk) ya están ajustados así.
    ;   d (día) está en CX (es 1).

    ; Componente del mes: floor((13 * (m_ajustado + 1)) / 5)
    ; m_ajustado está en BX (rango 3 a 14)
    mov ax, bx          ; ax = m_ajustado
    inc ax              ; ax = m_ajustado + 1
    mov cx, 13
    mul cx              ; dx:ax = 13 * (m_ajustado + 1)
                        ; Asumimos que cabe en AX para m<=14. 13*15 = 195. Sí cabe.
    mov cx, 5
    div cx              ; ax = floor((13*(m+1))/5). Residuo en dx.
    mov bp, ax          ; bp = término del mes

    ; Componente del año: y + floor(y/4)
    ; y (año ajustado) está en SI.
    mov ax, si          ; ax = y
    push dx             ; Guardar dx (residuo de div cx)
    mov dx, 0
    mov cx, 4
    div cx              ; ax = y/4
                        ; Suma de año:
    add ax, si          ; ax = y/4 + y = y + y/4
    pop dx              ; Restaurar dx

    ; Suma total: d + term_mes + term_año + C_julian
    ; d = 1 (día del mes, que para esta función siempre es 1)
    add ax, bp          ; ax = (y+y/4) + term_mes
    inc ax              ; ax = (y+y/4) + term_mes + d (d=1)

    ; Constante de anclaje para Juliano con Zeller-like (Domingo=0, Lunes=1...)
    ; Si usamos J (año/100) y K (año%100) de Zeller, para Juliano es más simple:
    ; h = ( q + floor(13(m+1)/5) + K + floor(K/4) + floor(J/4) - 2J ) mod 7 (para Gregoriano)
    ; Para Juliano: h = ( q + floor(13(m+1)/5) + K + floor(K/4) + 5 - J ) mod 7 (si J es año/100)
    ; O más simple: h = (d + m' + y' + floor(y'/4) + C) mod 7.
    ; Una constante que funciona para Zeller Juliano donde d=día, m'=mes_term, y'=año es +5 (o -2) para que Domingo=0.
    ; Si el resultado de (d + m_term + y + y/4) % 7 da Sábado para el 1 de Enero del año 1 (que fue Sábado),
    ; entonces C = 0.
    ; Test: 1 Ene 1 (Juliano) -> Sábado (día 6)
    ; y_orig=1, m_orig=1, d=1.  Ajustado: y=0, m=13, d=1.
    ; m_term = floor((13*(13+1))/5) = floor(182/5) = floor(36.4) = 36.
    ; y_term = y + y/4 = 0 + 0 = 0.
    ; suma = d + m_term + y_term = 1 + 36 + 0 = 37.
    ; 37 % 7 = 2 (Martes, si Dom=0). Necesitamos que sea 6 (Sábado). Entonces 2 + C_adj = 6 => C_adj = 4.
    ; O si Sábado=0, Mar=3, 3 + C_adj = 0 => C_adj = -3 = 4.
    ; Añadamos 4 o 5 como constante de ajuste. Zeller usa +5 para anclaje Juliano.
    ; El algoritmo de Sakamoto ya da 0 para Domingo. Si esta fórmula Juliana también lo hace, bien.
    ; La fórmula de Sakamoto para Gregoriano es y + y/4 - y/100 + y/400.
    ; La fórmula Juliana equivalente es y + y/4. La diferencia es la corrección -y/100 + y/400.
    ; Si usamos la tabla t[] de Sakamoto: (y + y/4 + t[m-1_orig] + d + offset) % 7
    ; El `offset` sería para compensar la falta de `-y/100 + y/400` y el anclaje.
    ; Para el día 4 de Octubre de 1582 (Juliano), debería ser Jueves (4).
    ; y_adj=1582, m_adj=10. d=4. t[9]=6.
    ; Juliano: (1582 + 1582/4 + t[9] + 4 + C_jul) % 7
    ;          (1582 + 395 + 6 + 4 + C_jul) % 7
    ;          (1987 + C_jul) % 7 = 4
    ; 1987 % 7 = 6 (Sábado).
    ; (6 + C_jul) % 7 = 4  => C_jul = -2 = 5.
    ; Probemos con C_jul = 5.
    add ax, 4             ; Constante de anclaje Juliano (ajustar si es necesario)

    mov dx, 0
    mov bx, 7
    div bx              ; DX = residuo (día de la semana Juliano, 0=Dom si el anclaje es correcto)

CDoW_SaveResult:
    mov [firstDayOfWeek], dx ; Guardar el residuo (0-6)

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
CalculateDayOfWeek endp

; ==================================================================
; Imprime el calendario formateado
; ==================================================================
PrintCalendar proc
    lea dx, newLine
    call PrintString

    ; --- Imprimir Nombre del Mes y Año ---
    mov bx, inputMonth
    dec bx
    shl bx, 1           ; Índice * 2 para array de words
    mov dx, monthNames[bx] ; Cargar offset del nombre del mes
    call PrintString

    lea dx, space
    call PrintString

    mov ax, inputYear
    call PrintNumber    ; Imprime el año

    ; Verificar si el año es negativo
    push ax
    mov ah, 0
    mov al, [isNegativeFlag]
    cmp ax, 1
    jne skipNegativeYear
    lea dx, negativeYear
    call PrintString
skipNegativeYear:
    pop ax
    lea dx, newLine
    call PrintString

    ; --- Imprimir Cabecera de Días ---
    lea dx, dayHeader
    call PrintString

    ; --- Imprimir Espacios Iniciales ---
    mov cx, firstDayOfWeek ; Número de espacios a imprimir
    mov bx, 0              ; Contador de espacios impresos
printSpacesLoop:
    cmp bx, cx
    je printDaysStart    ; Si ya imprimimos los espacios, empezar días
    push cx              ; Guardar CX (contador de días) temporalmente
    lea dx, space        ; Imprimir "   " (3 espacios por día)
    call PrintString
    call PrintString
    call PrintString
    pop cx               ; Restaurar CX
    inc bx
    jmp printSpacesLoop

printDaysStart:
    ; --- Imprimir Días del Mes ---
    mov cx, 1           ; Día actual (empieza en 1)
    mov bx, firstDayOfWeek ; Día de la semana actual (0=Do..6=Sa)

printDaysLoop:
    cmp cx, numDays     ; Hemos impreso todos los días?
    jg calendarEnd      ; Si sí, terminar

    ; --- Manejo especial Octubre 1582 ---
    cmp word ptr [inputYear], 1582
    jne NotOct1582_PC
    cmp byte ptr [isNegativeFlag], 1
    je NotOct1582_PC
    cmp word ptr [inputMonth], 10
    jne NotOct1582_PC

    ; Es Octubre de 1582 D.C.
    cmp cx, 5       ; ¿Estamos a punto de imprimir el día 5?
    jne NotOct1582_PC
    ; Sí, es el día 5. Deberíamos saltar al 15.
    mov cx, 15      ; Saltar el contador de días a 15

NotOct1582_PC:

    ; Imprimir número del día (con padding)
    push bx             ; Guardar día de la semana actual
    push cx             ; Guardar día actual
    mov ax, cx          ; Mover día actual a AX para imprimir
    call PrintDayNumber ; Imprime el número (ej. " 1", "10")
    pop cx              ; Restaurar día actual
    pop bx              ; Restaurar día de la semana actual

    ; Imprimir espacio después del número
    push cx
    push bx
    lea dx, space
    call PrintString
    pop bx
    pop cx

    inc bx              ; Siguiente día de la semana
    mov ax, bx
    mov dx, 0
    mov si, 7
    div si              ; AX = bx / 7, DX = bx % 7
    mov bx, dx          ; Nuevo día de la semana = bx % 7

    cmp bx, 0           ; Es Domingo (acabamos de imprimir Sábado)?
    jne nextDayNoNewLine
    push cx
    push bx
    lea dx, newLine     ; Si sí, imprimir nueva línea
    call PrintString
    pop bx
    pop cx

nextDayNoNewLine:
    inc cx              ; Siguiente día del mes
    jmp printDaysLoop

calendarEnd:
    lea dx, newLine
    call PrintString
    ret
PrintCalendar endp


; ==================================================================
; Procedimientos Auxiliares (Entrada/Salida)
; ==================================================================

; --- Imprime una cadena terminada en '$' (DX = offset) ---
PrintString proc
    mov ah, 09h
    int 21h
    ret
PrintString endp

; --- Imprime un carácter (DL = caracter) ---
PrintChar proc
    mov ah, 02h
    int 21h
    ret
PrintChar endp

; --- Lee un número desde el teclado ---
; Usa buffer, convierte la cadena a número.
; Devuelve: AX = número leído, CF = 1 si error/overflow, 0 si OK.
ReadNumber proc
    push bx
    push cx
    push dx
    push si

    ; mov [isNegativeFlag], 0 ; Inicializar flag de negativo

    ; Leer cadena usando DOS func 0Ah
    mov ah, 0Ah
    lea dx, buffer      ; DX apunta a la estructura del buffer
    int 21h             ; DOS lee la entrada aquí

    ; Obtener longitud real y apuntar al inicio de la cadena
    lea si, buffer      ; SI apunta al buffer
    mov bl, [si+1]      ; BL = longitud real leída por DOS
    mov bh, 0           ; BX = longitud real
    lea si, [si+2]      ; SI apunta al primer carácter de la cadena leída

    mov dl, [si]
    cmp dl, '-'      ; Es un número negativo?
    jne noNegativeFlag  ; Si no, continuar sin negativo
    lea si, [si+1]      ; Avanzar puntero al siguiente carácter
    mov ax, 0           ; Reiniciar AX para la conversión
    mov al, 1
    mov [isNegativeFlag], al ; Marcar como negativo
    
noNegativeFlag:

    ; Convertir cadena a número
    mov ax, 0           ; AX = Acumulador del número
    mov cx, 0           ; CX = Contador de caracteres procesados

convertLoop:
    cmp cx, bx          ; Hemos procesado todos los caracteres según la longitud (BX)?
    je conversionDone   ; Si CX == BX, terminamos porque leímos todos los chars indicados por DOS

    mov dl, [si]        ; Obtener caracter actual
    inc si              ; Avanzar puntero
    inc cx              ; Incrementar caracteres procesados

    cmp dl, 13          ; Es Carriage Return (fin de entrada del usuario)?
    je conversionDoneCR ; Si sí, terminamos la conversión útil

    cmp dl, '0'
    jl conversionError  ; No es dígito
    cmp dl, '9'
    jg conversionError  ; No es dígito

    ; Convertir caracter a número
    sub dl, '0'         ; DL = valor numérico del dígito
    mov dh, 0           ; DX = valor numérico del dígito (0-9)

    ; Multiplicar acumulador actual (AX) por 10
    push dx             ; Guardar el dígito nuevo (DX) temporalmente
    mov bx, 10          ; BX = Multiplicador 10
    mul bx              ; DX:AX = AX_viejo * 10

    ; Verificar Overflow de multiplicación
    cmp dx, 0           ; DX debería ser 0 si el resultado cabe en 16 bits
    pop dx              ; Recuperar el nuevo dígito (0-9) en DX ANTES de la suma
    jne conversionOverflow ; Salta si el resultado excedió 16 bits (DX != 0)

    ; Sumar el nuevo dígito (que está ahora en DX)
    add ax, dx          ; AX = (AX_viejo * 10) + nuevo_dígito
    ; Verificar Overflow de la suma
    jc conversionOverflow ; Salta si la suma causó acarreo (carry flag set)

    jmp convertLoop

conversionDoneCR: ; Etiqueta específica si terminamos por CR
    ; Llegamos aquí porque el último carácter leído fue CR.
    ; CX ya se incrementó para el CR.
    dec cx              ; Decrementar CX para no contar el CR mismo.
    ; Ahora CX refleja el número de dígitos *antes* del CR.
    cmp cx, 0           ; Si CX es 0 ahora, solo se tecleó Enter (sin dígitos).
    je conversionErrorNoDigits ; Considerar solo Enter como error.
    jmp conversionOk    ; Si CX > 0, al menos un dígito fue procesado.

conversionDone:     ; Etiqueta si terminamos porque CX == BX
    ; Llegamos aquí porque procesamos exactamente BX caracteres (buffer lleno).
    cmp bx, 0           ; BX tiene la longitud original. ¿Es 0?
    je conversionErrorNoDigits ; Si longitud leída es 0, es error.
    ; Si BX > 0, la conversión fue (potencialmente) exitosa.

conversionOk:       ; Etiqueta común para salida exitosa
    clc                 ; No hubo error detectado, limpiar Carry Flag
    jmp exitReadNumber

conversionOverflow:
    ; Podrías imprimir un mensaje aquí si quisieras
    stc                 ; Establecer Carry Flag para indicar error de overflow
    jmp exitReadNumber  ; Salir (AX contendrá un valor parcial/incorrecto)

conversionErrorNoDigits: ; Etiqueta si no se ingresaron dígitos
    mov ax, 0           ; Devolver 0 en AX en caso de error parece razonable
    stc                 ; Indicar error con Carry Flag
    jmp exitReadNumber

conversionError:    ; Etiqueta para otros errores (caracter no válido)
    mov ax, 0           ; Devolver 0 en AX
    stc                 ; Hubo error, poner Carry Flag

exitReadNumber:
    ; Imprimir nueva línea (estético, después de que el usuario presiona Enter)
    push ax             ; Guardar AX (resultado o 0)
    lea dx, newLine
    call PrintString
    pop ax              ; Restaurar AX

    pop si
    pop dx
    pop cx
    pop bx
    ret
ReadNumber endp

; --- Imprime un número decimal en AX ---
PrintNumber proc
    push ax
    push bx
    push cx
    push dx

    cmp ax, 0
    jne printNumLoop
    ; Si AX es 0, imprimir '0'
    mov dl, '0'
    call PrintChar
    jmp printNumExit

printNumLoop:
    mov cx, 0           ; Contador de dígitos
    mov bx, 10          ; Divisor

divideLoop:
    mov dx, 0           ; Limpiar DX para división
    div bx              ; AX = AX / 10, DX = AX % 10
    push dx             ; Guardar residuo (dígito) en la pila
    inc cx              ; Incrementar contador de dígitos
    cmp ax, 0           ; Si cociente es 0, terminamos de dividir
    jne divideLoop

printDigitsLoop:
    pop dx              ; Recuperar dígito de la pila
    add dl, '0'         ; Convertir a ASCII
    call PrintChar      ; Imprimir dígito
    loop printDigitsLoop ; Decrementa CX y salta si no es cero

printNumExit:
    pop dx
    pop cx
    pop bx
    pop ax
    ret
PrintNumber endp

; --- Imprime un número de día (1-31) con padding ---
; AX = número del día
PrintDayNumber proc
    push ax
    push dx

    cmp ax, 10          ; Si es menor que 10, imprimir espacio antes
    jge printDayNoPad
    mov dl, ' '
    call PrintChar

printDayNoPad:
    pop dx              ; Restaurar DX (PrintNumber lo usa)
    pop ax              ; Restaurar AX para PrintNumber
    call PrintNumber    ; Imprimir el número
    ret
PrintDayNumber endp


end main