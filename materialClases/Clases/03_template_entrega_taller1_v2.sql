-- =====================================================================
-- 03_template_entrega_taller1_v2.sql
-- Taller aplicado 1 - SQL avanzado + Transacciones (ACID) aplicado
-- Plantilla de entrega para estudiantes
--
-- IMPORTANTE:
-- 1. Trabajar únicamente sobre las tablas T1_% y AUDIT_SALARY_ADJUSTMENTS_T1
-- 2. NO modificar la estructura del entorno entregado por el docente
-- 3. NO eliminar secciones de esta plantilla
-- 4. Reemplazar únicamente los bloques indicados como "ESCRIBA AQUÍ"
-- 5. Usar la variante asignada por el docente (1, 2, 3 o 4)
-- 6. Usar un tag único de ejecución final, por ejemplo: P03_FINAL
-- =====================================================================

SET SERVEROUTPUT ON
SET FEEDBACK ON

-- ============================================================
-- 0. ENCABEZADO OBLIGATORIO
-- Complete toda esta información antes de ejecutar el script.
-- ============================================================
-- Integrante 1: David Santiago Ramirez Arevalo
-- Integrante 2: Hernando Javier Garcia Mogollon
-- Curso: Bases de Datos 2
-- Fecha: 04/08/26
-- Variante asignada por el docente (1, 2, 3 o 4): 3
-- Tag de ejecución final (ejemplo: P03_FINAL): Ex01

DEFINE p_variant_id = 3
DEFINE p_execution_tag = 'Ex01'

PROMPT ===== 0. VERIFICACIÓN DE LA VARIANTE ASIGNADA =====
SELECT
    variant_id,
    variant_name,
    excluded_department_id,
    min_years_service,
    recent_job_history_months,
    gap_high_threshold_pct,
    gap_mid_threshold_pct,
    raise_high_pct,
    raise_mid_pct,
    raise_low_pct,
    max_salary_vs_avg_pct,
    notes
FROM t1_variants
WHERE variant_id = &p_variant_id;

-- ============================================================
-- GUÍA RÁPIDA DE OBJETOS DISPONIBLES
-- Use estos nombres reales de tablas y columnas.
-- ============================================================
-- Tabla principal de empleados: T1_EMPLOYEES
-- Columnas más importantes:
--   employee_id, first_name, last_name, email, phone_number,
--   hire_date, job_id, salary, commission_pct, manager_id, department_id
--
-- Tabla de departamentos: T1_DEPARTMENTS
-- Columnas más importantes:
--   department_id, department_name, manager_id, location_id
--
-- Tabla de historial laboral: T1_JOB_HISTORY
-- Columnas más importantes:
--   employee_id, start_date, end_date, job_id, department_id
--
-- Tabla de auditoría: AUDIT_SALARY_ADJUSTMENTS_T1
-- Columnas:
--   audit_id, execution_tag, variant_id, employee_id, department_id,
--   salary_before, salary_after, pct_gap_to_avg_before, rule_applied,
--   executed_by, executed_at, notes
--
-- Tabla de variantes: T1_VARIANTS
-- Columnas:
--   variant_id, variant_name, excluded_department_id, min_years_service,
--   recent_job_history_months, gap_high_threshold_pct,
--   gap_mid_threshold_pct, raise_high_pct, raise_mid_pct,
--   raise_low_pct, max_salary_vs_avg_pct, notes

-- ============================================================
-- GUÍA RÁPIDA DE TÉRMINOS QUE DEBE USAR EN SU SOLUCIÓN
-- ============================================================
-- CTE:
--   Una CTE es una consulta temporal escrita con WITH.
--   Sirve para dividir una consulta grande en partes más claras.
--
--   Ejemplo:
--   WITH dept_stats AS (
--       SELECT department_id, AVG(salary) avg_salary
--       FROM t1_employees
--       GROUP BY department_id
--   )
--   SELECT *
--   FROM dept_stats;
--
-- Función analítica:
--   Es una función como ROW_NUMBER, RANK o DENSE_RANK.
--   Sirve para calcular posiciones o comparaciones sin perder el detalle.
--
--   Ejemplo:
--   DENSE_RANK() OVER (PARTITION BY department_id ORDER BY salary DESC)
--
-- JOIN:
--   Es la unión entre tablas relacionadas, por ejemplo empleados y departamentos.
--
-- Subconsulta:
--   Es una consulta dentro de otra consulta.
--
-- SAVEPOINT:
--   Es un punto de restauración dentro de una transacción.
--   Permite devolver la operación a un punto intermedio con ROLLBACK TO.

-- ============================================================
-- 1. CONSULTA DIAGNÓSTICA
-- OBJETIVO:
-- Analizar la información antes de actualizar salarios.
--
-- SU CONSULTA DEBE MOSTRAR, COMO MÍNIMO, ESTAS COLUMNAS:
--   employee_id
--   first_name
--   last_name
--   job_id
--   manager_id
--   department_id
--   department_name
--   salary
--   hire_date
--   years_service
--   dept_avg_salary
--   dept_max_salary
--   dept_employee_count
--   pct_gap_to_avg
--   recent_job_history_flag
--   salary_rank_in_department
--
-- QUÉ SIGNIFICA CADA COLUMNA:
--   years_service: años de antigüedad del empleado
--   dept_avg_salary: promedio salarial del departamento
--   dept_max_salary: salario más alto del departamento
--   dept_employee_count: cantidad de empleados del departamento
--   pct_gap_to_avg: porcentaje que le falta al salario del empleado para llegar
--                   al promedio del departamento
--   recent_job_history_flag: SI o NO, según si tuvo historial reciente
--   salary_rank_in_department: posición salarial dentro del departamento
--
-- IMPORTANTE:
-- - Puede usar una o varias CTE
-- - Debe usar al menos una función analítica
-- - Debe unir como mínimo T1_EMPLOYEES con T1_DEPARTMENTS
-- - Debe revisar T1_JOB_HISTORY para detectar historial reciente
-- ============================================================

PROMPT ===== 1. CONSULTA DIAGNÓSTICA =====

-- ESCRIBA AQUÍ SU CONSULTA DIAGNÓSTICA PRINCIPAL
WITH variant_info AS (
    SELECT recent_job_history_months
    FROM t1_variants
    WHERE variant_id = &p_variant_id
),
emp_dept_stats AS (
    -- Funciones analíticas para sacar promedios y máximos sin agrupar y dañar el detalle
    SELECT 
        e.employee_id, e.first_name, e.last_name, e.job_id, e.manager_id, e.department_id,
        d.department_name, e.salary, e.hire_date,
        TRUNC(MONTHS_BETWEEN(SYSDATE, e.hire_date) / 12) AS years_service,
        ROUND(AVG(e.salary) OVER(PARTITION BY e.department_id), 2) AS dept_avg_salary,
        MAX(e.salary) OVER(PARTITION BY e.department_id) AS dept_max_salary,
        COUNT(e.employee_id) OVER(PARTITION BY e.department_id) AS dept_employee_count,
        DENSE_RANK() OVER(PARTITION BY e.department_id ORDER BY e.salary DESC) AS salary_rank_in_department
    FROM t1_employees e
    LEFT JOIN t1_departments d ON e.department_id = d.department_id
),
job_hist_check AS (
    -- Validamos si tuvo cambios recientes leyendo el parámetro dinámico de la variante
    SELECT DISTINCT jh.employee_id
    FROM t1_job_history jh
    CROSS JOIN variant_info vi
    WHERE jh.end_date >= ADD_MONTHS(SYSDATE, -vi.recent_job_history_months)
)
SELECT 
    eds.employee_id, eds.first_name, eds.last_name, eds.job_id, eds.manager_id, 
    eds.department_id, eds.department_name, eds.salary, eds.hire_date, eds.years_service, 
    eds.dept_avg_salary, eds.dept_max_salary, eds.dept_employee_count,
    CASE 
        WHEN eds.dept_avg_salary > eds.salary 
        THEN ROUND(((eds.dept_avg_salary - eds.salary) / eds.salary) * 100, 2)
        ELSE 0 
    END AS pct_gap_to_avg,
    CASE WHEN jhc.employee_id IS NOT NULL THEN 'SI' ELSE 'NO' END AS recent_job_history_flag,
    eds.salary_rank_in_department
FROM emp_dept_stats eds
LEFT JOIN job_hist_check jhc ON eds.employee_id = jhc.employee_id
ORDER BY eds.department_id, eds.salary DESC;

-- COMENTARIO OBLIGATORIO:
/*
Esta consulta demuestra el panorama salarial actual por departamento usando funciones analíticas 
para no perder el detalle a nivel de empleado. Nos sirve para identificar fácilmente quiénes 
están por debajo del promedio (pct_gap_to_avg), quiénes tienen historial reciente, y filtrar de 
una vez los elegibles según la antigüedad y las reglas de la variante asignada.
*/




-- COMENTARIO OBLIGATORIO:
-- Explique en 3 a 5 líneas qué demuestra su consulta diagnóstica y por qué
-- le sirve para decidir qué empleados pueden ser elegibles.

-- ============================================================
-- 2. DECISIÓN DE POBLACIÓN ELEGIBLE
-- OBJETIVO:
-- Determinar qué empleados sí califican, cuáles no califican y por qué.
--
-- SU CONSULTA DEBE MOSTRAR, COMO MÍNIMO, ESTAS COLUMNAS:
--   employee_id
--   first_name
--   last_name
--   department_id
--   department_name
--   salary
--   years_service
--   dept_avg_salary
--   dept_max_salary
--   dept_employee_count
--   pct_gap_to_avg
--   recent_job_history_flag
--   manager_or_exec_flag
--   eligibility_flag
--   exclusion_reason
--   adjustment_pct
--   rule_applied
--
-- QUÉ SIGNIFICA CADA COLUMNA:
--   manager_or_exec_flag: SI o NO, según si es gerente principal o alta dirección
--   eligibility_flag: ELEGIBLE o NO_ELEGIBLE
--   exclusion_reason: motivo de exclusión, por ejemplo:
--                     SIN_DEPARTAMENTO, HISTORIAL_RECIENTE,
--                     ANTIGUEDAD_INSUFICIENTE, MANAGER_O_DIRECTIVO,
--                     DEPTO_EXCLUIDO, DEPTO_MENOR_A_3, SALARIO_NO_APLICA
--   adjustment_pct: porcentaje de ajuste que le corresponde
--   rule_applied: regla aplicada, por ejemplo AJUSTE_ALTO, AJUSTE_MEDIO, AJUSTE_BAJO
--
-- IMPORTANTE:
-- - Debe tomar en cuenta la variante asignada por el docente
-- - Debe usar los valores de T1_VARIANTS según &p_variant_id
-- - Debe quedar visible por qué una persona sí o no entra al proceso
-- ============================================================

PROMPT ===== 2. DECISIÓN DE ELEGIBLES =====

-- ESCRIBA AQUÍ SU CONSULTA DE DECISIÓN DE ELEGIBLES
WITH variant_info AS (
    -- Traemos los parámetros de la Variante 3 dinámicamente
    SELECT * FROM t1_variants WHERE variant_id = 3
),
emp_dept_stats AS (
    -- Funciones analíticas: promedios, máximos y detectamos directivos
    SELECT 
        e.employee_id, e.first_name, e.last_name, e.department_id,
        d.department_name, e.salary, e.hire_date, e.job_id,
        TRUNC(MONTHS_BETWEEN(SYSDATE, e.hire_date) / 12) AS years_service,
        ROUND(AVG(e.salary) OVER(PARTITION BY e.department_id), 2) AS dept_avg_salary,
        MAX(e.salary) OVER(PARTITION BY e.department_id) AS dept_max_salary,
        COUNT(e.employee_id) OVER(PARTITION BY e.department_id) AS dept_employee_count,
        CASE WHEN e.job_id LIKE '%MAN' OR e.job_id LIKE '%MGR' OR e.job_id LIKE '%VP%' OR e.job_id LIKE '%PRES%' THEN 'SI' ELSE 'NO' END AS manager_or_exec_flag
    FROM t1_employees e
    LEFT JOIN t1_departments d ON e.department_id = d.department_id
),
job_hist_check AS (
    -- Validamos si tuvo cambios recientes leyendo el parámetro (24 meses para variante 3)
    SELECT DISTINCT jh.employee_id
    FROM t1_job_history jh
    CROSS JOIN variant_info vi
    WHERE jh.end_date >= ADD_MONTHS(SYSDATE, -vi.recent_job_history_months)
)
SELECT 
    eds.employee_id, eds.first_name, eds.last_name, eds.department_id, eds.department_name, 
    eds.salary, eds.years_service, eds.dept_avg_salary, eds.dept_max_salary, eds.dept_employee_count, 
    
    -- Brecha porcentual calculada una sola vez para reusar lógica
    (CASE WHEN eds.dept_avg_salary > eds.salary THEN ROUND(((eds.dept_avg_salary - eds.salary) / eds.salary) * 100, 2) ELSE 0 END) AS pct_gap_to_avg,
    
    CASE WHEN jhc.employee_id IS NOT NULL THEN 'SI' ELSE 'NO' END AS recent_job_history_flag,
    eds.manager_or_exec_flag,
    
    -- Ajuste de etiquetas según el estándar del template
    CASE 
        WHEN eds.department_id IS NULL OR eds.department_id = vi.excluded_department_id OR eds.dept_employee_count < 3 OR eds.manager_or_exec_flag = 'SI' OR jhc.employee_id IS NOT NULL OR eds.years_service < vi.min_years_service THEN 'NO_ELEGIBLE'
        ELSE 'ELEGIBLE'
    END AS eligibility_flag,
    
    CASE 
        WHEN eds.department_id IS NULL OR eds.department_id = vi.excluded_department_id OR eds.dept_employee_count < 3 OR eds.manager_or_exec_flag = 'SI' OR jhc.employee_id IS NOT NULL OR eds.years_service < vi.min_years_service THEN 'EXCLUIDO'
        ELSE 'NINGUNO'
    END AS exclusion_reason,
    
    -- Porcentaje de ajuste
    CASE
        WHEN (eds.department_id IS NULL OR eds.department_id = vi.excluded_department_id OR eds.dept_employee_count < 3 OR eds.manager_or_exec_flag = 'SI' OR jhc.employee_id IS NOT NULL OR eds.years_service < vi.min_years_service) THEN 0
        WHEN (CASE WHEN eds.dept_avg_salary > eds.salary THEN ROUND(((eds.dept_avg_salary - eds.salary) / eds.salary) * 100, 2) ELSE 0 END) >= vi.gap_high_threshold_pct THEN vi.raise_high_pct
        WHEN (CASE WHEN eds.dept_avg_salary > eds.salary THEN ROUND(((eds.dept_avg_salary - eds.salary) / eds.salary) * 100, 2) ELSE 0 END) >= vi.gap_mid_threshold_pct THEN vi.raise_mid_pct
        ELSE vi.raise_low_pct
    END AS adjustment_pct,
    
    CASE
        WHEN (eds.department_id IS NULL OR eds.department_id = vi.excluded_department_id OR eds.dept_employee_count < 3 OR eds.manager_or_exec_flag = 'SI' OR jhc.employee_id IS NOT NULL OR eds.years_service < vi.min_years_service) THEN 'NO_APLICA'
        WHEN (CASE WHEN eds.dept_avg_salary > eds.salary THEN ROUND(((eds.dept_avg_salary - eds.salary) / eds.salary) * 100, 2) ELSE 0 END) >= vi.gap_high_threshold_pct THEN 'AJUSTE_ALTO'
        WHEN (CASE WHEN eds.dept_avg_salary > eds.salary THEN ROUND(((eds.dept_avg_salary - eds.salary) / eds.salary) * 100, 2) ELSE 0 END) >= vi.gap_mid_threshold_pct THEN 'AJUSTE_MEDIO'
        ELSE 'AJUSTE_BAJO'
    END AS rule_applied

FROM emp_dept_stats eds
CROSS JOIN variant_info vi
LEFT JOIN job_hist_check jhc ON eds.employee_id = jhc.employee_id
ORDER BY eligibility_flag ASC, eds.department_id, eds.salary DESC;

-- COMENTARIO OBLIGATORIO:
/*
Se aplica la lógica de la Variante 3 de forma dinámica. La consulta identifica a los 
empleados 'ELEGIBLE' basándose en antigüedad (>=4 años), pertenencia a departamentos 
con más de 3 empleados y exclusión del depto 100, además de filtrar cargos gerenciales 
e historial reciente.
*/
-- COMENTARIO OBLIGATORIO:
-- Explique en 3 a 5 líneas cómo aplicó la variante y por qué su población
-- elegible sí cumple las reglas del caso.

-- ============================================================
-- 3. PREVALIDACIÓN ANTES DE LA TRANSACCIÓN
-- OBJETIVO:
-- Mostrar qué pasaría antes de ejecutar el cambio real.
--
-- DEBE MOSTRAR, COMO MÍNIMO:
-- A. Un resumen con estas columnas:
--    total_eligible_employees
--    total_salary_before
--    total_salary_after
--    total_increment
--
-- B. Un detalle de empleados elegibles con estas columnas:
--    employee_id
--    department_id
--    salary_before
--    salary_after
--    adjustment_pct
--    rule_applied
--
-- C. Un control de topes por departamento con estas columnas:
--    department_id
--    department_name
--    dept_avg_salary
--    dept_max_salary
--    max_allowed_salary_by_variant
--
-- QUÉ SIGNIFICA:
--   total_salary_before: suma de salarios antes del ajuste
--   total_salary_after: suma de salarios proyectados después del ajuste
--   total_increment: incremento total proyectado
--   max_allowed_salary_by_variant: salario máximo permitido según la variante
-- ============================================================

PROMPT ===== 3. PREVALIDACIÓN =====

-- Definimos la variante al inicio para que todo el script la tome
DEFINE p_variant_id = 3;

PROMPT ===== A. RESUMEN DE IMPACTO (PROYECTADO) =====
SELECT 
    COUNT(*) as total_eligible_employees,
    SUM(salary_before) as total_salary_before,
    SUM(salary_after) as total_salary_after,
    SUM(salary_after - salary_before) as total_increment
FROM (
    SELECT 
        e.salary as salary_before,
        -- Cálculo del nuevo salario respetando el tope del 118% (Variante 3)
        LEAST(
            e.salary * (1 + (CASE 
                WHEN ((AVG(e.salary) OVER(PARTITION BY e.department_id) - e.salary) / NULLIF(AVG(e.salary) OVER(PARTITION BY e.department_id),0)) * 100 >= 12 THEN 7 -- High
                WHEN ((AVG(e.salary) OVER(PARTITION BY e.department_id) - e.salary) / NULLIF(AVG(e.salary) OVER(PARTITION BY e.department_id),0)) * 100 >= 6 THEN 4  -- Mid
                ELSE 2 -- Low
            END) / 100),
            AVG(e.salary) OVER(PARTITION BY e.department_id) * 1.18
        ) as salary_after
    FROM t1_employees e
    WHERE e.department_id <> 100 -- Exclusión Variante 3
      AND e.hire_date <= ADD_MONTHS(SYSDATE, -48) -- Mínimo 4 años (48 meses)
      AND NOT EXISTS (
          SELECT 1 FROM t1_job_history jh 
          WHERE jh.employee_id = e.employee_id 
            AND jh.start_date >= ADD_MONTHS(SYSDATE, -24) -- Historial 24 meses
      )
);

PROMPT ===== B. DETALLE DE EMPLEADOS ELEGIBLES =====
SELECT 
    employee_id,
    department_id,
    salary_before,
    salary_after,
    adjustment_pct || '%' as adjustment_pct,
    rule_applied
FROM (
    SELECT 
        e.employee_id,
        e.department_id,
        e.salary as salary_before,
        CASE 
            WHEN ((AVG(e.salary) OVER(PARTITION BY e.department_id) - e.salary) / NULLIF(AVG(e.salary) OVER(PARTITION BY e.department_id),0)) * 100 >= 12 THEN 7
            WHEN ((AVG(e.salary) OVER(PARTITION BY e.department_id) - e.salary) / NULLIF(AVG(e.salary) OVER(PARTITION BY e.department_id),0)) * 100 >= 6 THEN 4
            ELSE 2
        END as adjustment_pct,
        LEAST(
            e.salary * (1 + (CASE 
                WHEN ((AVG(e.salary) OVER(PARTITION BY e.department_id) - e.salary) / NULLIF(AVG(e.salary) OVER(PARTITION BY e.department_id),0)) * 100 >= 12 THEN 7
                WHEN ((AVG(e.salary) OVER(PARTITION BY e.department_id) - e.salary) / NULLIF(AVG(e.salary) OVER(PARTITION BY e.department_id),0)) * 100 >= 6 THEN 4
                ELSE 2
            END) / 100),
            AVG(e.salary) OVER(PARTITION BY e.department_id) * 1.18
        ) as salary_after,
        'V3-Gap-' || (CASE 
            WHEN ((AVG(e.salary) OVER(PARTITION BY e.department_id) - e.salary) / NULLIF(AVG(e.salary) OVER(PARTITION BY e.department_id),0)) * 100 >= 12 THEN 'High'
            WHEN ((AVG(e.salary) OVER(PARTITION BY e.department_id) - e.salary) / NULLIF(AVG(e.salary) OVER(PARTITION BY e.department_id),0)) * 100 >= 6 THEN 'Mid'
            ELSE 'Low'
        END) as rule_applied
    FROM t1_employees e
    WHERE e.department_id <> 100
      AND e.hire_date <= ADD_MONTHS(SYSDATE, -48)
      AND NOT EXISTS (
          SELECT 1 FROM t1_job_history jh 
          WHERE jh.employee_id = e.employee_id 
            AND jh.start_date >= ADD_MONTHS(SYSDATE, -24)
      )
)
ORDER BY department_id, employee_id;

PROMPT ===== C. CONTROL DE TOPES POR DEPARTAMENTO =====
SELECT 
    d.department_id,
    d.department_name,
    ROUND(AVG(e.salary), 2) as dept_avg_salary,
    MAX(e.salary) as dept_max_salary,
    ROUND(AVG(e.salary) * 1.18, 2) as max_allowed_salary_by_variant
FROM t1_employees e
JOIN t1_departments d ON e.department_id = d.department_id
GROUP BY d.department_id, d.department_name
ORDER BY d.department_id;




-- ============================================================
-- 4. EJECUCIÓN TRANSACCIONAL
-- OBJETIVO:
-- Ejecutar la actualización real y registrar la auditoría.
--
-- DEBE INCLUIR OBLIGATORIAMENTE:
-- 1. SAVEPOINT
-- 2. UPDATE o MERGE para actualizar salarios
-- 3. INSERT a AUDIT_SALARY_ADJUSTMENTS_T1
-- 4. Validación intermedia
-- 5. COMMIT o ROLLBACK TO SAVEPOINT
--
-- IMPORTANTE:
-- - La auditoría debe usar el valor &p_execution_tag
-- - La auditoría debe usar el valor &p_variant_id
-- - Debe usar la secuencia AUDIT_SALARY_ADJ_T1_SEQ.NEXTVAL
-- ============================================================

PROMPT ===== 4. EJECUCIÓN TRANSACCIONAL =====

SAVEPOINT sv_before_adjustment;

-- 4.1 ACTUALIZACIÓN DE SALARIOS
DECLARE
    v_variant_id NUMBER := &p_variant_id;
    v_execution_tag VARCHAR2(30) := '&p_execution_tag';
    v_rows_updated NUMBER;
BEGIN
    -- Actualizar empleados elegibles según Variante 3
    UPDATE t1_employees e
    SET e.salary = ROUND(e.salary * (1 + 
        CASE 
            WHEN (SELECT ROUND(((AVG(e2.salary) - e.salary) / AVG(e2.salary)) * 100, 2)
                  FROM t1_employees e2
                  WHERE e2.department_id = e.department_id
                  GROUP BY e2.department_id) >= 
                 (SELECT gap_high_threshold_pct FROM t1_variants WHERE variant_id = v_variant_id)
            THEN (SELECT raise_high_pct/100 FROM t1_variants WHERE variant_id = v_variant_id)
            WHEN (SELECT ROUND(((AVG(e2.salary) - e.salary) / AVG(e2.salary)) * 100, 2)
                  FROM t1_employees e2
                  WHERE e2.department_id = e.department_id
                  GROUP BY e2.department_id) >= 
                 (SELECT gap_mid_threshold_pct FROM t1_variants WHERE variant_id = v_variant_id)
            THEN (SELECT raise_mid_pct/100 FROM t1_variants WHERE variant_id = v_variant_id)
            ELSE (SELECT raise_low_pct/100 FROM t1_variants WHERE variant_id = v_variant_id)
        END
    ), 2)
    WHERE EXISTS (
        WITH variant AS (SELECT * FROM t1_variants WHERE variant_id = v_variant_id),
        dept_stats AS (
            SELECT department_id, COUNT(*) AS cnt, AVG(salary) AS avg_sal
            FROM t1_employees
            WHERE department_id IS NOT NULL
            GROUP BY department_id
        ),
        recent_job AS (
            SELECT DISTINCT employee_id
            FROM t1_job_history
            WHERE start_date >= ADD_MONTHS(TRUNC(SYSDATE), - (SELECT recent_job_history_months FROM variant))
        )
        SELECT 1
        FROM dept_stats ds
        LEFT JOIN recent_job rj ON e.employee_id = rj.employee_id
        CROSS JOIN variant v
        WHERE e.department_id = ds.department_id
          AND e.department_id IS NOT NULL
          AND e.department_id != v.excluded_department_id
          AND ds.cnt >= 3
          AND MONTHS_BETWEEN(SYSDATE, e.hire_date) / 12 >= v.min_years_service
          AND rj.employee_id IS NULL
          AND e.job_id NOT IN ('AD_PRES', 'AD_VP', 'AD_ASST')
          AND (e.manager_id IS NOT NULL OR e.job_id NOT LIKE 'AD%')
          AND ((ds.avg_sal - e.salary) / ds.avg_sal) * 100 > 0
          AND (e.salary * 100 / ds.avg_sal) <= v.max_salary_vs_avg_pct
    );
    
    v_rows_updated := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('Empleados actualizados: ' || v_rows_updated);
-- Debe actualizar únicamente empleados ELEGIBLES.



-- 4.2 INSERCIÓN EN AUDITORÍA
-- Debe llenar estas columnas de AUDIT_SALARY_ADJUSTMENTS_T1:
--   audit_id               -> usar AUDIT_SALARY_ADJ_T1_SEQ.NEXTVAL
--   execution_tag          -> usar &p_execution_tag
--   variant_id             -> usar &p_variant_id
--   employee_id            -> id del empleado ajustado
--   department_id          -> departamento del empleado
--   salary_before          -> salario antes del ajuste
--   salary_after           -> salario después del ajuste
--   pct_gap_to_avg_before  -> brecha porcentual antes del ajuste
--   rule_applied           -> regla aplicada
--   executed_by            -> USER
--   executed_at            -> SYSDATE
--   notes                  -> comentario libre

INSERT INTO audit_salary_adjustments_t1 (
    audit_id,
    execution_tag,
    variant_id,
    employee_id,
    department_id,
    salary_before,
    salary_after,
    pct_gap_to_avg_before,
    rule_applied,
    executed_by,
    executed_at,
    notes
)
WITH variant AS (SELECT * FROM t1_variants WHERE variant_id = v_variant_id),
    dept_stats AS (
        SELECT department_id, COUNT(*) AS cnt, AVG(salary) AS avg_sal
        FROM t1_employees
        WHERE department_id IS NOT NULL
        GROUP BY department_id
    ),
    recent_job AS (
        SELECT DISTINCT employee_id
        FROM t1_job_history
        WHERE start_date >= ADD_MONTHS(TRUNC(SYSDATE), - (SELECT recent_job_history_months FROM variant))
    ),
    elegibles_con_auditoria AS (
        SELECT 
            e.employee_id,
            e.department_id,
            e.salary AS salary_before,
            ROUND(((ds.avg_sal - e.salary) / ds.avg_sal) * 100, 2) AS pct_gap_to_avg_before,
            CASE 
                WHEN ROUND(((ds.avg_sal - e.salary) / ds.avg_sal) * 100, 2) >= v.gap_high_threshold_pct THEN 'AJUSTE_ALTO'
                WHEN ROUND(((ds.avg_sal - e.salary) / ds.avg_sal) * 100, 2) >= v.gap_mid_threshold_pct THEN 'AJUSTE_MEDIO'
                ELSE 'AJUSTE_BAJO'
            END AS rule_applied,
            CASE 
                WHEN ROUND(((ds.avg_sal - e.salary) / ds.avg_sal) * 100, 2) >= v.gap_high_threshold_pct THEN v.raise_high_pct
                WHEN ROUND(((ds.avg_sal - e.salary) / ds.avg_sal) * 100, 2) >= v.gap_mid_threshold_pct THEN v.raise_mid_pct
                ELSE v.raise_low_pct
            END AS adjustment_pct;

-- 4.3 VALIDACIÓN INTERMEDIA
-- Debe mostrar, como mínimo, estas columnas:
--   employee_id
--   department_id
--   current_salary
--   original_salary
--   allowed_max_salary
--   validation_status
--
-- validation_status debe indicar si cumple o no cumple.

PROMPT ===== 4.3 VALIDACIÓN INTERMEDIA =====

 FROM t1_employees e
        INNER JOIN dept_stats ds ON e.department_id = ds.department_id
        CROSS JOIN variant v
        LEFT JOIN recent_job rj ON e.employee_id = rj.employee_id
        WHERE e.department_id IS NOT NULL
          AND e.department_id != v.excluded_department_id
          AND ds.cnt >= 3
          AND MONTHS_BETWEEN(SYSDATE, e.hire_date) / 12 >= v.min_years_service
          AND rj.employee_id IS NULL
          AND e.job_id NOT IN ('AD_PRES', 'AD_VP', 'AD_ASST')
          AND (e.manager_id IS NOT NULL OR e.job_id NOT LIKE 'AD%')
          AND ((ds.avg_sal - e.salary) / ds.avg_sal) * 100 > 0
          AND (e.salary * 100 / ds.avg_sal) <= v.max_salary_vs_avg_pct
    )
    SELECT 
        audit_salary_adj_t1_seq.NEXTVAL,
        v_execution_tag,
        v_variant_id,
        employee_id,
        department_id,
        salary_before,
        ROUND(salary_before * (1 + adjustment_pct/100), 2) AS salary_after,
        pct_gap_to_avg_before,
        rule_applied,
        USER,
        SYSDATE,
        'Ajuste por Variante ' || v_variant_id || ' - ' || rule_applied
    FROM elegibles_con_auditoria;



-- 4.4 CONTROL TRANSACCIONAL
-- Debe demostrar UNO de estos escenarios:
-- A. COMMIT si toda la validación es correcta
-- B. ROLLBACK TO SAVEPOINT si detecta incumplimientos
--
-- 4.4 CONTROL TRANSACCIONAL
-- Debe demostrar UNO de estos escenarios:
-- A. COMMIT si toda la validación es correcta
-- B. ROLLBACK TO SAVEPOINT si detecta incumplimientos

PROMPT ===== 4.4 CONTROL TRANSACCIONAL =====

DECLARE
    v_variant_id NUMBER := &p_variant_id;
    v_execution_tag VARCHAR2(30) := '&p_execution_tag';
    v_inconsistent_count NUMBER;
    v_total_eligible NUMBER;
    v_validation_status VARCHAR2(50);
BEGIN
    -- Validar si algún empleado actualizado excede el tope permitido
    WITH variant AS (
        SELECT * FROM t1_variants WHERE variant_id = v_variant_id
    ),
    dept_stats AS (
        SELECT 
            department_id,
            AVG(salary) AS dept_avg_salary
        FROM t1_employees
        WHERE department_id IS NOT NULL
        GROUP BY department_id
    ),
    top_validation AS (
        SELECT 
            e.employee_id,
            e.department_id,
            e.salary AS current_salary,
            ROUND(ds.dept_avg_salary * (v.max_salary_vs_avg_pct/100), 2) AS allowed_max_salary,
            CASE 
                WHEN e.salary <= ROUND(ds.dept_avg_salary * (v.max_salary_vs_avg_pct/100), 2) 
                THEN 'CUMPLE'
                ELSE 'INCUMPLE'
            END AS validation_status
        FROM t1_employees e
        INNER JOIN dept_stats ds ON e.department_id = ds.department_id
        CROSS JOIN variant v
        WHERE e.department_id IN (
            SELECT DISTINCT department_id 
            FROM audit_salary_adjustments_t1 
            WHERE execution_tag = v_execution_tag 
              AND variant_id = v_variant_id
        )
    )
    SELECT COUNT(*), MAX(validation_status)
    INTO v_inconsistent_count, v_validation_status
    FROM top_validation
    WHERE validation_status = 'INCUMPLE';
    
    -- Contar cuántos empleados fueron elegibles
    SELECT COUNT(*)
    INTO v_total_eligible
    FROM audit_salary_adjustments_t1
    WHERE execution_tag = v_execution_tag 
      AND variant_id = v_variant_id;
    
    -- Mostrar resultados de la validación
    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('CONTROL TRANSACCIONAL - VARIANTE ' || v_variant_id);
    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('Total empleados elegibles: ' || v_total_eligible);
    DBMS_OUTPUT.PUT_LINE('Empleados que excederían tope: ' || v_inconsistent_count);
    DBMS_OUTPUT.PUT_LINE('Estado de validación: ' || v_validation_status);
    DBMS_OUTPUT.PUT_LINE('========================================');
    
    -- DECISIÓN TRANSACCIONAL
    IF v_inconsistent_count = 0 AND v_total_eligible > 0 THEN
        -- Escenario A: TODO CORRECTO
        COMMIT;
        DBMS_OUTPUT.PUT_LINE(' TRANSACCIÓN CONFIRMADA (COMMIT)');
        DBMS_OUTPUT.PUT_LINE('   Razón: Todos los empleados actualizados cumplen los topes');
        DBMS_OUTPUT.PUT_LINE('   y la validación es completamente exitosa.');
        
    ELSIF v_inconsistent_count > 0 THEN
        -- Escenario B: INCUMPLIMIENTO DETECTADO
        ROLLBACK TO sv_before_adjustment;
        DBMS_OUTPUT.PUT_LINE(' TRANSACCIÓN RECHAZADA (ROLLBACK)');
        DBMS_OUTPUT.PUT_LINE('   Razón: Se detectaron ' || v_inconsistent_count || 
                             ' empleados que exceden el tope salarial permitido.');
        DBMS_OUTPUT.PUT_LINE('   Acción: Revertidos todos los cambios al punto SAVEPOINT.');
        
        -- Opcional: Registrar el error en una tabla de logs (si existiera)
        -- INSERT INTO error_log_t1 VALUES (SYSDATE, 'TOPE_EXCEDIDO', v_inconsistent_count);
        
    ELSIF v_total_eligible = 0 THEN
        -- Escenario C: SIN EMPLEADOS ELEGIBLES
        ROLLBACK TO sv_before_adjustment;
        DBMS_OUTPUT.PUT_LINE('  TRANSACCIÓN SIN EFECTO (ROLLBACK)');
        DBMS_OUTPUT.PUT_LINE('   Razón: No se encontraron empleados elegibles para la variante ' || v_variant_id);
        DBMS_OUTPUT.PUT_LINE('   Acción: No se realizaron cambios en la base de datos.');
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        -- Error inesperado: hacer ROLLBACK y mostrar el error
        ROLLBACK TO sv_before_adjustment;
        DBMS_OUTPUT.PUT_LINE(' ERROR INESPERADO - TRANSACCIÓN RECHAZADA');
        DBMS_OUTPUT.PUT_LINE('   Error: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('   Se ejecutó ROLLBACK al SAVEPOINT.');
        RAISE;
END;
/

-- Mostrar estado final después del control transaccional
PROMPT ===== ESTADO FINAL DE LA TRANSACCIÓN =====
SELECT 
    CASE 
        WHEN COUNT(*) > 0 THEN 'TRANSACCIÓN ACTIVA - CAMBIOS CONFIRMADOS'
        ELSE '️  SIN REGISTROS - ROLLBACK EJECUTADO'
    END AS transaction_status,
    COUNT(*) AS registros_audit,
    SUM(salary_after - salary_before) AS incremento_total
FROM audit_salary_adjustments_t1
WHERE execution_tag = '&p_execution_tag'
  AND variant_id = &p_variant_id;



-- ============================================================
-- 5. VALIDACIÓN POSTERIOR
-- OBJETIVO:
-- Demostrar el resultado final de la transacción.
--
-- DEBE MOSTRAR, COMO MÍNIMO, ESTAS 4 SALIDAS:
--
-- SALIDA 1. Empleados impactados
-- Columnas mínimas:
--   employee_id, first_name, last_name, department_id,
--   salary_before, salary_after, execution_tag
--
-- SALIDA 2. Resumen económico final
-- Columnas mínimas:
--   total_rows_audited, total_salary_before, total_salary_after, total_increment
--
-- SALIDA 3. Validación de topes
-- Columnas mínimas:
--   employee_id, department_id, salary_after, allowed_max_salary, top_limit_status
--
-- SALIDA 4. Auditoría generada
-- Columnas mínimas:
--   audit_id, execution_tag, variant_id, employee_id, department_id,
--   salary_before, salary_after, rule_applied, executed_by, executed_at
--
-- IMPORTANTE:
-- Todas las validaciones posteriores deben filtrar por &p_execution_tag
-- ============================================================

PROMPT ===== 5. VALIDACIÓN POSTERIOR =====

-- SALIDA 1. EMPLEADOS IMPACTADOS
-- SALIDA 1. EMPLEADOS IMPACTADOS
SELECT 
    a.employee_id,
    e.first_name,
    e.last_name,
    a.department_id,
    d.department_name,
    a.salary_before,
    a.salary_after,
    ROUND(a.salary_after - a.salary_before, 2) AS incremento,
    ROUND(((a.salary_after - a.salary_before) / a.salary_before) * 100, 2) AS pct_incremento,
    a.execution_tag,
    a.rule_applied
FROM audit_salary_adjustments_t1 a
INNER JOIN t1_employees e ON a.employee_id = e.employee_id
LEFT JOIN t1_departments d ON a.department_id = d.department_id
WHERE a.execution_tag = '&p_execution_tag'
  AND a.variant_id = &p_variant_id
ORDER BY a.department_id, a.salary_after DESC;



-- SALIDA 2. RESUMEN ECONÓMICO FINAL (VERSIÓN CORREGIDA)
SELECT 
    'RESUMEN EJECUCIÓN' AS concepto,
    COUNT(*) AS total_empleados_ajustados,
    ROUND(SUM(salary_before), 2) AS total_salary_before,
    ROUND(SUM(salary_after), 2) AS total_salary_after,
    ROUND(SUM(salary_after - salary_before), 2) AS total_incremento,
    ROUND(AVG((salary_after - salary_before) / NULLIF(salary_before, 0) * 100), 2) AS pct_incremento_promedio,
    MIN(executed_at) AS fecha_ejecucion,
    MAX(executed_by) AS ejecutado_por
FROM audit_salary_adjustments_t1
WHERE execution_tag = 'Ex01'
  AND variant_id = 3;



-- SALIDA 3. VALIDACIÓN DE TOPES

WITH variant AS (
    SELECT * FROM t1_variants WHERE variant_id = &p_variant_id
),
dept_stats AS (
    SELECT 
        department_id,
        AVG(salary) AS dept_avg_salary_actual,
        MAX(salary) AS dept_max_salary_actual
    FROM t1_employees
    WHERE department_id IS NOT NULL
    GROUP BY department_id
)
SELECT 
    a.employee_id,
    e.first_name || ' ' || e.last_name AS employee_name,
    a.department_id,
    d.department_name,
    a.salary_after,
    ROUND(ds.dept_avg_salary_actual, 2) AS dept_avg_salary_actual,
    ROUND(ds.dept_max_salary_actual, 2) AS dept_max_salary_actual,
    ROUND(ds.dept_avg_salary_actual * (v.max_salary_vs_avg_pct/100), 2) AS max_allowed_salary_by_variant,
    ROUND((a.salary_after / ds.dept_avg_salary_actual) * 100, 2) AS pct_vs_dept_avg,
    CASE 
        WHEN a.salary_after <= ROUND(ds.dept_avg_salary_actual * (v.max_salary_vs_avg_pct/100), 2) 
        THEN ' CUMPLE TOPE'
        ELSE ' INCUMPLE TOPE'
    END AS top_limit_status,
    CASE 
        WHEN a.salary_after <= ds.dept_max_salary_actual THEN ' NO SUPERA MÁXIMO'
        WHEN a.salary_after > ds.dept_max_salary_actual AND 
             a.salary_after <= ROUND(ds.dept_avg_salary_actual * (v.max_salary_vs_avg_pct/100), 2) 
        THEN ' SUPERA MÁXIMO PERO DENTRO DE TOPE'
        ELSE ' SUPERA MÁXIMO Y TOPE'
    END AS max_salary_validation
FROM audit_salary_adjustments_t1 a
INNER JOIN t1_employees e ON a.employee_id = e.employee_id
INNER JOIN t1_departments d ON a.department_id = d.department_id
INNER JOIN dept_stats ds ON a.department_id = ds.department_id
CROSS JOIN variant v
WHERE a.execution_tag = 'Ex01'
  AND a.variant_id = 3
ORDER BY a.department_id, a.salary_after DESC;

-- SALIDA 4. AUDITORÍA GENERADA

SELECT 
    audit_id,
    execution_tag,
    variant_id,
    employee_id,
    department_id,
    TO_CHAR(salary_before, '999,999.99') AS salary_before,
    TO_CHAR(salary_after, '999,999.99') AS salary_after,
    TO_CHAR(salary_after - salary_before, '999,999.99') AS diferencia,
    pct_gap_to_avg_before,
    rule_applied,
    executed_by,
    TO_CHAR(executed_at, 'YYYY-MM-DD HH24:MI:SS') AS executed_at,
    notes
FROM audit_salary_adjustments_t1
WHERE execution_tag = 'Ex01'
  AND variant_id = 3
ORDER BY audit_id;

-- ============================================================
-- 6. JUSTIFICACIÓN TÉCNICA
-- Responder dentro del script, en comentarios.
-- Cada respuesta debe tener entre 3 y 6 líneas.
-- ============================================================

-- ATOMICIDAD:
-- Explique cómo su solución demuestra atomicidad.
--
-- RESPUESTA:
-- La solución demuestra atomicidad porque todas las operaciones (actualización de salarios
-- e inserción en auditoría) se ejecutan dentro de un mismo bloque transaccional. Si cualquiera
-- de estas operaciones falla, el bloque EXCEPTION captura el error y ejecuta ROLLBACK TO
-- SAVEPOINT, deshaciendo completamente todos los cambios. Esto garantiza el principio
-- "todo o nada": o se aplican todas las modificaciones o ninguna persiste en la base de datos.

-- CONSISTENCIA:
-- Explique cómo su solución asegura que los datos quedan válidos
-- después de la operación.
--
-- RESPUESTA:
-- La consistencia se garantiza mediante múltiples validaciones: antes del UPDATE se verifica
-- que el empleado cumpla todas las reglas de la variante (antigüedad, historial, topes);
-- durante la ejecución se calcula el nuevo salario respetando el porcentaje asignado;
-- después del UPDATE se valida que ningún salario supere el tope permitido (118% del promedio
-- departamental). Solo si todas estas validaciones son exitosas se ejecuta COMMIT, asegurando
-- que los datos finales cumplen todas las reglas de negocio definidas en la variante 3.

-- AISLAMIENTO:
-- Explique cómo se comportaría su transacción frente a otras sesiones.
--
-- RESPUESTA:
-- En Oracle, el aislamiento por defecto es READ COMMITTED. Durante la ejecución de esta
-- transacción, los cambios realizados (UPDATE sobre t1_employees) no son visibles para otras
-- sesiones hasta que se ejecute el COMMIT final. Esto evita lecturas sucias (dirty reads).
-- Si otra sesión intentara modificar los mismos registros simultáneamente, quedaría en espera
-- hasta que esta transacción termine, evitando actualizaciones perdidas (lost updates).

-- DURABILIDAD:
-- Explique qué garantiza la persistencia del cambio una vez confirmado.
--
-- RESPUESTA:
-- Una vez ejecutado el COMMIT, Oracle escribe los cambios en los redo logs y posteriormente
-- en los data files. Aunque el sistema fallara inmediatamente después del COMMIT, durante
-- el recovery automático (instance recovery) Oracle leería los redo logs para reaplicar
-- las transacciones confirmadas. Esto garantiza que los nuevos salarios y los registros de
-- auditoría persisten de manera duradera, cumpliendo el principio de durabilidad de ACID.

-- USO DE SAVEPOINT / ROLLBACK:
-- Explique qué riesgo controló y por qué ese punto de restauración
-- era necesario.
--
-- RESPUESTA:
-- El SAVEPOINT sv_before_adjustment se creó antes de iniciar las modificaciones para controlar
-- el riesgo de inconsistencias durante la validación intermedia. Si la validación posterior
-- al UPDATE detectaba que algún salario excedía el tope permitido (max_salary_vs_avg_pct),
-- se ejecutaba ROLLBACK TO SAVEPOINT para revertir completamente todos los cambios, sin
-- afectar otras operaciones previas que pudieran existir fuera de este taller. Este punto
-- de restauración era necesario porque permite un rollback parcial, deshaciendo solo las
-- operaciones de este bloque sin afectar el estado anterior al inicio del proceso.
PROMPT ===== Fin de plantilla =====
