SET SERVEROUTPUT ON;
CREATE OR REPLACE
FUNCTION fn_saludar (param_nombre VARCHAR2)
RETURN VARCHAR2
IS
saludo VARCHAR2(60);
BEGIN
saludo := 'hola buen dia ' || param_nombre;
RETURN(saludo);
END;
/
DECLARE
vv_operacion VARCHAR2(30);
BEGIN
vv_operacion := fn_saludar('santiago');
dbms_output.put_line(vv_operacion);
END;

CREATE OR REPLACE
FUNCTION fn_integral (param_valor_x VARCHAR2)
RETURN VARCHAR2
IS
saludo VARCHAR2(60);
BEGIN
saludo := 'hola buen dia ' || param_nombre;
RETURN(saludo);
END;
/

CREATE OR REPLACE FUNCTION FN_INTEGRAL_TRAPECIO(
    p_limite_inf  IN NUMBER,  -- Límite inferior (a)
    p_limite_sup  IN NUMBER,  -- Límite superior (x)
    p_intervalos  IN NUMBER DEFAULT 1000  -- Precisión: más intervalos = más exacto
) RETURN NUMBER IS

    v_h       NUMBER;
    v_suma    NUMBER := 0;
    v_x       NUMBER;

    -- Define aquí tu función f(x) — actualmente f(x) = x²
    FUNCTION f(x IN NUMBER) RETURN NUMBER IS
    BEGIN
        RETURN POWER(x, 2) + power(x,4) + 3;  -- Cambia esto por la función que necesites
    END f;

BEGIN
    -- Tamaño de cada subintervalo
    v_h := (p_limite_sup - p_limite_inf) / p_intervalos;

    -- Regla del Trapecio Compuesta
    -- Integral ≈ (h/2) * [f(a) + 2*f(x1) + 2*f(x2) + ... + f(b)]
    v_suma := f(p_limite_inf) + f(p_limite_sup);

    FOR i IN 1 .. p_intervalos - 1 LOOP
        v_x := p_limite_inf + i * v_h;
        v_suma := v_suma + 2 * f(v_x);
    END LOOP;

    RETURN ROUND((v_h / 2) * v_suma, 6);

END FN_INTEGRAL_TRAPECIO;
/
SELECT FN_INTEGRAL_TRAPECIO(0, 3) AS resultado FROM DUAL;
-- Integral de x² entre 0 y 3 → resultado esperado: 9.0