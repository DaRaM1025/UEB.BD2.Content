CREATE OR REPLACE PROCEDURE sp_liquidar_empleado(
    p_id_empleado NUMBER,
    p_id_quincena VARCHAR2
) IS
    -- Variables de validación
    v_estado       EMPLEADOS.estado%TYPE;
    v_existe       NUMBER;
    
    -- Componentes de la liquidación
    v_salario_base_q   NUMBER(12,2);
    v_recargos         NUMBER(12,2);
    v_bonificacion     NUMBER(12,2);
    v_auxilio_transp   NUMBER(12,2);
    v_bono_sede        NUMBER(12,2);
    v_bruto            NUMBER(12,2);
    
    -- Deducciones
    v_salud            NUMBER(12,2);
    v_pension          NUMBER(12,2);
    v_fondo_solid      NUMBER(12,2) := 0;
    v_embargo          NUMBER(12,2) := 0;
    v_libranzas        NUMBER(12,2) := 0;
    v_aporte_vol       NUMBER(12,2) := 0;
    v_total_deducciones NUMBER(12,2);
    v_neto             NUMBER(12,2);
    
    -- Parámetros desde tabla PARAMETROS
    v_pct_salud        NUMBER(5,2);
    v_pct_pension      NUMBER(5,2);
    v_pct_fondo        NUMBER(5,2);
    v_umbral_fondo     NUMBER;
    v_smlmv            NUMBER(12,2);
    v_aporte_vol_bog   NUMBER(12,2);
    v_aux_transp_mens  NUMBER(12,2);
    
    -- Para embargos y libranzas
    v_porc_embargo     NUMBER(5,2);
    v_total_libranzas_mens NUMBER(12,2);
    
    -- Para sede y aporte voluntario
    v_cod_sede         VARCHAR2(5);
    v_acepta_vol       VARCHAR2(1);
    
BEGIN
    -- 13. Validar existencia del empleado
    BEGIN
        SELECT estado, cod_sede, acepta_aporte_vol
        INTO v_estado, v_cod_sede, v_acepta_vol
        FROM EMPLEADOS
        WHERE id_empleado = p_id_empleado;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'Empleado no encontrado: ' || p_id_empleado);
    END;
    
    -- 14. Validar que esté ACTIVO
    IF v_estado != 'ACTIVO' THEN
        RAISE_APPLICATION_ERROR(-20002, 'Empleado no activo: estado = ' || v_estado);
    END IF;
    
    -- 15. Validar que no exista liquidación previa
    SELECT COUNT(*)
    INTO v_existe
    FROM LIQUIDACION
    WHERE id_empleado = p_id_empleado AND id_quincena = p_id_quincena;
    
    IF v_existe > 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Liquidación ya existe para empleado ' || p_id_empleado || ' quincena ' || p_id_quincena);
    END IF;
    
    -- 16. Calcular conceptos usando funciones del Punto 2
    v_salario_base_q := fn_salario_base_q(p_id_empleado, p_id_quincena);
    v_recargos       := fn_recargos(p_id_empleado, p_id_quincena);
    v_bonificacion   := fn_bonificacion(p_id_empleado);
    
    -- Calcular auxilio de transporte (Regla 4) – reutilizando lógica de fn_bruto
    -- Obtenemos parámetros necesarios
    SELECT valor_numerico INTO v_smlmv FROM PARAMETROS WHERE cod_parametro = 'SMLMV';
    SELECT valor_numerico INTO v_aux_transp_mens FROM PARAMETROS WHERE cod_parametro = 'AUX_TRANSPORTE';
    
    DECLARE
        v_tipo_contrato EMPLEADOS.tipo_contrato%TYPE;
        v_salario_mensual_equiv NUMBER;
        v_valor_hora NUMBER;
        v_horas_normales NUMBER;
    BEGIN
        SELECT tipo_contrato INTO v_tipo_contrato FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
        IF v_tipo_contrato IN ('PLANTA', 'TEMPORAL') THEN
            IF v_tipo_contrato = 'PLANTA' THEN
                SELECT salario_base INTO v_salario_mensual_equiv FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
            ELSE
                SELECT salario_base INTO v_valor_hora FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
                SELECT NVL(SUM(cantidad_horas),0) INTO v_horas_normales
                FROM HORAS_TRABAJADAS
                WHERE id_empleado = p_id_empleado AND id_quincena = p_id_quincena AND tipo_hora = 'NORMAL';
                v_salario_mensual_equiv := v_horas_normales * v_valor_hora * 2;
            END IF;
            IF v_salario_mensual_equiv <= 2 * v_smlmv THEN
                v_auxilio_transp := v_aux_transp_mens / 2;
            ELSE
                v_auxilio_transp := 0;
            END IF;
        ELSE
            v_auxilio_transp := 0;
        END IF;
    END;
    
    -- Calcular bono de sede (Regla 5)
    DECLARE
        v_tipo_contrato EMPLEADOS.tipo_contrato%TYPE;
        v_bono_clima_sma NUMBER;
    BEGIN
        SELECT tipo_contrato INTO v_tipo_contrato FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
        IF v_tipo_contrato IN ('PLANTA', 'TEMPORAL') AND v_cod_sede = 'SMA' THEN
            SELECT valor_numerico INTO v_bono_clima_sma FROM PARAMETROS WHERE cod_parametro = 'BONO_CLIMA_SMA';
            v_bono_sede := v_bono_clima_sma;
        ELSE
            v_bono_sede := 0;
        END IF;
    END;
    
    -- Bruto (Regla 6)
    v_bruto := v_salario_base_q + v_recargos + v_bonificacion + v_auxilio_transp + v_bono_sede;
    
    -- 7. Deducciones (Regla 7)
    SELECT valor_numerico INTO v_pct_salud FROM PARAMETROS WHERE cod_parametro = 'PCT_SALUD';
    SELECT valor_numerico INTO v_pct_pension FROM PARAMETROS WHERE cod_parametro = 'PCT_PENSION';
    SELECT valor_numerico INTO v_pct_fondo FROM PARAMETROS WHERE cod_parametro = 'PCT_FONDO_SOLIDARIDAD';
    SELECT valor_numerico INTO v_umbral_fondo FROM PARAMETROS WHERE cod_parametro = 'UMBRAL_FONDO_SMLMV';
    SELECT valor_numerico INTO v_aporte_vol_bog FROM PARAMETROS WHERE cod_parametro = 'APORTE_VOL_BOG';
    
    v_salud   := v_bruto * v_pct_salud / 100;
    v_pension := v_bruto * v_pct_pension / 100;
    
    -- Fondo de solidaridad (solo si bruto mensual > umbral * SMLMV)
    IF (v_bruto * 2) > (v_umbral_fondo * v_smlmv) THEN
        v_fondo_solid := v_bruto * v_pct_fondo / 100;
    END IF;
    
    -- Embargos
    SELECT NVL(SUM(porcentaje), 0) INTO v_porc_embargo
    FROM EMBARGOS
    WHERE id_empleado = p_id_empleado AND estado = 'ACTIVO';
    
    IF v_porc_embargo > 0 THEN
        v_embargo := (v_bruto - v_salud - v_pension - v_fondo_solid) * v_porc_embargo / 100;
    END IF;
    
    -- Libranzas
    SELECT NVL(SUM(cuota_mensual), 0) INTO v_total_libranzas_mens
    FROM LIBRANZAS
    WHERE id_empleado = p_id_empleado AND estado = 'ACTIVA';
    v_libranzas := v_total_libranzas_mens / 2;
    
    -- Aporte voluntario (solo Bogotá y si acepta)
    IF v_cod_sede = 'BOG' AND v_acepta_vol = 'S' THEN
        v_aporte_vol := v_aporte_vol_bog;
    END IF;
    
    v_total_deducciones := v_salud + v_pension + v_fondo_solid + v_embargo + v_libranzas + v_aporte_vol;
    v_neto := v_bruto - v_total_deducciones;
    
    -- 17. Caso especial: neto negativo (Regla 8)
    IF v_neto < 0 THEN
        -- Paso 1: eliminar embargo
        v_embargo := 0;
        v_total_deducciones := v_salud + v_pension + v_fondo_solid + v_embargo + v_libranzas + v_aporte_vol;
        v_neto := v_bruto - v_total_deducciones;
        
        IF v_neto < 0 THEN
            -- Paso 2: eliminar libranzas
            v_libranzas := 0;
            v_total_deducciones := v_salud + v_pension + v_fondo_solid + v_embargo + v_libranzas + v_aporte_vol;
            v_neto := v_bruto - v_total_deducciones;
        END IF;
    END IF;
    
    -- 18. Insertar en LIQUIDACION
    INSERT INTO LIQUIDACION (
        id_liquidacion, id_empleado, id_quincena,
        salario_base_q, recargos, bonificacion,
        auxilio_transp, bono_sede, bruto,
        deduccion_salud, deduccion_pension,
        fondo_solidaridad, embargo, libranzas,
        aporte_voluntario, total_deducciones, neto
    ) VALUES (
        SEQ_LIQUIDACION.NEXTVAL, p_id_empleado, p_id_quincena,
        v_salario_base_q, v_recargos, v_bonificacion,
        v_auxilio_transp, v_bono_sede, v_bruto,
        v_salud, v_pension, v_fondo_solid,
        v_embargo, v_libranzas, v_aporte_vol,
        v_total_deducciones, v_neto
    );
    
    -- 19. COMMIT
    COMMIT;
    
EXCEPTION
    -- Capturar cualquier otro error y hacer rollback implícito
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_liquidar_empleado;
/

--Validaciones segun el documento--
-- Empleado inexistente
BEGIN
    sp_liquidar_empleado(9999, '2026-Q1-ENE');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE(SQLERRM);
END;
--Validacion aprobada--
/

-- Empleado inactivo (1017)
BEGIN
    sp_liquidar_empleado(1017, '2026-Q1-ENE');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE(SQLERRM);
END;
--Validacion Aprobada--
/

-- Liquidación repetida (ejecutar dos veces para el mismo empleado)
BEGIN
    sp_liquidar_empleado(1001, '2026-Q1-ENE');
    sp_liquidar_empleado(1001, '2026-Q1-ENE');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE(SQLERRM);
END;
--Validacion Aprobada--
/
