SET SERVEROUTPUT ON;
DECLARE 
CURSOR C_MYEMPLOYEES
IS 
SELECT First_Name, department_id 
FROM spinzonv.employees 
where department_id = 80; 

vv_firtsName VARCHAR2(30);
vn_departmentID NUMBER(4,0);

BEGIN
OPEN C_MYEMPLOYEES;
FETCH C_MYEMPLOYEES INTO vv_firtsName, vn_departmentID;
dbms_output.put_line(vv_firtsName||' '||vn_departmentID);
CLOSE C_MYEMPLOYEES;
END;