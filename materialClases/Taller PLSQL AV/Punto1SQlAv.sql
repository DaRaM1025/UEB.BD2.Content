Set SERVEROUTPUT ON;
-- PUNTO 1: Bloque anónimo corregido
DECLARE
    v_id_empleado     EMPLEADOS.id_empleado%TYPE := &empleadoId;   -- Cambiar para probar otros
    v_id_quincena     VARCHAR2(15) := '2026-Q1-ENE';
    v_nombre          EMPLEADOS.nombre%TYPE;
    v_nombre_sede     SEDES.nombre_sede%TYPE;
    v_tipo_contrato   EMPLEADOS.tipo_contrato%TYPE;
    v_antiguedad      NUMBER;
    v_salario_base_q  NUMBER(12,2);
    v_valor_hora      NUMBER(12,2);
    v_recargos        NUMBER(12,2) := 0;
    v_bonificacion    NUMBER(12,2) := 0;
    v_auxilio_transp  NUMBER(12,2) := 0;
    v_bono_sede       NUMBER(12,2) := 0;
    v_bruto           NUMBER(12,2);
    
    -- Parámetros desde PARAMETROS
    v_smlmv           NUMBER(12,2);
    v_aux_transp_mens NUMBER(12,2);
    v_rec_noct        NUMBER(5,2);
    v_rec_dom         NUMBER(5,2);
    v_rec_noct_dom    NUMBER(5,2);
    v_bono_clima_sma  NUMBER(12,2);
    v_retencion_serv  NUMBER(5,2);
    
    -- Cursor para horas trabajadas (excluye NORMAL porque no genera recargo)
    CURSOR c_horas_recargo IS
        SELECT tipo_hora, cantidad_horas
        FROM HORAS_TRABAJADAS
        WHERE id_empleado = v_id_empleado
          AND id_quincena = v_id_quincena
          AND tipo_hora IN ('NOCTURNA', 'DOMINICAL', 'NOCTURNA_DOM');
    
    -- Variables auxiliares
    v_horas_normales  NUMBER;
    v_salario_mensual_equiv NUMBER;
    v_num_sanciones   NUMBER;
    v_cod_sede        VARCHAR2(5);
BEGIN
    -- Obtener datos del empleado y su sede
    SELECT e.nombre, s.nombre_sede, e.tipo_contrato, e.cod_sede,
           TRUNC(MONTHS_BETWEEN(SYSDATE, e.fecha_ingreso) / 12) AS antiguedad,
           e.salario_base
    INTO v_nombre, v_nombre_sede, v_tipo_contrato, v_cod_sede, v_antiguedad, v_salario_base_q
    FROM EMPLEADOS e
    JOIN SEDES s ON e.cod_sede = s.cod_sede
    WHERE e.id_empleado = v_id_empleado;
    
    -- Leer parámetros generales
    SELECT valor_numerico INTO v_smlmv FROM PARAMETROS WHERE cod_parametro = 'SMLMV';
    SELECT valor_numerico INTO v_aux_transp_mens FROM PARAMETROS WHERE cod_parametro = 'AUX_TRANSPORTE';
    SELECT valor_numerico INTO v_rec_noct FROM PARAMETROS WHERE cod_parametro = 'RECARGO_NOCTURNO';
    SELECT valor_numerico INTO v_rec_dom FROM PARAMETROS WHERE cod_parametro = 'RECARGO_DOMINICAL';
    SELECT valor_numerico INTO v_rec_noct_dom FROM PARAMETROS WHERE cod_parametro = 'RECARGO_NOCT_DOM';
    SELECT valor_numerico INTO v_bono_clima_sma FROM PARAMETROS WHERE cod_parametro = 'BONO_CLIMA_SMA';
    SELECT valor_numerico INTO v_retencion_serv FROM PARAMETROS WHERE cod_parametro = 'RET_SERVICIOS';
    
    -- ========== REGLA 1: Salario base quincenal ==========
    CASE v_tipo_contrato
        WHEN 'PLANTA' THEN
            v_salario_base_q := v_salario_base_q / 2;
            -- Valor hora para recargos (salario mensual / 240)
            v_valor_hora := (v_salario_base_q * 2) / 240;
            
        WHEN 'TEMPORAL' THEN
            -- Obtener horas normales de la quincena
            SELECT NVL(SUM(cantidad_horas), 0) INTO v_horas_normales
            FROM HORAS_TRABAJADAS
            WHERE id_empleado = v_id_empleado
              AND id_quincena = v_id_quincena
              AND tipo_hora = 'NORMAL';
            -- salario_base es el valor_hora
            SELECT salario_base INTO v_valor_hora
            FROM EMPLEADOS WHERE id_empleado = v_id_empleado;
            v_salario_base_q := v_horas_normales * v_valor_hora;
            
        WHEN 'SERVICIOS' THEN
            v_salario_base_q := (v_salario_base_q - (v_salario_base_q * v_retencion_serv / 100)) / 2;
            v_valor_hora := 0; -- No aplica
    END CASE;
    
    -- ========== REGLA 2: Recargos (solo PLANTA y TEMPORAL) ==========
    IF v_tipo_contrato IN ('PLANTA', 'TEMPORAL') THEN
        FOR rec IN c_horas_recargo LOOP
            CASE rec.tipo_hora
                WHEN 'NOCTURNA' THEN
                    v_recargos := v_recargos + rec.cantidad_horas * v_valor_hora * (v_rec_noct / 100);
                WHEN 'DOMINICAL' THEN
                    v_recargos := v_recargos + rec.cantidad_horas * v_valor_hora * (v_rec_dom / 100);
                WHEN 'NOCTURNA_DOM' THEN
                    v_recargos := v_recargos + rec.cantidad_horas * v_valor_hora * (v_rec_noct_dom / 100);
            END CASE;
        END LOOP;
    END IF;
    
    -- ========== REGLA 3: Bonificación (solo PLANTA y TEMPORAL) ==========
    IF v_tipo_contrato IN ('PLANTA', 'TEMPORAL') THEN
        -- Contar sanciones en los últimos 6 meses
        SELECT COUNT(*) INTO v_num_sanciones
        FROM SANCIONES
        WHERE id_empleado = v_id_empleado
          AND fecha_sancion >= ADD_MONTHS(SYSDATE, -6);
        
        IF v_num_sanciones <= 2 THEN
            IF v_antiguedad BETWEEN 3 AND 5 THEN
                v_bonificacion := v_salario_base_q * 0.03;
            ELSIF v_antiguedad BETWEEN 6 AND 10 THEN
                v_bonificacion := v_salario_base_q * 0.06;
            ELSIF v_antiguedad > 10 THEN
                v_bonificacion := v_salario_base_q * 0.10;
            END IF;
        END IF;
    END IF;
    
    -- ========== REGLA 4: Auxilio de transporte ==========
    IF v_tipo_contrato IN ('PLANTA', 'TEMPORAL') THEN
        -- Calcular salario mensual equivalente
        IF v_tipo_contrato = 'PLANTA' THEN
            SELECT salario_base INTO v_salario_mensual_equiv
            FROM EMPLEADOS WHERE id_empleado = v_id_empleado;
        ELSE
            SELECT salario_base INTO v_valor_hora
            FROM EMPLEADOS WHERE id_empleado = v_id_empleado;
            SELECT NVL(SUM(cantidad_horas), 0) INTO v_horas_normales
            FROM HORAS_TRABAJADAS
            WHERE id_empleado = v_id_empleado AND id_quincena = v_id_quincena AND tipo_hora = 'NORMAL';
            v_salario_mensual_equiv := v_horas_normales * v_valor_hora * 2;
        END IF;
        
        IF v_salario_mensual_equiv <= 2 * v_smlmv THEN
            v_auxilio_transp := v_aux_transp_mens / 2;
        END IF;
    END IF;
    
    -- ========== REGLA 5: Bono por sede ==========
    IF v_tipo_contrato IN ('PLANTA', 'TEMPORAL') AND v_cod_sede = 'SMA' THEN
        v_bono_sede := v_bono_clima_sma;
    END IF;
    
    -- ========== BRUTO ==========
    v_bruto := v_salario_base_q + v_recargos + v_bonificacion + v_auxilio_transp + v_bono_sede;
    
    -- ========== SALIDA FORMATEADA ==========
    DBMS_OUTPUT.PUT_LINE('=== LIQUIDACIÓN QUINCENAL ===');
    DBMS_OUTPUT.PUT_LINE('Empleado: ' || v_nombre || ' (' || v_id_empleado || ')');
    DBMS_OUTPUT.PUT_LINE('Sede: ' || v_nombre_sede);
    DBMS_OUTPUT.PUT_LINE('Tipo contrato: ' || v_tipo_contrato);
    DBMS_OUTPUT.PUT_LINE('Antigüedad: ' || v_antiguedad || ' años');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('Salario base Q: ' || TO_CHAR(v_salario_base_q, '999,999,999.00'));
    DBMS_OUTPUT.PUT_LINE('Recargos: ' || TO_CHAR(v_recargos, '999,999,999.00'));
    DBMS_OUTPUT.PUT_LINE('Bonificación: ' || TO_CHAR(v_bonificacion, '999,999,999.00'));
    DBMS_OUTPUT.PUT_LINE('Auxilio transporte: ' || TO_CHAR(v_auxilio_transp, '999,999,999.00'));
    DBMS_OUTPUT.PUT_LINE('Bono sede: ' || TO_CHAR(v_bono_sede, '999,999,999.00'));
    DBMS_OUTPUT.PUT_LINE('SUBTOTAL (Bruto): ' || TO_CHAR(v_bruto, '999,999,999.00'));
    DBMS_OUTPUT.PUT_LINE('==============================');
    
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Error: No se encontraron datos para el empleado ' || v_id_empleado);
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error inesperado: ' || SQLERRM);
END;
/
/*
Segun el calculo arrojado por la consulta con el empleado de id 1001 se encuentra un error 
en las validaciondes del documento guia, ya que al empleado si le corresponde un auxilo de transporte segun la regla 4
*/