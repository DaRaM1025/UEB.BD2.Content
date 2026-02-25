--Este comando sirve para mostrar contenido en consola, se debe hacer solo una vez durante toda una sesion--
SET SERVEROUTPUT ON;

BEGIN
dbms_output.put_line('hola mundo');
END;
--Este script se conoce como un bloque anonimo ya que no tiene un nombre de proceso

DECLARE
    vv_variable VARCHAR2(50) :=  'david'  ;
BEGIN
dbms_output.put_line( vv_variable);
END;
-- este bloque muestra como se imprime una variable, hay que seguir estandares para la notacion de las variables--
DECLARE
    vv_nameEmployee VARCHAR2(20);
    vv_lastNameEmployee VARCHAR2(25);
BEGIN
    
    select first_name , last_name
    INTO vv_nameEmployee, vv_lastNameEmployee 
    FROM empleados
    WHERE employee_id = 110;
    
dbms_output.put_line('El nombre del empleado es: '  || vv_nameEmployee); --Los literales son las cadenas definidas dentro de la consulta--
END;
-- diccionarios de datos --
DECLARE
    vv_nameEmployee empleados.first_name%TYPE; --El operador %TYPE infiere el tipo de dato
BEGIN
    
    select first_name 
    INTO vv_nameEmployee 
    FROM empleados
    WHERE employee_id = 110;
    
dbms_output.put_line('El nombre del empleado es: '  || vv_nameEmployee); --Los literales son las cadenas definidas dentro de la consulta--
END;

DECLARE
    vv_nameEmployee empleados%ROWTYPE; --El operador %ROWTYPE infiere el tipo de dato de cada una de las columnas de la tabla, almacenando todos los datos de la fila
BEGIN
    
    select * 
    INTO vv_nameEmployee 
    FROM empleados
    WHERE employee_id = 110;
    
dbms_output.put_line('El nombre del empleado es: '  || vv_nameEmployee.first_name); --Los literales son las cadenas definidas dentro de la consulta--
END;