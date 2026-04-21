select count(*) from spinzonv.employees;
INSERT INTO spinzonv.EMPLOYEES (
    EMPLOYEE_ID,
    FIRST_NAME,
    LAST_NAME,
    EMAIL,
    PHONE_NUMBER,
    HIRE_DATE,
    JOB_ID,
    SALARY,
    COMMISSION_PCT,
    MANAGER_ID,
    DEPARTMENT_ID
)
SELECT
    1000 + LEVEL, -- evita chocar con IDs existentes del HR
    'Nombre' || LEVEL,
    'Apellido' || LEVEL,
    'EMP' || (1000 + LEVEL),
    '300' || LPAD(LEVEL,7,'0'),
    SYSDATE - MOD(LEVEL, 3650),
    'IT_PROG',
    3000 + MOD(LEVEL, 5000),
    CASE 
        WHEN MOD(LEVEL,5)=0 
        THEN ROUND(DBMS_RANDOM.VALUE(0.05,0.30),2)
        ELSE NULL
    END,
    -- Manager válido existente en HR
    (
      SELECT employee_id
      FROM (
            SELECT employee_id
            FROM spinzonv.employees
            ORDER BY DBMS_RANDOM.VALUE
           )
      WHERE ROWNUM = 1
    ),
    -- Departamento válido existente en HR
    (
      SELECT department_id
      FROM (
            SELECT department_id
            FROM spinzonv.departments
            ORDER BY DBMS_RANDOM.VALUE
           )
      WHERE ROWNUM = 1
    )
FROM dual
CONNECT BY LEVEL <= 5000;

COMMIT;