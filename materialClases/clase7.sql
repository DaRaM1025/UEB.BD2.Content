set serveroutput on; 

declare 
    registros EXCEPTION; 
    v_1 number(20);
    v_2 number(20) := 0; 
    v_3 number(9); 
begin 
    SELECT count(country_name) into v_1 from hr.countries where country_name = 'bogota';
    if v_1 = 0 then
            raise registros; 
    end if; 
    v_3 := v_1 / v_2; 
exception 
    when registros then 
        dbms_output.put_line('no se encontraron estudiantes');
    when zero_divide then
    dbms_output.put_line('no se encontraron estudiantes');
ENd;