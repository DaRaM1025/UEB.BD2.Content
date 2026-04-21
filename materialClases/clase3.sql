Set serverOutput ON; 

create or replace procedure SP_holaMundo (param_nombre IN VARCHAR2 DEFAULT 'JAIBER')
/*
AUTOR: 
FECHA: 
DESCRIPCION: 
*/
IS
vv_mensaje VARCHAR2(40);
BEGIN
    vv_mensaje := 'Hola el nombre es: ' || param_nombre;
     DBMS_OUTPUT.PUT_LINE(vv_mensaje);
END SP_holaMundo;
/ -- el proposito es darle finalizacion y salto de linea de manera grafica para cuando no se cuenta con GUI --

BEGIN
SP_holaMundo('DAVID');
END;
/

Select ADD_MONTHS(NEXT_DAY(LAST_DAY(SYSDATE)-7, 'FRIDAY'), 2)
FROM DUAL;